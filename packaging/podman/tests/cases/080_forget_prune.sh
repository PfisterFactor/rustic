#!/usr/bin/env bash
#
# 080_forget_prune — forget all but the latest, prune, verify the repo
# still checks clean and the snapshot count went down.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src_a="${TESTS_FIXTURES}/tree-a"
src_b="${TESTS_FIXTURES}/tree-b"

rt::init_repo "${repo}"
rt::rustic_repo_quiet "${repo}" backup "${src_a}"
rt::rustic_repo_quiet "${repo}" backup "${src_b}"

before="$(rt::rustic_repo_quiet "${repo}" snapshots --json | jq 'length')"
assert_eq "2" "${before}" "two snapshots before forget"

# Keep only the most recent.
rt::rustic_repo_quiet "${repo}" forget --keep-last 1 --prune

after="$(rt::rustic_repo_quiet "${repo}" snapshots --json | jq 'length')"
assert_eq "1" "${after}" "one snapshot remains after forget --keep-last 1 --prune"

# Repository still checks clean.
rt::rustic_repo_quiet "${repo}" check
