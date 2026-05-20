#!/usr/bin/env bash
#
# 220_json_output — `--json` on snapshots, ls, repoinfo yields jq-parseable
# output.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"

rt::init_repo "${repo}"
rt::rustic_repo_quiet "${repo}" backup "${src}"

snaps_json="$(rt::rustic_repo_quiet "${repo}" snapshots --json)"
assert_json "${snaps_json}" "snapshots --json"
assert_ge "$(printf '%s' "${snaps_json}" | jq 'length')" "1" "at least one snapshot"

ls_json="$(rt::rustic_repo_quiet "${repo}" ls --recursive --json latest)"
assert_json "${ls_json}" "ls --json"
assert_ge "$(printf '%s' "${ls_json}" | jq 'length')" "1" "at least one ls entry"

info_json="$(rt::rustic_repo_quiet "${repo}" repoinfo --json)"
assert_json "${info_json}" "repoinfo --json"

# Make sure each is non-empty / has at least one top-level key.
info_keys="$(printf '%s' "${info_json}" | jq -r 'keys | join(",")')"
assert_ne "" "${info_keys}" "repoinfo --json non-empty"
