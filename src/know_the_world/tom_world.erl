%% @doc Loads and checks a world.
%%
%% A world is a file of Erlang terms: one world header, then regions, goods,
%% harbours and recipes in any order. It is data. Adding a good or a harbour is an
%% edit to that file, not a release of this library.
%%
%% The line between code and data: this library defines the map every good,
%% harbour and recipe has, and checks that a world fills them in and hangs
%% together. The entries themselves live in the file. There is no closed
%% vocabulary left anywhere in it, so every name a world uses is the world's to
%% choose.
%%
%% Loading either succeeds with a whole world or fails with every problem it
%% found, not the first. A half-loaded world is worse than none.
%%
%% digest/1 is what two peers compare. Somebody edits the world file, redeploys
%% one harbour, and that harbour now disagrees with everyone else about what
%% exists, silently, with no error anywhere. A shared database quietly prevented
%% that and a mesh does not, so the check has to be explicit: exchange the
%% digest, refuse to trade with a peer whose world is not yours.
%%
%% See priv/worlds/macao.world for the shipped one.
%% @end
-module(tom_world).

-export([load/1,
         load_default/0,
         from_terms/1,
         default_path/0,
         id/1,
         name/1,
         regions/1,
         goods/1,
         harbours/1,
         recipes/1,
         waypoints/1,
         routes/1,
         digest/1,
         region_ids/1,
         region/2]).

-export_type([world/0, region/0, region_id/0, problem/0]).

-type region_id() :: atom().
-type region() :: #{id := region_id(), name := binary()}.

-type world() :: #{id := atom(),
                   name := binary(),
                   regions := #{region_id() => region()},
                   goods := #{tom_goods:id() => tom_goods:good()},
                   harbours := #{tom_harbours:id() => tom_harbours:harbour()},
                   recipes := #{tom_recipes:id() => tom_recipes:recipe()},
                   waypoints := #{tom_places:waypoint_id() => tom_places:waypoint()},
                   routes := #{tom_places:route_id() => tom_places:route()}}.

%% @doc Everything that can be wrong with a world file.
-type problem() :: {no_world_header, []}
                 | {several_world_headers, [atom()]}
                 | {unknown_term, term()}
                 | {missing_field, atom(), atom(), atom()}
                 | {duplicate, atom(), atom()}
                 | {unknown_region, atom(), atom(), region_id()}
                 | {unknown_good, atom(), tom_goods:id()}
                 | {recipe_pumps, tom_recipes:id(), tom_goods:id()}
                 | {empty_side, tom_recipes:id(), inputs | outputs}
                 | {unmakeable, tom_recipes:id(), [tom_goods:id()]}
                 | {unobtainable_good, tom_goods:id()}
                 | {unknown_place, tom_places:route_id(), atom()}
                 | {unknown_port, tom_places:route_id(), atom()}
                 | {route_to_nowhere, tom_places:route_id()}.

%% @doc Load the world shipped with this library.
-spec load_default() -> {ok, world()} | {error, [problem()]} | {error, term()}.
load_default() -> load(default_path()).

%% @doc Where the shipped world lives.
-spec default_path() -> file:filename_all().
default_path() ->
    filename:join([code:priv_dir(hecate_tom_world), "worlds", "macao.world"]).

%% @doc Load a world from a file of Erlang terms.
-spec load(file:filename_all()) ->
          {ok, world()} | {error, [problem()]} | {error, term()}.
load(Path) -> consulted(file:consult(Path)).

%% @doc Build a world from already-read terms. Every problem, not the first.
-spec from_terms([term()]) -> {ok, world()} | {error, [problem()]}.
from_terms(Terms) ->
    World = assemble(Terms),
    checked(World, problems(Terms, World)).

%% @doc The world's identifier.
-spec id(world()) -> atom().
id(World) -> maps:get(id, World).

%% @doc The world's display name.
-spec name(world()) -> binary().
name(World) -> maps:get(name, World).

%% @doc Every region, keyed by identifier.
-spec regions(world()) -> #{region_id() => region()}.
regions(World) -> maps:get(regions, World).

%% @doc Every good, keyed by identifier.
-spec goods(world()) -> #{tom_goods:id() => tom_goods:good()}.
goods(World) -> maps:get(goods, World).

%% @doc Every harbour, keyed by identifier.
-spec harbours(world()) -> #{tom_harbours:id() => tom_harbours:harbour()}.
harbours(World) -> maps:get(harbours, World).

%% @doc Every recipe, keyed by identifier.
-spec recipes(world()) -> #{tom_recipes:id() => tom_recipes:recipe()}.
recipes(World) -> maps:get(recipes, World).

