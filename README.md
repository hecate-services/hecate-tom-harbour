# hecate-tom-harbour

**TOM, Traders of Macao.** One port, and the market behind it.

*This exists so that a trader can look at a price and know why it is that
number.*

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

| Module | Is |
|--------|-----|
| `tom_market` | **The facade.** The port, its clock, and the folding of facts. The only module a caller needs |
| `tom_quay` | One good's stack: its heap, its posted price, its trades, its tick |
| `tom_crossing` | Where the two curves meet. The long-run structure of one good here |

| In `test/` | Is |
|------------|-----|
| `tom_sim` | A hand crank. Runs a port forward with a script of orders and gives back the price series |

**A market is a term.** You pass one in and you get one back. Nothing here reads
a clock, opens a socket or spawns a process, so it is testable and simulatable,
which is the whole point. The service that owns a market and the slice that
publishes its facts are somebody else's file, and neither needs anything here to
change.

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
9>  M2 = tom_market:sight_harbour(M1, 50, #{nutmeg => far}).
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

## Running one

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

## Build

```bash
rebar3 eunit
rebar3 lint
rebar3 dialyzer
```

## License

Apache-2.0. See [LICENSE](LICENSE).

## What is known to be wrong

Found by four independent probes against the built code, 2026-08-11. The
mechanism itself behaves: 192 cases of six ports by eight goods by four starting
stocks, 1200 ticks each, zero non-monotone steps, zero overshoots, zero
out-of-band prices, worst residual 9.87e-13. Round trip loses exactly 3.921569%
at every size in both directions and a 20,000-sequence search found no closing
cycle, so there is no money pump.

These three are faults in the collar around it, all reachable through the facade.

**1. The horizon snap deletes goods.** `advance/3` snaps the stock to natural
whenever the elapsed ticks reach the horizon, without asking whether the quay
could have got there. After a large works is demolished, `settle(+600)` in one
call reports stock 13.36 at the natural price and `at_rest` true, while six
hundred calls of `settle(+1)` give stock 1,398,238 and a price 318x away. Same
elapsed time, 1.4e6 units of musk deleted, and the wrong answer is the one that
looks right. Snap only when the stock is inside the range the band and the
horizon are valid for, and crank otherwise.

**2. `sight_harbour/3` moves a price the wrong way on the first news.**
`abundance/4` cannot tell "surveyed, nobody makes this" from "we have not heard
yet". Cannon at Macao is 77.22 while nobody is known to make them and 997.37 the
moment one distant producer is sighted. On a mesh where ports learn
asynchronously that is a standing 12.9x arbitrage against every port that has not
caught up, and it rewards trading with the ignorant. Ignorance has to be a state
in the census, not a value of the count.

**3. The settling gate is advertised as sufficient and is not.** It is the
linearisation at the fixed point. `open/2` accepts a legal configuration whose
market never settles: one landing then 3000 idle ticks leaves a permanent
period-2 cycle. The shipped constants are safe, so this is a guarantee that does
not exist rather than a market that is broken today, but the snap in fault 1 is
what turns it into a silent wrong answer.

Untidier, and listed rather than argued: `land/4` raises `badarith` on a bignum
quantity in a function documented as taking arguments from a stranger;
`raise_factory/3`, `demolish_factory/3` and `resurvey/3` validate nothing where
`open/2` returns a problem list; the error vocabulary answers `godown_full` on an
empty godown and `quay_empty` on a full quay, so a client that retries loops
forever; and the census only grows, so a harbour that stops producing cannot be
recorded.
