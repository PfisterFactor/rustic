#!/usr/bin/env bash
#
# 070_backup_dedup — backing up the same tree twice should reuse existing
# packs. We measure on-disk size of the repository's data/ tree before and
# after the second backup; dedup means the growth must be far smaller than
# the original payload.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"

# Size of the source tree in bytes — used as a sanity floor below.
src_bytes="$(du -sb -- "${src}" | awk '{print $1}')"
rt::log "source bytes: ${src_bytes}"

rt::init_repo "${repo}"
rt::rustic_repo_quiet "${repo}" backup "${src}"

bytes1="$(du -sb -- "${repo}/data" | awk '{print $1}')"
rt::log "data/ after first backup:  ${bytes1}"

# Sanity: the first backup wrote at least a meaningful fraction of the
# source into the repo (encrypted+packed, so not equal but >= a few kB).
assert_ge "${bytes1}" "1024" "first backup wrote at least 1 KiB of data"

# Second backup of the identical tree.
rt::rustic_repo_quiet "${repo}" backup "${src}"

bytes2="$(du -sb -- "${repo}/data" | awk '{print $1}')"
rt::log "data/ after second backup: ${bytes2}"

growth=$((bytes2 - bytes1))
rt::log "growth: ${growth} bytes"

# A second backup of an identical tree must NOT double the data dir. We
# allow a small per-snapshot bookkeeping growth (a few hundred bytes) but
# nothing close to the original payload.
limit=$((src_bytes / 4))
if (( growth >= limit )); then
    __assert_fail "dedup failed: data/ grew by ${growth} bytes (>= ${limit})"
fi

# And the snapshot count went up.
snap_count="$(rt::rustic_repo_quiet "${repo}" snapshots --json | jq 'length')"
assert_eq "2" "${snap_count}" "two snapshots present after second backup"

# repoinfo --json still parses; we don't pin its inner shape because that
# is rustic_core's contract.
info_json="$(rt::rustic_repo_quiet "${repo}" repoinfo --json)"
assert_json "${info_json}" "repoinfo --json parses"
