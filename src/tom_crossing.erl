%% @doc Where the two curves meet: the long-run structure of one good at one
%% port.
%%
%% NOTHING THAT ARRIVES HERE IS A PRICE. What arrives is a yield, the rate at
%% which a standard hinterland delivers a good to the quay, and that is the same
%% kind of fact as a recipe's ticks. A rate is physical. It says how fast the
%% world turns something out, not what anybody thinks it is worth.
%%
%% What comes out is a price, because a supply schedule and a demand schedule
%% cross at exactly one of them.
%%
%% THE DEMAND SCHEDULE IS NEVER DECLARED. It is the town's appetite spread over
%% a price, and the appetite is IDENTICAL for all goods. So a port can say it is
%% a big town and it can say its hinterland is wide, and it has no way at all of
%% saying that it thinks musk is fine. Demand is the complement of abundance,
%% which is what the world service already promises.
%%
%% Relative value emerges from yields and from geography, and the exponent
%% 1/(eta+eps) compresses both. With the shipped constants that exponent is
%% 0.556, so a thousandfold difference in price needs a quarter-million-fold
%% difference in yield. You cannot nudge a yield until it hits a price you had
%% in mind, and anyone reading the file can check a yield twice over: against
%% the fiction, a pouch of musk against a river of rice, and against the
%% recipes, since a batch that eats four ore is meaningless unless ore comes out
%% of the ground in bulk. A declared price is checkable against nothing.
%%
%% A FACTORY IS NOT A CURVE, IT IS A COUNTERPARTY. It buys and sells whatever
%% the price, so it enters as a price-inelastic flow and shifts the crossing
%% itself. Folding its rate into the elastic scale instead understates it by
%% roughly forty to one, which reads as a foundry that eats a quarter of a
%% port's copper and moves the copper price by half a percent.
%% @end
-module(tom_crossing).

-export([defaults/0,
         abundance/3,
         of_good/3,
         all/2,
         settling_rate/1,
         settling_horizon/1,
         band_factors/1]).

-export_type([good_id/0, config/0, census/0, survey/0, factory/0, standing/0,
              crossing/0]).

%% @doc A good's permanent identifier. Data, so any atom the caller uses.
-type good_id() :: atom().

%% @doc The dials of the mechanism. Global, never per good.
%%
%% There is deliberately no per-good elasticity. A per-good elasticity would let
%% an author make luxuries behave like luxuries, and that is the door through
%% which declared worth walks back in. Every good responds to scarcity
%% identically, and that is a known and accepted limitation.
-type config() :: #{demand_elasticity := float(),
                    supply_elasticity := float(),
                    stock_sensitivity := float(),
                    cover_ticks       := float(),
                    reserve_ticks     := float(),
                    godown_multiple   := float(),
                    appetite          := float(),
                    harbour_fee       := float(),
                    leak_base         := float(),
                    leak_near         := float(),
                    leak_far          := float()}.

%% @doc How many OTHER harbours this port knows to produce each good, split into
%% those in its own region and those beyond it.
%%
%% Counts harbours, not quantities, and the count is derived from produces lists
%% that already exist. It is the same arithmetic for every good, so it cannot
%% say that musk is special.
%%
%% A GOOD MISSING FROM THIS MAP IS UNSURVEYED, AND THAT IS NOT THE SAME AS A
%% COUNT OF NOUGHT. Nought means the port looked and nobody anywhere makes the
%% thing; absent means the port has not looked. Conflating the two is what once
%% made a port's price JUMP when it learned something, which is the wrong
%% direction and is arbitrage against whoever was behind.
-type census() :: #{good_id() => {NNear :: non_neg_integer(),
                                  NFar :: non_neg_integer()}}.

%% @doc What a port knows about who else makes one good.
-type survey() :: unsurveyed | {non_neg_integer(), non_neg_integer()}.

%% @doc A works standing behind the port. Flows are units per tick, which a
%% recipe already gives: outputs over ticks in, inputs over ticks out.
-type factory() :: #{id := term(),
                     consumes => #{good_id() => float()},
                     yields => #{good_id() => float()}}.

%% @doc Everything a port declares about itself. Three physical fields and two
%% derived ones, and not one of them says what anything is worth.
-type standing() :: #{town := float(),
                      hinterland := float(),
                      goods := #{good_id() => float()},
                      produces => [good_id()],
                      census => census(),
                      factories => [factory()]}.

