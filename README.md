# hecate-tom-world

**TOM, Traders of Macao.** The world: what exists, and one of the places in it.

*This exists so that a trader can buy goods in one port, fill a ship, and sell
them in another.*

**One binary, run once per place.** An instance is a harbour, which is a place
that has a market; a fort and a trading post are the same service with a
garrison and no market, and are the second game. Eight or more instances run two
apiece on `beam00` to `beam03`, each dialling a different station, owned by
nobody and always on. **This is never one process**, which is the mistake the
ocean died of.

It carries `priv/worlds/macao.world` in its own release, so what a good is and
where the ports are needs no service to answer and no event stream to catch up
on. A player learns the world by fetching that artifact and checking its digest
against `tom_world:digest/1`. What a **player** links is `macula` and nothing of
ours, and that boundary is the one that matters: see
[DESIGN_TWO_SERVICES.md](../hecate-tom-general/design/DESIGN_TWO_SERVICES.md).

Two halves, and they are kept apart on purpose. The **mechanism** is pure
functions: a market is a term, you pass one in and get one back, and nothing in
it reads a clock, opens a socket or spawns a process. The **service** is one
process that holds a market, a clock, a disk and a mesh connection, and every
call at this harbour serialises through it.

A harbour is a quay, a town behind it, and land behind that. Every good buys and
sells here at the going price. There is no stock list and no shopping list,
because a market has neither: it has a heap of each thing and a price that moves
when the heap does.

## The law

> **Price is always circumstantial.**

Nothing this service is given is ever a price. Not a base price, not a value,
not a cost. A number that says what something is **worth** is forbidden. Numbers
that say how much of something **exists**, or how fast it is yielded, or how
long a process takes, are physical facts and are welcome.

A harbour declares three things, and not one of them is about worth:

| Field | Is | Physical because |
|-------|-----|------------------|
| `town` | the settlement, as a multiple of a standard town | it is a headcount, and it multiplies demand **identically for every good** |
| `hinterland` | the land behind the port, as a multiple of a standard hinterland | it is an extent of land, not a judgement of it, and it multiplies every yield identically |
| `goods` | what a standard hinterland turns out per tick | it is a rate, the same kind of fact as a recipe's `ticks` |

Plus two things it does not declare but derives: `produces`, the list the world
service already publishes, and `census`, how many other harbours it has heard of
that produce each good, and whether they are near.

**Neither per-harbour number can reach a single good.** They scale everything
together. There is no per-good appetite, no desirability, no per-good
elasticity, and the last one is the subtle one: per-good elasticities would let
an author make luxuries behave like luxuries, and that is the door through which
declared worth walks back in. Every good responds to scarcity identically. That
is a known and accepted limitation.

## The mechanism

Two curves. The oldest story in economics, and the one the world service already
tells: demand is the complement of abundance and is never declared.

| At a price P | flows | which is |
|---|---|---|
| supply | `Y·P^0.4 + what a factory makes` | more arrives when it is worth carrying here |
| demand | `D·P^-1.4 + what a factory eats` | less leaves when it is dear |

They cross at exactly one price, because one side rises and the other falls.

- **Supply** is the yield, times the land, times how plentiful the good is here.
- **Demand** is the town's appetite, spread over a price. The appetite is the
  same number for all sixty-seven goods.
- They cross once. That crossing is the **natural price** and the flow through
  it is the **throughput**.

The heap on the quay does the rest:

- A resting quay holds **eight ticks of throughput**. That is the natural stock,
  and it is a quantity implied by a rate rather than a number anyone chose.
- The **posted price** is the natural price times the square root of how short
  the heap is. Strip it and the price rises; pile it up and it falls.
- **A trade pays the prices it moved through**, not the spot price times the
  quantity. Lifting five musk off a resting Macao costs 14.65 apiece against a
  posted 12.92, because it walked the price to 16.18 on the way.
- **Every tick, arrivals and offtake both read that price.** High price, more
  arrives and less leaves, so the heap climbs back. Left alone it comes to rest
  exactly at the crossing.

### Nothing runs away, and nothing rings

Both ends of the price are algebra, not a clamp. There is no clamp on a price
anywhere in this repository and there must never be one, because a clamp is a
number somebody chose.

