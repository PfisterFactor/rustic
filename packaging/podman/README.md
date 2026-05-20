# `rustic-hardened` — operator guide

`ghcr.io/PfisterFactor/rustic-hardened` is a Fedora-based, OCI-compliant,
security-hardened container image of
[`rustic`](https://github.com/PfisterFactor/rustic). It is intended as a drop-in
backup runner for read-only access to host filesystems (typically btrfs/zfs
snapshots bind-mounted into the container) running as a non-root user with
capabilities, syscalls, and writes locked down by construction.

This is a sibling of the upstream `ghcr.io/rustic-rs/rustic` image. They are not
interchangeable: the upstream image is a minimal `FROM scratch` repackage of
pre-built release binaries, while this image is built from source on Fedora with
the full feature set documented below, embeds an integration test suite into the
build itself, and ships a hardened runtime rootfs.

## At a glance

| Property                         | Value                                                                      |
| -------------------------------- | -------------------------------------------------------------------------- |
| Registry                         | `ghcr.io/PfisterFactor/rustic-hardened`                                    |
| Tags                             | `latest`, `main`, `v<X.Y.Z>`, `sha-<short>`                                |
| Architectures                    | `linux/amd64`, `linux/arm64`                                               |
| Base                             | `FROM scratch` (rootfs assembled from `registry.fedoraproject.org/fedora`) |
| Runtime user                     | `rustic` (UID/GID `65532:65532`); no shell, no login                       |
| Rust toolchain                   | pinned to `Cargo.toml` `rust-version` (1.88.0)                             |
| `rustic` features compiled in    | `jq,prometheus,opentelemetry,tui,webdav,mount,mimalloc`                    |
| Features explicitly **excluded** | `self-update` (immutable image must never rewrite itself)                  |
| Entrypoint                       | `/usr/local/bin/rustic`                                                    |
| Default command                  | `--help`                                                                   |
| Signing                          | cosign keyless via GitHub OIDC + explicit SPDX SBOM attestation            |
| Scanning                         | Trivy fail-on-HIGH/CRITICAL in CI                                          |
| Provenance                       | BuildKit SLSA provenance + SBOM attestations attached at push time         |

## What's deliberately missing from the runtime

The final image is `FROM scratch`. There is **no shell**, **no package manager**
(`dnf`/`dnf5`/`microdnf`/`yum`), **no `rpm`**, **no compiler**, **no busybox**,
and **no setuid/setgid binaries**. The runtime contains exactly:

```
/usr/local/bin/rustic
/usr/share/licenses/rustic/{LICENSE-APACHE,LICENSE-MIT}
/etc/passwd, /etc/group           # only root + rustic (UID/GID 65532)
/etc/pki/ca-trust/...             # CA bundle from ca-certificates
/usr/lib/{libc.so.*, libgcc_s.so.*, libfuse3.so.*, ld-linux*.so.*, ...}
/usr/share/zoneinfo/...           # tzdata
/work, /var/lib/rustic, /var/cache/rustic   # 65532-owned, mode 0750
```

That is checked by `packaging/podman/tests/cases/900_runtime_rootfs_contract.sh`
during the build (against the assembled `/rootfs` in the `runtime-rootfs` stage)
and again in CI against the final image after it has been unpacked.

## Pulling the image

```sh
podman pull ghcr.io/PfisterFactor/rustic-hardened:latest
# or pin a tag / digest:
podman pull ghcr.io/PfisterFactor/rustic-hardened:v0.11.2
podman pull ghcr.io/PfisterFactor/rustic-hardened@sha256:<digest>
```

`docker pull` works identically.

## Recommended run flags

The image is designed to run under the strictest container sandbox you can give
it. The example below is the recommended baseline. All flags except `--user` are
documentation, not enforcement — set them yourself when you run the image.

```sh
podman run --rm \
  --read-only \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --security-opt=label=disable \
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=64m \
  --tmpfs /work:rw,nosuid,nodev,size=512m \
  --user 65532:65532 \
  -e RUSTIC_PASSWORD \
  -v /srv/snapshots:/data:ro \
  -v rustic-repo:/repo \
  -v rustic-cache:/var/cache/rustic \
  ghcr.io/PfisterFactor/rustic-hardened:latest \
  -r /repo backup /data
```

What that buys you:

- `--read-only` makes the container's own filesystem read-only. `rustic` writes
  to `/repo` (the bind-mounted/volume backing store), `/work` (workspace tmpfs),
  `/tmp`, and `/var/cache/rustic` — all explicitly mounted or already writable.
- `--cap-drop=ALL` removes every Linux capability. `rustic` does not need any to
  read bind-mounted data and write a repository.
- `--security-opt=no-new-privileges` defangs setuid/setgid binaries in any child
  process — there are none in this image, but this hardens against future drift.
- `--user 65532:65532` matches the image's built-in `rustic` user. UID 65532 is
  intentionally high to avoid colliding with host user namespaces.

`--security-opt=label=disable` is only needed on SELinux hosts to allow the
`/data:ro` bind to be read; alternatively, label the source directory with
`:z`/`:Z` on Podman or use `--security-opt label=type:container_t`.

## Bind-mounting host snapshots

This is the primary use case: back up a host btrfs/zfs snapshot directory.

```sh
# Mount a read-only btrfs snapshot inside the container.
podman run --rm \
  --read-only --cap-drop=ALL --security-opt=no-new-privileges \
  --tmpfs /tmp --tmpfs /work \
  --user 65532:65532 \
  -e RUSTIC_PASSWORD \
  -v /var/lib/btrfs/snapshots/home@2026-05-20:/data:ro \
  -v /srv/rustic-repo:/repo \
  ghcr.io/PfisterFactor/rustic-hardened:latest \
  -r /repo --no-cache backup --host myhost --tag daily /data
```

`--no-cache` is a good fit for read-only filesystems where the default cache
directory cannot be written. If you do want a cache, mount a writable volume at
`/var/cache/rustic`.

## FUSE mount (`rustic mount`) — opt-in

`rustic mount` is compiled in but is host-dependent: it needs `/dev/fuse` and
`CAP_SYS_ADMIN`. By design, the hardened default does **not** grant those. Opt
in explicitly when you want to mount a snapshot:

```sh
podman run --rm -it \
  --read-only --security-opt=no-new-privileges \
  --tmpfs /tmp --tmpfs /work \
  --user 65532:65532 \
  --cap-drop=ALL --cap-add=SYS_ADMIN \
  --device /dev/fuse \
  -v /srv/rustic-repo:/repo:ro \
  -v /mnt/rustic:/mnt:rshared \
  -e RUSTIC_PASSWORD \
  ghcr.io/PfisterFactor/rustic-hardened:latest \
  -r /repo mount latest /mnt
```

The hardened image deliberately omits the setuid `fusermount3` helper, so
`rustic mount`'s FUSE path is exercised through the kernel device only.

## Shell-free runtime — what that means for you

The runtime image does not have `/bin/sh` or any other shell, by design. A few
rustic features delegate to a child process; in this image they will fail with
an `exec` error unless you provide the helper binary yourself:

| Feature                                                            | What it tries to exec                             |
| ------------------------------------------------------------------ | ------------------------------------------------- |
| `backup --stdin-command 'CMD'`                                     | runs `CMD` and pipes its stdout into the snapshot |
| `--password-command 'CMD'`                                         | runs `CMD` to fetch the repository password       |
| `[*.hooks].run-before/after/...`                                   | runs each `CommandInput` for the matching phase   |
| `[repository.options] post-create-command` / `post-delete-command` | runs each on local-backend snapshot create/delete |

For production deployments that need any of these, pick **one** of:

1. **Bind-mount a static helper**. Put a single statically linked binary on the
   host and bind-mount it into the container, then point the hook / command at
   it. Example (rustic invokes the path directly, no shell needed):
   `--password-command /usr/local/bin/get-password`.
2. **Derive a thin image on top**. Build your own image
   `FROM
   ghcr.io/PfisterFactor/rustic-hardened:<tag>` and `COPY` the helper
   binaries in. Keep them statically linked or compatible with the runtime
   closure.
3. **Inject the secret via env / file**. `RUSTIC_PASSWORD` (env) and
   `--password-file` work without any child process and are the recommended path
   for the common "feed me a password" case.

The hooks tests under `packaging/podman/tests/cases/180_hooks.sh` and
`160_backup_stdin_command.sh` run only inside the tester build stage, which
*does* have bash; they exercise the rustic-side wiring and are not a claim that
you can run these in the published runtime out of the box.

## Verifying the image you pulled

The image is signed with cosign keyless via GitHub's OIDC. The SPDX SBOM
generated by Syft is attached as a cosign attestation.

```sh
IMAGE=ghcr.io/PfisterFactor/rustic-hardened:latest

# Resolve to a digest so verification can't race the registry.
DIGEST=$(crane digest "$IMAGE")
PINNED="ghcr.io/PfisterFactor/rustic-hardened@$DIGEST"

# Signature: must be made by the publish workflow in this repo.
cosign verify \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --certificate-identity-regexp '^https://github.com/PfisterFactor/rustic/\.github/workflows/podman-image\.yml@.+$' \
  "$PINNED"

# SPDX SBOM attestation.
cosign verify-attestation --type spdxjson \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --certificate-identity-regexp '^https://github.com/PfisterFactor/rustic/\.github/workflows/podman-image\.yml@.+$' \
  "$PINNED"
```

If either command exits non-zero, do not run the image.

## SBOMs — two attestations, two consumers

Two SBOM-like artifacts ride with each published image. Pick the one your policy
engine knows how to parse:

- **BuildKit SBOM/provenance attestations** (`provenance: mode=max`,
  `sbom: true` on `docker/build-push-action`) — attached to the registry
  manifest as in-toto attestations. Use these if your tooling already groks
  BuildKit's manifest attestations (cosign's
  `verify-attestation
  --type slsaprovenance` works against them;
  `crane manifest` shows them).
