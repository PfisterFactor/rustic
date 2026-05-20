# `rustic-hardened` — design rationale

This document explains *why* the hardened image is built the way it is. The
choices are deliberate, and several of them trade convenience for security or
auditability. If you find yourself wanting to soften one, read this first.

## Why `FROM scratch` (and not `fedora-minimal`, distroless, alpine, etc.)

The runtime stage in `packaging/podman/Containerfile` is `FROM scratch`. Its
filesystem contents come from `/rootfs`, which is assembled in a dedicated
`runtime-rootfs` stage and then audited before it ships.

Two reasons:

1. **Construction over uninstall.** A "shrink the base image" approach relies on
   `dnf remove -y` / `rpm -e` / `rm -rf` to take things back out after they've
   been installed. That's inherently best-effort: the package's scriptlets have
   already run, and any file the maintainer forgot to register stays. With an
   `--installroot` assembled into `/rootfs` and then copied into `scratch`, the
   runtime contains *only* what we asked for — verified by the contract script.
2. **Provenance.** Every file in the final image is either
   `/usr/local/bin/rustic` (from the builder stage), the explicit `LICENSE-*`
   files, the `/etc/passwd` and `/etc/group` we stamp by hand, or a
   package-installed file from the `dnf5 --installroot` pass whose closure we
   control. There is no layer inherited from a third party that we have to trust
   opaquely.

We do not use distroless (Google) because:

- it's pinned to specific glibc/libfuse versions outside our control,
- its FUSE story is awkward (no `fuse3-libs` in the standard variants),
- and we want the same Fedora vendor for both build and runtime, so rebuilds
  against newer CVE patches stay in sync.

We do not use Alpine/musl because:

- mimalloc + glibc interop is what upstream rustic recommends for the fastest
  backups,
- `dav-server` / `axum` work fine on glibc and we'd lose the convenience of
  Fedora-vendored OpenSSL roots (rustic uses rustls, but several deps still read
  the system CA bundle layout),
- and `fuse_mt`'s FUSE3 dependency is straightforward on Fedora.

## Why a separate `runtime-rootfs` stage instead of doing it in the runtime

`FROM scratch` cannot run `RUN`. Anything that needs `dnf5`, `find`, `install`,
or `chroot` has to happen in a stage that *has* those tools. The runtime-rootfs
stage exists exactly for that, and is then discarded — its `/usr/bin` does not
survive into the final image.

The TESTS_PASSED sentinel gates the assembly: the `runtime-rootfs` stage does
`COPY --from=tester /var/lib/rustic/TESTS_PASSED /tmp/TESTS_PASSED`, which fails
the build if the tester stage didn't get that far. The rootfs isn't assembled —
and the runtime image isn't produced — unless the tests pass.

## Why UID/GID `65532:65532`

- High enough not to collide with host-side service users.
- Matches the convention used by Google distroless's `nonroot` user, so
  host-side bind-mount ownership patterns (`chown 65532:65532 /srv/rustic-repo`)
  carry over.
- `/etc/passwd` and `/etc/group` are stamped manually so we don't drag
  `shadow-utils` (and its setuid `newgidmap`/`newuidmap`, on some
  configurations) into the final rootfs.

We do *not* use UID 0 with `--cap-drop=ALL` because:

- container runtimes still treat UID 0 specially for some namespace decisions,
- it's easy to forget the `--cap-drop` on a one-off invocation,
- and an attacker who pops out into a host namespace from UID 0 has a more
  interesting starting position than from 65532.

## Why no shell, package manager, or developer tools

These exist purely to be available to an attacker. `rustic` doesn't need them at
runtime; the build needs them only in the builder stage, which is discarded.

The `900_runtime_rootfs_contract.sh` test asserts the absence of:

- `/bin/sh`, `/usr/bin/sh`, `/usr/bin/bash` and every other shell entry
- every package-manager entry point (`dnf`, `dnf5`, `microdnf`, `yum`, `rpm`)
- `useradd` / `groupadd` (they have no business being available)
- any setuid or setgid file anywhere under `/`