- The heap can never fall below a quarter-tick **reserve**, so the price is
  finite: at most **5.74** times natural.
- The heap can never be pushed past a **godown** of ten natural stocks, so the
  price has a floor: **0.32** times natural.

That band is eighteen wide. A famine is not expressible in it. That is the price
of a bounded step and it is a deliberate trade.

Settling is one inequality, `stock_sensitivity × (η + ε) / (τ + τmin) < 1`,
checked once when a market opens. It is **0.109** with the shipped constants, so
the half-life of any disturbance is six ticks. A factory can only ever make that
number smaller, which is why one line covers every port and every works the game
will ever build. Above one a market rings; above two it diverges; either is
refused at the door with `{gate_not_met, Rate}`.

### Depth, which is the useful thing to tell a player

> **Doubling a price costs one natural stock's worth, at the natural price.**

That falls out of inverting the posted price and integrating. `depth/3` answers
it for any target: how much you would have to move, and what it would cost you.

## Relative value, emerging

Nobody wrote any of these down. The only per-good input is a yield, and the
exponent between a yield and a price is 0.556, so a thousandfold price needs a
quarter-million-fold difference in yield. You cannot nudge a yield until it hits
a price you had in mind.

| | | |
|---|---|---|
| musk at Macao | **12.92** | 0.5 a tick, and Macao grows it |
| rice at Ayutthaya | **0.134** | 400 a tick |
| musk against rice, each at home | **96×** | out of a yield ratio of 800 |

Geography is the census and nothing else: how many harbours produce a good, and
whether they are in this sea or the next one.

| nutmeg at | | |
|---|---|---|
| Banda, where it grows | **0.753** | |
| Ternate, four producers in the same sea | **2.479** | 3.3× |
| Lisbon, four producers and a voyage | **8.553** | 11.4× |

And the galleon, which nobody designed:

| | Macao | Callao | |
|---|---|---|---|
| quicksilver | 7.94 | **57.24** | 7.2× westbound |
| silver ore | **2.00** | 0.112 | 17.8× eastbound |

Full in both directions, out of two produces lists.

**A factory is another counterparty**, not a new rule. It buys and sells
whatever the price, so it enters as a price-blind flow and moves the crossing
itself. Raise the gun foundry behind Macao and cannon fall from 77.2 to 51.5
while copper rises from 13.2 to 15.2: its selling depresses its output price and
its buying lifts its input price until it strangles itself. Permanent structure,
not a wobble in a heap.

## What is here

### The mechanism, which is pure

| Module | Is |
|--------|-----|
| `tom_market` | **The facade.** The port, its clock, and the folding of facts |
| `tom_quay` | One good's stack: its heap, its posted price, its trades, its tick |
| `tom_crossing` | Where the two curves meet. The long-run structure of one good here |

### What exists, which is data

| In `know_the_world/` | Is |
|--------|-----|
| `tom_world` | Loads a world and checks it. Reports every problem, not the first. `digest/1` is what two peers compare |
| `tom_goods` | The map a good is, and the questions you can ask about one |
| `tom_harbours` | The map a harbour is |
| `tom_places` | Waypoints and routes. The world says WHERE, and never how long |
| `tom_recipes` | What a factory eats, what it makes, and how long a batch takes |
| `tom_mri` | What any of them is called on the mesh, and how to resolve one back without minting an atom |

Nothing in the market calls these, and that is not an accident waiting to be
tidied up. A port's standing is still handed to `tom_market:open/1` as plain
data, so the mechanism stays testable without a world and a world stays
replaceable without a market.

### The service, which is not

| Module | Is |
|--------|-----|
| `hecate_tom_world_app` / `_sup` / `_service` | OTP entry, the tree, and the hecate_om contract |
| `open_the_port/tom_port` | **The one process.** Market, clock, hulls, receipts, disk |
| `open_the_port/tom_ledger` | What this port must not forget, on a disk, before it answers |
| `tom_standing` | Which port this instance IS, read from the environment |
| `tom_ship` | A hull, its hold, and what is in it |
| `tom_wire` | Binary keys, MRIs, instants: what leaves and what is accepted |
| `join_the_mesh/tom_advertiser` | The seven procedures, addressed at this instance |
| `join_the_mesh/tom_crier` | The port's one mouth. Four facts, best effort |
| `hand_over_ship/tom_hand_over_ship{,_sup}` | One promise per consigned hull, retried forever |
| `receive_ship/tom_take_landings` | The port's ears. Hears a landfall, asks the sea what landed here |

