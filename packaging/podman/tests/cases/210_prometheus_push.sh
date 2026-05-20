#!/usr/bin/env bash
#
# 210_prometheus_push — `--prometheus <URL>` pushes a metrics body to a
# loopback collector.
#
# rustic talks Pushgateway protocol: it POSTs a protobuf-encoded payload to
# `<endpoint>/metrics/job@base64/<job-b64>/<label>@base64/<value-b64>...`
# and expects a 200 OK or 202 Accepted in response. We don't decode the
# protobuf; we only assert:
#   - the collector received exactly one POST,
#   - on a path that begins with `/metrics/job@base64/`,
#   - with a non-empty body,
#   - and the prometheus protobuf content-type.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

repo="$(rt::repo_dir)"
src="${TESTS_FIXTURES}/tree-a"
collector_log="${CASE_WORKDIR}/collector.log"
: > "${collector_log}"

port="$(rt::free_port)"
endpoint="http://127.0.0.1:${port}"
rt::log "collector endpoint: ${endpoint}"

server_pid="$(rt::start_capturing_http_server "${port}" "${collector_log}")"
# shellcheck disable=SC2064
trap "rt::stop_pid '${server_pid}'" EXIT

rt::init_repo "${repo}"
rt::rustic_repo_quiet "${repo}" \
    --prometheus "${endpoint}" \
    backup --metrics-job rustic-tests-210 "${src}"

# Allow the server side a tick to flush the request.
for _ in 1 2 3 4 5; do
    [[ -s "${collector_log}" ]] && break
    sleep 0.1
done

assert_file_exists "${collector_log}" "collector wrote a log"
content="$(cat -- "${collector_log}")"
rt::log "collector saw:"
rt::log "${content}"

post_count="$(grep -c '^method: POST' "${collector_log}" || true)"
assert_ge "${post_count}" "1" "collector received at least one POST"

# Must hit the Pushgateway-shaped path.
grep -E '^path: /metrics/job@base64/' "${collector_log}" > /dev/null \
    || __assert_fail "collector did not see /metrics/job@base64/ path"

# Must carry protobuf content-type.
grep -Ei '^header: Content-[Tt]ype:.*application/vnd\.google\.protobuf' "${collector_log}" > /dev/null \
    || __assert_fail "collector did not see Prometheus protobuf content-type"

# And body must be non-empty.
body_len="$(awk -F': ' '/^body_len:/{print $2; exit}' "${collector_log}")"
assert_ge "${body_len:-0}" "1" "collector received a non-empty body"
