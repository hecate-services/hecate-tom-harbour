#!/usr/bin/env bash
#
# Open one port, in a shell, against a station.
#
#   scripts/open-a-port.sh macao
#   scripts/open-a-port.sh lisbon
#
# WHICH HARBOUR THIS INSTANCE IS comes from the environment and nowhere else,
# so the two lines above run two different ports out of one tree. Everything
# else has a default that follows from the name.
#
# Set MACULA_STATION_SEEDS to reach a mesh. Without it the port still opens,
# still trades and still records; it simply has nobody to tell, which is exactly
# the state the contract says no fact may be load-bearing in.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

harbour="${1:-}"
if [ -z "$harbour" ]; then
    echo "usage: $(basename "$0") <harbour>   (macao | lisbon)" >&2
    exit 2
fi

export TOM_HARBOUR="$harbour"
export TOM_REALM_NAME="${TOM_REALM_NAME:-io.macula}"
export TOM_DATA_DIR="${TOM_DATA_DIR:-${here}/_data/${harbour}}"
export TOM_TICK_MS="${TOM_TICK_MS:-10000}"

# Genesis is applied by exactly ONE port, or the same hull exists twice before
# anybody has sailed anywhere. Macao holds the Santa Clara; Lisbon holds nothing
# and receives her.
if [ -z "${TOM_SHIPS:-}" ] && [ -f "${here}/priv/ships/${harbour}.ships" ]; then
    export TOM_SHIPS="${here}/priv/ships/${harbour}.ships"
fi

mkdir -p "$TOM_DATA_DIR"

echo "opening ${harbour}"
echo "  realm     ${TOM_REALM_NAME}"
echo "  data      ${TOM_DATA_DIR}"
echo "  tick      ${TOM_TICK_MS} ms"
echo "  ships     ${TOM_SHIPS:-none}"
echo "  seeds     ${MACULA_STATION_SEEDS:-none, the port will run dark}"
echo

cd "$here"
exec rebar3 shell
