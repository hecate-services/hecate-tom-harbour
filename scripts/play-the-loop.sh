#!/usr/bin/env bash
#
# THE WHOLE GAME, ON ONE MACHINE, IN ONE COMMAND.
#
#   scripts/play-the-loop.sh          start everything and print the URL
#   scripts/play-the-loop.sh stop     stop everything
#   scripts/play-the-loop.sh status   who is up, and on which port
#   scripts/play-the-loop.sh wipe     stop, then throw away every ledger
#
# Five processes: a macula-station for them to dial out to, two harbours, one
# ocean, one house. They find each other over the MESH and nothing else: no
# Erlang distribution between the services, no shared disk, no shared library.
#
# WHAT THE STATION IS FOR. A hecate service opens no inbound port. It dials out
# to a station over QUIC and the station does the routing, so "two harbours can
# hear each other" is a statement about one station being up rather than about
# four processes knowing each other's addresses. This script runs one from the
# macula-station checkout beside this repo.
#
# ⚠ THE LOCAL STATION IS UNVERIFIED TLS. It is given a self-signed certificate
# generated here, and the four services dial it with `verify => none', which the
# SDK warns about once per link, loudly and correctly. There is no CA on a
# laptop and pinning wants an Ed25519 leaf the local cert has not got. This is
# the ONE thing about this script that a real deployment does differently: a
# real game dials a station holding a realm-issued certificate and verifies it.
# Nothing else here is a pretence.
#
# Everything it writes lives under _loop/ in this repo and is thrown away by
# `wipe'. Nothing is installed and nothing outside this tree is touched.

set -euo pipefail

harbour_repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
services="$(cd -- "${harbour_repo}/.." && pwd)"
ocean_repo="${TOM_OCEAN_REPO:-${services}/hecate-tom-ocean}"
house_repo="${TOM_HOUSE_REPO:-${services}/hecate-tom-house}"
station_repo="${MACULA_STATION_REPO:-$(cd -- "${services}/.." && pwd)/macula-io/macula-station}"

run="${TOM_LOOP_DIR:-${harbour_repo}/_loop}"

# ── What the game is ──────────────────────────────────────────────────────────
#
# The realm NAME goes inside every MRI and every topic. The realm TAG is the
# thirty-two bytes macula takes as its second argument. Both are called "the
# realm" and they are not the same thing; all four services must carry the same
# pair or they will each be perfectly healthy and unable to hear one another.
realm_name="io.macula"
realm_tag="746f6d2d6c6f63616c2d7265616c6d2d666f722d6c6f63616c2d706c61792d21"

player="raf"
ship="santa_clara"
# Goods the SHIPPED STANDINGS actually trade. Naming anything else gives a page
# with empty rows: `list_quotes' omits a good the port does not trade rather
# than refusing, so a wrong name here is silent.
goods="musk,nutmeg,quicksilver,silver_ore"
purse="1000.0"

station_port=4433
station_admin=8443
macao_health=8471
lisbon_health=8472
ocean_health=8473
house_health=8460
house_web=8461

# ── Bookkeeping ───────────────────────────────────────────────────────────────

say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

pidfile() { printf '%s/%s.pid' "$run" "$1"; }
logfile() { printf '%s/%s.log' "$run" "$1"; }

