-module(tom_crossing_tests).

-include_lib("eunit/include/eunit.hrl").

config() -> tom_crossing:defaults().

%% The shipped constants, written down so that changing one is a diff somebody
%% has to explain rather than a number that drifted.
defaults_are_the_shipped_constants_test() ->
    ?assertEqual(#{demand_elasticity => 1.4,
                   supply_elasticity => 0.4,
                   stock_sensitivity => 0.5,
                   cover_ticks => 8.0,
                   reserve_ticks => 0.25,
                   godown_multiple => 10.0,
                   appetite => 30.0,
                   harbour_fee => 0.02,
                   landing_horizon => 720.0,
                   leak_base => 0.004,
                   leak_near => 0.060,
                   leak_far => 0.006},
                 config()).

%% Clause one: the hinterland grows it, so the full rate applies and the survey
%% is not consulted at all.
abundance_of_a_local_good_is_whole_test() ->
    ?assertEqual(1.0, tom_crossing:abundance(config(), true, {0, 0})),
    ?assertEqual(1.0, tom_crossing:abundance(config(), true, {9, 9})),
    ?assertEqual(1.0, tom_crossing:abundance(config(), true, unsurveyed)).

%% Clause two: the port LOOKED and nobody anywhere produces it. The good has no
%% geography, so the declared yield already IS the artisan rate everywhere and a
%% trickle here would be a second discount on top of a rate that is already the
%% low one.
abundance_of_a_good_with_no_geography_is_whole_test() ->
    ?assertEqual(1.0, tom_crossing:abundance(config(), false, no_geography)),
    %% And a census of nought seeds exactly that, which is how a world file
    %% still says it.
    ?assertEqual(no_geography, tom_crossing:seed(config(), {0, 0})).

%% Clause three: it came across this quay, and how much of it did decides how
%% ordinary it is here. What a world file seeds that with is still a count of
%% harbours near and far, ten to one between a neighbour and a voyage, because
%% that is a fair statement of what was arriving when the game began. After
%% genesis nothing reads it again.
abundance_of_an_import_is_a_trickle_test() ->
    Far = tom_crossing:seed(config(), {0, 1}),
    Near = tom_crossing:seed(config(), {1, 0}),
    ?assertEqual(0.004 + 0.006, tom_crossing:abundance(config(), false, Far)),
    ?assertEqual(0.004 + 0.060, tom_crossing:abundance(config(), false, Near)),
    ?assert(Near > Far * 6),
    ?assert(tom_crossing:abundance(config(), false,
                                   tom_crossing:seed(config(), {4, 0}))
            > tom_crossing:abundance(config(), false, Near)).

%% A QUAY FORGETS. What it knows about plenty is what it has seen lately, so a
%% rate left alone decays toward nothing and the price drifts back to the scarce
%% end. A good with no geography does not: the smith goes on making cannon.
a_rate_left_alone_fades_test() ->
    Rate = tom_crossing:seed(config(), {4, 0}),
    Later = tom_crossing:faded(config(), Rate, 720.0),
    ?assert(Later < Rate),
    ?assert(Later > 0.0),
    ?assert(tom_crossing:faded(config(), Rate, 20000.0) < Rate / 100),
    ?assertEqual(no_geography,
                 tom_crossing:faded(config(), no_geography, 20000.0)).

%% IGNORANCE IS THE SCARCE END, AND IT IS A STATE RATHER THAN A COUNT. A port
%% that has not looked gets what turns up with no known source at all, which is
%% what leak_base means, and that is BELOW every surveyed answer. So hearing a
%% fact can only ever raise the abundance and lower the price.
%%
%% Without this, ignorance and "surveyed, nobody makes it" were the same value
%% and a port's price jumped thirteenfold on its first piece of news, which is a
%% standing arbitrage against every port that had not caught up yet.
ignorance_is_the_scarce_end_test() ->
    Blind = tom_crossing:abundance(config(), false, 0.0),
    ?assertEqual(0.004, Blind),
    ?assertEqual(0.0, tom_crossing:seed(config(), unsurveyed)),
    Ladder = [tom_crossing:abundance(config(), false,
                                     tom_crossing:seed(config(), {0, N}))
              || N <- lists:seq(1, 8)],
    ?assertEqual(Ladder, lists:sort(Ladder)),
    ?assert(Blind < hd(Ladder)).

%% THE GATE MEASURES THE WHOLE BAND, not the crossing. It is the longest step
%% any tick takes as a fraction of the distance it had left, over every heap
%% between an empty quay and a full godown, and it must be under one or some
%% heap overshoots and the market rings.
%%
%% The old gate was the linearisation at the crossing, 0.109 with these
%% constants, which describes the last few ticks of an approach and nothing
%% else. The real worst step is more than twice that and is taken from an empty
%% quay. Both numbers pass; only one of them was ever an argument.
settling_rate_is_the_worst_step_in_the_band_test() ->
    Rate = tom_crossing:settling_rate(config()),
    ?assert(abs(Rate - 0.24073022624655652) < 1.0e-12),
    ?assert(Rate > 0.5 * 1.8 / 8.25),
    ?assert(Rate < 1.0).

