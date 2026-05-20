#!/usr/bin/env bash
#
# 090_dump_and_diff — `dump` returns byte-equal content; `diff` between two
# snapshots reports differences in the modified file.

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
sleep 1  # ensure snap-b sorts strictly after snap-a
rt::rustic_repo_quiet "${repo}" backup "${src_b}"

# dump latest:<full path> should byte-match the source file.
dump_dest="${CASE_WORKDIR}/beta.dump.bin"
rt::rustic_repo_quiet "${repo}" dump "latest:${src_b}/nested/beta.bin" \
    --file "${dump_dest}"
assert_file_eq "${src_b}/nested/beta.bin" "${dump_dest}" \
    "dump produces byte-equal content"

# diff between the two snapshots should mention alpha.txt (modified) and
# gamma.txt (added). We compare snap-a:src_a against snap-b:src_b by id.
snaps="$(rt::rustic_repo_quiet "${repo}" snapshots --json)"
id_a="$(printf '%s' "${snaps}" | jq -r '.[0].id')"
id_b="$(printf '%s' "${snaps}" | jq -r '.[1].id')"
rt::log "diffing ${id_a} -> ${id_b}"

assert_exit_zero rt::rustic_repo_quiet "${repo}" diff \
    "${id_a}:${src_a}" "${id_b}:${src_b}"
diff_text="${ASSERT_OUTPUT}"
assert_contains "${diff_text}" "alpha.txt"  "diff mentions modified alpha.txt"
assert_contains "${diff_text}" "gamma.txt"  "diff mentions added gamma.txt"
