%% @doc A hand crank for the market. Not a test: a way to run one forward and
%% look at what came out.
%%
%% It carries a small slice of the Macao world, six ports and eight goods, with
%% the yields and standings from the design's worked example. That slice is what
%% the tests assert against and what the shell demo runs on, so there is one
%% copy of it and not two.
%%
%% From a shell:
%%
%%   scripts/simulate.sh 60
%%
%% or, if you would rather see the machinery,
%%
%%   erl -noshell -pa _build/test/lib/hecate_tom_world/ebin \
%%       -pa _build/test/lib/hecate_tom_world/test \
%%       -eval 'tom_sim:demo(), halt(0).'
%%
%% From code, tom_sim:run/3 gives back the price series as data, which is what
%% the next phase wants: a list of {Tick, #{Good => Price}}.
%% @end
-module(tom_sim).

-export([ports/0,
         goods/0,
         yields/0,
         standing/1,
         foundry/0,
         producers/1,
         run/3,
         run/4,
         prices/1,
         demo/0,
         print/1,
         main/1]).

-export_type([order/0, done/0]).

%% @doc One instruction: at this tick, take or leave this much of this good.
-type order() :: {Tick :: integer(), lift | land, tom_crossing:good_id(),
                  Quantity :: number()}.

%% @doc What actually happened when an order reached the quay.
-type done() :: {integer(), lift | land, tom_crossing:good_id(),
                 {filled, float(), float()} | {refused, atom()}}.

%% @doc The ports of the sample.
-spec ports() -> [atom()].
ports() -> [ayutthaya, banda, callao, lisbon, macao, ternate].

%% @doc The goods of the sample.
-spec goods() -> [tom_crossing:good_id()].
goods() -> lists:sort(maps:keys(yields())).

%% @doc What a standard hinterland turns out per tick, for a harbour that
%% produces the good at all.
%%
%% These are physical rates and nothing else. Rice is a river and musk is a
%% pouch, cannon are what a village smith manages without a foundry, and tin is
%% here because the foundry eats it. Nothing in this map says what anything is
%% worth, and the exponent between a yield and a price is 0.556, so nothing here
%% could be nudged toward a price even on purpose.
-spec yields() -> #{tom_crossing:good_id() => float()}.
yields() ->
    #{rice => 400.0,
      musk => 0.5,
      nutmeg => 40.0,
      copper => 30.0,
      quicksilver => 1.2,
      silver_ore => 900.0,
      cannon => 0.02,
      tin => 20.0}.

%% @doc Which harbours produce a good, as region and count.
%%
%% Straight off the world file's produces lists, which is the whole input to the
%% census. Cannon are produced by nobody: they come out of a factory, so they
%% have no geography and the trickle does not apply to them.
-spec producers(tom_crossing:good_id()) -> [{atom(), pos_integer()}].
producers(rice) -> [{southeast_asia, 3}];
producers(musk) -> [{china, 1}];
producers(nutmeg) -> [{southeast_asia, 4}];
producers(copper) -> [{japan, 2}];
producers(quicksilver) -> [{china, 1}];
producers(silver_ore) -> [{north_america, 1}, {south_america, 1}];
producers(tin) -> [{southeast_asia, 2}];
producers(cannon) -> [].

%% @doc A port's standing, ready for tom_market:open/1.
-spec standing(atom()) -> tom_crossing:standing().
standing(Port) ->
    {Region, Town, Land, Produces} = port(Port),
    #{town => Town,
      hinterland => Land,
      goods => yields(),
      produces => Produces,
      census => maps:from_list([{Good, census(Region, Good)}
                                || Good <- goods()]),
      factories => []}.

%% @doc The Macao gun foundry: one piece out of every eight ticks, three copper
%% and one tin in. Straight off the cast_cannon recipe, divided by its ticks.
-spec foundry() -> tom_crossing:factory().
foundry() ->
    #{id => cast_cannon,
      consumes => #{copper => 0.375, tin => 0.125},
      yields => #{cannon => 0.125}}.

%% @doc Run a port forward, applying orders as their ticks come round.
-spec run(atom(), [order()], non_neg_integer()) ->
          #{series := [{integer(), #{tom_crossing:good_id() => float()}}],
            done := [done()],
            market := tom_market:market()}.
run(Port, Orders, Ticks) -> run(Port, Orders, Ticks, []).

%% @doc As run/3, with factories standing behind the port from tick nought.
-spec run(atom(), [order()], non_neg_integer(), [tom_crossing:factory()]) ->
          #{series := [{integer(), #{tom_crossing:good_id() => float()}}],
            done := [done()],
            market := tom_market:market()}.
