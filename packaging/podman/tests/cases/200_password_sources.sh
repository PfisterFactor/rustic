#!/usr/bin/env bash
#
# 200_password_sources — `--password-file`, `RUSTIC_PASSWORD`, and
# `--password-command` all succeed for the same repository.
#
# Important: --password (RUSTIC_PASSWORD env) is mutually exclusive with
# --password-file and --password-command at the clap level. We `env -u` the
# inherited RUSTIC_PASSWORD before each variant that should source the
# password from somewhere else.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"

pw_file="${CASE_WORKDIR}/password"
printf '%s\n' "${RUSTIC_PASSWORD}" > "${pw_file}"
chmod 0600 -- "${pw_file}"

pw_cmd="${CASE_WORKDIR}/get-password.sh"
cat > "${pw_cmd}" <<EOF
#!/bin/sh
exec /usr/bin/printf '%s\n' '${RUSTIC_PASSWORD}'
EOF
chmod 0755 -- "${pw_cmd}"

# (1) init + backup via --password-file (no RUSTIC_PASSWORD in env).
rt::log "init via --password-file"
env -u RUSTIC_PASSWORD \
    "${RUSTIC_BIN}" --log-level warn -r "${repo}" --no-cache --group-by "" \
        --password-file "${pw_file}" init

rt::log "backup via --password-file"
env -u RUSTIC_PASSWORD \
    "${RUSTIC_BIN}" --log-level warn -r "${repo}" --no-cache --group-by "" \
        --password-file "${pw_file}" backup "${src}"

# (2) RUSTIC_PASSWORD env var alone (no --password-file).
rt::log "snapshots via RUSTIC_PASSWORD env"
env_only_out="$(env -i \
        HOME="${HOME}" XDG_CACHE_HOME="${XDG_CACHE_HOME:-}" PATH="/usr/local/bin:/usr/bin:/bin" \
        RUSTIC_PASSWORD="${RUSTIC_PASSWORD}" \
        "${RUSTIC_BIN}" --log-level warn -r "${repo}" --no-cache --group-by "" snapshots --json)"
assert_json "${env_only_out}" "snapshots --json under RUSTIC_PASSWORD"
assert_ge "$(printf '%s' "${env_only_out}" | jq 'length')" "1" \
    "RUSTIC_PASSWORD env alone opens the repo"

# (3) --password-command running the helper script.
rt::log "snapshots via --password-command"
env -u RUSTIC_PASSWORD \
    "${RUSTIC_BIN}" --log-level warn -r "${repo}" --no-cache --group-by "" \
        --password-command "${pw_cmd}" snapshots > /dev/null