%% @doc Every waypoint, keyed by identifier.
-spec waypoints(world()) -> #{tom_places:waypoint_id() => tom_places:waypoint()}.
waypoints(World) -> maps:get(waypoints, World).

%% @doc Every route, keyed by identifier.
-spec routes(world()) -> #{tom_places:route_id() => tom_places:route()}.
routes(World) -> maps:get(routes, World).

%% @doc A fingerprint of what this world contains.
%%
%% Over the content and not the file, so a reworded comment or a shuffled line
%% leaves it alone and a changed price, name or recipe does not. Two peers
%% comparing one value know at once whether they are playing the same game.
-spec digest(world()) -> binary().
digest(World) ->
    crypto:hash(sha256, term_to_binary(fingerprint(World))).

%% @doc Every region's identifier.
-spec region_ids(world()) -> [region_id()].
region_ids(World) -> lists:sort(maps:keys(regions(World))).

%% @doc Look a region up.
-spec region(world(), region_id()) -> {ok, region()} | {error, unknown_region}.
region(World, Id) -> looked_up(maps:find(Id, regions(World)), unknown_region).

%% Internal

%% Sorted lists all the way down, because map iteration order is not something
%% to stake a fleet-wide agreement on.
fingerprint(World) ->
    {id(World), name(World),
     [sorted(E) || E <- ordered(regions(World))],
     [sorted(E) || E <- ordered(goods(World))],
     [sorted(E) || E <- ordered(harbours(World))],
     [sorted(E) || E <- ordered(recipes(World))],
     [sorted(E) || E <- ordered(waypoints(World))],
     [sorted(E) || E <- ordered(routes(World))]}.

ordered(Entries) -> [E || {_Id, E} <- lists:sort(maps:to_list(Entries))].

sorted(Entry) -> lists:sort(maps:to_list(maps:map(fun deep/2, Entry))).

deep(_Key, Value) when is_map(Value) -> lists:sort(maps:to_list(Value));
deep(_Key, Value)                    -> Value.

consulted({ok, Terms})  -> from_terms(Terms);
consulted({error, Why}) -> {error, Why}.

checked(World, [])       -> {ok, World};
checked(_World, Problems) -> {error, Problems}.

looked_up({ok, Found}, _Missing) -> {ok, Found};
looked_up(error, Missing)        -> {error, Missing}.

assemble(Terms) ->
    Header = maps:merge(#{id => unnamed, name => <<>>}, header(Terms)),
    Header#{regions => keyed(region, Terms),
            goods => keyed(good, Terms),
            harbours => keyed(harbour, Terms),
            recipes => keyed(recipe, Terms),
            waypoints => keyed(waypoint, Terms),
            routes => keyed(route, Terms)}.

