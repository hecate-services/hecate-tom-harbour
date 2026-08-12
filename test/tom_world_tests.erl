-module(tom_world_tests).

-include_lib("eunit/include/eunit.hrl").

world() ->
    {ok, World} = tom_world:load_default(),
    World.

%% The shipped world must load clean. If it does not, every service that links
%% this library fails to start, so this is the first test that matters.
default_world_loads_test() ->
    ?assertMatch({ok, _}, tom_world:load_default()),
    ?assertEqual(macao, tom_world:id(world())),
    ?assertEqual(<<"Traders of Macao">>, tom_world:name(world())).

regions_test() ->
    Ids = tom_world:region_ids(world()),
    ?assert(lists:member(china, Ids)),
    ?assert(lists:member(south_america, Ids)),
    ?assertMatch({ok, #{name := <<"China">>}}, tom_world:region(world(), china)),
    ?assertEqual({error, unknown_region},
                 tom_world:region(world(), atlantis)).

%% Every region a world declares should have something in it, or it is a
%% region that exists only on paper.
every_region_is_inhabited_test() ->
    World = world(),
    [?assertNotEqual({R, [], []},
                     {R, tom_goods:from_region(World, R),
                      tom_harbours:in_region(World, R)})
     || R <- tom_world:region_ids(World)],
    ok.

%% Loading reports every problem, not the first. A half-loaded world is worse
%% than none.
broken_world_reports_all_problems_test() ->
    {error, Problems} = tom_world:from_terms(broken_terms()),
    ?assert(lists:member({unknown_good, ghost_port, unobtainium}, Problems)),
    ?assert(lists:member({duplicate, region, china}, Problems)).

missing_header_is_a_problem_test() ->
    {error, Problems} = tom_world:from_terms([]),
    ?assertEqual([{no_world_header, []}], Problems).

missing_fields_are_named_test() ->
    Terms = [{world, #{id => thin, name => <<"Thin">>}},
             {good, #{id => nameless}}],
    {error, Problems} = tom_world:from_terms(Terms),
    ?assert(lists:member({missing_field, good, nameless, name}, Problems)),
    ?assert(lists:member({missing_field, good, nameless, character}, Problems)).

unreadable_file_is_an_error_test() ->
    ?assertMatch({error, enoent}, tom_world:load("no/such/world")).

broken_terms() ->
    [{world, #{id => broken, name => <<"Broken">>}},
     {region, #{id => china, name => <<"China">>}},
     {region, #{id => china, name => <<"China again">>}},
     {good, #{id => ghost_silk, name => <<"Ghost silk">>,
              character => <<"Not there.">>}},
     {harbour, #{id => ghost_port, name => <<"Ghost port">>, region => china,
                 character => <<"Also not there.">>,
                 produces => [unobtainium]}}].
