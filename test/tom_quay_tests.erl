-module(tom_quay_tests).

-include_lib("eunit/include/eunit.hrl").

config() -> tom_crossing:defaults().

config(Overrides) -> maps:merge(config(), Overrides).

crossing(Good) ->
    tom_crossing:of_good(config(), tom_sim:standing(macao), Good).

quay(Good) -> tom_quay:open(crossing(Good)).

%% A quay opened at its natural stock posts its natural price, which is what
%% makes the natural price a description of a resting market rather than a
%% number written on it.
opens_at_rest_test() ->
    Quay = quay(musk),
    ?assert(tom_quay:at_rest(Quay)),
    ?assert(near(tom_quay:stock(Quay),
                 maps:get(natural_stock, crossing(musk)))),
    ?assert(near(tom_quay:posted_price(config(), Quay),
                 maps:get(natural_price, crossing(musk)))).

%% BUYING PUSHES A PRICE UP, SELLING PUSHES IT DOWN. The whole mandate in four
%% assertions.
lifting_raises_and_landing_lowers_test() ->
    Quay = quay(musk),
    Was = tom_quay:posted_price(config(), Quay),
    {ok, _, _, Stripped} = tom_quay:lift(config(), Quay, 4.0),
    {ok, _, _, Piled} = tom_quay:land(config(), Quay, 4.0),
    ?assert(tom_quay:posted_price(config(), Stripped) > Was),
    ?assert(tom_quay:posted_price(config(), Piled) < Was),
    ?assert(tom_quay:stock(Stripped) < tom_quay:stock(Quay)),
    ?assert(tom_quay:stock(Piled) > tom_quay:stock(Quay)).

%% A BIG ORDER PAYS FOR HAVING MOVED THE PRICE. Charging spot instead would make
%% a large order a subsidy, and the man who split his into a hundred the only
%% one paying properly.
a_big_order_pays_more_than_spot_test() ->
    Quay = quay(musk),
    Spot = tom_quay:posted_price(config(), Quay),
    {ok, Filled, Coin, _After} = tom_quay:lift(config(), Quay, 5.0),
    ?assert(Coin > Spot * Filled * 1.1).

%% And splitting it gains nothing, because the integral is path independent.
%% That is not an accident to be papered over; it is the property that makes the
%% harbour fee the only thing standing between a market and a money pump.
splitting_an_order_changes_nothing_test() ->
    {ok, _, Whole, _} = tom_quay:lift(config(), quay(musk), 5.0),
    Bit = fun(_N, {Quay, Coin}) ->
                  {ok, _, Some, Next} = tom_quay:lift(config(), Quay, 0.5),
                  {Next, Coin + Some}
          end,
    {_Quay, Piecemeal} = lists:foldl(Bit, {quay(musk), 0.0}, lists:seq(1, 10)),
    ?assert(near(Whole, Piecemeal)).

%% Ten thousand trades from ten thousand heaps. The price is positive, finite
%% and inside its band at every one of them, and none of that is a clamp: the
%% reserve makes the top finite and the godown makes the bottom.
price_stays_positive_finite_and_banded_test() ->
    rand:seed(exsss, {17, 89, 3}),
    Crossing = crossing(musk),
    Cap = maps:get(capacity, Crossing),
    {Floor, Ceiling} = tom_quay:price_band(config(), quay(musk)),
    [banded(Crossing, Cap, Floor, Ceiling) || _N <- lists:seq(1, 10000)],
    ok.

banded(Crossing, Cap, Floor, Ceiling) ->
    Quay = #{crossing => Crossing, stock => rand:uniform() * Cap,
             at_rest => false},
    Side = side(rand:uniform(2)),
    After = moved(Side, Quay, rand:uniform() * Cap),
    Price = tom_quay:posted_price(config(), After),
    ?assert(Price > 0.0),
    ?assert(Price < Ceiling * 1.000001),
    ?assert(Price > Floor * 0.999999),
    ?assert(tom_quay:stock(After) >= 0.0).

side(1) -> lift;
side(2) -> land.

moved(lift, Quay, Quantity) ->
    filled(Quay, tom_quay:lift(config(), Quay, Quantity));
moved(land, Quay, Quantity) ->
    filled(Quay, tom_quay:land(config(), Quay, Quantity)).

filled(_Quay, {ok, _Filled, _Coin, After}) -> After;
filled(Quay, {error, _Why}) -> Quay.

%% THE FILL IS PARTIAL. Asking for more than is there empties the quay and says
%% so, and the price at an empty quay is the ceiling and is a number.
lifting_more_than_there_is_empties_the_quay_test() ->
    Quay = quay(musk),
    {ok, Filled, Coin, Empty} = tom_quay:lift(config(), Quay, 1000.0),
    ?assertEqual(tom_quay:stock(Quay), Filled),
    ?assertEqual(0.0, tom_quay:stock(Empty)),
    ?assert(Coin > 0.0),
    {_Floor, Ceiling} = tom_quay:price_band(config(), Quay),
    ?assert(near(tom_quay:posted_price(config(), Empty), Ceiling)),
    ?assertEqual({error, quay_empty}, tom_quay:lift(config(), Empty, 1.0)).

