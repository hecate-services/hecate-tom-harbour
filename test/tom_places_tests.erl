-module(tom_places_tests).

-include_lib("eunit/include/eunit.hrl").

world() ->
    {ok, World} = tom_world:load_default(),
    World.

waypoints_and_routes_exist_test() ->
    World = world(),
    ?assert(length(tom_places:waypoint_ids(World)) > 0),
    ?assert(length(tom_places:route_ids(World)) > 0).

ids_are_unique_test() ->
    World = world(),
    [?assertEqual(length(Ids), length(lists:usort(Ids)))
     || Ids <- [tom_places:waypoint_ids(World), tom_places:route_ids(World)]],
    ok.

everything_is_named_and_described_test() ->
    World = world(),
    [begin
         ?assertNotEqual(<<>>, maps:get(name, Thing)),
         ?assertNotEqual(<<>>, maps:get(character, Thing))
     end || Thing <- tom_places:waypoints(World) ++ tom_places:routes(World)],
    ok.

%% A waypoint says WHERE and nothing else, and since 2026-08-13 it says it in
%% degrees rather than by implication. The moment one carries a duration the map
%% has started deciding what belongs to the sea: distance is geography and comes
%% from these two numbers, and how long that takes is the passage's business.
a_waypoint_says_where_and_never_how_long_test() ->
    World = world(),
    [?assertEqual([at, character, id, name], lists:sort(maps:keys(W)))
     || W <- tom_places:waypoints(World)],
    [?assertMatch({Lat, Lng} when is_number(Lat) andalso is_number(Lng),
                  maps:get(at, W))
     || W <- tom_places:waypoints(World)],
    ok.

%% THE CONSTANT NOBODY CAN CHECK BY EYE. Every route stays in proportion when
%% the earth's radius is in the wrong unit, so the only way to catch it is to
%% compare one distance with something a person can look up. Macao to Nagasaki
%% is a little over a thousand nautical miles, which is about 350 leagues; the
%% Manila galleon is about 7,800, which is about 2,600. Both were 80 percent too
%% long for an hour on 2026-08-13 and every route looked perfectly plausible.
a_league_is_three_nautical_miles_test() ->
    World = world(),
    {ok, Short} = tom_places:leagues(World, macao, nagasaki),
    {ok, Galleon} = tom_places:leagues(World, manila, acapulco),
    ?assert(Short > 330 andalso Short < 380),
    ?assert(Galleon > 2500 andalso Galleon < 2700).

%% THE ANTIMERIDIAN. Nothing in this world crosses it except the one route that
%% matters: the Luzon Strait is 121 east and the open Pacific is 175 west, so
%% subtracting longitudes flat would send the galleon 296 degrees the wrong way
%% round the world, back over Asia and Africa, and make the leg four times what
%% it is. A great circle does not care where the map is cut.
the_galleon_crosses_the_antimeridian_test() ->
    World = world(),
    {ok, Leagues} = tom_places:leagues(World, luzon_strait, the_open_pacific),
    ?assert(Leagues > 1000 andalso Leagues < 1300).

