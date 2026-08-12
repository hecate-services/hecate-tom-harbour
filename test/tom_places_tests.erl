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

%% A waypoint says where and nothing else. The moment one carries a duration,
%% the map has started deciding what belongs to the sea.
a_waypoint_has_no_duration_test() ->
    World = world(),
    [?assertEqual([character, id, name], lists:sort(maps:keys(W)))
     || W <- tom_places:waypoints(World)],
    ok.

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
