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
         abundance/4,
         of_good/3,
         all/2,
         settling_rate/1,
         settling_horizon/1,
         band_factors/1]).

-export_type([good_id/0, config/0, census/0, factory/0, standing/0,
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
-type census() :: #{good_id() => {NNear :: non_neg_integer(),
                                  NFar :: non_neg_integer()}}.

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

%% How far past machine precision the settling horizon reaches. Doubled, because
%% the linearised rate is only the behaviour near rest and the approach from an
%% empty quay is slower than the linear one.
-define(SETTLED, 1.0e-15).

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
%% Clause one: the hinterland grows it. Full rate.
%%
%% Clause two: no harbour anywhere is known to produce it. The good has no
%% geography, so the produces flag carries no information and the declared yield
%% already IS the artisan rate everywhere. A trickle here would be a double
%% discount, and that is what once made cannon so dear at Macao that a cargo of
%% ten could not be landed at all.
%%
%% Clause three: it comes from somewhere else. leak_base is what local gardens
%% and scavenging turn out with no source at all; leak_near is per producing
%% harbour in this port's own region, which is coastal traffic; leak_far is per
%% producing harbour beyond it. The ten to one ratio between them IS the
%% geography gradient, and it is the only place in the mechanism where distance
%% is expressed.
-spec abundance(config(), boolean(), non_neg_integer(), non_neg_integer()) ->
          float().
abundance(_Config, true, _Near, _Far) ->
    1.0;
abundance(_Config, false, 0, 0) ->
    1.0;
abundance(Config, false, Near, Far) when is_integer(Near), Near >= 0,
                                         is_integer(Far), Far >= 0 ->
    maps:get(leak_base, Config)
        + maps:get(leak_near, Config) * Near
        + maps:get(leak_far, Config) * Far.

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

%% @doc The worst case per-tick contraction toward rest.
%%
%% Worst case because a factory can only make it smaller. Both elastic flows at
%% the crossing are the throughput minus an inelastic part, so the factory-free
%% value bounds every port and every works the game will ever build, and the
%% gate is therefore one inequality on four global constants checked once.
%%
%% Below one the approach is monotone. Between one and two it rings. Above two
%% it diverges, and a market that diverges is not a market.
-spec settling_rate(config()) -> float().
settling_rate(Config) ->
    maps:get(stock_sensitivity, Config)
        * (maps:get(demand_elasticity, Config)
           + maps:get(supply_elasticity, Config))
        / (maps:get(cover_ticks, Config) + maps:get(reserve_ticks, Config)).

%% @doc After this many idle ticks a quay is at its natural stock and no
%% arithmetic will move it.
%%
%% The natural stock is a genuine fixed point of the tick, so snapping to it is
%% exact rather than an approximation. With the shipped constants this is six
%% hundred ticks, and a port idle for longer than that costs one comparison per
%% good instead of six hundred.
-spec settling_horizon(config()) -> pos_integer().
settling_horizon(Config) ->
    2 * ceil(math:log(?SETTLED) / math:log(1.0 - settling_rate(Config))).

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
supply_scale(Config, Standing, Good) ->
    {Near, Far} = maps:get(Good, maps:get(census, Standing, #{}), {0, 0}),
    Produced = lists:member(Good, maps:get(produces, Standing, [])),
    maps:get(Good, maps:get(goods, Standing))
        * maps:get(hinterland, Standing)
        * abundance(Config, Produced, Near, Far).

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
      demand => maps:get(demand, Curve),
      supply => maps:get(supply, Curve),
      inelastic_demand => maps:get(inelastic_demand, Curve),
      inelastic_supply => maps:get(inelastic_supply, Curve)}.
