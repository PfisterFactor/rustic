#!/usr/bin/env bash
#
# 040_check_integrity — `rustic check --read-data` against a freshly built repo.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"

rt::init_repo "${repo}"
rt::rustic_repo_quiet "${repo}" backup "${src}"

# `--read-data` exercises pack decryption + content hash verification.
rt::rustic_repo_quiet "${repo}" check --read-data

# Also verify the smaller (metadata-only) check passes.
rt::rustic_repo_quiet "${repo}" check