### The desks, one directory each

| Desk | Answers |
|------|---------|
| `list_quotes/` | what everything goes for |
| `quote_purchase/` | what an order would cost, moving nothing |
| `buy_cargo/` | quay to hold, in one act, idempotent on the order |
| `sell_cargo/` | hold to quay, in one act, idempotent on the order |
| `sail_ship/` | promise a hull to the ocean and freeze it |
| `receive_ship/` | take custody of a hull the sea landed here, idempotent on the ship and the hop. **Nobody calls it**: it is entered from the sea's announcement and from this port's own catch-up ask |
| `get_ship/` | where a hull is |

| In `test/` | Is |
|------------|-----|
| `tom_sim` | A hand crank. Runs a port forward with a script of orders |

**A desk is a function**, from the port's state and one payload to a reply, a new
state and a list of things the world must do. `tom_port` is the only thing in the
service holding a pid, a disk or a socket, so every desk is tested by calling it,
and the order of the effects is decided in one place: **written down first, said
out loud second, and only then answered.**

**There is no dependency on `hecate-tom-world`**, and there will not be one. A
shared domain library is the problem that service exists to avoid. Goods arrive
here as plain data: a map of identifiers to yields, and a list of which of them
this port produces.

## Using it

```erlang
1> Standing = #{town => 2.0, hinterland => 1.2,
                goods => #{musk => 0.5, rice => 400.0, nutmeg => 40.0},
                produces => [musk],
                census => #{nutmeg => {4, 0}, rice => {3, 0}},
                factories => []}.
2> {ok, M0} = tom_market:open(Standing).
3> tom_market:quote(M0, musk).
12.915496650148841
4> tom_market:in_terms_of(M0, musk, rice).
16.010069889844136
5> {ok, Filled, Coin, M1} = tom_market:lift(M0, musk, 5, 0).
{ok,5.0,73.264513956432609,#{...}}
6> tom_market:quote(M1, musk).
16.182488565095465
7> tom_market:quote(M1, musk, 40).           % what it will be at tick 40
12.936240631306845
8> tom_market:depth(M0, musk, 2 * 12.915496650148841).
{lift,10.33025178069395,181.45165188549564}
```

Line 8 is the depth statement in one call: doubling musk takes 10.33 off the
quay, which is 0.75 of the anchor, and costs 181.45, which is one natural stock
at the natural price plus the fee. Line 4 is the law in one call: musk is
sixteen times rice here because this port grows musk and rice reaches it as a
trickle from three harbours along the same coast, and nobody wrote sixteen down.

Facts fold in, and every one of them settles the market to its own tick before
it touches anything, because a crossing rewritten out of order retroactively
rewrites every tick since the last stamp:

```erlang
9>  {ok, _, _, M2} = tom_market:land(M1, nutmeg, 40, 50).
10> M3 = tom_market:raise_factory(M2, 60, #{id => cast_cannon,
                                            consumes => #{copper => 0.375},
                                            yields => #{cannon => 0.125}}).
11> M4 = tom_market:resurvey(M3, 70, #{town => 2.4}).
```

The event vocabulary for the CMD slice that will one day wrap this, business
verbs and no CRUD: `market_opened`, `cargo_lifted`, `cargo_landed`,
`harbour_sighted`, `factory_raised`, `factory_demolished`,
`hinterland_resurveyed`. **The tick is not an event.** It is a pure function of
elapsed time and carries nothing a replay cannot derive, so replay is a fold of
those six facts with a settle between them.

## What this harbour says on the mesh

Four facts, and **not one of them is load-bearing**. A missed fact costs a page
update, never a coin and never a ton, because everything that must be true is
established by a call with a receipt or read back later from the service that
owns it. That is what lets a player switch off for a voyage and be exactly right
when he comes back.

| Topic | When |
|-------|------|
| `{realm}/tom/harbour/trade/cargo_loaded_v1` | goods went from this quay into a hold |
| `{realm}/tom/harbour/trade/cargo_discharged_v1` | goods came out of a hold onto this quay |
| `{realm}/tom/harbour/custody/ship_moored_v1` | this port took custody of a hull |
| `{realm}/tom/harbour/custody/ship_consigned_v1` | this port promised one away and froze it |