%% THE CAPE IS THE WHOLE POINT OF `via'. Goa to Lisbon in a straight line is
%% 1,502 leagues across Arabia and the Sahara and no ship has ever done it. The
%% route goes down the length of Africa and back up the Atlantic, and is more
%% than twice as far. A distance that ignored the waters would be a map with no
%% Cape in it, which is a different game.
a_route_is_measured_over_water_test() ->
    World = world(),
    {ok, Sailed} = tom_places:route_leagues(World, goa_to_lisbon),
    {ok, Straight} = tom_places:leagues(World, goa, lisbon),
    ?assert(Sailed > Straight * 2).

%% Routes are directional, and so are their lengths. Manila to Macao goes inside
%% the reefs because the strait will not have you westbound in season, and the
%% inside passage is half as far again as the strait.
the_way_home_is_not_the_way_out_test() ->
    World = world(),
    {ok, Out} = tom_places:route_leagues(World, macao_to_manila),
    {ok, Home} = tom_places:route_leagues(World, manila_to_macao),
    ?assert(Home > Out).

%% A route names harbours and waters in one list, so both kinds answer the same
%% question about where they are.
either_kind_of_place_has_a_position_test() ->
    World = world(),
    ?assertMatch({ok, {_Lat, _Lng}}, tom_places:position(World, macao)),
    ?assertMatch({ok, {_Lat, _Lng}}, tom_places:position(World, the_kuroshio)),
    ?assertEqual({error, no_such_place}, tom_places:position(World, atlantis)).

%% Same for a route. Which waters, in order, and nothing about how long.
a_route_is_only_geography_test() ->
    World = world(),
    [?assertEqual([character, from, id, name, to, via], lists:sort(maps:keys(R)))
     || R <- tom_places:routes(World)],
    ok.

%% Routes are directional because the way home was not the way out. The galleon
%% is the case that proves it: north into the current and east for weeks one
%% way, downwind and far quicker the other, which is why the quicksilver goes
%% west and the silver comes east.
the_galleon_goes_a_different_way_home_test() ->
    World = world(),
    {ok, Out} = tom_places:route_between(World, manila, acapulco),
    {ok, Home} = tom_places:route_between(World, acapulco, manila),
    ?assertNotEqual(maps:get(via, Out), maps:get(via, Home)),
    ?assert(length(maps:get(via, Out)) > length(maps:get(via, Home))).

%% A harbour is a waypoint that happens to have a market, so a route may name
%% one, and a route that passes a port is a route a ship may put in at.
a_route_may_name_a_harbour_test() ->
    World = world(),
    ?assert(tom_places:is_place(World, the_paracels)),
    ?assert(tom_places:is_place(World, macao)),
    ?assertNot(tom_places:is_place(World, atlantis)).

legs_are_the_hops_a_ship_makes_test() ->
    World = world(),
    Legs = tom_places:legs(World, macao_to_nagasaki),
    ?assertEqual([{macao, formosa_strait}, {formosa_strait, nagasaki}], Legs).

no_route_is_an_answer_test() ->
    World = world(),
    ?assertEqual({error, no_route},
                 tom_places:route_between(World, nagasaki, bahia)),
    ?assertEqual({error, unknown_route}, tom_places:route(World, the_north_pole)),
    ?assertEqual({error, unknown_waypoint},
                 tom_places:waypoint(World, atlantis)).

%% Every port that plays in the first game must be reachable and must be
%% leavable, or a player can be stranded by the map rather than by the sea.
every_playing_port_can_be_left_test() ->
    World = world(),
    [?assertNotEqual({Port, []}, {Port, tom_places:routes_from(World, Port)})
     || Port <- [macao, nagasaki, malacca, goa, manila, lisbon, acapulco,
                 bahia]],
    ok.

%% And the loader refuses a map that is wrong rather than a ship discovering it.
a_route_through_uncharted_water_is_refused_test() ->
    {error, Problems} = tom_world:from_terms(bad_map()),
    ?assert(lists:member({unknown_place, ghost_run, nowhere_at_all}, Problems)),
    ?assert(lists:member({unknown_port, ghost_run, atlantis}, Problems)),
    ?assert(lists:member({route_to_nowhere, round_in_circles}, Problems)).

bad_map() ->
    [{world, #{id => bad, name => <<"Bad">>}},
     {region, #{id => china, name => <<"China">>}},
     {good, #{id => rice, name => <<"Rice">>, character => <<"Food.">>}},
     {harbour, #{id => macao, name => <<"Macao">>, region => china,
                 character => <<"A port.">>, produces => [rice]}},
     {route, #{id => ghost_run, name => <<"Ghost run">>,
               from => macao, to => atlantis, via => [nowhere_at_all],
               character => <<"To a port that is not there.">>}},
     {route, #{id => round_in_circles, name => <<"Round in circles">>,
               from => macao, to => macao, via => [],
               character => <<"Out of Macao and into Macao.">>}}].