running() {
    local pid
    pid="$(cat "$(pidfile "$1")" 2>/dev/null || true)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# A release started with `foreground' is a plain child process, so the pid is
# the whole story and there is no run_erl pipe to lose track of.
spawn() {
    local name="$1"; shift
    mkdir -p "$run"
    ( "$@" >"$(logfile "$name")" 2>&1 & echo $! >"$(pidfile "$name")" )
}

reap() {
    local name="$1" pid
    pid="$(cat "$(pidfile "$1")" 2>/dev/null || true)"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    # The start script execs the emulator, so the pid IS the beam; give it a
    # moment to flush its ledger before insisting.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.3
    done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$(pidfile "$name")"
}

# Wait for a thing to answer, rather than sleeping and hoping. Every service in
# this game dials out and retries, so "up" is a question with a real answer.
await() {
    local what="$1" url="$2" tries="${3:-60}"
    for _ in $(seq "$tries"); do
        curl -sf --max-time 2 "$url" >/dev/null 2>&1 && return 0
        sleep 1
    done
    warn "${what} never answered ${url}; see $(logfile "$what")"
    return 1
}

# ── The mesh block every service carries ──────────────────────────────────────
#
# station_seeds is a list of MAPS rather than URL binaries because a map is the
# only seed shape that can carry `verify'. hecate_om passes whatever it finds
# straight to macula:connect/2, and macula's parse_seed keeps a map as it is, so
# this needs nothing added to hecate_om.
#
# MACULA_STATION_SEEDS is deliberately unset below: hecate_om prefers it over
# this, and a CSV of URLs cannot say `verify => none'.
mesh_block() {
    cat <<EOF
    {hecate_om, [
        {health_port,      $1},
        {capability_topic, <<"_mesh.cap.">>},
        {realm,            <<"${realm_tag}">>},
        {station_seeds,    [#{host => <<"127.0.0.1">>,
                              port => ${station_port},
                              verify => none}]}
    ]},
EOF
}

# ── The station ───────────────────────────────────────────────────────────────

