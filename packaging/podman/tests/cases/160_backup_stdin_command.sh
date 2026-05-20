#!/usr/bin/env bash
#
# 160_backup_stdin_command — `--stdin-command` runs a helper and pipes its
# stdout into the snapshot.
#
# This case runs only in the tester stage. The hardened runtime image is
# shell-free and `rustic` cannot exec arbitrary command strings there.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
rt::init_repo "${repo}"

# Pin the helper to absolute paths so the test does not rely on PATH.
rt::rustic_repo_quiet "${repo}" backup \
    --stdin-filename "case160.txt" \
    --stdin-command "/usr/bin/printf case160-from-command" \
    -

out_file="${CASE_WORKDIR}/dumped.txt"
rt::rustic_repo_quiet "${repo}" dump "latest:case160.txt" --file "${out_file}"
got="$(cat -- "${out_file}")"
assert_eq "case160-from-command" "${got}" "stdin-command output round-trips"
