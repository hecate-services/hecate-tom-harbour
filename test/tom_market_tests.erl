-module(tom_market_tests).

-include_lib("eunit/include/eunit.hrl").

macao() ->
    {ok, Market} = tom_market:open(tom_sim:standing(macao)),
    Market.

opens_at_rest_and_at_tick_nought_test() ->
    Market = macao(),
    ?assertEqual(0, tom_market:tick(Market)),
    ?assertEqual(tom_sim:goods(), tom_market:goods(Market)),
    [?assert(tom_quay:at_rest(tom_market:quay(Market, Good)))
     || Good <- tom_market:goods(Market)],
    [?assertEqual(tom_market:natural_price(Market, Good),
                  tom_market:quote(Market, Good))
     || Good <- tom_market:goods(Market)],
    ok.

%% EVERY PROBLEM, NOT THE FIRST. The same promise the world service makes about
%% a world file, for the same reason: a caller who has to fix eleven constants
%% one round trip at a time stops reading the errors.
open_reports_every_problem_test() ->
    Broken = #{town => 0.0, hinterland => -1,
               goods => #{musk => 0.5, rice => 0.0},
               produces => [saffron], census => #{pepper => {1, 1}},
               factories => [#{id => works, consumes => #{tea => 1.0},
                               yields => #{musk => 1.0}},
                             #{id => works, consumes => #{musk => 1.0},
                               yields => #{rice => 1.0}}]},
    {error, Problems} = tom_market:open(Broken),
    ?assert(lists:member({bad_town, 0.0}, Problems)),
    ?assert(lists:member({bad_hinterland, -1}, Problems)),
    ?assert(lists:member({bad_yield, rice, 0.0}, Problems)),
    ?assert(lists:member({produces_unknown_good, saffron}, Problems)),
    ?assert(lists:member({census_unknown_good, pepper}, Problems)),
    ?assert(lists:member({factory_unknown_good, works, tea}, Problems)),
    ?assert(lists:member({duplicate_factory, works}, Problems)).

bad_constants_are_all_named_test() ->
    {error, Problems} = tom_market:open(tom_sim:standing(macao),
                                        #{stock_sensitivity => 1.0,
                                          godown_multiple => 1.0,
                                          harbour_fee => 1.0}),
    ?assert(lists:member({bad_config, stock_sensitivity, 1.0}, Problems)),
    ?assert(lists:member({bad_config, godown_multiple, 1.0}, Problems)),
    ?assert(lists:member({bad_config, harbour_fee, 1.0}, Problems)),
    ?assert(lists:member({bad_config, demand_elasticity, undefined}, Problems)),
    ?assert(lists:member({bad_config, appetite, undefined}, Problems)).

%% THE GATE. A market that rings is not a market, and this is the whole of the
%% check: one number, at open, once.
a_ringing_config_is_refused_test() ->
    Ringing = maps:merge(tom_crossing:defaults(),
                         #{stock_sensitivity => 0.9, cover_ticks => 0.5,
                           reserve_ticks => 0.05}),
    {error, Problems} = tom_market:open(tom_sim:standing(macao), Ringing),
    ?assertMatch([{gate_not_met, _Rate}], Problems),
    [{gate_not_met, Rate}] = Problems,
    ?assert(abs(Rate - 4.6441994) < 1.0e-6).

%% AND ONE THE OLD GATE LET THROUGH. Linearised at the crossing this
%% configuration scores 0.873 and passes; the step it actually takes from an
%% empty quay is nearly twice the distance to rest, so a single landing left it
%% swinging between two heaps forever. The gate that reads the whole band
%% refuses it at the door, which is the point of reading the whole band.
a_config_that_only_rings_far_from_rest_is_refused_test() ->
    Ringing = maps:merge(tom_crossing:defaults(),
                         #{stock_sensitivity => 0.9, cover_ticks => 1.5,
                           reserve_ticks => 0.35}),
    Linearised = 0.9 * 1.8 / 1.85,
    ?assert(Linearised < 1.0),
    {error, [{gate_not_met, Rate}]} =
        tom_market:open(tom_sim:standing(macao), Ringing),
    ?assert(Rate > 1.0).

