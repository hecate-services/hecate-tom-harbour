%% @doc THE FACADE. One port, its market, its clock, and the folding of facts.
%%
%% A market is a term. You pass one in and you get one back, and nothing here
%% reads a clock, opens a socket or spawns a process. The service that owns a
%% market and the slice that publishes its facts are somebody else's file. This
%% is the mechanism, and it is complete without them.
%%
%% A TICK IS NOT A CLOCK. Every mutating call carries the tick it happens at.
%% The port service converts wall time to ticks at whatever cadence it chose
%% when it opened. That keeps every function pure and every test deterministic,
%% and it is why replay works.
%%
%% THE ORDERING RULE IS ENFORCED, NOT DOCUMENTED. No exported function lets a
%% caller change a market's structure without settling it first, because a
%% crossing rewritten out of order retroactively rewrites every tick since the
%% last stamp. The error is silent, plausible and unrecoverable, so the fix is
%% not a comment. It is that every fact fold settles to its own tick before it
%% touches anything.
%%
%% WITHIN A TICK, ARRIVAL ORDER. Two traders trading in the same tick get
%% different prices, and the second one sees what the first one did. There is no
%% batching and no clearing auction, because that is what a market is.
%%
%% COIN IS NOT SILVER. Coin is an abstract unit of account. Silver and gold are
%% ordinary goods with ordinary crossings, so they go for something different at
%% every port, which is the entire reason the Manila galleon existed. Making
%% silver the numeraire would delete the game's central trade. Scaling the
%% appetite scales every price together, which is precisely what choosing a
%% currency unit does.
%%
%% MONEY IS NOT CONSERVED. The town's purse is unmodelled and bottomless, and
%% the harbour fee is the only sink. Giving the town a treasury would introduce
%% a lagged feedback from price back to demand, which is exactly the thing the
%% settling argument depends on not existing. Conserving money and guaranteeing
%% that prices settle are in tension, and this mechanism chooses settling.
%% @end
-module(tom_market).

-export([open/1,
         open/2,
         open/3,
         config/1,
         standing/1,
         tick/1,
         goods/1,
         quay/2,
         crossing/2,
         natural_price/2,
         price_band/2,
         stock/2,
         settle/2,
         quote/2,
         quote/3,
         in_terms_of/3,
         depth/3,
         lift/4,
         land/4,
         raise_factory/3,
         demolish_factory/3,
         resurvey/3]).

-export_type([market/0, problem/0]).

-type market() :: #{config := tom_crossing:config(),
                    standing := tom_crossing:standing(),
                    tick := integer(),
                    quays := #{tom_crossing:good_id() => tom_quay:quay()}}.

%% @doc Everything that can be wrong with a market before it opens.
-type problem() :: {bad_config, atom(), term()}
                 | {gate_not_met, float()}
                 | {bad_town, term()}
                 | {bad_hinterland, term()}
                 | {bad_yield, tom_crossing:good_id(), term()}
                 | {produces_unknown_good, tom_crossing:good_id()}
                 | {census_unknown_good, tom_crossing:good_id()}
                 | {factory_unknown_good, term(), tom_crossing:good_id()}
                 | {duplicate_factory, term()}.

%% @doc Open a port on the shipped constants.
-spec open(tom_crossing:standing()) -> {ok, market()} | {error, [problem()]}.
open(Standing) -> open(Standing, tom_crossing:defaults(), 0).

%% @doc Open a port.
%%
%% Reports EVERY problem it found, not the first, which is the same promise the
%% world service makes about a world file. A half-opened market is worse than
%% none, and a caller who has to fix eleven constants one round trip at a time
%% will stop reading the errors.
-spec open(tom_crossing:standing(), tom_crossing:config()) ->
          {ok, market()} | {error, [problem()]}.
open(Standing, Config) -> open(Standing, Config, 0).

