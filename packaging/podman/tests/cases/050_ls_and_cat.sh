#!/usr/bin/env bash
#
# 050_ls_and_cat — list files in latest snapshot and dump the snapshot record.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"

rt::init_repo "${repo}"
rt::rustic_repo_quiet "${repo}" backup "${src}"

# `ls latest --recursive --json` emits a single JSON array of path strings,
# one entry per visited node.
ls_json="$(rt::rustic_repo_quiet "${repo}" ls --recursive --json latest)"
assert_json "${ls_json}" "ls --json output"

count="$(printf '%s' "${ls_json}" | jq 'length')"
assert_ge "${count}" "4" "ls walks at least four entries (alpha + nested + unicode + symlinks)"

paths="$(printf '%s' "${ls_json}" | jq -r '.[]')"
assert_contains "${paths}" "alpha.txt"     "ls lists alpha.txt"
assert_contains "${paths}" "beta.bin"      "ls lists beta.bin"
assert_contains "${paths}" "unicode-名前.txt" "ls lists unicode file"

# `cat snapshot <id>` returns the SnapshotFile as JSON.
snaps_json="$(rt::rustic_repo_quiet "${repo}" snapshots --json)"
snap_id="$(printf '%s' "${snaps_json}" | jq -r '.[0].id')"
cat_out="$(rt::rustic_repo_quiet "${repo}" cat snapshot "${snap_id}")"
assert_json "${cat_out}" "cat snapshot JSON"

# The dumped snapshot should reference our source path.
src_in_cat="$(printf '%s' "${cat_out}" | jq -r '.paths | join(",")')"
assert_contains "${src_in_cat}" "${src}" "cat snapshot mentions source path"
