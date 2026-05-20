# shellcheck shell=bash
#
# Runtime helpers for the rustic-hardened integration suite.
#
# Conventions:
# - All exported helpers use the `rt::` prefix to namespace them.
# - Cases are expected to source assert.sh and runtime.sh themselves; the
#   orchestrator also pre-sources them so cases inherit the common env.
# - All paths are absolute. All tmpdirs live under ${CASE_WORKDIR}.

# Guard against double-source.
if [[ "${__RUSTIC_TEST_RUNTIME_SOURCED:-}" == "1" ]]; then
    return 0
fi
__RUSTIC_TEST_RUNTIME_SOURCED=1

# Strict bash for whoever sources us.
set -o errtrace
set -o pipefail

# --- logging ----------------------------------------------------------------

rt::log() {
    printf '[%s] %s\n' "${CASE_NAME:-runner}" "$*"
}

rt::header() {
    printf '\n=== %s ===\n' "$*"
}

rt::die() {
    rt::log "FATAL: $*" >&2
    exit 1
}

# --- workspace --------------------------------------------------------------

# rt::mktmp [name]
#   Make a per-case tmpdir under ${CASE_WORKDIR}. Returns the absolute path on
#   stdout. The dir is created with mode 0700 and inherits the caller's uid.
rt::mktmp() {
    local prefix="${1:-tmp}"
    local d
    d="$(mktemp -d -- "${CASE_WORKDIR:-/tmp}/${prefix}.XXXXXX")"
    chmod 0700 -- "${d}"
    printf '%s\n' "${d}"
}

# rt::repo_dir
#   Make a per-case rustic repository directory. Returns the path on stdout.
rt::repo_dir() {
    rt::mktmp repo
}

# rt::scratch_dir
#   Make a per-case scratch / restore directory. Returns the path on stdout.
rt::scratch_dir() {
    rt::mktmp scratch
}

# --- rustic invocation ------------------------------------------------------

# rt::rustic <args...>
#   Invoke the rustic binary under test with the given args. Honors
#   RUSTIC_BIN; cases should never call /usr/local/bin/rustic directly so
#   the host-side runner can override.
rt::rustic() {
    "${RUSTIC_BIN}" "$@"
}

# rt::rustic_quiet <args...>
#   Same, but suppress info-level chatter so case asserts have clean output.
rt::rustic_quiet() {
    "${RUSTIC_BIN}" --log-level warn "$@"
}

# rt::rustic_repo <repo> <args...>
#   Invoke rustic against a specific repo directory. Defaults to no
#   grouping so `snapshots --json` returns a flat array per the
#   single-group branch in src/commands/snapshots.rs.
rt::rustic_repo() {
    local repo="$1"
    shift
    "${RUSTIC_BIN}" -r "${repo}" --no-cache --group-by "" "$@"
}

# rt::rustic_repo_quiet <repo> <args...>
rt::rustic_repo_quiet() {
    local repo="$1"
    shift
    "${RUSTIC_BIN}" --log-level warn -r "${repo}" --no-cache --group-by "" "$@"
}

# rt::init_repo <repo>
#   Initialize a repo at <repo>. Password comes from RUSTIC_PASSWORD env.
rt::init_repo() {
    local repo="$1"
    rt::rustic_repo_quiet "${repo}" init
}


# --- network helpers --------------------------------------------------------

# rt::free_port
#   Print an unused TCP port number on 127.0.0.1.
rt::free_port() {
    python3 -c '
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
'
}

# rt::start_capturing_http_server <port> <log_path>
#   Start a small python HTTP server that accepts any POST/PUT/GET on any
#   path, dumps the path + headers + body bytes to <log_path>, and replies
#   202 Accepted. Returns the server's PID on stdout.
rt::start_capturing_http_server() {
    local port="$1"
    local log_path="$2"
    # Background the python listener with stdout/stderr/stdin detached so the
    # caller's command substitution `$(rt::start_capturing_http_server ...)`
    # doesn't hang waiting for the long-lived python process to release the
    # inherited pipe.
    python3 - "${port}" "${log_path}" > /dev/null 2>&1 <<'PY' &
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
LOG_PATH = sys.argv[2]

class Capture(BaseHTTPRequestHandler):
    def log_message(self, *args, **kwargs):
        return  # silence default logging

    def _accept(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        with open(LOG_PATH, "ab") as fh:
            fh.write(b"--- request ---\n")
            fh.write(f"method: {self.command}\n".encode())
            fh.write(f"path: {self.path}\n".encode())
            for k, v in self.headers.items():
                fh.write(f"header: {k}: {v}\n".encode())
            fh.write(f"body_len: {len(body)}\n".encode())
            fh.write(b"body_b64: ")
            import base64
            fh.write(base64.b64encode(body) + b"\n")
        self.send_response(202)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        self._accept()

    def do_POST(self):
        self._accept()

    def do_PUT(self):
        self._accept()

HTTPServer(("127.0.0.1", PORT), Capture).serve_forever()
PY
    local pid=$!
    # Give it a moment to bind, but cap the wait so a hung server doesn't
    # silently lock the test for its full timeout.
    local n=0
    while ! (echo > "/dev/tcp/127.0.0.1/${port}") 2>/dev/null; do
        n=$((n + 1))
        if (( n > 50 )); then
            kill -9 "${pid}" 2>/dev/null || true
            rt::die "capturing http server did not bind on 127.0.0.1:${port}"
        fi
        sleep 0.05
    done
    printf '%s\n' "${pid}"
}

# rt::stop_pid <pid>
#   Kill a background pid if it's still running. No-op if it isn't.
rt::stop_pid() {
    local pid="$1"
    [[ -z "${pid}" ]] && return 0
    kill "${pid}" 2>/dev/null || true
    # Give it a tick to exit cleanly.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "${pid}" 2>/dev/null || return 0
        sleep 0.05
    done
    kill -9 "${pid}" 2>/dev/null || true
}