It runs twice: once in `runtime-rootfs` against the assembled `/rootfs`
(build-time gate, hard-fails the image), and once in CI against the final
image's unpacked rootfs (verification gate). A `|| true` workaround would defeat
the point — the script must exit non-zero to fail the build.

## Why `self-update` is excluded

The runtime image is immutable. A successful self-update would mean the binary
on the running container differs from the one that was scanned, signed,
attested, and SBOM-ed at publish time. That breaks every supply chain claim we
make. The user should pull a new image instead.

## Why `STOPSIGNAL SIGTERM`

`rustic` doesn't install a signal handler that needs anything more than the
default. `SIGTERM` lets `podman stop` deliver a graceful shutdown to
long-running `mount` / `webdav` invocations before the runtime forcibly sends
`SIGKILL` after the grace period. The default would have been `SIGTERM` already;
we set it explicitly so a future change has to be deliberate.

## Why no `EXPOSE`

`rustic webdav` and `rustic mount` are opt-in: the operator wires up the ports
they need with `-p` at run time, and the docker/podman metadata shouldn't lie
about what the image listens on by default (nothing). `EXPOSE` is documentation,
not enforcement, and stale documentation is worse than none.

## Why `--read-only`-compatible by design

The image works under `--read-only` because every directory it writes to is
either:

- a tmpfs the operator mounts (`/tmp`, `/work`),
- a bind-mounted volume the operator provides (`/repo`),
- or `/var/cache/rustic` (operator-supplied volume; `--no-cache` short-circuits
  this entirely).

Nothing the image needs is written to its own filesystem. If it were, the
operator would be forced to drop `--read-only` and we'd lose a meaningful
sandbox guarantee.

## Why the hardened runtime is shell-free even though some rustic commands exec

`backup --stdin-command`, `--password-command`, and the various `[*.hooks]`
entries pass a string to a child process. In every existing rustic deployment,
that string is interpreted by `/bin/sh`. In this image, it cannot be — there is
no `sh`.

Two reasons to keep it that way:

1. A shell is a generic local code-execution primitive. The whole point of the
   image is to deny that primitive to anyone who pops `rustic`.
2. The use cases that legitimately need exec all have a known helper binary on
   the operator's side. Bind-mounting that binary in (path-only invocation, no
   shell) keeps the runtime sandbox intact while giving the operator the
   integration point they need.

`README.md` documents the bind-mount and "derive an image" patterns.

## Why an explicit SPDX SBOM attestation in addition to BuildKit's

`docker/build-push-action`'s `sbom: true` and `provenance: mode=max` attach SBOM
and SLSA provenance attestations to the registry image at push time. Those are
correct and fine to use, but:

- Most existing policy engines speak SPDX 2.3 JSON specifically; they don't all
  know how to walk a BuildKit attestation manifest.
- The BuildKit attestations live next to the manifest in the registry; they
  don't drop a file on disk in CI. If we ever need to ship the SBOM to a
  downstream system that isn't an OCI registry, we want the file.

So we additionally run `anchore/sbom-action` (Syft) against the *registry
digest* of the pushed image and attach the resulting SPDX JSON via
`cosign attest --type spdxjson`. Both attestations are verified before the sign
job exits — if signing or attestation verification fails, the run fails, and we
never claim a green publish.

## Why pinning Fedora by manifest digest

Tags drift. `fedora:44` will, in a few months, refer to a different image index.
Pinning by `@sha256:...` makes the build reproducible from a given
`Containerfile` revision and a given `Cargo.lock`. Renovate (or a manual update)
bumps the digest deliberately, with a diff the reviewer can see.

The two arguments — `FEDORA_IMAGE` and `FEDORA_MINIMAL_IMAGE` — are overridable
at build time, so security teams can pin to a private mirror without forking the
`Containerfile`.

## Why the rust-toolchain is pinned at build time, not via `rust-toolchain.toml`

Pinning at the Containerfile level (`ARG RUST_TOOLCHAIN=1.88.0`) keeps the
hardened image's toolchain decision out of the upstream repo's normal Rust
workflow. Upstream contributors don't have to care that bumping `rust-version`
in `Cargo.toml` would also bump the image; the `Containerfile` documents the
dependency explicitly. CI overrides it via `--build-arg` when we want to test on
a newer compiler.