%% Eleven hundred and twenty eight idle ticks and a quay with no works behind it
%% is at its natural stock to the last bit. Derived from the SLOWEST step in the
%% band, which is taken from a full godown, and not from the fastest.
%% tom_quay_tests proves it is long enough from both ends.
settling_horizon_covers_the_slowest_corner_test() ->
    ?assertEqual(1128, tom_crossing:settling_horizon(config())).

%% AND EVERY CROSSING CARRIES ITS OWN. A works buys and sells whatever the
%% price, so its flows do not chase the heap, and a quay whose throughput is
%% mostly a works takes longer to come to rest. One horizon on the constants
%% would be too short for it, and too short is what deletes goods.
a_works_lengthens_the_horizon_test() ->
    Standing = tom_sim:standing(macao),
    Bare = tom_crossing:of_good(config(), Standing, cannon),
    Works = tom_crossing:of_good(config(),
                                 Standing#{factories => [tom_sim:foundry()]},
                                 cannon),
    ?assertEqual(tom_crossing:settling_horizon(config()),
                 maps:get(horizon, Bare)),
    ?assert(maps:get(horizon, Works) > maps:get(horizon, Bare)).

%% Eighteen wide, and both ends are algebra rather than a clamp. A famine is not
%% expressible here and that is a deliberate trade for a bounded step.
band_is_eighteen_wide_test() ->
    {Floor, Ceiling} = tom_crossing:band_factors(config()),
    ?assert(abs(Floor - 0.32063022) < 1.0e-7),
    ?assert(abs(Ceiling - 5.74456265) < 1.0e-7),
    ?assert(abs(Ceiling / Floor - 17.9166) < 1.0e-3).

%% The crossing is where the curves meet, so at the natural price the two sides
%% agree, and the throughput is what flows through at that price. With no
%% factory both have a closed form, and this is the check that the closed form
%% is the same crossing the equations describe.
closed_form_is_the_crossing_test() ->
    Crossing = tom_crossing:of_good(config(), tom_sim:standing(macao), musk),
    #{natural_price := Pbar, throughput := Qbar,
      demand := D, supply := Y} = Crossing,
    ?assert(near(D * math:pow(Pbar, -1.4), Qbar)),
    ?assert(near(Y * math:pow(Pbar, 0.4), Qbar)).

%% With a works standing there the crossing has no closed form and is bisected.
%% The test of a root is that the curves meet at it, not that it looks right.
bisected_crossing_is_a_root_test() ->
    Standing = tom_sim:standing(macao),
    Crossing = tom_crossing:of_good(config(),
                                    Standing#{factories => [tom_sim:foundry()]},
                                    copper),
    #{natural_price := Pbar, throughput := Qbar, demand := D, supply := Y,
      inelastic_demand := In, inelastic_supply := Out} = Crossing,
    ?assert(near(D * math:pow(Pbar, -1.4) + In, Qbar)),
    ?assert(near(Y * math:pow(Pbar, 0.4) + Out, Qbar)),
    ?assert(In > 0.0).

%% A quay holds eight ticks of throughput at rest and a quarter of a tick behind
%% the counter, because that is what the constants say a quay is. Nobody chose
%% the natural stock; it is a quantity of goods implied by a rate.
the_natural_stock_is_cover_not_a_number_test() ->
    Crossing = tom_crossing:of_good(config(), tom_sim:standing(macao), musk),
    #{throughput := Qbar, natural_stock := Sbar, reserve := Res,
      capacity := Cap, anchor := Anchor} = Crossing,
    ?assert(near(Sbar, 8.0 * Qbar)),
    ?assert(near(Res, 0.25 * Qbar)),
    ?assert(near(Cap, 10.0 * Sbar)),
    ?assert(near(Anchor, Sbar + Res)).

%% THE ONLY PER-GOOD INPUT IS A YIELD. Two goods that arrive at the same rate
%% from the same distance are indistinguishable to this mechanism, which is
%% exactly what it means to have nowhere to declare that one is finer.
yield_is_the_only_per_good_input_test() ->
    Standing = #{town => 1.0, hinterland => 1.0,
                 goods => #{musk => 0.5, nutmeg => 0.5, rice => 0.5},
                 produces => [], census => #{}, factories => []},
    {ok, Market} = tom_market:open(Standing),
    ?assertEqual(tom_market:natural_price(Market, musk),
                 tom_market:natural_price(Market, nutmeg)),
    ?assertEqual(tom_market:natural_price(Market, musk),
                 tom_market:natural_price(Market, rice)).

%% all/2 does one good's work for every good and nothing else.
all_covers_every_good_test() ->
    Crossings = tom_crossing:all(config(), tom_sim:standing(macao)),
    ?assertEqual(tom_sim:goods(), lists:sort(maps:keys(Crossings))),
    ?assertEqual(maps:get(musk, Crossings),
                 tom_crossing:of_good(config(), tom_sim:standing(macao), musk)).

near(A, B) -> abs(A - B) =< 1.0e-9 * max(abs(A), abs(B)).
