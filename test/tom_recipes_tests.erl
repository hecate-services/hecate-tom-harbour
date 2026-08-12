-module(tom_recipes_tests).

-include_lib("eunit/include/eunit.hrl").

world() ->
    {ok, World} = tom_world:load_default(),
    World.

count_test() ->
    ?assert(tom_recipes:count(world()) > 0),
    ?assertEqual(tom_recipes:count(world()), length(tom_recipes:all(world()))).

ids_are_unique_test() ->
    Ids = tom_recipes:ids(world()),
    ?assertEqual(length(Ids), length(lists:usort(Ids))).

fetch_known_test() ->
    World = world(),
    ?assertEqual(<<"Silk weaving">>, tom_recipes:name(World, weave_silk)),
    ?assertEqual(#{raw_silk => 2}, tom_recipes:inputs(World, weave_silk)),
    ?assertEqual(#{silk_piece_goods => 1},
                 tom_recipes:outputs(World, weave_silk)).

fetch_unknown_test() ->
    World = world(),
    ?assertEqual({error, unknown_recipe},
                 tom_recipes:fetch(World, transmute_lead)),
    ?assertNot(tom_recipes:exists(World, transmute_lead)),
    ?assert(tom_recipes:exists(World, cast_cannon)).

%% A recipe is three physical facts and no money. Nothing goes in for free and
%% nothing comes out instantly. What a batch is worth is the market's business.
nothing_is_free_and_nothing_is_instant_test() ->
    World = world(),
    [begin
         Id = maps:get(id, Recipe),
         ?assertNotEqual(#{}, tom_recipes:inputs(World, Id)),
         ?assertNotEqual(#{}, tom_recipes:outputs(World, Id)),
         ?assert(tom_recipes:ticks(World, Id) > 0)
     end || Recipe <- tom_recipes:all(World)],
    ok.

%% No price lives on a recipe. Prices emerge from trade; a number here would be
%% an island of central planning in a market game.
no_money_on_a_recipe_test() ->
    World = world(),
    [begin
         {ok, Recipe} = tom_recipes:fetch(World, Id),
         ?assertEqual([character, id, inputs, name, outputs, ticks],
                      lists:sort(maps:keys(Recipe)))
     end || Id <- tom_recipes:ids(World)],
    ok.

%% A recipe with the same good on both sides is a pump. tom_world rejects it,
%% and this is the shape of the thing it rejects.
pump_is_rejected_test() ->
    {error, Problems} = tom_world:from_terms(pump_terms()),
    ?assert(lists:member({recipe_pumps, endless_gold, gold}, Problems)).

%% A cycle never resolves, so it shows up as a recipe whose inputs can never be
%% obtained. One check catches both a cycle and an unobtainable input.
cycle_is_rejected_test() ->
    {error, Problems} = tom_world:from_terms(cycle_terms()),
    ?assert(lists:member({unmakeable, make_a, [b]}, Problems)),
    ?assert(lists:member({unmakeable, make_b, [a]}, Problems)),
    ?assert(lists:member({unobtainable_good, a}, Problems)),
    ?assert(lists:member({unobtainable_good, b}, Problems)).

%% The tier is real: some goods only exist because a factory makes them.
manufactured_and_raw_partition_the_goods_test() ->
    World = world(),
    Made = tom_recipes:manufactured(World),
    Raw = tom_recipes:raw(World),
    ?assert(length(Made) > 0),
    ?assertEqual(tom_goods:ids(World), lists:usort(Made ++ Raw)),
    ?assertEqual([], [G || G <- Made, lists:member(G, Raw)]).

%% Silk piece goods are woven, and raw silk is not. That is the tier in one
%% assertion.
silk_is_the_worked_example_test() ->
    World = world(),
    ?assert(lists:member(silk_piece_goods, tom_recipes:manufactured(World))),
    ?assert(lists:member(raw_silk, tom_recipes:raw(World))),
    ?assertEqual([weave_silk],
                 [maps:get(id, R) || R <- tom_recipes:eating(World, raw_silk)]).

%% Quicksilver exists to refine silver and gold. Before the refineries it was a
%% good nothing consumed, which is what an absent ore tier looks like from
%% inside.
%%
%% Two consumers and one source is the point, not an accident. Macao is the only
%% harbour with quicksilver, so the silver refiners and the gold refiners are
%% bidding against each other for the same flask.
quicksilver_is_contested_test() ->
    World = world(),
    ?assertEqual([amalgamate_gold, amalgamate_silver],
                 [maps:get(id, R) || R <- tom_recipes:eating(World, quicksilver)]),
    ?assertEqual([macao],
                 [maps:get(id, H)
                  || H <- tom_harbours:producing(World, quicksilver)]).

%% Both money metals now have two paths into the world: found, which is limited
%% and needs nobody, and refined, which needs ore, mercury and a works.
money_metals_are_found_and_refined_test() ->
    World = world(),
    [begin
         ?assert(lists:member(M, tom_recipes:manufactured(World))),
         ?assertNotEqual([], tom_harbours:producing(World, M))
     end || M <- [gold, silver]],
    [?assert(lists:member(Ore, tom_recipes:raw(World)))
     || Ore <- [gold_ore, silver_ore]],
    ok.

%% Kinds of wood, because they are not one thing. Each is plentiful somewhere
%% different, which is what keeps the map from going uniform once recipes start
%% travelling.
woods_are_several_and_scattered_test() ->
    World = world(),
    Woods = [teak, oak, pine, ebony, brazilwood],
    [?assert(tom_goods:exists(World, W)) || W <- Woods],
    Regions = lists:usort(lists:flatmap(
                            fun(W) -> tom_goods:origins(World, W) end, Woods)),
    ?assert(length(Regions) >= 4).

pump_terms() ->
    [{world, #{id => pump, name => <<"Pump">>}},
     {region, #{id => china, name => <<"China">>}},
     {good, #{id => gold, name => <<"Gold">>, character => <<"Shiny.">>}},
     {harbour, #{id => port, name => <<"Port">>, region => china,
                 character => <<"Somewhere.">>, produces => [gold]}},
     {recipe, #{id => endless_gold, name => <<"Endless gold">>,
                character => <<"One in, two out.">>,
                inputs => #{gold => 1}, outputs => #{gold => 2},
                ticks => 1}}].

cycle_terms() ->
    [{world, #{id => loop, name => <<"Loop">>}},
     {region, #{id => china, name => <<"China">>}},
     {good, #{id => a, name => <<"A">>, character => <<"A.">>}},
     {good, #{id => b, name => <<"B">>, character => <<"B.">>}},
     {harbour, #{id => port, name => <<"Port">>, region => china,
                 character => <<"Produces neither.">>, produces => []}},
     {recipe, #{id => make_a, name => <<"Make A">>, character => <<"B to A.">>,
                inputs => #{b => 1}, outputs => #{a => 1},
                ticks => 1}},
     {recipe, #{id => make_b, name => <<"Make B">>, character => <<"A to B.">>,
                inputs => #{a => 1}, outputs => #{b => 1},
                ticks => 1}}].
