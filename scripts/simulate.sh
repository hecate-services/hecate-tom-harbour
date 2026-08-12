#!/usr/bin/env bash
#
# Run a port forward and print the price series.
#
#   scripts/simulate.sh          40 ticks, the shipped scenario
#   scripts/simulate.sh 120      120 ticks
#
# The driver itself is test/tom_sim.erl. It is in test/ rather than src/ because
# it is a hand crank for looking at the mechanism, not part of it.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ticks="${1:-40}"

cd "$here"
rebar3 as test compile >/dev/null

erl -noshell \
    -pa "$here/_build/test/lib/hecate_tom_world/ebin" \
    -pa "$here/_build/test/lib/hecate_tom_world/test" \
    -eval "tom_sim:main([\"$ticks\"]), halt(0)."
