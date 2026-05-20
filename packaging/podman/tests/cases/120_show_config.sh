#!/usr/bin/env bash
#
# 120_show_config — `rustic show-config` against the bundled fixture profile.

set -euo pipefail

# shellcheck disable=SC1091
source "${TESTS_LIB}/runtime.sh"
# shellcheck disable=SC1091
source "${TESTS_LIB}/assert.sh"

# rustic looks for profiles in a small set of directories. Stage our fixture
# under XDG_CONFIG_HOME so the loader finds it under the explicit profile
# name we pass with -P.
cfg_dir="$(rt::mktmp config)"
export XDG_CONFIG_HOME="${cfg_dir}"
install -Dm0644 "${TESTS_FIXTURES}/rustic.toml" "${cfg_dir}/rustic/rustic-tests-fixture.toml"

out="$(rt::rustic -P rustic-tests-fixture show-config)"

# show-config emits a pretty-printed TOML rendering of the merged config;
# every fixture value we care about must round-trip.
assert_contains "${out}" 'log-level = "warn"'                     "log-level from fixture"
assert_contains "${out}" '/tmp/rustic-tests-show-config'           "repository from fixture"
assert_contains "${out}" 'test-host-fixture'                       "filter-host from fixture"
assert_contains "${out}" 'no-cache = true'                         "no-cache from fixture"
