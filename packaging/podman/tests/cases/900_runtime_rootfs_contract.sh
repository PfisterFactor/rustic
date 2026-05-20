#!/usr/bin/env bash
#
# 900_runtime_rootfs_contract — assert that an assembled rustic-hardened
# rootfs does not ship anything that would compromise the runtime sandbox.
#
# This script is *host-side*: it takes a rootfs path on argv ($1) and uses
# the host's bash/find/stat/grep to inspect it. It never `chroot`s or
# `exec`s into the rootfs (which deliberately has no shell).
#
# It is invoked twice across the build:
#   - In the `runtime-rootfs` stage of packaging/podman/Containerfile,
#     against the assembled `/rootfs`. Failure there hard-fails the image
#     build, before the `runtime` stage even starts.
#   - In CI (.github/workflows/podman-image.yml), against the unpacked
#     rootfs of the final published image (via `podman image mount`).
#
# This script intentionally has the simplest possible dependency surface
# (bash + coreutils + find + grep) so it can run inside the bare Fedora
# stage in the build and in a vanilla Ubuntu runner in CI.

set -euo pipefail

usage() {
    cat <<EOF >&2
usage: $0 <rootfs-path>

Asserts that <rootfs-path> matches the hardened-runtime contract:
  - no shell (sh, bash, dash, zsh, ksh, ash) entry under /bin or /usr/bin
  - no package-manager entry (dnf, dnf5, microdnf, yum, rpm)
  - no useradd / groupadd / usermod / groupmod
  - no setuid or setgid files anywhere under rootfs
  - /etc/passwd contains rustic:x:65532:65532:
  - /etc/group contains rustic:x:65532:
EOF
    exit 2
}

if (( $# != 1 )); then
    usage
fi

ROOTFS="$1"

if [[ ! -d "${ROOTFS}" ]]; then
    printf 'FATAL: %s is not a directory\n' "${ROOTFS}" >&2
    exit 2
fi

# Resolve to a real path so relative inputs (e.g. "./rootfs") work.
ROOTFS="$(cd -- "${ROOTFS}" && pwd -P)"

fail_count=0
log() {
    printf '[rootfs-contract] %s\n' "$*"
}
fail() {
    printf '[rootfs-contract] FAIL: %s\n' "$*" >&2
    fail_count=$((fail_count + 1))
}

log "inspecting rootfs at ${ROOTFS}"

# 1. Banned absolute paths — these must not exist (regular files, symlinks,
#    or anything else).
BANNED_PATHS=(
    # shells
    /bin/sh /bin/bash /bin/dash /bin/ash /bin/zsh /bin/ksh /bin/csh /bin/tcsh
    /usr/bin/sh /usr/bin/bash /usr/bin/dash /usr/bin/ash /usr/bin/zsh
    /usr/bin/ksh /usr/bin/csh /usr/bin/tcsh
    /sbin/sh /usr/sbin/sh
    # busybox would expose every shell tool via multicall
    /bin/busybox /usr/bin/busybox
    # package managers
    /usr/bin/dnf /usr/bin/dnf-3 /usr/bin/dnf5 /usr/bin/microdnf
    /usr/bin/yum /usr/bin/rpm /usr/bin/dpkg /usr/bin/apt /usr/bin/apt-get
    /bin/dnf /bin/dnf5 /bin/rpm /bin/yum
    # user/group management
    /usr/sbin/useradd /usr/sbin/groupadd /usr/sbin/usermod /usr/sbin/groupmod
    /sbin/useradd /sbin/groupadd
    # compilers / interpreters we don't ship
    /usr/bin/gcc /usr/bin/cc /usr/bin/g++ /usr/bin/clang
    /usr/bin/python3 /usr/bin/python /usr/bin/perl
    # SSH client/server should not be in here
    /usr/bin/ssh /usr/bin/scp /usr/sbin/sshd
    # cron / at would let an attacker schedule things
    /usr/sbin/crond /usr/bin/at
)

for p in "${BANNED_PATHS[@]}"; do
    full="${ROOTFS}${p}"
    if [[ -e "${full}" ]] || [[ -L "${full}" ]]; then
        # If it's a dangling symlink, [[ -e ... ]] is false; [[ -L ... ]] catches it.
        fail "banned path present: ${p}"
    fi
done

# 2. No setuid or setgid files anywhere.
#    `find -perm /6000` matches either bit; -xdev keeps us on the single fs.
mapfile -t setid_hits < <(find "${ROOTFS}" -xdev \( -type f -o -type l \) -perm /6000 -print)
if (( ${#setid_hits[@]} > 0 )); then
    for hit in "${setid_hits[@]}"; do
        fail "setuid/setgid bit on ${hit#"${ROOTFS}"}"
    done
fi

# 3. /etc/passwd and /etc/group must have the rustic entry exactly.
passwd="${ROOTFS}/etc/passwd"
group="${ROOTFS}/etc/group"
if [[ ! -f "${passwd}" ]]; then
    fail "missing /etc/passwd"
else
    if ! grep -qE '^rustic:x:65532:65532:' "${passwd}"; then
        fail "/etc/passwd does not contain a rustic:x:65532:65532: entry"
    fi
    # Make sure we don't also ship the system users that the dnf install
    # closure tends to drag in. Allow only root + rustic.
    while IFS= read -r line; do
        case "${line}" in
            ''|'#'*) continue ;;
            root:*|rustic:*) continue ;;
            *)
                user="${line%%:*}"
                fail "unexpected /etc/passwd entry: ${user}"
                ;;
        esac
    done < "${passwd}"
fi

if [[ ! -f "${group}" ]]; then
    fail "missing /etc/group"
else
    if ! grep -qE '^rustic:x:65532:' "${group}"; then
        fail "/etc/group does not contain a rustic:x:65532: entry"
    fi
    while IFS= read -r line; do
        case "${line}" in
            ''|'#'*) continue ;;
            root:*|rustic:*) continue ;;
            *)
                grp="${line%%:*}"
                fail "unexpected /etc/group entry: ${grp}"
                ;;
        esac
    done < "${group}"
fi

# 4. The rustic binary must be present and executable.
RUSTIC="${ROOTFS}/usr/local/bin/rustic"
if [[ ! -x "${RUSTIC}" ]]; then
    fail "missing or non-executable /usr/local/bin/rustic"
fi

# 5. /etc/shadow must NOT exist — we don't manage passwords in this image,
#    and shadow's mode-0000 file is a red flag for "shadow-utils landed".
if [[ -e "${ROOTFS}/etc/shadow" ]]; then
    fail "/etc/shadow exists — shadow-utils probably leaked into the image"
fi

# 6. License files must be present.
for lic in LICENSE-APACHE LICENSE-MIT; do
    if [[ ! -f "${ROOTFS}/usr/share/licenses/rustic/${lic}" ]]; then
        fail "missing /usr/share/licenses/rustic/${lic}"
    fi
done

if (( fail_count > 0 )); then
    printf '[rootfs-contract] %d violation(s) — image build rejected.\n' \
        "${fail_count}" >&2
    exit 1
fi

log "all checks passed for ${ROOTFS}"
