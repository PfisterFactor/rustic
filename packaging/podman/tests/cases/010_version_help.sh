#!/usr/bin/env bash
#
# 010_version_help — `rustic --version` and `--help` smoke checks.
#
# Verifies:
#   - `rustic --version` exits 0 and emits a non-empty version line.
#   - The reported version matches Cargo.toml's [package] version when we
#     can find Cargo.toml on disk (host runs), or at least matches a
#     semver-shaped string when we can't (in-container runs where Cargo.toml
#     is not available).
#   - `rustic --help` lists every subcommand we expect the hardened build
#     to ship.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

assert_exit_zero rt::rustic --version
version_line="${ASSERT_OUTPUT}"
rt::log "version line: ${version_line}"

# Extract the version token from output like:
#   rustic 0.11.2
# or
#   rustic 0.11.2-... (semver with metadata)
version="$(printf '%s\n' "${version_line}" | awk 'NR==1 {print $NF; exit}')"
assert_ne "" "${version}" "non-empty version token"
case "${version}" in
    [0-9]*.[0-9]*.[0-9]*)
        rt::log "version looks semver-shaped: ${version}" ;;
    *)
        __assert_fail "version is not semver-shaped: ${version}" ;;
esac

# If Cargo.toml is around (host run), the two MUST agree on the package
# version up to any "+meta" suffix. Inside the tester stage, Cargo.toml is
# not present so we skip the cross-check.
cargo_toml="${TESTS_ROOT}/../../../Cargo.toml"
if [[ -f "${cargo_toml}" ]]; then
    cargo_version="$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "${cargo_toml}")"
    rt::log "Cargo.toml version: ${cargo_version}"
    assert_eq "${cargo_version}" "${version%%[-+]*}" "Cargo.toml version vs --version output"
fi

assert_exit_zero rt::rustic --help
help_text="${ASSERT_OUTPUT}"

# The hardened build advertises the full feature set; spot-check every
# subcommand we promise.
for sub in \
    backup snapshots check ls cat restore forget prune \
    dump diff find tag repoinfo show-config completions copy init \
    self-update mount webdav
do
    case "${sub}" in
        self-update)
            assert_not_contains "${help_text}" "self-update" \
                "self-update must be compiled out of the hardened image" ;;
        *)
            assert_contains "${help_text}" "${sub}" "help lists ${sub} subcommand" ;;
    esac
done
