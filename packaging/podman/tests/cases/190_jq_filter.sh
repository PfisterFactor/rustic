#!/usr/bin/env bash
#
# 190_jq_filter — `--filter-jq` is a snapshot-filter expression that returns
# a bool. Verify it accepts a real predicate AND eliminates the snapshot
# when the predicate is false.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src_a="${TESTS_FIXTURES}/tree-a"
src_b="${TESTS_FIXTURES}/tree-b"

rt::init_repo "${repo}"

# Two snapshots with different tags so a jq predicate can distinguish them.
rt::rustic_repo_quiet "${repo}" backup --tag jq-keep   "${src_a}"
rt::rustic_repo_quiet "${repo}" backup --tag jq-drop   "${src_b}"

# Baseline: no filter -> two snapshots.
baseline="$(rt::rustic_repo_quiet "${repo}" snapshots --json | jq 'length')"
assert_eq "2" "${baseline}" "baseline lists both snapshots"

# Predicate that keeps only the "jq-keep"-tagged snapshot.
keep_only="$(rt::rustic_repo_quiet "${repo}" --filter-jq '.tags | index("jq-keep") != null' snapshots --json | jq 'length')"
assert_eq "1" "${keep_only}" "filter-jq keeps a single snapshot"

keep_tag="$(rt::rustic_repo_quiet "${repo}" --filter-jq '.tags | index("jq-keep") != null' snapshots --json | jq -r '.[0].tags | join(",")')"
assert_contains "${keep_tag}" "jq-keep" "filter-jq kept the right snapshot"

# A predicate that's always false yields no snapshots.
none="$(rt::rustic_repo_quiet "${repo}" --filter-jq 'false' snapshots --json | jq 'length')"
assert_eq "0" "${none}" "filter-jq 'false' eliminates all snapshots"
