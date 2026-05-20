#!/usr/bin/env bash
#
# 170_excludes — `backup --glob '!*.log'` skips matching files.
#
# rustic uses gitignore-style globs through the local-source filter:
#   - "*.log" includes; "!*.log" excludes.
# We back up a tree containing a .log file and assert the file is absent
# from the resulting snapshot via `ls --recursive`.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

src="$(rt::mktmp source-with-log)"
printf 'keep me\n'  > "${src}/keep.txt"
printf 'discard me\n' > "${src}/discard.log"

repo="$(rt::repo_dir)"
rt::init_repo "${repo}"

# `--glob '!*.log'` translates to "exclude every .log file" through
# rustic_core's LocalSource filter.
rt::rustic_repo_quiet "${repo}" backup --glob '!*.log' "${src}"

listing="$(rt::rustic_repo_quiet "${repo}" ls --recursive latest)"
assert_contains "${listing}"    "keep.txt"    "kept file survived backup"
assert_not_contains "${listing}" "discard.log" "excluded .log file is absent"
