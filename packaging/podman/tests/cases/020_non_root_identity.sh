#!/usr/bin/env bash
#
# 020_non_root_identity — process runs as UID/GID 65532 and cannot write /etc.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

uid="$(id -u)"
gid="$(id -g)"
rt::log "uid=${uid} gid=${gid}"
assert_eq "65532" "${uid}" "uid is the hardened rustic user"
assert_eq "65532" "${gid}" "gid is the hardened rustic group"

# Writing to /etc must fail. We attempt to create a small sentinel; expect
# permission denied (or read-only filesystem inside the runtime image).
sentinel="/etc/rustic-tests-should-not-exist"
if : > "${sentinel}" 2>/dev/null; then
    rm -f -- "${sentinel}"
    __assert_fail "managed to write ${sentinel} as uid ${uid} — expected EACCES/EROFS"
fi
rt::log "writes to /etc correctly denied"

# Writing to /usr must also fail.
sentinel="/usr/rustic-tests-should-not-exist"
if : > "${sentinel}" 2>/dev/null; then
    rm -f -- "${sentinel}"
    __assert_fail "managed to write ${sentinel} as uid ${uid} — expected EACCES/EROFS"
fi
rt::log "writes to /usr correctly denied"

# rustic still runs cleanly as this user.
assert_exit_zero rt::rustic --version
