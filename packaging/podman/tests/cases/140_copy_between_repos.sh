#!/usr/bin/env bash
#
# 140_copy_between_repos — `copy` snapshots from A to B and verify B holds
# the same logical content.
#
# Notes on what to assert:
#   - `copy` re-encrypts snapshot files in the target with the target's
#     key, so target snapshot ids differ from source ids by design.
#   - The invariant that survives is the snapshot's *tree* id, which
#     hashes the actual directory contents and is reproducible.
#   - We also let `copy --init` initialize the target with the source's
#     chunker parameters; independently `rustic init`-ing both repos
#     produces different random chunker polynomials and `copy` refuses
#     to bridge them (re-chunking is not implemented).

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo_a="$(rt::repo_dir)"
repo_b="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"

rt::init_repo "${repo_a}"
rt::rustic_repo_quiet "${repo_a}" backup "${src}"

cfg_dir="$(rt::mktmp config)"
export XDG_CONFIG_HOME="${cfg_dir}"
mkdir -p -- "${cfg_dir}/rustic"

cat > "${cfg_dir}/rustic/copy_source.toml" <<EOF
[repository]
repository = "${repo_a}"
password   = "${RUSTIC_PASSWORD}"
no-cache   = true

[copy]
targets = ["copy_target"]
EOF

cat > "${cfg_dir}/rustic/copy_target.toml" <<EOF
[repository]
repository = "${repo_b}"
password   = "${RUSTIC_PASSWORD}"
no-cache   = true
EOF

rt::rustic --group-by "" -P copy_source copy --init

a_count="$(rt::rustic_repo_quiet "${repo_a}" snapshots --json | jq 'length')"
b_count="$(rt::rustic_repo_quiet "${repo_b}" snapshots --json | jq 'length')"
assert_eq "${a_count}" "${b_count}" "target repo has the same number of snapshots as source"

a_trees="$(rt::rustic_repo_quiet "${repo_a}" snapshots --json | jq -r '.[].tree' | sort)"
b_trees="$(rt::rustic_repo_quiet "${repo_b}" snapshots --json | jq -r '.[].tree' | sort)"
rt::log "source trees: ${a_trees}"
rt::log "target trees: ${b_trees}"
assert_eq "${a_trees}" "${b_trees}" "target repo carries the same tree ids (i.e. content) as source"

# And the copied repo is still well-formed.
rt::rustic_repo_quiet "${repo_b}" check
