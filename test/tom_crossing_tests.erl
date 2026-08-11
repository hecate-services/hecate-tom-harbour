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
                   leak_base => 0.004,
                   leak_near => 0.060,
                   leak_far => 0.006},
                 config()).

%% Clause one: the hinterland grows it, so the full rate applies and the census
%% is not consulted at all.
abundance_of_a_local_good_is_whole_test() ->
    ?assertEqual(1.0, tom_crossing:abundance(config(), true, 0, 0)),
    ?assertEqual(1.0, tom_crossing:abundance(config(), true, 9, 9)).

%% Clause two: nobody anywhere produces it. The good has no geography, so the
%% declared yield already IS the artisan rate everywhere and a trickle here
%% would be a second discount on top of a rate that is already the low one.
abundance_of_a_good_with_no_geography_is_whole_test() ->
    ?assertEqual(1.0, tom_crossing:abundance(config(), false, 0, 0)).

%% Clause three: it comes from somewhere else, and how far away decides how much
%% of it drifts in. Ten to one between a neighbour and a voyage is the only
%% place distance is expressed in the whole mechanism.
abundance_of_an_import_is_a_trickle_test() ->
    Base = tom_crossing:abundance(config(), false, 0, 1),
    Near = tom_crossing:abundance(config(), false, 1, 0),
    ?assertEqual(0.004 + 0.006, Base),
    ?assertEqual(0.004 + 0.060, Near),
    ?assert(Near > Base * 6),
    ?assert(tom_crossing:abundance(config(), false, 4, 0)
            > tom_crossing:abundance(config(), false, 1, 0)).

%% The gate is one inequality on four constants, and the number it produces is
%% the worst case for every port and every works that will ever exist, because
%% a factory can only ever make the contraction smaller.
settling_rate_is_the_worst_case_test() ->
    ?assert(abs(tom_crossing:settling_rate(config()) - 0.5 * 1.8 / 8.25)
            < 1.0e-15),
    ?assert(tom_crossing:settling_rate(config()) < 1.0).

%% Six hundred idle ticks and a quay is at its natural stock to the last bit.
%% tom_quay_tests proves the horizon is long enough from both ends of the band.
settling_horizon_is_six_hundred_test() ->
    ?assertEqual(600, tom_crossing:settling_horizon(config())).

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