%% Integers are welcome at the boundary and are floats from there on, so that
%% nothing inside can divide two integers and get a surprise.
integers_at_the_boundary_become_floats_test() ->
    {ok, Market} = tom_market:open(#{town => 2, hinterland => 1,
                                     goods => #{musk => 1}}),
    ?assert(is_float(tom_market:quote(Market, musk))),
    ?assert(is_float(maps:get(town, tom_market:standing(Market)))),
    ?assert(is_float(maps:get(musk, maps:get(goods,
                                             tom_market:standing(Market))))).

%% A CLOCK GOING BACKWARDS IS A BUG. A market that quietly accepted one would
%% go on producing plausible prices for the rest of the game.
settle_refuses_a_clock_going_backwards_test() ->
    Market = tom_market:settle(macao(), 20),
    ?assertEqual(20, tom_market:tick(Market)),
    ?assertError(function_clause, tom_market:settle(Market, 19)).

%% Reads crash on an unknown good, because a read is local and the caller has
%% the list. Trades answer, because those two are what a stranger on the mesh
%% will one day be calling and a peer that has not heard of a good is a soft
%% failure and not a fault.
unknown_goods_are_soft_for_trades_and_hard_for_reads_test() ->
    Market = macao(),
    ?assertEqual({error, unknown_good},
                 tom_market:lift(Market, saffron, 1.0, 0)),
    ?assertEqual({error, unknown_good},
                 tom_market:land(Market, saffron, 1.0, 0)),
    ?assertError({badkey, saffron}, tom_market:quote(Market, saffron)).

%% Trades settle to their own tick first, so a trader arriving late buys at the
%% price the market drifted to and not at the price he last saw.
a_trade_settles_before_it_fills_test() ->
    {ok, _, _, Stripped} = tom_market:lift(macao(), musk, 5.0, 0),
    Dear = tom_market:quote(Stripped, musk),
    {ok, _, Late, Filled} = tom_market:lift(Stripped, musk, 1.0, 30),
    {ok, _, AtOnce, _} = tom_market:lift(Stripped, musk, 1.0, 0),
    ?assertEqual(30, tom_market:tick(Filled)),
    ?assert(Late < AtOnce),
    ?assert(tom_market:quote(Filled, musk) < Dear).

%% WITHIN A TICK, ARRIVAL ORDER. The second trader pays for what the first one
%% did. There is no batching and no clearing auction, because that is what a
%% market is.
the_second_trader_in_a_tick_sees_the_first_test() ->
    {ok, _, First, Market} = tom_market:lift(macao(), musk, 2.0, 7),
    {ok, _, Second, _} = tom_market:lift(Market, musk, 2.0, 7),
    ?assert(Second > First).

%% THE TEST THAT CATCHES THE REAL BUG. Restructuring without settling first
%% retroactively rewrites every tick since the last stamp, silently and
%% plausibly. Both routes to tick fifty must land in the same place.
a_fact_settles_before_it_restructures_test() ->
    {ok, _, _, Traded} = tom_market:lift(macao(), nutmeg, 5.0, 3),
    {ok, _, _, Straight} = tom_market:land(Traded, nutmeg, 5.0, 50),
    {ok, _, _, Stepwise} = tom_market:land(tom_market:settle(Traded, 50),
                                           nutmeg, 5.0, 50),
    ?assertEqual(tom_market:stock(Stepwise, nutmeg),
                 tom_market:stock(Straight, nutmeg)),
    ?assertEqual(tom_market:quote(Stepwise, nutmeg),
                 tom_market:quote(Straight, nutmeg)),
    ?assertEqual(50, tom_market:tick(Straight)).

%% A LANDING ONLY TOUCHES ITS OWN GOOD. Bringing nutmeg here says nothing about
%% copper, which is the whole of what makes this local: a port's opinion of a
%% good is what has come across its quay, one good at a time, and nothing about
%% anybody else's fields.
a_landing_touches_only_its_own_good_test() ->
    Market = macao(),
    {ok, _, _, Fed} = tom_market:land(Market, nutmeg, 40.0, 0),
    ?assert(tom_market:natural_price(Fed, nutmeg)
            < tom_market:natural_price(Market, nutmeg)),
    ?assertEqual(tom_market:natural_price(Market, copper),
                 tom_market:natural_price(Fed, copper)),
    ?assertEqual(tom_sim:goods(), tom_market:goods(Fed)).

%% THE FAULT THAT DELETED GOODS, through the facade, which is where it was
%% reachable. A works eating ten million musk a tick makes the natural stock
%% eighty million; demolish it and the natural stock is thirteen again while
%% eighty million are still standing on the quay.
%%
%% Waiting a settling horizon used to answer thirteen, at the natural price,
%% with the quay reported at rest. Waiting the same time one tick at a time
%% answered sixteen million, still draining, which is the truth. The two must
%% agree, and the port service reaches this every time it settles a market that
%% has been left alone for a while.
a_wait_out_of_the_godown_does_not_delete_the_goods_test() ->
    Works = #{id => big_works, consumes => #{musk => 1.0e7}, yields => #{}},
    {ok, Raised} = tom_market:open((tom_sim:standing(macao))#{
                                     factories => [Works]}),
    Razed = tom_market:demolish_factory(Raised, 0, big_works),
    Horizon = maps:get(horizon, tom_market:crossing(Razed, musk)),
    ?assert(tom_market:stock(Razed, musk) > 1.0e7),
    Straight = tom_market:settle(Razed, Horizon),
    Stepwise = lists:foldl(fun(Tick, M) -> tom_market:settle(M, Tick) end,
                           Razed, lists:seq(1, Horizon)),
    ?assert(near(tom_market:stock(Straight, musk),
                 tom_market:stock(Stepwise, musk))),
    ?assert(tom_market:stock(Straight, musk) > 1.0e6),
    ?assertNot(tom_quay:at_rest(tom_market:quay(Straight, musk))).