- **Explicit SPDX 2.3 JSON SBOM attestation** generated by Syft and attached via
  `cosign attest --type spdxjson`. This is what most policy engines (Kyverno,
  OPA Gatekeeper external data, in-toto policies) consume today. Verify with
  `cosign verify-attestation --type spdxjson`.

Both are kept up to date by the publish workflow; the explicit SPDX attestation
is the canonical one to pin against.

## Vulnerability scanning

CI runs `aquasecurity/trivy-action` against the pushed digest and fails the
workflow on HIGH or CRITICAL. There is no allow-list; if you need to ship a
known-vulnerable image, add a time-bound entry to `.trivyignore` with an owner
and an expiry date. No silent ignores.

## Building locally

```sh
# Run the tests inside the build (multi-arch via QEMU is supported but slow):
podman build \
  --file packaging/podman/Containerfile \
  --target runtime \
  --tag rustic-hardened:local .

# Run it with the recommended sandbox:
podman run --rm \
  --read-only --cap-drop=ALL --security-opt=no-new-privileges \
  --tmpfs /tmp --tmpfs /work \
  rustic-hardened:local --version
```

The integration suite under `packaging/podman/tests/` runs as part of the build
(in the `tester` stage). If you want to run only the tests against your local
development binary, you can:

```sh
# (Assumes /usr/local/bin/rustic is the binary under test.)
bash packaging/podman/tests/run.sh
```

The runtime-rootfs contract (`900_runtime_rootfs_contract.sh`) is a host-side
script — it does not exec into the rootfs it inspects.

## Threat model assumed by this image

This image is designed against an attacker who:

- has read-only access to the data being backed up (e.g. host snapshots),
- does **not** have a foothold on the host running the container,
- may control the destination repository (the image must not allow the attacker
  to escalate by writing a malicious repo file that, on the next backup, gets
  executed),
- may attempt to find a setuid binary, a shell, a network listener, or a package
  manager inside the running container to pivot from.

The runtime is therefore stripped of every such tool. Anything you add by
bind-mounting helpers (above) is your responsibility to harden separately.

## Reporting problems

Open an issue at <https://github.com/PfisterFactor/rustic/issues>. Include the
output of:

```sh
crane manifest "$IMAGE"
crane digest   "$IMAGE"
cosign verify  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
               --certificate-identity-regexp '^https://github.com/PfisterFactor/rustic/.+' "$PINNED"
```