%% @doc The long-run structure of one good here. Recomputed only when the
%% structure changes, never per tick and never per trade.
-type crossing() :: #{natural_price := float(),
                      throughput := float(),
                      natural_stock := float(),
                      reserve := float(),
                      capacity := float(),
                      anchor := float(),
                      integral_scale := float(),
                      horizon := pos_integer(),
                      demand := float(),
                      supply := float(),
                      inelastic_demand := float(),
                      inelastic_supply := float()}.

%% The two schedules of one good, before they are made to meet. Internal,
%% because a caller has no business holding half a crossing.
-type curve() :: #{demand := float(),
                   supply := float(),
                   inelastic_demand := float(),
                   inelastic_supply := float(),
                   demand_elasticity := float(),
                   supply_elasticity := float()}.

%% Bisection runs on the logarithm of the price, so eighty halvings of a bracket
%% at most 2 * 64 * ln 2 wide leaves nothing behind the decimal point. There is
%% no convergence test because there is nothing a convergence test would catch.
-define(BRACKET_TRIES, 64).
-define(BISECTIONS, 80).

%% How near rest the horizon reaches before a quay is said to have arrived.
%% Doubled where it is used, which takes the relative distance to a thirtieth
%% power of ten, well under the last bit of a double. That is what licenses
%% advance/3 to write the natural stock down rather than approach it.
-define(SETTLED, 1.0e-15).

%% How many heaps the band is sampled at when the contraction is measured.
%%
%% THE RATIO IS SAMPLED BECAUSE IT HAS NO CLOSED FORM, and it is smooth in the
%% heap, being a sum of two powers over a line, so a ladder this dense cannot
%% step over a feature. The alternative was the LINEARISATION AT REST, which is
%% one line of algebra and was wrong: it describes only the last few ticks of
%% the approach and says nothing about the step taken from an empty quay, which
%% is the largest step there is.
-define(SAMPLES, 512).

%% Nearer to rest than this and the ratio is taken from its limit instead. Both
%% the step and the distance go to nought together there, and a quotient of two
%% cancelled differences is noise.
-define(AT_REST, 1.0e-6).

%% @doc The shipped constants.
%%
%% Two of them carry the mechanism. cover_ticks says a resting quay holds eight
%% ticks of throughput, which is what makes the natural stock a quantity rather
%% than an invented number. stock_sensitivity says a heap at half its natural
%% size posts a price at the square root of two above natural, which is what
%% makes the price band eighteen wide and finite at both ends.
-spec defaults() -> config().
defaults() ->
    #{demand_elasticity => 1.4,
      supply_elasticity => 0.4,
      stock_sensitivity => 0.5,
      cover_ticks => 8.0,
      reserve_ticks => 0.25,
      godown_multiple => 10.0,
      appetite => 30.0,
      harbour_fee => 0.02,
      leak_base => 0.004,
      leak_near => 0.060,
      leak_far => 0.006}.

%% @doc How plentiful a good is here, as a multiple of the hinterland's rate.
%%
%% Clause one: the hinterland grows it. Full rate, and the survey is not read.
%%
%% Clause two: the port looked and no harbour anywhere produces it. The good has
%% no geography, so the produces flag carries no information and the declared
%% yield already IS the artisan rate everywhere. A trickle here would be a
%% double discount, and that is what once made cannon so dear at Macao that a
%% cargo of ten could not be landed at all.
%%
%% Clause three: it comes from somewhere else. leak_base is what local gardens
%% and scavenging turn out with no source at all; leak_near is per producing
%% harbour in this port's own region, which is coastal traffic; leak_far is per
%% producing harbour beyond it. The ten to one ratio between them IS the
%% geography gradient, and it is the only place in the mechanism where distance
%% is expressed.
%%
%% Clause four: the port has not looked. It gets leak_base and nothing else,
%% which is precisely what leak_base MEANS, what turns up with no known source
%% at all. That is the scarce end of the ladder, so LEARNING CAN ONLY EVER MAKE
%% A GOOD CHEAPER HERE and never dearer: an unsurveyed good is dearer than one
%% with a single distant producer, which is dearer than one with four.
%%
%% The old arrangement gave ignorance the SAME full rate as clause two, which
%% made a port's price jump thirteenfold the moment it heard its first piece of
%% news. On a mesh where ports learn asynchronously that was a standing
%% arbitrage against everyone who had not caught up, and it paid to trade with
%% the ignorant. Now the port that is behind quotes DEAR, so being behind costs
%% its owner rather than its counterparty.
-spec abundance(config(), boolean(), survey()) -> float().
abundance(_Config, true, _Survey) ->
    1.0;
