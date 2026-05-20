#!/usr/bin/env bash
#
# 180_hooks — global/repository/backup hooks all fire and create sentinels.
#
# Runs only in the tester stage; the hardened runtime image cannot exec
# /usr/bin/touch because there is no /usr/bin/touch (no coreutils).

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"
sentinel_dir="$(rt::mktmp sentinels)"

export RUSTIC_HOOKS_REPO="${repo}"
export RUSTIC_SENTINEL_DIR="${sentinel_dir}"

cfg_dir="$(rt::mktmp config)"
export XDG_CONFIG_HOME="${cfg_dir}"
install -Dm0644 "${TESTS_FIXTURES}/hooks.toml" \
    "${cfg_dir}/rustic/hooks.toml"

# `--init` lets backup create the repo on first run, so we don't have to
# duplicate the profile substitution work for an explicit `init` call.
rt::rustic -P hooks --profile-substitute-env backup --init "${src}"

for sentinel in global_before global_after repo_before repo_after backup_before backup_after; do
    assert_file_exists "${sentinel_dir}/${sentinel}" \
        "hook sentinel ${sentinel} was created"
done