%% @doc Open a port at a tick.
%%
%% A MARKET OPENS AT THE TICK IT IS AT, and the third argument exists because
%% forgetting is now a thing markets do. A tick is the wall clock divided by the
%% length of one, so it is counted from the epoch and not from the game: a market
%% opened at nought and then settled to now would be handed fifty-six years of
%% elapsed time on its first breath, and the trickle a world file seeded it with
%% would decay to nothing before anybody had bought anything.
-spec open(tom_crossing:standing(), tom_crossing:config(), integer()) ->
          {ok, market()} | {error, [problem()]}.
open(Standing, Config, AtTick) ->
    opened(Config, Standing, AtTick, problems(Config, Standing)).

%% @doc The constants this market runs on.
-spec config(market()) -> tom_crossing:config().
config(Market) -> maps:get(config, Market).

%% @doc What the port declares about itself.
-spec standing(market()) -> tom_crossing:standing().
standing(Market) -> maps:get(standing, Market).

%% @doc The tick this market is settled to.
-spec tick(market()) -> integer().
tick(Market) -> maps:get(tick, Market).

%% @doc Every good traded here, ordered.
-spec goods(market()) -> [tom_crossing:good_id()].
goods(Market) -> lists:sort(maps:keys(maps:get(quays, Market))).

%% @doc One good's quay. Crashes on a good this port does not trade, because
%% this is a local read and an unknown good is a bug in the caller.
-spec quay(market(), tom_crossing:good_id()) -> tom_quay:quay().
quay(Market, Good) -> maps:get(Good, maps:get(quays, Market)).

%% @doc One good's crossing.
-spec crossing(market(), tom_crossing:good_id()) -> tom_crossing:crossing().
crossing(Market, Good) -> tom_quay:crossing(quay(Market, Good)).

%% @doc What a good would go for on a quay standing at its natural stock.
-spec natural_price(market(), tom_crossing:good_id()) -> float().
natural_price(Market, Good) -> maps:get(natural_price, crossing(Market, Good)).

%% @doc How far a good can be driven here, at the bottom and at the top.
-spec price_band(market(), tom_crossing:good_id()) -> {float(), float()}.
price_band(Market, Good) ->
    tom_quay:price_band(config(Market), quay(Market, Good)).

%% @doc What is on a good's quay.
-spec stock(market(), tom_crossing:good_id()) -> float().
stock(Market, Good) -> tom_quay:stock(quay(Market, Good)).