start_station() {
    step "station"
    if running station; then say "  already up on :${station_port}"; return 0; fi

    [ -d "$station_repo" ] || {
        warn "no macula-station checkout at ${station_repo}"
        warn "set MACULA_STATION_REPO, or the four services will run dark"
        return 1
    }

    mkdir -p "$run/station/data" "$run/station/content" "$run/station/certs"

    if [ ! -f "$run/station/certs/station.crt" ]; then
        say "  minting a self-signed certificate (loopback only)"
        openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
            -keyout "$run/station/certs/station.key" \
            -out    "$run/station/certs/station.crt" \
            -subj "/CN=localhost" \
            -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null
    fi

    cat >"$run/station/config.json" <<EOF
{
  "data_dir": "${run}/station/data",
  "bind": "127.0.0.1",
  "port": ${station_port},
  "certfile": "${run}/station/certs/station.crt",
  "keyfile":  "${run}/station/certs/station.key",
  "capabilities": 0,
  "geo": { "hostname": "localhost", "city": "local", "country": "BE",
           "lat": 50.8, "lng": 4.94, "power_m": 100 },
  "outbound_peers": [],
  "admin": { "bind": "127.0.0.1", "port": ${station_admin} }
}
EOF

    # A station with no outbound peers configures no bootstrap tier and halts on
    # `no_tiers'. One station IS the whole mesh here, so it is told to look for
    # peers, accept finding none, and come up anyway.
    cat >"$run/station/sys.config" <<EOF
[
    {kernel, [{logger_level, notice}]},
    {macula, [{pubsub_emit_publisher_sig, true}]},
    {macula_content, [{store_dir, "${run}/station/content"}]},
    {macula_bootstrap, [
        {discoverers, [{macula_station_via_seed_dial, #{wait_ms => 1000}}]},
        {cascade_opts, #{min_peers => 0, timeout_ms => 5000}}
    ]},
    {macula_station, [{admin, #{bind => "127.0.0.1", port => ${station_admin}}}]}
].
EOF

    if [ ! -x "${station_repo}/_build/default/rel/macula_station/bin/macula_station" ]; then
        say "  building the station (once; this takes a few minutes)"
        ( cd "$station_repo" && rebar3 release ) >"$(logfile station-build)" 2>&1 || {
            warn "the station would not build; see $(logfile station-build)"
            return 1
        }
    fi

    # The start script rewrites vm.args.src in place and keeps a .orig beside
    # whatever RELX_CONFIG_PATH points at. A stale .orig from a previous run is
    # read in preference to the file this script just wrote, so it goes first.
    rm -f "$run/station/sys.config.orig"
    mkdir -p "$run/station/out"

    say "  starting on 127.0.0.1:${station_port} (QUIC), admin :${station_admin}"
    ( cd "$station_repo" \
      && MACULA_STATION_CONFIG="$run/station/config.json" \
         MACULA_NODE_NAME=macula_station_tom \
         RELX_REPLACE_OS_VARS=true \
         RELX_CONFIG_PATH="$run/station/sys.config" \
         RELX_OUT_FILE_PATH="$run/station/out" \
         spawn station "${station_repo}/_build/default/rel/macula_station/bin/macula_station" foreground )

    await station "http://127.0.0.1:${station_admin}/status" 90
}

# ── A harbour ─────────────────────────────────────────────────────────────────
#
# ONE RELEASE, TWO PORTS. Nothing in the build says Macao: which harbour an
# instance IS comes from TOM_HARBOUR, which is also what its node name is built
# from, so the two run side by side out of one tree.
start_harbour() {
    local name="$1" health="$2" ships="$3"
    step "harbour ${name}"
    if running "$name"; then say "  already up"; return 0; fi

    mkdir -p "$run/$name/out" "$run/$name/data"
    { say "["; mesh_block "$health"; say '    {kernel, [{logger_level, info}]}'; say "]."; } \
        >"$run/$name/sys.config"

    # Genesis belongs to exactly ONE port. Macao holds the Santa Clara at hop
    # nought; Lisbon holds nothing and receives her. Seeding both would mint two
    # hulls with one name before anybody had sailed anywhere.
    local ships_env=""
    [ -n "$ships" ] && ships_env="${harbour_repo}/priv/ships/${ships}.ships"

    say "  health :${health}, data ${run}/${name}/data, genesis ${ships:-none}"
    ( cd "$harbour_repo" \
      && TOM_HARBOUR="$name" \
         TOM_REALM_NAME="$realm_name" \
         TOM_DATA_DIR="$run/$name/data" \
         TOM_TICK_MS=10000 \
         TOM_SHIPS="$ships_env" \
         ERLANG_COOKIE=tom_loop \
         RELX_CONFIG_PATH="$run/$name/sys.config" \
         RELX_OUT_FILE_PATH="$run/$name/out" \
         spawn "$name" "${harbour_repo}/_build/default/rel/hecate_tom_harbour/bin/hecate_tom_harbour" foreground )

    await "$name" "http://127.0.0.1:${health}/health" 60
}

# ── The ocean ─────────────────────────────────────────────────────────────────

start_ocean() {
    step "ocean"
    if running ocean; then say "  already up"; return 0; fi

    mkdir -p "$run/ocean/out" "$run/ocean/data"
    { say "["
      say "    {hecate_tom_ocean, [{ocean_mri, <<\"mri:instance:${realm_name}/tom/ocean\">>}]},"
      mesh_block "$ocean_health"
      say '    {kernel, [{logger_level, info}]}'
      say "]." ; } >"$run/ocean/sys.config"

    say "  health :${ocean_health}, data ${run}/ocean/data"
    ( cd "$ocean_repo" \
      && HECATE_DATA_DIR="$run/ocean/data" \
         HECATE_NODE_NAME=tom_ocean \
         HECATE_NODE_HOST=127.0.0.1 \
         HECATE_COOKIE=tom_loop \
         RELX_CONFIG_PATH="$run/ocean/sys.config" \
         RELX_OUT_FILE_PATH="$run/ocean/out" \
         spawn ocean "${ocean_repo}/_build/default/rel/hecate_tom_ocean/bin/hecate_tom_ocean" foreground )

    await ocean "http://127.0.0.1:${ocean_health}/health" 60
}

# ── The house ─────────────────────────────────────────────────────────────────
#
# The player. It advertises nothing and nobody ever calls it, which is why it is
# the one service here that can be killed mid-voyage without anything being at
# risk. Its /health reports degraded until the pool attaches, so the page is
# waited on rather than the health endpoint.
start_house() {
    step "house"
    if running house; then say "  already up"; return 0; fi

    mkdir -p "$run/house/out" "$run/house/data"
    { say "["
      mesh_block "$house_health"
      cat <<EOF
    {hecate_tom_house, [
        {realm_name,         <<"${realm_name}">>},
        {player,             <<"${player}">>},
        {ship,               <<"${ship}">>},
        {harbours,           <<"macao,lisbon">>},
        {goods,              <<"${goods}">>},
        {purse,              ${purse}},
        {ledger,             "${run}/house/data/house.log"},
        {web_port,           ${house_web}},
        {quote_interval_ms,  5000},
        {locate_interval_ms, 10000}
    ]},
    {kernel, [{logger_level, info}]}
].
EOF
    } >"$run/house/sys.config"

    say "  page :${house_web}, health :${house_health}, ledger ${run}/house/data/house.log"
    ( cd "$house_repo" \
      && TOM_COOKIE=tom_loop \
         RELX_CONFIG_PATH="$run/house/sys.config" \
         RELX_OUT_FILE_PATH="$run/house/out" \
         spawn house "${house_repo}/_build/default/rel/hecate_tom_house/bin/hecate_tom_house" foreground )

    await house "http://127.0.0.1:${house_web}/view" 60
}

# ── Building ──────────────────────────────────────────────────────────────────

build() {
    step "building"
    local repo name
    for repo in "$harbour_repo" "$ocean_repo" "$house_repo"; do
        name="$(basename "$repo")"
        [ -d "$repo" ] || { warn "no checkout at ${repo}"; return 1; }
        say "  ${name}"
        ( cd "$repo" && rebar3 release ) >"$(logfile "build-${name}")" 2>&1 || {
            warn "${name} would not build; see $(logfile "build-${name}")"
            return 1
        }
    done
}

# ── Verbs ─────────────────────────────────────────────────────────────────────

start() {
    mkdir -p "$run"
    # hecate_om prefers this over the configured seeds, and a URL in it cannot
    # carry `verify => none', so an inherited one would send every service to a
    # station it then refuses to trust.
    unset MACULA_STATION_SEEDS || true

    build
    start_station
    start_harbour macao  "$macao_health"  macao
    start_harbour lisbon "$lisbon_health" ""
    start_ocean
    start_house

    step "the game is open"
    cat <<EOF

    ┌─────────────────────────────────────────────────────────┐
    │  http://localhost:${house_web}                                 │
    └─────────────────────────────────────────────────────────┘

    Buy musk at Macao, sail her to Lisbon, wait ninety seconds,
    sell, and watch the purse.

    macao   http://127.0.0.1:${macao_health}/health
    lisbon  http://127.0.0.1:${lisbon_health}/health
    ocean   http://127.0.0.1:${ocean_health}/health
    station http://127.0.0.1:${station_admin}/status

    logs    ${run}/*.log
    stop    scripts/play-the-loop.sh stop

EOF
}

stop() {
    step "stopping"
    local name
    for name in house ocean lisbon macao station; do
        running "$name" && { say "  ${name}"; reap "$name"; } || rm -f "$(pidfile "$name")"
    done
}

status() {
    local name
    printf '%-10s %-8s %s\n' SERVICE STATE WHERE
    for name in station macao lisbon ocean house; do
        printf '%-10s %-8s %s\n' "$name" \
            "$(running "$name" && echo up || echo down)" \
            "$(logfile "$name")"
    done
}

wipe() {
    stop
    step "wiping"
    say "  ${run}"
    rm -rf "$run"
}

case "${1:-start}" in
    start)  start ;;
    stop)   stop ;;
    status) status ;;
    wipe)   wipe ;;
    *) say "usage: $(basename "$0") [start|stop|status|wipe]"; exit 2 ;;
esac
