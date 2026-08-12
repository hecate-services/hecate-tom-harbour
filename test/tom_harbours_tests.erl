-module(tom_harbours_tests).

-include_lib("eunit/include/eunit.hrl").

world() ->
    {ok, World} = tom_world:load_default(),
    World.

%% The pool is bigger than a game. Eight play; the rest are there to be chosen.
pool_is_larger_than_a_game_test() ->
    ?assert(tom_harbours:count(world()) > 8).

ids_are_unique_test() ->
    Ids = tom_harbours:ids(world()),
    ?assertEqual(length(Ids), length(lists:usort(Ids))).

every_harbour_is_named_and_described_test() ->
    [begin
         ?assertNotEqual(<<>>, maps:get(name, Harbour)),
         ?assertNotEqual(<<>>, maps:get(character, Harbour))
     end || Harbour <- tom_harbours:all(world())],
    ok.

fetch_known_test() ->
    World = world(),
    ?assertEqual(<<"Malacca">>, tom_harbours:name(World, malacca)),
    ?assertEqual(southeast_asia, tom_harbours:region(World, malacca)),
    ?assert(tom_harbours:plentiful(World, malacca, pepper)),
    ?assertNot(tom_harbours:plentiful(World, malacca, opium)).

fetch_unknown_test() ->
    World = world(),
    ?assertEqual({error, unknown_harbour}, tom_harbours:fetch(World, atlantis)),
    ?assertNot(tom_harbours:exists(World, atlantis)),
    ?assert(tom_harbours:exists(World, macao)).

%% Every good must be able to enter the world, either dug out of the ground at
%% some harbour or made by a factory. tom_world enforces this on load; here it
%% is stated as the thing it means.
every_good_can_enter_the_world_test() ->
    World = world(),
    Made = tom_recipes:manufactured(World),
    [?assert(tom_harbours:producing(World, Id) =/= []
             orelse lists:member(Id, Made))
     || Id <- tom_goods:ids(World)],
    ok.

%% Raw materials are exactly the goods no factory makes, and every one of them
%% must come out of the ground somewhere.
every_raw_good_is_plentiful_somewhere_test() ->
    World = world(),
    [?assertNotEqual({Id, []}, {Id, tom_harbours:producing(World, Id)})
     || Id <- tom_recipes:raw(World)],
    ok.

%% Demand is the absence of abundance, so the two queries partition the pool.
%% Nothing is both cheap and dear in the same place, and no harbour is neither.
supply_and_demand_partition_the_pool_test() ->
    World = world(),
    Total = tom_harbours:count(World),
    [?assertEqual({Id, Total},
                  {Id, length(tom_harbours:producing(World, Id))
                       + length(tom_harbours:wanting(World, Id))})
     || Id <- tom_goods:ids(World)],
    ok.

%% A good plentiful nowhere would be dear everywhere. Nothing in this world is,
%% but the query must still answer, because that is what a shortage looks like.
everything_is_short_somewhere_test() ->
    World = world(),
    [?assertNotEqual({Id, []}, {Id, tom_harbours:wanting(World, Id)})
     || Id <- tom_goods:ids(World)],
    ok.

%% A pure entrepot makes nothing of its own and is rich anyway. Manila is the
%% case, and it is deliberate rather than an omission.
entrepot_produces_nothing_test() ->
    ?assertEqual([], tom_harbours:produces(world(), manila)).

%% Acapulco is a dead end with one route and an enormous prize on it. What it
%% digs is ore, and the ore is worth nothing until quicksilver arrives from
%% China, so the galleon is loaded in both directions. Who eats the quicksilver
%% is tom_recipes' business, not this module's.
acapulco_digs_ore_not_silver_test() ->
    World = world(),
    ?assertEqual([silver_ore], tom_harbours:produces(World, acapulco)),
    ?assertEqual([silver_ore], tom_harbours:produces(World, callao)).
