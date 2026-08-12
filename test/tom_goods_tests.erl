-module(tom_goods_tests).

-include_lib("eunit/include/eunit.hrl").

world() ->
    {ok, World} = tom_world:load_default(),
    World.

count_test() ->
    ?assertEqual(67, tom_goods:count(world())),
    ?assertEqual(67, length(tom_goods:all(world()))).

ids_are_unique_test() ->
    Ids = tom_goods:ids(world()),
    ?assertEqual(length(Ids), length(lists:usort(Ids))).

every_good_is_named_and_described_test() ->
    [begin
         ?assertNotEqual(<<>>, maps:get(name, Good)),
         ?assertNotEqual(<<>>, maps:get(character, Good))
     end || Good <- tom_goods:all(world())],
    ok.

fetch_known_test() ->
    World = world(),
    {ok, Good} = tom_goods:fetch(World, sandalwood),
    ?assertEqual(sandalwood, maps:get(id, Good)),
    ?assertEqual(<<"Sandalwood">>, tom_goods:name(World, sandalwood)),
    ?assertEqual([southeast_asia], tom_goods:origins(World, sandalwood)).

fetch_unknown_test() ->
    World = world(),
    ?assertEqual({error, unknown_good}, tom_goods:fetch(World, spice_melange)),
    ?assertNot(tom_goods:exists(World, spice_melange)),
    ?assert(tom_goods:exists(World, silver)).

%% Origins are derived from the harbours that produce a good, so they cannot go
%% stale. Silver is dug in Japan and nowhere else; the Americas dig ore, and it
%% is the refinery that turns that into silver. The declared field went on
%% claiming the Americas for a day after that stopped being true.
origins_are_derived_and_therefore_current_test() ->
    World = world(),
    ?assertEqual([japan], tom_goods:origins(World, silver)),
    ?assertEqual([north_america, south_america],
                 tom_goods:origins(World, silver_ore)).

%% A good no harbour produces comes out of no ground at all. It is made, and a
%% factory stands wherever its recipe and its inputs are.
a_made_good_comes_from_nowhere_test() ->
    World = world(),
    [?assertEqual({Id, []}, {Id, tom_goods:origins(World, Id)})
     || Id <- [chintz, cordage, sailcloth, gunpowder, cannon, ironwork,
               candles, incense, arrack]],
    ok.

%% And a good that is both dug and made still comes from where it is dug.
a_good_can_be_dug_and_made_test() ->
    World = world(),
    ?assertEqual([china], tom_goods:origins(World, porcelain)),
    ?assert(lists:member(porcelain, tom_recipes:manufactured(World))).
