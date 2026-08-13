%% @doc The sea must be checkable, and these are the checks.
-module(tom_passage_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SHIP,   <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(OWNER,  <<"mri:instance:io.macula/tom/house/raf">>).
-define(MACAO,  <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(LISBON, <<"mri:instance:io.macula/tom/harbour/lisbon">>).

departure() ->
    #{ship      => ?SHIP,
      owner     => ?OWNER,
      from      => ?MACAO,
      bound_for => ?LISBON,
      sailed_at => 1786528800000}.

a_crossing_takes_ninety_seconds_test() ->
    ?assertEqual(90000, tom_passage:passage_ms()).

the_hazard_is_a_share_of_ten_thousand_test() ->
    Hazard = tom_passage:hazard(),
    ?assert(Hazard >= 0),
    ?assert(Hazard =< 10000).

%% The property the whole design rests on: no state, no clock, no randomness.
the_same_departure_always_draws_the_same_fate_test() ->
    Departure = departure(),
    First = tom_passage:fate(Departure),
    Repeats = [tom_passage:fate(Departure) || _ <- lists:seq(1, 200)],
    ?assert(lists:all(fun(Fate) -> Fate =:= First end, Repeats)).

%% ...and it is not a constant either: change any one of the five fields and the
%% draw is redrawn from scratch.
a_different_departure_is_a_different_draw_test() ->
    Departure = departure(),
    Fates = [tom_passage:fate(Departure#{sailed_at => 1786528800000 + N})
             || N <- lists:seq(1, 500)],
    ?assert(length(lists:usort(Fates)) > 1).

%% Without a separator, ship "ab" + owner "c" and ship "a" + owner "bc" would
%% hash to the same bytes, and two different departures would share a fate.
%% A zero byte cannot occur inside an MRI, so it cannot be smuggled in either.
fields_cannot_be_run_together_into_one_seed_test() ->
    Departure = departure(),
    Left  = Departure#{ship => <<"ab">>, owner => <<"c">>},
    Right = Departure#{ship => <<"a">>,  owner => <<"bc">>},
    ?assertNotEqual(tom_passage:seed(Left), tom_passage:seed(Right)).

the_seed_is_exactly_the_five_published_fields_test() ->
    Expected = <<?SHIP/binary, 0, ?OWNER/binary, 0, ?MACAO/binary, 0,
                 ?LISBON/binary, 0, "1786528800000">>,
    ?assertEqual(Expected, tom_passage:seed(departure())).

%% Twenty thousand crossings, and the loss rate must land where the constant
%% says. Five standard deviations of slack, so this cannot flap; it fails if
%% the draw is biased, inverted, or reading the wrong bits.
losses_land_where_the_hazard_says_test() ->
    Departure = departure(),
    Runs = 20000,
    Fates = [tom_passage:fate(Departure#{sailed_at => N}) || N <- lists:seq(1, Runs)],
    Lost = length([F || F <- Fates, F =/= arrives]),
    Expected = Runs * tom_passage:hazard() / 10000,
    Slack = 5 * math:sqrt(Expected),
    ?assert(abs(Lost - Expected) < Slack).

both_kinds_of_bad_luck_happen_test() ->
    Departure = departure(),
    Fates = [tom_passage:fate(Departure#{sailed_at => N}) || N <- lists:seq(1, 20000)],
    Causes = lists:usort([Cause || {lost, Cause} <- Fates]),
    ?assertEqual([pirates, storm], Causes).

nothing_but_arrival_and_the_two_causes_is_ever_drawn_test() ->
    Departure = departure(),
    Fates = lists:usort([tom_passage:fate(Departure#{sailed_at => N})
                         || N <- lists:seq(1, 5000)]),
    ?assertEqual([], Fates -- [arrives, {lost, storm}, {lost, pirates}]).