header(Terms) ->
    hd(entries(world, Terms) ++ [#{}]).

entries(Tag, Terms) ->
    [Map || {T, Map} <- Terms, T =:= Tag, is_map(Map)].

keyed(Tag, Terms) ->
    maps:from_list([{maps:get(id, E), E} || E <- entries(Tag, Terms),
                                            maps:is_key(id, E)]).

%% Checks -----------------------------------------------------------------

problems(Terms, World) ->
    header_problems(Terms)
        ++ shape_problems(Terms)
        ++ duplicate_problems(Terms)
        ++ harbour_problems(World)
        ++ recipe_problems(World)
        ++ reach_problems(World)
        ++ route_problems(World).

header_problems(Terms) ->
    headers(entries(world, Terms)).

headers([_One]) -> [];
headers([])     -> [{no_world_header, []}];
headers(Many)   -> [{several_world_headers, [maps:get(id, M, unnamed)
                                             || M <- Many]}].

shape_problems(Terms) ->
    lists:flatmap(fun shape_problem/1, Terms).

shape_problem({world, Map}) when is_map(Map) ->
    missing(world, Map, [id, name]);
shape_problem({region, Map}) when is_map(Map) ->
    missing(region, Map, [id, name]);
shape_problem({good, Map}) when is_map(Map) ->
    missing(good, Map, [id, name, character]);
shape_problem({harbour, Map}) when is_map(Map) ->
    missing(harbour, Map, [id, name, region, character, produces]);
shape_problem({waypoint, Map}) when is_map(Map) ->
    missing(waypoint, Map, [id, name, character]);
shape_problem({route, Map}) when is_map(Map) ->
    missing(route, Map, [id, name, from, to, via, character]);
shape_problem({recipe, Map}) when is_map(Map) ->
    missing(recipe, Map,
            [id, name, character, inputs, outputs, ticks]);
shape_problem(Other) ->
    [{unknown_term, Other}].

missing(Tag, Map, Required) ->
    [{missing_field, Tag, maps:get(id, Map, unnamed), Field}
     || Field <- Required, not maps:is_key(Field, Map)].

duplicate_problems(Terms) ->
    lists:flatmap(fun(Tag) -> duplicates(Tag, Terms) end,
                  [region, good, harbour, recipe, waypoint, route]).

duplicates(Tag, Terms) ->
    Ids = [maps:get(id, E) || E <- entries(Tag, Terms), maps:is_key(id, E)],
    [{duplicate, Tag, Id} || Id <- Ids -- lists:usort(Ids)].

harbour_problems(World) ->
    lists:flatmap(fun(Harbour) -> harbour_problem(World, Harbour) end,
                  maps:values(harbours(World))).

harbour_problem(World, Harbour) ->
    Id = maps:get(id, Harbour),
    Region = maps:get(region, Harbour, undefined),
    [{unknown_region, harbour, Id, Region}
     || not maps:is_key(Region, regions(World))]
        ++ [{unknown_good, Id, G}
            || G <- maps:get(produces, Harbour, []),
               not maps:is_key(G, goods(World))].

recipe_problems(World) ->
    lists:flatmap(fun(Recipe) -> recipe_problem(World, Recipe) end,
                  maps:values(recipes(World))).

recipe_problem(World, Recipe) ->
    Id = maps:get(id, Recipe),
    In = maps:keys(maps:get(inputs, Recipe, #{})),
    Out = maps:keys(maps:get(outputs, Recipe, #{})),
    [{unknown_good, Id, G} || G <- In ++ Out, not maps:is_key(G, goods(World))]
        ++ [{recipe_pumps, Id, G} || G <- In, lists:member(G, Out)]
        ++ empty_side(Id, inputs, In)
        ++ empty_side(Id, outputs, Out).

empty_side(Id, Side, []) -> [{empty_side, Id, Side}];
empty_side(_Id, _Side, _) -> [].

%% A good must be able to enter the world, out of the ground at some harbour or
%% out of a factory whose own inputs can enter the world. Growing the set from
%% what harbours produce catches an unobtainable input and a cycle in one pass,
%% since a cycle simply never resolves.
reach_problems(World) ->
    Obtainable = obtainable(World),
    [{unobtainable_good, G}
     || G <- lists:sort(maps:keys(goods(World))),
        not lists:member(G, Obtainable)]
        ++ lists:flatmap(fun(R) -> unmakeable(R, Obtainable) end,
                         maps:values(recipes(World))).

unmakeable(Recipe, Obtainable) ->
    Missing = maps:keys(maps:get(inputs, Recipe, #{})) -- Obtainable,
    missing_inputs(maps:get(id, Recipe), Missing).

missing_inputs(_Id, [])     -> [];
missing_inputs(Id, Missing) -> [{unmakeable, Id, lists:sort(Missing)}].

obtainable(World) ->
    Dug = lists:usort(lists:flatmap(fun(H) -> maps:get(produces, H, []) end,
                                    maps:values(harbours(World)))),
    grow(World, Dug).

grow(World, Have) ->
    Grown = lists:foldl(fun(R, Acc) -> yielded(R, Acc) end, Have,
                        maps:values(recipes(World))),
    settled(World, Have, Grown).

settled(_World, Have, Have) -> Have;
settled(World, _Was, Grown) -> grow(World, Grown).

yielded(Recipe, Have) ->
    In = maps:keys(maps:get(inputs, Recipe, #{})),
    Out = maps:keys(maps:get(outputs, Recipe, #{})),
    runnable(In -- Have, Out, Have).

runnable([], Out, Have) -> lists:usort(Have ++ Out);
runnable(_Missing, _Out, Have) -> Have.

%% A route is geography, so the only things that can be wrong with one are
%% geographic: it names water nobody has charted, it starts or ends somewhere
%% that is not a port, or it goes nowhere.
route_problems(World) ->
    lists:flatmap(fun(Route) -> route_problem(World, Route) end,
                  maps:values(routes(World))).

route_problem(World, Route) ->
    Id = maps:get(id, Route),
    From = maps:get(from, Route, undefined),
    To = maps:get(to, Route, undefined),
    nowhere(Id, From, To)
        ++ [{unknown_port, Id, P}
            || P <- [From, To], not tom_harbours:exists(World, P)]
        ++ [{unknown_place, Id, W}
            || W <- maps:get(via, Route, []),
               not tom_places:is_place(World, W)].

nowhere(Id, Same, Same) -> [{route_to_nowhere, Id}];
nowhere(_Id, _From, _To) -> [].