**No identifier is ever in a topic.** The harbour, the ship and the good travel
in the payload, so a house watching a voyage subscribes to four topics rather
than four times the number of ports.

The facts are named for what happened to the **ship**; this repository's own
vocabulary above names what happened to the **quay**. That divergence is
deliberate: the producer owns the content of what it publishes, and an outsider
watching a voyage cares that a hold got fuller, not that a heap got shorter.

### Two things the wire does that the contract did not say it did

Both were found by running the four services against a real station, and both
break the loop silently rather than loudly. They are the reason
`tom_wire:accept/1` and `tom_wire:answer/1` exist.

**A key does not arrive in the shape it was sent.** The contract says every key
on the wire is a binary. That is true of what a sender writes and false of what
a receiver gets. macula encodes a binary key as a CBOR text string, and
`macula_frame:from_wire_envelope/1` then runs `binary_to_existing_atom` over
every one: a key whose name is already in the receiving node's atom table
arrives as an **atom**, one whose name is not arrives as **`{text, Binary}`**.
Both shapes turn up in one payload, and which shape a given key takes is a
property of the receiving node rather than of the message — load a module that
happens to mention the atom `good` and every payload afterwards is shaped
differently. `tom_wire:accept/1` folds a payload back to binary keys at the one
place every desk is entered, `tom_port:ask/1`, and mints no atom doing it.

**A refusal's reason does not survive `{error, Binary}`.** macula turns a
handler's error tuple into a BOLT#4 frame with code `0x0F`, renders the reason
into the frame's `detail`, and the SDK's caller path reads only the code. So
`quay_empty`, `hold_full`, `not_here`, `not_yours` and `ship_consigned` all
reach a house as one indistinguishable `{call_error, 15, unknown_error}`, and a
player is told an order failed with no way to say why. A refusal therefore
travels as a **successful reply carrying the reason**:

```erlang
{ok, #{<<"refused">> => <<"hold_full">>}}
```

which is the one shape the wire keeps whole. The desks still return
`{error, Binary}`, because that is what a refusal IS to this port; the
translation is `tom_wire:answer/1`, at the edge, once. The final-versus-transient
split a caller retries on is unaffected: a reply is an answer, and a crash or a
timeout is not.

## What this harbour listens to

One topic, and it is the sea's:

| Topic | Means |
|-------|-------|
| `{realm}/tom/ocean/voyage/landfall_made_v1` | a ship has landed somewhere. If it is here, look now |

**A harbour is infrastructure and has no say in whether a ship turns up.** She is
this port's from the instant the sea says so, whether or not this port has heard
yet. Arrival is a statement, not a transaction between two parties, so nobody
knocks here: the port finds out for itself, two ways that end at the same desk.

- **It hears.** A landfall bound for this port arms a look in one second, so a
  burst of announcements is one walk.
- **It asks.** Every thirty seconds, unconditionally, and once at boot, it calls
  the sea's `landings_at` and takes whatever it has not taken. That is what a
  port that was switched off for a week does, and it is the same code path an
  ordinary Tuesday afternoon uses. A recovery path that only runs after an
  outage is a broken recovery path nobody notices.

**The fact is a nudge and never a delivery.** `landfall_made_v1` carries the ship
as a bare identifier, so hearing one changes *when* this port asks, never *what*
it believes. Cargo manifests stay off a broadcast topic, and a forged fact
carries no authority: the worst a stranger can do is make this port ask its own
configured ocean a question whose answer is the same as it would have been.

**And the ask is a read, not a handshake.** Nobody is waiting on the answer and
nothing retries until acknowledged. The sea stores nothing about this port; its
state after answering equals its state before. The tick is not armed because
something is outstanding and does not stop when something is acknowledged, so a
port with nothing owed to it asks exactly as often as one that missed a week, and
gets an empty list.

**What it remembers is in memory only, and it is not the authority.** The ledger
is: `taken` is durable, never pruned, and rebuilt at boot. The cursor on top of
it is a bandwidth bound, so a restarted port walks the sea's whole history of
landings here again and every take after the first writes nothing and says
nothing. That costs one walk per restart and buys no second clock in the port's
record and no extra fsync per arrival.

