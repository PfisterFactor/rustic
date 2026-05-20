#!/usr/bin/env bash
#
# 110_repoinfo — `repoinfo --json` parses and reports a non-empty snapshot
# of the repository. We deliberately do NOT pin the inner shape — that is
# rustic_core's contract and changes with releases. We just assert the
# output parses and is non-empty.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"

rt::init_repo "${repo}"
rt::rustic_repo_quiet "${repo}" backup "${src}"

info="$(rt::rustic_repo_quiet "${repo}" repoinfo --json)"
assert_json "${info}" "repoinfo --json output"

# Non-empty object.
keys="$(printf '%s' "${info}" | jq -r 'keys | join(",")')"
rt::log "repoinfo --json top-level keys: ${keys}"
assert_ne "" "${keys}" "repoinfo --json carries at least one top-level key"

# Variants must also parse.
files_only="$(rt::rustic_repo_quiet "${repo}" repoinfo --json --only-files)"
assert_json "${files_only}" "repoinfo --json --only-files output"

index_only="$(rt::rustic_repo_quiet "${repo}" repoinfo --json --only-index)"
assert_json "${index_only}" "repoinfo --json --only-index output"
