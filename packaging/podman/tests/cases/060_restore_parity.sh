#!/usr/bin/env bash
#
# 060_restore_parity — restore a snapshot and compare it byte-for-byte
# against the source tree.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"
dest="$(rt::scratch_dir)"

rt::init_repo "${repo}"
rt::rustic_repo_quiet "${repo}" backup "${src}"

# Restore "latest:<src>" into ${dest}. Rustic preserves the absolute path
# inside the snapshot, so restoring "latest:${src}" lands the tree at the
# given destination root (it does NOT recreate the absolute path under it).
rt::rustic_repo_quiet "${repo}" restore "latest:${src}" "${dest}"

# A few specific spot checks first.
assert_file_eq "${src}/alpha.txt"            "${dest}/alpha.txt"
assert_file_eq "${src}/nested/beta.bin"      "${dest}/nested/beta.bin"
assert_file_eq "${src}/unicode-名前.txt"     "${dest}/unicode-名前.txt"

# Then full recursive parity.
assert_dirs_eq "${src}" "${dest}" "restored tree matches source"