## The custody rule, as implemented

> **Custody is held by whoever has recorded taking the hull at the highest hop.**

One sentence, and it resolves every crash. There is no vote, no quorum and no
arbiter, because the hop is monotone and only a durable taking advances it.

**The two directions are not symmetrical, and that is the whole design.** Leaving
a port is a **command** this port issues and must see acknowledged. Arriving at a
port is a **statement** the sea makes and nobody has to agree to.

*Leaving here, toward the sea:*

- A **consignment is not a hop.** It freezes the hull and obliges this port to
  keep calling; this port stays the custodian at the old hop until it is told
  otherwise. If the ocean is down for an hour the hull sits here for an hour,
  visibly consigned, which is the truth.
- The consigner **retries until `held`**, then drops the hull, writes its own
  terminal record and forgets. Retrying a **command** until it is acknowledged is
  not the same as asking permission, which is why this half keeps its loop.

*Arriving here, from the sea:*

- **A harbour has no say in whether a ship turns up.** It does not accept her, it
  receives her, and she is this port's from the moment the sea says so, whether
  or not this port has heard yet. There is no acceptance, so there is no state
  meaning "arrived but not yet accepted" and nothing anywhere is waiting.
- The port **finds out for itself**, by listening and by asking. Neither is a
  handshake and neither stops when somebody acknowledges.
- **Taking is durable before the reply.** `tom_port` writes and then answers,
  never the other way round.
- `receive_ship` is **idempotent on the ship and the hop, permanently**. A port
  that ever took a hull at a hop or higher answers `held`, whether or not it
  still has it, and writes nothing the second time. Heard, asked for, or both, it
  is **one take**: the ledger is the authority and the cursor is only a bandwidth
  bound on top of it.
- **The only refusal is a payload that is not a hull**, and it is final rather
  than transient. That landing can never become takeable, so the walk says so out
  loud and steps past it rather than wedging every later ship behind it.

## Playing the whole game

```bash
scripts/play-the-loop.sh          # then open http://localhost:8461
scripts/play-the-loop.sh stop
scripts/play-the-loop.sh status
scripts/play-the-loop.sh wipe     # stop, and throw every ledger away
```

Five processes: a `macula-station` for them to dial out to, **two harbours**, the
ocean and the house. They find each other over the mesh and nothing else — no
Erlang distribution between the services, no shared disk, no shared library.
Everything it writes lives under `_loop/`.

It expects `hecate-tom-ocean`, `hecate-tom-player` and `macula-io/macula-station`
checked out beside this repository; override with `TOM_OCEAN_REPO`,
`TOM_HOUSE_REPO` and `MACULA_STATION_REPO`.

⚠ **The local station is unverified TLS.** It gets a self-signed certificate
minted by the script and the four services dial it with `verify => none`, which
the SDK warns about once per link, loudly and correctly. There is no CA on a
laptop and pinning wants an Ed25519 leaf this certificate has not got. That is
the one thing this script does differently from a real deployment, where a
station holds a realm-issued certificate and is verified.

## Opening one port on its own

```bash
scripts/open-a-port.sh macao
scripts/open-a-port.sh lisbon
```

**Which harbour an instance IS comes from the environment and nowhere else.**
Nothing in the image says Macao, which is what lets one release run two ports.

| Variable | Default | Is |
|----------|---------|-----|
| `TOM_HARBOUR` | **none, and it will not start without it** | the port's name: `macao`, `lisbon` |
| `TOM_REALM_NAME` | `io.macula` | the realm NAME inside every MRI and topic. **Not** the realm tag |
| `TOM_OCEAN` | `mri:instance:{realm}/tom/ocean` | the ocean. There is one, so the default is derivable |
| `TOM_STANDING` | `priv/harbours/{harbour}.standing` | what this port declares about itself |
| `TOM_SHIPS` | none | genesis hulls. **Exactly one port may be given these** |
| `TOM_DATA_DIR` | `/var/lib/hecate-tom-world` | where the record lives. Must outlive the container |
| `TOM_TICK_MS` | `10000` | how long a tick of the market lasts in wall time |
| `MACULA_STATION_SEEDS` | none | the station to dial. Without it the port runs dark |
| `HECATE_REALM` | none | the 32-byte realm TAG, as 64 hex characters, for macula |