abundance(_Config, false, {0, 0}) ->
    1.0;
abundance(Config, false, {Near, Far}) when is_integer(Near), Near >= 0,
                                           is_integer(Far), Far >= 0 ->
    maps:get(leak_base, Config)
        + maps:get(leak_near, Config) * Near
        + maps:get(leak_far, Config) * Far;
abundance(Config, false, unsurveyed) ->
    maps:get(leak_base, Config).

%% @doc The crossing for one good at one port.
-spec of_good(config(), standing(), good_id()) -> crossing().
of_good(Config, Standing, Good) ->
    Curve = curve(Config, Standing, Good),
    shaped(Config, Curve, meeting(Curve)).

%% @doc The crossing for every good the port trades.
-spec all(config(), standing()) -> #{good_id() => crossing()}.
all(Config, Standing) ->
    maps:map(fun(Good, _Yield) -> of_good(Config, Standing, Good) end,
             maps:get(goods, Standing)).

%% @doc The longest step any tick will ever take, as a fraction of the distance
%% it had left to go, ANYWHERE IN THE BAND.
%%
%% THE GATE, and it says what it claims now. It used to be the linearisation of
%% the tick at the crossing, which describes the last few ticks of an approach
%% and nothing else: a configuration whose step near an empty quay overshoots
%% and comes back passed the door and then rang forever, one landing and three
%% thousand idle ticks leaving a permanent cycle of two. The number below is the
%% worst step over every heap the godown and the reserve admit, so it covers the
%% empty quay, which is where the largest step is taken.
%%
%% Worst case over ports as well as over heaps, because a factory can only make
%% the step SMALLER. A works buys and sells whatever the price, so its flows do
%% not respond to the heap at all, and replacing part of an elastic flow with a
%% blind one can only shorten the step the heap takes. The factory-free
%% arithmetic therefore bounds every port and every works the game will ever
%% build, and the gate stays one number checked once at the door.
%%
%% Below one the approach is monotone from everywhere. At or above one some heap
%% overshoots, which is a market that rings or diverges, and neither is a
%% market.
-spec settling_rate(config()) -> float().
settling_rate(Config) -> lists:max(contractions(Config, 0.0, 0.0)).

%% @doc After this many idle ticks a quay with no works behind it is at its
%% natural stock and no arithmetic will move it.
%%
%% The natural stock is a genuine fixed point of the tick, so writing it down is
%% exact rather than an approximation, and a port idle for longer costs one
%% comparison per good instead of a thousand ticks of arithmetic.
%%
%% Derived from the SLOWEST step in the band rather than the fastest, which is a
%% different number from the gate's and is the one that has to be true. The
%% slowest step is taken from a full godown, where the price is on the floor and
%% neither side is in a hurry.
%%
%% A works makes it longer, because a blind flow contracts a heap more slowly
%% than a hungry one, so every crossing carries its OWN horizon and this one is
%% the factory-free case. See the horizon field of a crossing.
-spec settling_horizon(config()) -> pos_integer().
settling_horizon(Config) -> horizon(Config, 0.0, 0.0).

%% @doc How far the posted price of any good can be pushed, as multiples of its
%% natural price.
%%
%% Both ends are algebra rather than a clamp. The floor is a full godown, the
%% ceiling a stripped quay holding nothing but its reserve. With the shipped
%% constants the band runs from 0.32 to 5.74, eighteen wide. A famine is not
%% expressible, which is the price of a bounded step and a deliberate trade.
-spec band_factors(config()) -> {float(), float()}.
band_factors(Config) ->
    Tau = maps:get(cover_ticks, Config),
    Min = maps:get(reserve_ticks, Config),
    Gamma = maps:get(stock_sensitivity, Config),
    {math:pow((Tau + Min) / (maps:get(godown_multiple, Config) * Tau + Min),
              Gamma),
     math:pow((Tau + Min) / Min, Gamma)}.

%% Internal

