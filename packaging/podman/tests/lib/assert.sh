# shellcheck shell=bash
#
# Assertion helpers for the rustic-hardened integration suite.
#
# All assertions exit the calling script non-zero on failure with a clear
# message including the test case name.

if [[ "${__RUSTIC_TEST_ASSERT_SOURCED:-}" == "1" ]]; then
    return 0
fi
__RUSTIC_TEST_ASSERT_SOURCED=1

__assert_fail() {
    printf '[%s] ASSERT FAIL: %s\n' "${CASE_NAME:-runner}" "$*" >&2
    # Surface a backtrace to help diagnose which check fired.
    local i=0
    local f l n
    while caller $i > /dev/null 2>&1; do
        # caller prints: <line> <func> <file>
        read -r l n f < <(caller $i)
        printf '    at %s:%s (%s)\n' "${f}" "${l}" "${n}" >&2
        i=$((i + 1))
    done
    exit 1
}

# assert_eq <expected> <actual> [message]
assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-equality}"
    if [[ "${expected}" != "${actual}" ]]; then
        __assert_fail "${msg}: expected [${expected}] actual [${actual}]"
    fi
}

# assert_ne <a> <b> [message]
assert_ne() {
    local a="$1"
    local b="$2"
    local msg="${3:-inequality}"
    if [[ "${a}" == "${b}" ]]; then
        __assert_fail "${msg}: both values were [${a}]"
    fi
}

# assert_contains <haystack> <needle> [message]
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-substring}"
    case "${haystack}" in
        *"${needle}"*) return 0 ;;
        *) __assert_fail "${msg}: [${needle}] not found in [${haystack}]" ;;
    esac
}

# assert_not_contains <haystack> <needle> [message]
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-no-substring}"
    case "${haystack}" in
        *"${needle}"*) __assert_fail "${msg}: [${needle}] unexpectedly found in [${haystack}]" ;;
        *) return 0 ;;
    esac
}

# assert_file_exists <path> [message]
assert_file_exists() {
    local path="$1"
    local msg="${2:-file exists}"
    [[ -e "${path}" ]] || __assert_fail "${msg}: ${path} does not exist"
}

# assert_file_missing <path> [message]
assert_file_missing() {
    local path="$1"
    local msg="${2:-file missing}"
    [[ ! -e "${path}" ]] || __assert_fail "${msg}: ${path} unexpectedly exists"
}

# assert_file_eq <a> <b> [message]
#   Byte-equal compare two files. Uses cmp so 0/non-0 maps directly.
assert_file_eq() {
    local a="$1"
    local b="$2"
    local msg="${3:-byte-equal}"
    cmp -s -- "${a}" "${b}" || __assert_fail "${msg}: ${a} != ${b}"
}

# assert_dirs_eq <a> <b> [message]
#   Recursive content comparison via diff -r --no-dereference.
assert_dirs_eq() {
    local a="$1"
    local b="$2"
    local msg="${3:-dir-equal}"
    local out
    if ! out="$(diff -r --no-dereference -- "${a}" "${b}" 2>&1)"; then
        __assert_fail "${msg}: ${a} != ${b}: ${out}"
    fi
}

# assert_exit_zero <command...>
#   Run a command; fail if exit non-zero. Stdout/stderr is captured to a
#   variable available to the caller as ASSERT_OUTPUT.
export ASSERT_OUTPUT=""
assert_exit_zero() {
    local out rc
    out="$("$@" 2>&1)" || rc=$?
    rc="${rc:-0}"
    ASSERT_OUTPUT="${out}"
    if (( rc != 0 )); then
        __assert_fail "expected exit 0 from [$*], got ${rc}: ${out}"
    fi
}

# assert_exit_nonzero <command...>
#   Run a command; fail if exit zero. ASSERT_OUTPUT carries combined output.
assert_exit_nonzero() {
    local out rc
    out="$("$@" 2>&1)" || rc=$?
    rc="${rc:-0}"
    ASSERT_OUTPUT="${out}"
    if (( rc == 0 )); then
        __assert_fail "expected non-zero exit from [$*], got 0: ${out}"
    fi
}

# assert_json <string> [message]
#   Verify <string> parses as JSON via jq.
assert_json() {
    local s="$1"
    local msg="${2:-valid json}"
    if ! printf '%s' "${s}" | jq -e . > /dev/null 2>&1; then
        __assert_fail "${msg}: not parseable as json:\n${s}"
    fi
}

# assert_json_file <path> [message]
assert_json_file() {
    local path="$1"
    local msg="${2:-valid json file}"
    if ! jq -e . < "${path}" > /dev/null 2>&1; then
        __assert_fail "${msg}: ${path} not parseable as json"
    fi
}

# assert_ge <actual> <minimum> [message]
assert_ge() {
    local actual="$1"
    local minimum="$2"
    local msg="${3:-numeric ge}"
    if (( actual < minimum )); then
        __assert_fail "${msg}: expected >= ${minimum}, got ${actual}"
    fi
}

# assert_le <actual> <maximum> [message]
assert_le() {
    local actual="$1"
    local maximum="$2"
    local msg="${3:-numeric le}"
    if (( actual > maximum )); then
        __assert_fail "${msg}: expected <= ${maximum}, got ${actual}"
    fi
}