landing_more_than_fits_fills_the_godown_test() ->
    Quay = quay(musk),
    Cap = maps:get(capacity, crossing(musk)),
    {ok, Filled, _Coin, Full} = tom_quay:land(config(), Quay, 10000.0),
    ?assert(near(Filled, Cap - tom_quay:stock(Quay))),
    ?assert(near(tom_quay:stock(Full), Cap)),
    {Floor, _Ceiling} = tom_quay:price_band(config(), Quay),
    ?assert(near(tom_quay:posted_price(config(), Full), Floor)),
    ?assertEqual({error, godown_full}, tom_quay:land(config(), Full, 1.0)).

%% PRICES SETTLE. From a stripped quay and from a full godown, one settling
%% horizon of ticks lands on the natural stock to nine figures, which is what
%% licenses advance/3 to snap rather than iterate.
settles_from_both_ends_test() ->
    Crossing = crossing(musk),
    Sbar = maps:get(natural_stock, Crossing),
    Horizon = tom_crossing:settling_horizon(config()),
    [?assert(abs(tom_quay:stock(cranked(at(Crossing, Start), Horizon)) - Sbar)
             < 1.0e-9 * Sbar)
     || Start <- [0.0, maps:get(capacity, Crossing),
                  50.0 * maps:get(capacity, Crossing)]],
    ok.

%% MONOTONE AND NEVER OVERSHOOTING, EVERYWHERE, not merely near rest. The step
%% always points at the crossing and is always shorter than the distance to it,
%% across five decades of stock. This is what says the market comes to rest
%% rather than ringing around it.
never_overshoots_anywhere_test() ->
    Crossing = crossing(musk),
    Sbar = maps:get(natural_stock, Crossing),
    [begin
         Step = step(config(), Crossing, Stock),
         Distance = Sbar - Stock,
         ?assert(Step * Distance > 0.0),
         ?assert(abs(Step) < abs(Distance))
     end || Stock <- sweep(Crossing), abs(Stock - Sbar) > 1.0e-6 * Sbar],
    ok.

%% A WORKS ONLY EVER DAMPS. Its flows are price blind, so they cannot push a
%% heap harder than the elastic flows of the same crossing would. That is why
%% the settling gate is one line on four constants and not a condition per port.
a_factory_never_widens_the_step_test() ->
    Standing = tom_sim:standing(macao),
    Crossing = tom_crossing:of_good(config(),
                                    Standing#{factories => [tom_sim:foundry()]},
                                    copper),
    Sbar = maps:get(natural_stock, Crossing),
    ?assert(maps:get(inelastic_demand, Crossing) > 0.0),
    [begin
         Step = step(config(), Crossing, Stock),
         ?assert(abs(Step)
                 =< abs(elastic_step(config(), Crossing, Stock)) * 1.000000001),
         ?assert(Step * (Sbar - Stock) > 0.0),
         ?assert(abs(Step) < abs(Sbar - Stock))
     end || Stock <- sweep(Crossing), abs(Stock - Sbar) > 1.0e-6 * Sbar],
    ok.

%% THE ROUND TRIP LOSES THE FEE AND NOTHING ELSE. The integral is path
%% independent, so walking out and back leaves the heap where it was, bit for
%% bit, and the only thing missing is twice the harbour fee.
round_trip_loses_exactly_the_fee_test() ->
    Quay = quay(musk),
    {ok, Q, Paid, Stripped} = tom_quay:lift(config(), Quay, 5.0),
    {ok, Q, Got, Back} = tom_quay:land(config(), Stripped, 5.0),
    ?assertEqual(tom_quay:stock(Quay), tom_quay:stock(Back)),
    ?assert(abs((Paid - Got) / Paid - 2 * 0.02 / 1.02) < 1.0e-12).