-spec curve(config(), standing(), good_id()) -> curve().
curve(Config, Standing, Good) ->
    #{demand => maps:get(appetite, Config) * maps:get(town, Standing),
      supply => supply_scale(Config, Standing, Good),
      inelastic_demand => factory_flow(consumes, Standing, Good),
      inelastic_supply => factory_flow(yields, Standing, Good),
      demand_elasticity => maps:get(demand_elasticity, Config),
      supply_elasticity => maps:get(supply_elasticity, Config)}.

%% The whole of a good's individuality: its yield, the land behind the port, and
%% how far away everyone else who makes it stands.
%%
%% A good the census does not mention is UNSURVEYED, not surveyed-and-empty, and
%% the default below is the whole of the difference.
supply_scale(Config, Standing, Good) ->
    Survey = maps:get(Good, maps:get(census, Standing, #{}), unsurveyed),
    Produced = lists:member(Good, maps:get(produces, Standing, [])),
    maps:get(Good, maps:get(goods, Standing))
        * maps:get(hinterland, Standing)
        * abundance(Config, Produced, Survey).

factory_flow(Side, Standing, Good) ->
    lists:foldl(fun(Works, Sum) -> Sum + flow(Works, Side, Good) end,
                0.0, maps:get(factories, Standing, [])).

flow(Works, Side, Good) ->
    maps:get(Good, maps:get(Side, Works, #{}), 0.0).

%% Whether a factory stands here is a fact about the arithmetic, not about the
%% economics. The curves are the same curves either way; with no inelastic flow
%% they cross somewhere with a closed form, and with one they do not.
meeting(Curve) ->
    met(Curve, inelastic(Curve) > 0.0).

inelastic(#{inelastic_demand := In, inelastic_supply := Out}) -> In + Out.

met(#{demand := D, supply := Y,
      demand_elasticity := Eta, supply_elasticity := Eps} = Curve, false) ->
    Span = Eta + Eps,
    {frictionless_price(Curve),
     math:pow(D, Eps / Span) * math:pow(Y, Eta / Span)};
met(#{demand := D, demand_elasticity := Eta, inelastic_demand := In} = Curve,
    true) ->
    Pbar = root(Curve, frictionless_price(Curve)),
    {Pbar, D * math:pow(Pbar, -Eta) + In}.

frictionless_price(#{demand := D, supply := Y,
                     demand_elasticity := Eta, supply_elasticity := Eps}) ->
    math:pow(D / Y, 1.0 / (Eta + Eps)).

%% Supply minus demand. Strictly increasing, minus infinity at nothing and plus
%% infinity at everything, so it has exactly one root and bisection cannot be
%% fooled about which side of it it is on.
gap(#{demand := D, supply := Y, inelastic_demand := In, inelastic_supply := Out,
      demand_elasticity := Eta, supply_elasticity := Eps}, P) ->
    Y * math:pow(P, Eps) + Out - D * math:pow(P, -Eta) - In.

root(Curve, Seed) ->
    {Lo, Hi} = bracket(Curve, Seed, 1),
    bisect(Curve, math:log(Lo), math:log(Hi), ?BISECTIONS).

bracket(_Curve, _Seed, J) when J > ?BRACKET_TRIES ->
    error(no_bracket);
bracket(Curve, Seed, J) ->
    Width = math:pow(2.0, J),
    widened(Curve, Seed, J, Seed / Width, Seed * Width).

widened(Curve, Seed, J, Lo, Hi) ->
    bracketed(Curve, Seed, J, Lo, Hi,
              gap(Curve, Lo) < 0.0 andalso gap(Curve, Hi) > 0.0).

bracketed(_Curve, _Seed, _J, Lo, Hi, true) -> {Lo, Hi};
bracketed(Curve, Seed, J, _Lo, _Hi, false) -> bracket(Curve, Seed, J + 1).

bisect(_Curve, LnLo, LnHi, 0) ->
    math:exp((LnLo + LnHi) / 2.0);
bisect(Curve, LnLo, LnHi, N) ->
    Mid = (LnLo + LnHi) / 2.0,
    narrowed(Curve, LnLo, LnHi, N, Mid, gap(Curve, math:exp(Mid)) < 0.0).

narrowed(Curve, _LnLo, LnHi, N, Mid, true) -> bisect(Curve, Mid, LnHi, N - 1);
narrowed(Curve, LnLo, _LnHi, N, Mid, false) -> bisect(Curve, LnLo, Mid, N - 1).

%% The natural stock is what the crossing implies, not a number anyone chose:
%% eight ticks of throughput, because that is what cover_ticks says a quay
%% holds. Depth follows from the town and the hinterland TOGETHER, while price
%% follows from their ratio, which is why a bigger town is deeper without being
%% dearer.
shaped(Config, Curve, {Pbar, Qbar}) ->
    Gamma = maps:get(stock_sensitivity, Config),
    Sbar = maps:get(cover_ticks, Config) * Qbar,
    Res = maps:get(reserve_ticks, Config) * Qbar,
    Anchor = Sbar + Res,
    #{natural_price => Pbar,
      throughput => Qbar,
      natural_stock => Sbar,
      reserve => Res,
      capacity => maps:get(godown_multiple, Config) * Sbar,
      anchor => Anchor,
      integral_scale => Pbar * math:pow(Anchor, Gamma) / (1.0 - Gamma),
      horizon => horizon(Config,
                         maps:get(inelastic_supply, Curve) / Qbar,
                         maps:get(inelastic_demand, Curve) / Qbar),
      demand => maps:get(demand, Curve),
      supply => maps:get(supply, Curve),
      inelastic_demand => maps:get(inelastic_demand, Curve),
      inelastic_supply => maps:get(inelastic_supply, Curve)}.

%% The contraction ------------------------------------------------------

%% How long until a quay whose flows are this blind has arrived.
%%
%% Every tick closes at least the slowest fraction of what is left, and the band
%% is invariant once the gate has passed, so the distance falls by that fraction
%% compounded and the count is a logarithm. Doubling it takes the remaining
%% distance below the last bit of a double, which is what makes arrival exact.
horizon(Config, Out, In) ->
    2 * ceil(math:log(?SETTLED)
             / math:log(1.0 - lists:min(contractions(Config, Out, In)))).

%% The step a tick takes, as a fraction of the distance it had left, at every
%% heap the band admits.
%%
%% Out and In are the shares of the throughput that a works accounts for on each
%% side, so nought and nought is a port with no works behind it. Everything else
%% divides out: the shape of this ladder depends on the constants and on those
%% two shares and on nothing about the good, which is why one scan answers for a
%% whole port.
contractions(Config, Out, In) ->
    {Low, High} = heap_span(Config),
    Ladder = [Low * math:pow(High / Low, K / ?SAMPLES)
              || K <- lists:seq(0, ?SAMPLES)],
    [at_rest_contraction(Config, Out, In)
     | [contraction(Config, Out, In, U)
        || U <- Ladder, abs(1.0 - U) > ?AT_REST]].

%% The heap, counted in anchors, at an empty quay and at a full godown. One is
%% the reserve alone and the other is the godown plus the reserve, both over the
%% anchor, and the throughput divides out of all three.
heap_span(Config) ->
    Min = maps:get(reserve_ticks, Config),
    Tau = maps:get(cover_ticks, Config),
    {Min / span(Config),
     (maps:get(godown_multiple, Config) * Tau + Min) / span(Config)}.

contraction(Config, Out, In, U) ->
    abs(normal_step(Config, Out, In, U)) / (span(Config) * abs(1.0 - U)).

%% One tick's net flow, counted in throughputs, at a heap counted in anchors.
%% The price at that heap is the anchor over the heap, raised to the stock
%% sensitivity, times the natural price, and the natural price divides out.
normal_step(Config, Out, In, U) ->
    Ratio = math:pow(U, -maps:get(stock_sensitivity, Config)),
    (1.0 - Out) * math:pow(Ratio, maps:get(supply_elasticity, Config)) + Out
        - (1.0 - In) * math:pow(Ratio, -maps:get(demand_elasticity, Config))
        - In.

%% The same quantity in the limit at rest, where the step and the distance have
%% both gone to nought and the quotient is the derivative.
at_rest_contraction(Config, Out, In) ->
    maps:get(stock_sensitivity, Config)
        * ((1.0 - Out) * maps:get(supply_elasticity, Config)
           + (1.0 - In) * maps:get(demand_elasticity, Config))
        / span(Config).

%% How many ticks of throughput a resting quay and its reserve hold together.
%% Every distance in this module is counted in these.
span(Config) ->
    maps:get(cover_ticks, Config) + maps:get(reserve_ticks, Config).