A port with no seeds still opens, still trades and still records. It simply has
nobody to tell, which is exactly the state the contract says no fact may be
load-bearing in.

## Running the mechanism on its own

```bash
scripts/simulate.sh 40
```

A trader works the musk quay over four visits, lands a cargo of nutmeg he
brought from Banda, and the port recovers:

```
tick        musk      nutmeg      copper      cannon
   0     12.9155      8.2514     13.2118     77.2226
   5     24.2940      8.2514     13.2118     77.2226
  12     15.1305      5.1663     13.2118     77.2226
  20     13.6316      6.2732     13.2118    103.5468
  32     13.0802      7.5099      8.2015     81.3766
```

From code, `tom_sim:run/3` gives the series back as data.

## Decisions that would otherwise be left open

**Coin is not silver.** Coin is an abstract unit of account. Silver and gold are
ordinary goods with ordinary crossings, so they go for something different at
every port, which is the entire reason the Manila galleon existed. Making silver
the numeraire would delete the game's central trade. Scaling `appetite` scales
every price together, which is what choosing a currency unit does, and it moves
no ratio at all.

**Money is not conserved.** The town's purse is unmodelled and bottomless, and
the harbour fee is the only sink. A treasury would introduce a lagged feedback
from price back to demand, which is exactly the thing the settling argument
depends on not existing. Conserving money and guaranteeing that prices settle
are in tension, and this chooses settling.

**A tick is not a clock.** Every mutating call carries the tick it happens at.
The port service converts wall time to ticks at whatever cadence it chose. That
is why everything here is pure and every test is deterministic.

**Within a tick, arrival order.** Two traders trading in the same tick get
different prices, and the second sees what the first did. No batching, no
clearing auction.

**Ignorance is not scarcity, and that is on purpose.** A good no harbour
anywhere produces has no geography, so the trickle does not apply to it and the
declared yield is already the artisan rate everywhere. That is what cannon are.
The port that has heard of exactly **one** distant producer is the one that pays
most, and the price falls back as more facts arrive.

**What this still cannot say, honestly.** Broadcloth is the trap good because
nobody wants it, and unwantedness is a declared demand. Produced only in Europe,
this mechanism makes it seven to eleven times dearer in Asia and a perfectly
good trade. The law-abiding repair is a very large yield, Europe drowning in
wool, which puts the base so low that the ratio is real and the absolute margin
will not pay the freight. That is how a trap good actually works, and it is the
best the law permits.

## What this harbour answers to

Seven procedures, every one of them **addressed at this instance**:

```
{realm}/tom/harbour/macao.list_quotes       what everything goes for
{realm}/tom/harbour/macao.quote_purchase    what an order would cost
{realm}/tom/harbour/macao.buy_cargo         quay to hold, in one act
{realm}/tom/harbour/macao.sell_cargo        hold to quay, in one act
{realm}/tom/harbour/macao.sail_ship         promise a hull to the ocean
{realm}/tom/harbour/macao.get_ship          where a hull is
{realm}/tom/harbour/macao.commission_ship   a house that lost its ship takes up another
```

The harbour is in the name because a call has to reach **one** harbour. Macao
and Lisbon both answer `buy_cargo`, and `macula:call` is first-success across a
pool's links, so a name that did not carry the harbour would hand a Macao order
to Lisbon and the coin would be gone.