%% Without the fee the round trip is EXACTLY break even, which is the money pump
%% the fee exists to close. This is why phi is not decoration.
without_a_fee_the_round_trip_is_break_even_test() ->
    Free = config(#{harbour_fee => 0.0}),
    Quay = quay(musk),
    {ok, _, Paid, Stripped} = tom_quay:lift(Free, Quay, 5.0),
    {ok, _, Got, _Back} = tom_quay:land(Free, Stripped, 5.0),
    ?assert(abs(Paid - Got) < 1.0e-12 * Paid).

%% Depth is the same integral read from the other end, so walking the price to
%% where a trade would have put it must cost what the trade cost. If these two
%% ever disagree, one of them is lying to a player.
depth_agrees_with_the_trade_test() ->
    Quay = quay(musk),
    {ok, Filled, Coin, After} = tom_quay:lift(config(), Quay, 5.0),
    Target = tom_quay:posted_price(config(), After),
    {lift, Quantity, Purse} = tom_quay:depth(config(), Quay, Target),
    ?assert(near(Quantity, Filled)),
    ?assert(near(Purse, Coin)).

depth_the_other_way_agrees_too_test() ->
    Quay = quay(musk),
    {ok, Filled, Coin, After} = tom_quay:land(config(), Quay, 20.0),
    Target = tom_quay:posted_price(config(), After),
    {land, Quantity, Purse} = tom_quay:depth(config(), Quay, Target),
    ?assert(near(Quantity, Filled)),
    ?assert(near(Purse, Coin)).

%% DOUBLING A PRICE COSTS ONE NATURAL STOCK'S WORTH AT THE NATURAL PRICE. The
%% closed form of the depth, derived by inverting the posted price, and the one
%% sentence about this market a seventeenth century factor could hold.
doubling_a_price_costs_one_natural_stock_test() ->
    Crossing = crossing(musk),
    Pbar = maps:get(natural_price, Crossing),
    Anchor = maps:get(anchor, Crossing),
    {lift, _Quantity, Purse} = tom_quay:depth(config(#{harbour_fee => 0.0}),
                                              quay(musk), 2.0 * Pbar),
    ?assert(near(Purse, Pbar * Anchor)).

%% And the general closed form, which the implementation never uses, agrees with
%% the integral the implementation does use.
depth_closed_form_agrees_test() ->
    Free = config(#{harbour_fee => 0.0}),
    Crossing = crossing(musk),
    Pbar = maps:get(natural_price, Crossing),
    Anchor = maps:get(anchor, Crossing),
    Gamma = maps:get(stock_sensitivity, Free),
    Beta = (1.0 - Gamma) / Gamma,
    Now = tom_quay:posted_price(Free, quay(musk)),
    [begin
         {lift, _Q, Purse} = tom_quay:depth(Free, quay(musk), To),
         Closed = Pbar * Anchor / (1.0 - Gamma)
             * (math:pow(Pbar / Now, Beta) - math:pow(Pbar / To, Beta)),
         ?assert(near(Purse, Closed))
     end || To <- [1.5 * Pbar, 2.0 * Pbar, 3.0 * Pbar, 5.0 * Pbar]],
    ok.

%% Outside the band there is no answer, because there is no heap that would post
%% that price. Refusing is honest; clamping would invent a quantity.
depth_out_of_band_is_refused_test() ->
    {Floor, Ceiling} = tom_quay:price_band(config(), quay(musk)),
    ?assertEqual({error, out_of_band},
                 tom_quay:depth(config(), quay(musk), Ceiling * 1.01)),
    ?assertEqual({error, out_of_band},
                 tom_quay:depth(config(), quay(musk), Floor * 0.99)),
    ?assertEqual({lift, 0.0, 0.0},
                 tom_quay:depth(config(), quay(musk),
                                tom_quay:posted_price(config(), quay(musk)))).

%% An idle quay costs nothing, and one idle past the horizon costs a comparison.
idle_is_free_test() ->
    Quay = quay(musk),
    ?assertEqual(Quay, tom_quay:advance(config(), Quay, 1000000)),
    {ok, _, _, Stirred} = tom_quay:lift(config(), Quay, 3.0),
    ?assertNot(tom_quay:at_rest(Stirred)),
    Snapped = tom_quay:advance(config(), Stirred, 1000000),
    ?assert(tom_quay:at_rest(Snapped)),
    ?assertEqual(tom_quay:stock(Quay), tom_quay:stock(Snapped)).

%% A tick moves the heap toward the crossing and a trade moves it away, and both
%% of them together are the whole of what happens at a port.
a_tick_walks_the_price_back_test() ->
    Quay = quay(musk),
    Was = tom_quay:posted_price(config(), Quay),
    {ok, _, _, Stripped} = tom_quay:lift(config(), Quay, 5.0),
    Dear = tom_quay:posted_price(config(), Stripped),
    Later = tom_quay:posted_price(config(),
                                  tom_quay:advance(config(), Stripped, 10)),
    ?assert(Dear > Later),
    ?assert(Later > Was).

%% Helpers

at(Crossing, Stock) ->
    #{crossing => Crossing, stock => Stock, at_rest => false}.

cranked(Quay, 0) -> Quay;
cranked(Quay, N) -> cranked(tom_quay:advance(config(), Quay, 1), N - 1).

step(Config, Crossing, Stock) ->
    Quay = at(Crossing, Stock),
    tom_quay:stock(tom_quay:advance(Config, Quay, 1)) - Stock.

%% The same crossing with its inelastic flows made elastic: the step this heap
%% would take if the works were a hinterland and a town instead of a foundry.
elastic_step(Config, Crossing, Stock) ->
    Ratio = tom_quay:posted_price(Config, at(Crossing, Stock))
        / maps:get(natural_price, Crossing),
    Qbar = maps:get(throughput, Crossing),
    Qbar * math:pow(Ratio, maps:get(supply_elasticity, Config))
        - Qbar * math:pow(Ratio, -maps:get(demand_elasticity, Config)).

sweep(Crossing) ->
    Top = 50.0 * maps:get(capacity, Crossing),
    Bottom = Top / 1.0e5,
    [0.0 | [Bottom * math:pow(1.0e5, N / 199.0) || N <- lists:seq(0, 199)]].

near(A, B) -> abs(A - B) =< 1.0e-9 * max(abs(A), abs(B)).