%% A works keeps whatever was already on the quay. Only the structure moved.
raising_a_factory_keeps_the_goods_on_the_quay_test() ->
    {ok, _, _, Traded} = tom_market:lift(macao(), copper, 4.0, 5),
    Was = tom_market:stock(Traded, copper),
    Raised = tom_market:raise_factory(Traded, 5, tom_sim:foundry()),
    ?assertEqual(Was, tom_market:stock(Raised, copper)),
    ?assert(tom_market:natural_price(Raised, copper)
            > tom_market:natural_price(Traded, copper)).

demolishing_a_factory_puts_it_back_test() ->
    Market = macao(),
    Raised = tom_market:raise_factory(Market, 0, tom_sim:foundry()),
    Razed = tom_market:demolish_factory(Raised, 0, cast_cannon),
    [?assert(near(tom_market:natural_price(Market, Good),
                  tom_market:natural_price(Razed, Good)))
     || Good <- [cannon, copper, tin]],
    ?assertError({unknown_factory, mint},
                 tom_market:demolish_factory(Market, 0, mint)),
    ?assertError({duplicate_factory, cast_cannon},
                 tom_market:raise_factory(Raised, 0, tom_sim:foundry())).

a_factory_on_a_good_we_do_not_trade_is_refused_test() ->
    ?assertError({factory_unknown_good, still, saffron},
                 tom_market:raise_factory(macao(), 0,
                                          #{id => still,
                                            consumes => #{saffron => 1.0},
                                            yields => #{musk => 1.0}})).

%% A BIGGER TOWN IS DEEPER WITHOUT BEING DEARER. Price follows the ratio of the
%% town to its hinterland and depth follows their weighted product, so doubling
%% both leaves every price alone and makes every market harder to move.
a_bigger_port_is_deeper_not_dearer_test() ->
    Market = macao(),
    Grown = tom_market:resurvey(Market, 0, #{town => 4.0, hinterland => 2.4}),
    [begin
         ?assert(near(tom_market:natural_price(Market, Good),
                      tom_market:natural_price(Grown, Good))),
         ?assert(maps:get(natural_stock, tom_market:crossing(Grown, Good))
                 > maps:get(natural_stock, tom_market:crossing(Market, Good)))
     end || Good <- tom_market:goods(Market)],
    ?assertError({bad_survey, [town]},
                 tom_market:resurvey(Market, 0, #{town => 0.0})).

%% Asking does not move the market on. quote/3 settles a copy and throws it out.
quoting_ahead_does_not_move_the_market_test() ->
    {ok, _, _, Market} = tom_market:lift(macao(), musk, 5.0, 0),
    Later = tom_market:quote(Market, musk, 40),
    ?assertEqual(0, tom_market:tick(Market)),
    ?assert(Later < tom_market:quote(Market, musk)).

%% A price is a ratio. This is the most legible one line statement of the law
%% there is, and it is the one the next phase will publish.
in_terms_of_is_a_pure_ratio_test() ->
    Market = macao(),
    ?assert(near(tom_market:in_terms_of(Market, musk, rice),
                 tom_market:quote(Market, musk)
                 / tom_market:quote(Market, rice))),
    ?assert(near(tom_market:in_terms_of(Market, musk, musk), 1.0)).

%% Settling a whole port over a whole settling horizon, from a standing start,
%% because that is the worst thing a returning player can ask of it.
settling_a_whole_port_is_cheap_test() ->
    {ok, Market0} = tom_market:open(sixty_seven()),
    Stir = fun(Good, Acc) -> element(4, tom_market:lift(Acc, Good, 1.0, 0)) end,
    Market = lists:foldl(Stir, Market0, tom_market:goods(Market0)),
    Horizon = tom_crossing:settling_horizon(tom_crossing:defaults()) - 1,
    Settling = fun() -> tom_market:settle(Market, Horizon) end,
    {Micros, Settled} = timer:tc(Settling),
    ?assertEqual(Horizon, tom_market:tick(Settled)),
    ?assert(Micros < 50000).

%% And a port nobody has touched costs nothing at all, however long it stood.
settling_an_idle_port_is_free_test() ->
    {ok, Market} = tom_market:open(sixty_seven()),
    Standing = fun() -> tom_market:settle(Market, 1000000) end,
    {Micros, Settled} = timer:tc(Standing),
    ?assertEqual(1000000, tom_market:tick(Settled)),
    ?assert(Micros < 1000).

sixty_seven() ->
    Goods = [{list_to_atom("good_" ++ integer_to_list(N)),
              math:pow(10.0, (N rem 7) - 2.0)} || N <- lists:seq(1, 67)],
    #{town => 1.5, hinterland => 1.0, goods => maps:from_list(Goods),
      produces => [G || {G, _Y} <- lists:sublist(Goods, 9)],
      census => #{}, factories => []}.

near(A, B) -> abs(A - B) =< 1.0e-9 * max(abs(A), abs(B)).
