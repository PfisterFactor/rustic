#!/usr/bin/env bash
#
# 100_find_and_tag — locate a known path with `find` and verify `tag --add`
# attaches the tag to the snapshot record.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"

rt::init_repo "${repo}"
rt::rustic_repo_quiet "${repo}" backup "${src}"

# `find --glob 'alpha.txt'` should report the file in the latest snapshot.
assert_exit_zero rt::rustic_repo_quiet "${repo}" find --glob 'alpha.txt'
find_text="${ASSERT_OUTPUT}"
assert_contains "${find_text}" "alpha.txt" "find locates alpha.txt"

# Tag the snapshot and verify the tag landed.
rt::rustic_repo_quiet "${repo}" tag --add "case100-tag" latest

snaps="$(rt::rustic_repo_quiet "${repo}" snapshots --json)"
tags="$(printf '%s' "${snaps}" | jq -r '.[0].tags | join(",")')"
rt::log "snapshot tags: ${tags}"
assert_contains "${tags}" "case100-tag" "snapshot record carries the new tag"