**Every one of them is a thing a house asks this port to do, and there is no
eighth for arrivals.** A ship landing here is not a call anybody makes; see
[what this harbour listens to](#what-this-harbour-listens-to).

The one procedure this port **calls** on somebody else, besides handing a hull to
the sea, is `{realm}/tom/ocean.landings_at`: what have you landed at me since,
answered as a page, waited on by nobody.

## Build

```bash
rebar3 eunit      # 135 tests
rebar3 lint
rebar3 dialyzer
rebar3 release
```

## License

Apache-2.0. See [LICENSE](LICENSE).

## What was wrong, and what was done about it

Four independent probes against the built code, 2026-08-11, found the mechanism
itself sound: 192 cases of six ports by eight goods by four starting stocks, 1200
ticks each, zero non-monotone steps, zero overshoots, zero out-of-band prices,
worst residual 9.87e-13. Round trip loses exactly 3.921569% at every size in both
directions and a 20,000-sequence search found no closing cycle, so there is no
money pump.

Three faults in the collar around it were recorded. **All three are fixed**, and
each has a test that fails when the fix is reverted.

**1. The horizon snap deleted goods. FIXED.** `advance/3` wrote the natural stock
down whenever the elapsed ticks reached the horizon, without asking whether the
quay could have got there. Everything that licenses that write, the gate, the
band, the count of ticks, is an argument about heaps between nothing and a full
godown, and `re_cross/2` can leave far more than that on a quay. Reproduced at
scale: a works eating ten million musk a tick, demolished, leaves eighty million
on the quay; one call of `settle(+1128)` answered 13.36 at the natural price with
`at_rest` true while 1128 calls of `settle(+1)` answered 15,937,484, still
draining. Sixteen million units deleted, and the wrong answer looked right.

Now a quay outside the godown is **cranked, a horizon at a time, until it is back
inside one**, and only then is the rest of the wait taken in a comparison. It
costs what it costs. `at_rest` was also made to mean what it says: a crank that
arrives within rounding of the fixed point is put **on** it, so the two ways of
waiting out the same hour cannot differ in the last bits.

**2. `sight_harbour/3` moved a price the wrong way on the first news. FIXED.**
`abundance` could not tell "surveyed, nobody makes this" from "we have not heard
yet", so a port's first piece of news sent a good UP thirteenfold. On a mesh
where ports learn asynchronously that was a standing arbitrage against everyone
who had not caught up, and it paid to trade with the ignorant.

Ignorance is now **a state in the census rather than a value of the count**. A
good missing from the census is unsurveyed and gets `leak_base` alone, which is
exactly what that constant means: what turns up with no known source at all. That
is the scarce end, so **learning can only ever make a good cheaper here**, never
dearer, and the port that is behind quotes dear, which costs its owner rather
than its counterparty. A surveyed `{0, 0}` still means the good has no geography
and still gets the full artisan rate, so cannon at Macao are unchanged at 77.22.

**3. The settling gate was advertised as sufficient and was not. FIXED.** It was
the linearisation at the fixed point, which describes the last few ticks of an
approach and says nothing about the step taken from an empty quay, where the
largest step is.

The gate now measures **the longest step any tick takes anywhere in the band**,
as a fraction of the distance it had left, sampled across every heap between an
empty quay and a full godown. It is still one number checked once at the door,
because a works can only ever make a step smaller, so the factory-free arithmetic
bounds every port and every works the game will ever build. With the shipped
constants it is **0.2407** rather than the linearisation's 0.109, and both pass,
but only one of them was ever an argument. A configuration that scores 0.873
linearised and 1.13 across the band is now refused.

The horizon is the same argument read the other way, from the **slowest** step
rather than the fastest, which is taken from a full godown. It is **1128** ticks
with the shipped constants, not 600. And because a works contracts a heap more
slowly than a hungry market does, **every crossing now carries its own horizon**
rather than there being one on the constants.

Also fixed, from the untidier list: `lift/3` and `land/3` no longer raise
`badarith` on a quantity no float can hold, and a request for nothing is
answered `bad_quantity` rather than `quay_empty` on a full quay or `godown_full`
on an empty one, which used to send a client that reads its own errors into a
retry loop forever.

Still true and still listed rather than argued: `raise_factory/3`,
`demolish_factory/3` and `resurvey/3` raise where `open/2` returns a problem
list, which is defensible while their arguments come from a configuration file
and not from a stranger; and the census only grows, so a harbour that stops
producing cannot be recorded.

## What the service does not keep

**The heaps on the quays are rebuilt, not stored.** What survives a restart is
custody and receipts, which is what exactly-once is about, and they come off the
ledger. The heaps come back by replaying the settled orders into a market opened
from the standing, at the ticks those orders happened at, so a port that traded
comes back where it was and one that never traded comes back at rest, which is
where it would have been anyway.

What this does **not** recover is a price move caused by something other than a
trade through this service. There is nothing else in this cut, so today the
replay is exact. It stops being exact the moment a fact from another service can
move a crossing, and at that point the six-verb event log the mechanism's own
vocabulary already anticipates is the answer, not a bigger ledger.
