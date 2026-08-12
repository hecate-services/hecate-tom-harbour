-module(tom_mri_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REALM, <<"org.example.tom">>).

world() ->
    {ok, World} = tom_world:load_default(),
    World.

names_are_classes_not_instances_test() ->
    ?assertEqual({ok, <<"mri:class:org.example.tom/tom/good/raw_silk">>},
                 tom_mri:good(?REALM, raw_silk)),
    ?assertEqual({ok, <<"mri:class:org.example.tom/tom/harbour/macao">>},
                 tom_mri:harbour(?REALM, macao)),
    ?assertEqual({ok, <<"mri:class:org.example.tom/tom/recipe/weave_silk">>},
                 tom_mri:recipe(?REALM, weave_silk)).

round_trip_test() ->
    World = world(),
    [begin
         {ok, MRI} = tom_mri:good(?REALM, Id),
         ?assertEqual({ok, {good, Id}}, tom_mri:resolve(World, MRI))
     end || Id <- tom_goods:ids(World)],
    [begin
         {ok, MRI} = tom_mri:harbour(?REALM, Id),
         ?assertEqual({ok, {harbour, Id}}, tom_mri:resolve(World, MRI))
     end || Id <- tom_harbours:ids(World)],
    [begin
         {ok, MRI} = tom_mri:recipe(?REALM, Id),
         ?assertEqual({ok, {recipe, Id}}, tom_mri:resolve(World, MRI))
     end || Id <- tom_recipes:ids(World)],
    ok.

%% Everything a stranger can send fails closed, and none of it costs an atom.
resolution_fails_closed_test() ->
    World = world(),
    ?assertEqual({error, unknown_name},
                 tom_mri:resolve(
                   World, <<"mri:class:org.example.tom/tom/good/spice_melange">>)),
    ?assertEqual({error, unknown_kind},
                 tom_mri:resolve(
                   World, <<"mri:class:org.example.tom/tom/dragon/smaug">>)),
    ?assertEqual({error, not_a_tom_mri},
                 tom_mri:resolve(World, <<"mri:realm:org.example.tom">>)),
    ?assertEqual({error, not_a_tom_mri},
                 tom_mri:resolve(
                   World, <<"mri:class:org.example.tom/elsewhere/good/tea">>)),
    ?assertMatch({error, _}, tom_mri:resolve(World, <<"not an mri at all">>)),
    ?assertMatch({error, _}, tom_mri:resolve(World, <<>>)).

%% The point of failing closed. A name nobody declared must not become an atom,
%% because atoms are never collected and a stranger sends the names.
strangers_do_not_mint_atoms_test() ->
    World = world(),
    Before = erlang:system_info(atom_count),
    [tom_mri:resolve(World, invented(N)) || N <- lists:seq(1, 500)],
    ?assertEqual(Before, erlang:system_info(atom_count)).

invented(N) ->
    Name = integer_to_binary(N),
    <<"mri:class:org.example.tom/tom/good/never_seen_", Name/binary>>.

%% Two peers compare one value to know whether they are playing the same game.
digest_is_stable_and_content_sensitive_test() ->
    World = world(),
    {ok, Same} = tom_world:load_default(),
    ?assertEqual(tom_world:digest(World), tom_world:digest(Same)),
    ?assertEqual(32, byte_size(tom_world:digest(World))),
    {ok, Other} = tom_world:from_terms(small()),
    ?assertNotEqual(tom_world:digest(World), tom_world:digest(Other)).

%% A different world is a different world. A peer running a doctored process is
%% exactly what the digest exists to catch.
digest_notices_a_doctored_recipe_test() ->
    {ok, A} = tom_world:from_terms(small()),
    {ok, B} = tom_world:from_terms(retuned(small())),
    ?assertNotEqual(tom_world:digest(A), tom_world:digest(B)).

small() ->
    [{world, #{id => small, name => <<"Small">>}},
     {region, #{id => china, name => <<"China">>}},
     {good, #{id => raw_silk, name => <<"Raw silk">>, character => <<"Dear.">>}},
     {good, #{id => silk_piece_goods, name => <<"Silk piece goods">>,
              character => <<"Dearer.">>}},
     {harbour, #{id => macao, name => <<"Macao">>, region => china,
                 character => <<"The river mouth.">>,
                 produces => [raw_silk]}},
     {recipe, #{id => weave_silk, name => <<"Silk weaving">>,
                character => <<"On the loom.">>,
                inputs => #{raw_silk => 2},
                outputs => #{silk_piece_goods => 1},
                ticks => 4}}].

retuned(Terms) ->
    [retune(T) || T <- Terms].

retune({recipe, Recipe}) -> {recipe, Recipe#{ticks => 5}};
retune(Other)            -> Other.