%% @doc Bring the market up to a tick.
%%
%% Guarded rather than clamped: a clock going backwards is a bug in the port
%% service and a market that quietly accepts one will produce plausible prices
%% for the rest of the game.
%%
%% Settling to the tick it already stands at is free rather than nearly free,
%% because the port service winds its clock on far more often than a tick
%% actually turns over and rebuilding sixty seven quays to change nothing is
%% still rebuilding sixty seven quays.
-spec settle(market(), integer()) -> market().
settle(#{tick := Now} = Market, Now) ->
    Market;
settle(#{tick := Now} = Market, AtTick)
  when is_integer(AtTick), AtTick >= Now ->
    Config = config(Market),
    Elapsed = AtTick - Now,
    Onward = fun(_Good, Quay) -> tom_quay:advance(Config, Quay, Elapsed) end,
    forgotten(Market#{tick := AtTick,
                      quays := maps:map(Onward, maps:get(quays, Market))},
              Elapsed).

%% WHAT A QUAY KNOWS ABOUT PLENTY IS WHAT IT HAS SEEN LATELY, so it fades. A
%% port nobody calls at drifts back to leak_base and everything it does not grow
%% becomes precious, which is the correct account of a port nobody calls at. It
%% is also what keeps the world file's census a seed rather than a law: the
%% opening trickle decays like any other landing unless play sustains it.
%%
%% Only the goods with something to forget are touched, and a good at rest costs
%% nothing, which is the same bargain the quays already strike.
forgotten(Market, Elapsed) ->
    Config = config(Market),
    Standing = standing(Market),
    Landings = maps:get(landings, Standing, #{}),
    Moved = [Good || {Good, Landed} <- maps:to_list(Landings),
                     is_number(Landed), Landed > 0.0],
    faded(Market, Config, Standing, Landings, Moved, Elapsed).

faded(Market, _Config, _Standing, _Landings, [], _Elapsed) ->
    Market;
faded(Market, Config, Standing, Landings, Moved, Elapsed) ->
    Older = maps:map(fun(_G, L) -> tom_crossing:faded(Config, L, Elapsed) end,
                     Landings),
    Config = config(Market),
    Rebuild = fun(Good, Acc) ->
                      recrossed(Config, Standing#{landings => Older}, Good, Acc)
              end,
    Market#{standing := Standing#{landings => Older},
            quays := lists:foldl(Rebuild, maps:get(quays, Market), Moved)}.

%% @doc What a good goes for, at the tick this market is already settled to.
-spec quote(market(), tom_crossing:good_id()) -> float().
quote(Market, Good) ->
    tom_quay:posted_price(config(Market), quay(Market, Good)).

%% @doc What a good would go for at a later tick. Settles a copy and throws it
%% away, so asking does not move the market on.
-spec quote(market(), tom_crossing:good_id(), integer()) -> float().
quote(Market, Good, AtTick) -> quote(settle(Market, AtTick), Good).

%% @doc One good priced in another.
%%
%% The most legible statement of the law there is. A price is a pure ratio, and
%% a good is dearer than another exactly in proportion to how much less of it
%% arrives, raised to one over the sum of the elasticities. Nobody wrote either
%% number down.
-spec in_terms_of(market(), tom_crossing:good_id(), tom_crossing:good_id()) ->
          float().
in_terms_of(Market, Good, Other) -> quote(Market, Good) / quote(Market, Other).

%% @doc What it would take to walk a good's price to a given number.
-spec depth(market(), tom_crossing:good_id(), float()) -> tom_quay:reach().
depth(Market, Good, ToPrice) ->
    tom_quay:depth(config(Market), quay(Market, Good), ToPrice).

%% @doc Take goods off a quay, at a tick.
%%
%% Answers unknown_good rather than crashing, because this and land/4 are the
%% two functions that will one day take their arguments from a stranger on the
%% mesh. A peer that has not heard of a good is the world service's soft
%% failure, not a fault.
-spec lift(market(), tom_crossing:good_id(), number(), integer()) ->
          {ok, float(), float(), market()}
              | {error, quay_empty | unknown_good | bad_quantity}.
lift(Market, Good, Requested, AtTick) ->
    lifting(Market, Good, Requested, AtTick, trades(Market, Good)).

%% @doc Put goods on a quay, at a tick.
-spec land(market(), tom_crossing:good_id(), number(), integer()) ->
          {ok, float(), float(), market()}
              | {error, godown_full | unknown_good | bad_quantity}.
land(Market, Good, Requested, AtTick) ->
    brought(landing(Market, Good, Requested, AtTick, trades(Market, Good)),
            Good, AtTick).

%% WHAT ARRIVES IS WHAT MAKES A THING COMMON HERE, and this is the whole of the
%% feedback the mechanism was missing. A cargo does two things now: it puts a
%% heap on the quay, which is the short run and recovers, and it raises the rate
%% at which this port has been seeing the good, which is the long run and moves
%% the crossing itself. Land enough here often enough and the port becomes a
%% place where the thing is ordinary.
brought({ok, Filled, Coin, Market}, Good, AtTick) ->
    Standing = standing(Market),
    Was = maps:get(Good, maps:get(landings, Standing, #{}), 0.0),
    Now = arrived(Was, tom_crossing:landing(config(Market), Standing, Good,
                                            Filled)),
    Landings = maps:put(Good, Now, maps:get(landings, Standing, #{})),
    {ok, Filled, Coin,
     restructure(Market, AtTick, Standing#{landings => Landings}, [Good])};
brought(Other, _Good, _AtTick) ->
    Other.

%% A good with no geography stays that way. Landing cannon at a port does not
%% teach it that cannon grow somewhere.
arrived(no_geography, _Added) -> no_geography;
arrived(Was, Added)           -> Was + Added.

%% @doc A works opens behind the port.
%%
%% It needs no new rule. It is another counterparty, buying and selling whatever
%% the price, so it shifts the crossing rather than bending a curve: its buying
%% lifts its input price and its selling depresses its output price until it
%% strangles itself. That is permanent structure, not a wobble in the stock.
-spec raise_factory(market(), integer(), tom_crossing:factory()) -> market().
raise_factory(Market, AtTick, Factory) ->
    Works = admitted(Market, normal_factory(Factory)),
    Standing = standing(Market),
    Standing1 = Standing#{factories =>
                              maps:get(factories, Standing, []) ++ [Works]},
    restructure(Market, AtTick, Standing1, factory_goods(Works)).

%% @doc A works closes.
-spec demolish_factory(market(), integer(), term()) -> market().
demolish_factory(Market, AtTick, FactoryId) ->
    Standing = standing(Market),
    Standing0 = maps:get(factories, Standing, []),
    Works = razed(FactoryId, Standing0),
    restructure(Market, AtTick,
                Standing#{factories => lists:delete(Works, Standing0)},
                factory_goods(Works)).

%% @doc The town grew, or the survey was wrong.
%%
%% Affects every good identically, which is the point of both numbers: town is a
%% headcount and hinterland is an extent of land, and neither can reach a single
%% good.
-spec resurvey(market(), integer(),
               #{town => number(), hinterland => number()}) -> market().
resurvey(Market, AtTick, Survey) ->
    Wanted = maps:with([town, hinterland], Survey),
    Standing = maps:merge(standing(Market), surveyed(Wanted, unsound(Wanted))),
    restructure(Market, AtTick, Standing, goods(Market)).

%% Internal

opened(Config, Standing, AtTick, []) ->
    Sound = normal_config(Config),
    Here = seeded(Sound, normal_standing(Standing)),
    Opened = fun(_Good, Crossing) -> tom_quay:open(Crossing) end,
    {ok, #{config => Sound,
           standing => Here,
           tick => AtTick,
           quays => maps:map(Opened, tom_crossing:all(Sound, Here))}};
opened(_Config, _Standing, _AtTick, Problems) ->
    {error, Problems}.

trades(Market, Good) -> maps:is_key(Good, maps:get(quays, Market)).

lifting(_Market, _Good, _Requested, _AtTick, false) ->
    {error, unknown_good};
lifting(Market0, Good, Requested, AtTick, true) ->
    Market = settle(Market0, AtTick),
    lifted(Market, Good,
           tom_quay:lift(config(Market), quay(Market, Good), Requested)).

lifted(Market, Good, {ok, Filled, Coin, Quay}) ->
    {ok, Filled, Coin, restocked(Market, Good, Quay)};
lifted(_Market, _Good, {error, Why}) ->
    {error, Why}.

landing(_Market, _Good, _Requested, _AtTick, false) ->
    {error, unknown_good};
landing(Market0, Good, Requested, AtTick, true) ->
    Market = settle(Market0, AtTick),
    landed(Market, Good,
           tom_quay:land(config(Market), quay(Market, Good), Requested)).

landed(Market, Good, {ok, Filled, Coin, Quay}) ->
    {ok, Filled, Coin, restocked(Market, Good, Quay)};
landed(_Market, _Good, {error, Why}) ->
    {error, Why}.

restocked(Market, Good, Quay) ->
    Market#{quays := maps:put(Good, Quay, maps:get(quays, Market))}.

%% SETTLE FIRST, ALWAYS. This is the one line that makes the ordering rule real.
%% @doc The landed rates a world file's census implies, applied once.
%%
%% After this nothing reads the census again. It said how many harbours near and
%% far produced a good when the game began, which is a fine way to say what was
%% arriving here THEN, and a hopeless way to say what is arriving now.
seeded(Config, Standing) ->
    Census = maps:get(census, Standing, #{}),
    Landings = maps:from_list(
                 [{Good, tom_crossing:seed(Config, maps:get(Good, Census,
                                                            unsurveyed))}
                  || Good <- maps:keys(maps:get(goods, Standing))]),
    Standing#{landings => Landings}.

restructure(Market0, AtTick, Standing, Affected) ->
    Market = settle(Market0, AtTick),
    Config = config(Market),
    Rebuild = fun(Good, Acc) -> recrossed(Config, Standing, Good, Acc) end,
    Quays = lists:foldl(Rebuild, maps:get(quays, Market), Affected),
    Market#{standing := Standing, quays := Quays}.

recrossed(Config, Standing, Good, Quays) ->
    Crossing = tom_crossing:of_good(Config, Standing, Good),
    Quays#{Good => tom_quay:re_cross(maps:get(Good, Quays), Crossing)}.


admitted(Market, Factory) ->
    Strangers = [Good || Good <- factory_goods(Factory),
                         not trades(Market, Good)],
    Standing = maps:get(factories, standing(Market), []),
    Known = [maps:get(id, Works) || Works <- Standing],
    checked(Factory, lists:member(maps:get(id, Factory), Known), Strangers).

checked(Factory, false, []) ->
    Factory;
checked(Factory, true, _Strangers) ->
    error({duplicate_factory, maps:get(id, Factory)});
checked(Factory, false, [Good | _]) ->
    error({factory_unknown_good, maps:get(id, Factory), Good}).

razed(FactoryId, Factories) ->
    only(FactoryId, [Works || Works <- Factories,
                              maps:get(id, Works) =:= FactoryId]).

only(_FactoryId, [Works | _]) -> Works;
only(FactoryId, []) -> error({unknown_factory, FactoryId}).

factory_goods(Factory) ->
    lists:usort(maps:keys(maps:get(consumes, Factory, #{}))
                ++ maps:keys(maps:get(yields, Factory, #{}))).

unsound(Survey) ->
    [Key || {Key, Value} <- maps:to_list(Survey), not positive(Value)].

surveyed(Survey, []) -> maps:map(fun(_Key, Value) -> Value * 1.0 end, Survey);
surveyed(_Survey, Unsound) -> error({bad_survey, Unsound}).

%% Checks -----------------------------------------------------------------

problems(Config, Standing) ->
    config_problems(Config)
        ++ gate_problems(Config)
        ++ standing_problems(Standing)
        ++ yield_problems(Standing)
        ++ produces_problems(Standing)
        ++ census_problems(Standing)
        ++ factory_problems(Standing).

config_problems(Config) ->
    [{bad_config, Key, maps:get(Key, Config, undefined)}
     || {Key, Test} <- config_rules(),
        not Test(maps:get(Key, Config, undefined))].

config_rules() ->
    [{demand_elasticity, fun positive/1},
     {supply_elasticity, fun positive/1},
     {stock_sensitivity, fun fraction/1},
     {cover_ticks, fun positive/1},
     {reserve_ticks, fun positive/1},
     {godown_multiple, fun above_one/1},
     {appetite, fun positive/1},
     {harbour_fee, fun bounded_fee/1},
     {leak_base, fun positive/1},
     {leak_near, fun positive/1},
     {leak_far, fun positive/1},
     %% How long a quay remembers what was landed on it. Long enough that a
     %% world holds its shape across an evening, short enough that a port
     %% nobody calls at goes quiet.
     {landing_horizon, fun positive/1}].

positive(Value) -> is_number(Value) andalso Value > 0.

%% Strictly inside nought and one, because at one the trade integral is a
%% logarithm and at nought the heap stops mattering.
fraction(Value) -> is_number(Value) andalso Value > 0 andalso Value < 1.

above_one(Value) -> is_number(Value) andalso Value > 1.

bounded_fee(Value) -> is_number(Value) andalso Value >= 0 andalso Value < 1.

%% THE GATE. One number, checked once, covering every port and every works the
%% game will ever build: the longest step any tick takes anywhere in the band,
%% as a fraction of the distance it had left. At or above one some heap
%% overshoots and the market rings rather than settling.
%%
%% It used to be the linearisation at the crossing, which is the behaviour of
%% the last few ticks of an approach and says nothing about the step taken from
%% an empty quay. That gate passed configurations whose markets never settled.
gate_problems(Config) ->
    Sound = fun({Key, Test}) -> Test(maps:get(Key, Config, undefined)) end,
    gate(Config, lists:all(Sound, gate_rules())).

%% godown_multiple is here because the gate now scans the WHOLE band and the
%% godown is where the band ends. The old gate read only the crossing and could
%% get away without it.
gate_rules() ->
    Wanted = [stock_sensitivity, demand_elasticity, supply_elasticity,
              cover_ticks, reserve_ticks, godown_multiple],
    [Rule || {Key, _Test} = Rule <- config_rules(), lists:member(Key, Wanted)].

gate(_Config, false) -> [];
gate(Config, true) -> rate(tom_crossing:settling_rate(Config)).

rate(Rate) when Rate < 1.0 -> [];
rate(Rate) -> [{gate_not_met, Rate * 1.0}].

standing_problems(Standing) ->
    Town = maps:get(town, Standing, undefined),
    Land = maps:get(hinterland, Standing, undefined),
    [{bad_town, Town} || not positive(Town)]
        ++ [{bad_hinterland, Land} || not positive(Land)].

yield_problems(Standing) ->
    Yields = lists:sort(maps:to_list(maps:get(goods, Standing, #{}))),
    [{bad_yield, Good, Yield} || {Good, Yield} <- Yields, not positive(Yield)].

produces_problems(Standing) ->
    Goods = maps:get(goods, Standing, #{}),
    [{produces_unknown_good, Good}
     || Good <- maps:get(produces, Standing, []), not maps:is_key(Good, Goods)].

census_problems(Standing) ->
    Goods = maps:get(goods, Standing, #{}),
    [{census_unknown_good, Good}
     || Good <- lists:sort(maps:keys(maps:get(census, Standing, #{}))),
        not maps:is_key(Good, Goods)].

factory_problems(Standing) ->
    Factories = maps:get(factories, Standing, []),
    lists:flatmap(fun(Works) -> factory_problem(Standing, Works) end, Factories)
        ++ duplicate_factories(Factories).

factory_problem(Standing, Works) ->
    Goods = maps:get(goods, Standing, #{}),
    [{factory_unknown_good, maps:get(id, Works, unnamed), Good}
     || Good <- factory_goods(Works), not maps:is_key(Good, Goods)].

duplicate_factories(Factories) ->
    Ids = [maps:get(id, Works, unnamed) || Works <- Factories],
    [{duplicate_factory, Id} || Id <- lists:usort(Ids -- lists:usort(Ids))].

%% Coercion ---------------------------------------------------------------

%% Every number inside is a float, so that dialyzer never sees number() and the
%% arithmetic never has an integer division hiding in it. Integers are welcome
%% at the boundary and are multiplied by one on the way in.

normal_config(Config) ->
    maps:map(fun(_Key, Value) -> Value * 1.0 end,
             maps:with([Key || {Key, _Test} <- config_rules()], Config)).

normal_standing(Standing) ->
    #{town => maps:get(town, Standing) * 1.0,
      hinterland => maps:get(hinterland, Standing) * 1.0,
      goods => maps:map(fun(_Good, Yield) -> Yield * 1.0 end,
                        maps:get(goods, Standing, #{})),
      produces => maps:get(produces, Standing, []),
      census => maps:get(census, Standing, #{}),
      factories => [normal_factory(Works)
                    || Works <- maps:get(factories, Standing, [])]}.

normal_factory(Factory) ->
    Factory#{consumes => normal_flows(maps:get(consumes, Factory, #{})),
             yields => normal_flows(maps:get(yields, Factory, #{}))}.

normal_flows(Flows) -> maps:map(fun(_Good, Rate) -> Rate * 1.0 end, Flows).
