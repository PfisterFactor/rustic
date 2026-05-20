#!/usr/bin/env bash
#
# Orchestrator for the rustic-hardened in-build integration suite.
#
# Runs every `cases/*.sh` in lexical order, captures each case's stdout+stderr
# to a per-case log, prints a final pass/fail summary, and exits non-zero on
# the first failure (with the failing log dumped to the build output).

set -euo pipefail

# Resolve our own directory so this works regardless of where it's invoked
# from. Inside the tester stage we're at /opt/rustic-tests, but we keep this
# generic so the suite also runs against a host-side rustic for local dev.
TESTS_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export TESTS_ROOT
export TESTS_LIB="${TESTS_ROOT}/lib"
export TESTS_FIXTURES="${TESTS_ROOT}/fixtures"
export TESTS_CASES="${TESTS_ROOT}/cases"

# All cases share one workspace root so we can clean it up in one shot.
# RUSTIC_TEST_TMP defaults to /work (set by the tester stage). For host-side
# runs, fall back to a fresh mktemp.
if [[ -z "${RUSTIC_TEST_TMP:-}" ]]; then
    RUSTIC_TEST_TMP="$(mktemp -d -t rustic-tests.XXXXXX)"
    export RUSTIC_TEST_TMP
fi
mkdir -p -- "${RUSTIC_TEST_TMP}"

LOG_ROOT="${RUSTIC_TEST_TMP}/logs"
mkdir -p -- "${LOG_ROOT}"

# Shared password used by all cases that need a repository password.
export RUSTIC_PASSWORD="${RUSTIC_PASSWORD:-rustic-tests-password}"

# Locate the rustic binary. Allow override for host-side dev runs.
if [[ -z "${RUSTIC_BIN:-}" ]]; then
    RUSTIC_BIN="$(command -v rustic 2>/dev/null || true)"
    if [[ -z "${RUSTIC_BIN}" ]]; then
        RUSTIC_BIN="/usr/local/bin/rustic"
    fi
fi
export RUSTIC_BIN

if [[ ! -x "${RUSTIC_BIN}" ]]; then
    echo "FATAL: rustic binary not found or not executable at ${RUSTIC_BIN}" >&2
    exit 2
fi

# shellcheck source=lib/runtime.sh disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck source=lib/assert.sh disable=SC1091
source "${TESTS_LIB}/assert.sh"

rt::header "rustic-hardened integration suite"
rt::log "binary:       ${RUSTIC_BIN}"
rt::log "tests root:   ${TESTS_ROOT}"
rt::log "work tmp:     ${RUSTIC_TEST_TMP}"
rt::log "logs:         ${LOG_ROOT}"
"${RUSTIC_BIN}" --version

shopt -s nullglob
all_cases=("${TESTS_CASES}"/*.sh)
shopt -u nullglob

# Filter out host-side contract scripts (900_*). Those take a rootfs path
# argument and are driven by the Containerfile and CI, not by this runner.
cases=()
for case_path in "${all_cases[@]}"; do
    case "$(basename -- "${case_path}")" in
        9*_*.sh)
            : "skip host-side contract: $(basename -- "${case_path}")"
            ;;
        *)
            cases+=("${case_path}")
            ;;
    esac
done

if (( ${#cases[@]} == 0 )); then
    echo "FATAL: no test cases found in ${TESTS_CASES}" >&2
    exit 2
fi

# Sort lexically so 010 < 020 < ... < 220.
IFS=$'\n' read -r -d '' -a cases < <(printf '%s\n' "${cases[@]}" | LC_ALL=C sort && printf '\0')

PASS=0
FAIL=0
FAILED_CASES=()

for case_path in "${cases[@]}"; do
    case_name="$(basename -- "${case_path}" .sh)"
    case_workdir="${RUSTIC_TEST_TMP}/${case_name}"
    case_log="${LOG_ROOT}/${case_name}.log"
    mkdir -p -- "${case_workdir}"

    rt::header "case ${case_name}"
    rt::log "workdir:  ${case_workdir}"
    rt::log "log:      ${case_log}"

    # Each case runs in its own bash to isolate variable leakage and trap
    # mishaps. We tee output so the build log shows progress AND each case
    # log is preserved for post-hoc inspection.
    set +e
    (
        export CASE_NAME="${case_name}"
        export CASE_WORKDIR="${case_workdir}"
        cd -- "${case_workdir}"
        bash -- "${case_path}"
    ) > >(tee -- "${case_log}") 2>&1
    status=$?
    set -e

    if (( status == 0 )); then
        rt::log "PASS: ${case_name}"
        PASS=$((PASS + 1))
    else
        rt::log "FAIL: ${case_name} (exit ${status})"
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("${case_name}")
    fi
done

rt::header "summary"
rt::log "passed: ${PASS}"
rt::log "failed: ${FAIL}"
if (( FAIL > 0 )); then
    rt::log "failing cases:"
    for c in "${FAILED_CASES[@]}"; do
        rt::log "  - ${c}"
        if [[ -s "${LOG_ROOT}/${c}.log" ]]; then
            echo "----- ${c}.log -----"
            cat -- "${LOG_ROOT}/${c}.log"
            echo "----- end ${c}.log -----"
        fi
    done
    exit 1
fi

rt::log "all cases passed."
