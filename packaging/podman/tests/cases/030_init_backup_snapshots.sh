#!/usr/bin/env bash
#
# 030_init_backup_snapshots — init a repo, back up tree-a, list snapshots.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"

rt::log "repo: ${repo}"
rt::log "src:  ${src}"

rt::init_repo "${repo}"
assert_file_exists "${repo}/config" "repo config file"

# First backup; produce a snapshot from tree-a.
rt::rustic_repo_quiet "${repo}" backup "${src}"

# `snapshots --json` returns a JSON array of SnapshotFile objects.
snaps_json="$(rt::rustic_repo_quiet "${repo}" snapshots --json)"
assert_json "${snaps_json}" "snapshots --json output"

count="$(printf '%s' "${snaps_json}" | jq 'length')"
assert_eq "1" "${count}" "exactly one snapshot present"

# The snapshot must reference our backed-up source path.
ids_json="$(printf '%s' "${snaps_json}" | jq -r '.[0].paths | join(",")')"
assert_contains "${ids_json}" "${src}" "snapshot references the source path"

snap_id="$(printf '%s' "${snaps_json}" | jq -r '.[0].id')"
case "${snap_id}" in
    [0-9a-f]*) rt::log "snapshot id ${snap_id}" ;;
    *) __assert_fail "snapshot id is not hex-shaped: ${snap_id}" ;;
esac