run(Port, Orders, Ticks, Factories) ->
    Standing = standing(Port),
    {ok, Market} = tom_market:open(Standing#{factories => Factories}),
    walk(Market, Orders, 0, Ticks, [], []).

%% @doc Every good's posted price, as the market stands.
-spec prices(tom_market:market()) -> #{tom_crossing:good_id() => float()}.
prices(Market) ->
    maps:from_list([{Good, tom_market:quote(Market, Good)}
                    || Good <- tom_market:goods(Market)]).

%% @doc The shipped scenario: a trader strips Macao of musk over four visits,
%% then lands a cargo of nutmeg he brought from Banda, and the port recovers.
-spec demo() -> ok.
demo() -> main(["40"]).

%% @doc Shell entry. One optional argument, how many ticks to run.
-spec main([string()]) -> ok.
main(Args) ->
    Ticks = ticks(Args),
    io:format("~nMACAO, ~p ticks. A trader works the musk quay, then lands "
              "nutmeg.~n~n", [Ticks]),
    print(run(macao, script(), Ticks)),
    ok.

%% @doc Print a run: the price series, then what the orders actually did.
-spec print(#{series := [{integer(), #{tom_crossing:good_id() => float()}}],
              done := [done()], market := tom_market:market()}) -> ok.
print(#{series := Series, done := Done}) ->
    Watched = [musk, nutmeg, copper, cannon],
    io:format("tick~s~n", [[io_lib:format("~12s", [atom_to_list(G)])
                            || G <- Watched]]),
    [io:format("~4w~s~n",
               [Tick, [io_lib:format("~12.4f", [maps:get(G, Prices)])
                       || G <- Watched]])
     || {Tick, Prices} <- Series],
    io:format("~norders~n"),
    [io:format("  ~4w ~-5s ~-12s ~p~n", [Tick, Side, Good, What])
     || {Tick, Side, Good, What} <- Done],
    ok.

%% Internal

port(macao) -> {china, 2.0, 1.2, [musk, quicksilver]};
port(ayutthaya) -> {southeast_asia, 0.5, 1.4, [rice]};
port(banda) -> {southeast_asia, 0.08, 0.10, [nutmeg]};
port(lisbon) -> {europe, 1.6, 0.9, []};
port(ternate) -> {southeast_asia, 0.10, 0.06, []};
port(callao) -> {south_america, 0.35, 0.60, [silver_ore]}.

%% A harbour in this port's own region is coastal traffic; one beyond it is a
%% voyage. The port itself is not in its own census, because producing a good is
%% already said by the produces list.
census(Region, Good) ->
    Split = fun({Where, N}, Counts) -> counted(Where =:= Region, N, Counts) end,
    lists:foldl(Split, {0, 0}, producers(Good)).

counted(true, N, {Near, Far}) -> {Near + N, Far};
counted(false, N, {Near, Far}) -> {Near, Far + N}.

ticks([]) -> 40;
ticks([Arg | _]) -> list_to_integer(Arg).

script() ->
    [{2, lift, musk, 3.0},
     {3, lift, musk, 3.0},
     {4, lift, musk, 3.0},
     {5, lift, musk, 3.0},
     {12, land, nutmeg, 40.0},
     {20, lift, cannon, 0.5},
     {28, land, copper, 30.0}].

walk(Market, _Orders, Tick, Ticks, Series, Done) when Tick > Ticks ->
    #{series => lists:reverse(Series),
      done => lists:reverse(Done),
      market => Market};
walk(Market0, Orders, Tick, Ticks, Series, Done) ->
    Settled = tom_market:settle(Market0, Tick),
    {Market, Happened} = trade(Settled, due(Orders, Tick), Tick, []),
    walk(Market, Orders, Tick + 1, Ticks,
         [{Tick, prices(Market)} | Series], Happened ++ Done).

due(Orders, Tick) -> [Order || {At, _S, _G, _Q} = Order <- Orders, At =:= Tick].

trade(Market, [], _Tick, Done) ->
    {Market, Done};
trade(Market, [{_At, Side, Good, Quantity} | Rest], Tick, Done) ->
    Answer = attempt(Side, Market, Good, Quantity, Tick),
    trade(taken(Market, Answer), Rest, Tick,
          [{Tick, Side, Good, outcome(Answer)} | Done]).

attempt(lift, Market, Good, Quantity, Tick) ->
    tom_market:lift(Market, Good, Quantity, Tick);
attempt(land, Market, Good, Quantity, Tick) ->
    tom_market:land(Market, Good, Quantity, Tick).

taken(_Market, {ok, _Filled, _Coin, Market}) -> Market;
taken(Market, {error, _Why}) -> Market.

outcome({ok, Filled, Coin, _Market}) -> {filled, Filled, Coin};
outcome({error, Why}) -> {refused, Why}.
