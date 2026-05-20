#!/usr/bin/env bash
#
# 150_backup_stdin — `rustic backup -` reads its source from stdin.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"

rt::init_repo "${repo}"
payload="case150-payload"
printf '%s' "${payload}" | rt::rustic_repo_quiet "${repo}" backup \
    --stdin-filename "case150.txt" -

# Verify the snapshot exists and the dump of latest:case150.txt matches.
out_file="${CASE_WORKDIR}/dumped.txt"
rt::rustic_repo_quiet "${repo}" dump "latest:case150.txt" --file "${out_file}"
got="$(cat -- "${out_file}")"
assert_eq "${payload}" "${got}" "stdin payload round-trips through backup/dump"
