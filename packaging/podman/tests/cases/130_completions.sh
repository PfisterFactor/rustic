#!/usr/bin/env bash
#
# 130_completions — `completions <shell>` emits non-empty, shell-shaped text
# for every supported shell.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

for shell in bash zsh fish powershell; do
    out="$(rt::rustic completions "${shell}")"
    if [[ -z "${out}" ]]; then
        __assert_fail "completions ${shell}: empty output"
    fi
    # Each shell's completion has a recognizable signature in the output.
    case "${shell}" in
        bash)       assert_contains "${out}" "complete -F"             "bash completion signature" ;;
        zsh)        assert_contains "${out}" "#compdef rustic"         "zsh completion signature" ;;
        fish)       assert_contains "${out}" "complete -c rustic"      "fish completion signature" ;;
        powershell) assert_contains "${out}" "Register-ArgumentCompleter" "powershell completion signature" ;;
    esac
    rt::log "${shell} completion looks good ($(wc -c <<< "${out}") bytes)"
done
