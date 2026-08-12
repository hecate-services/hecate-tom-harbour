%% @doc The places on the map, and the routes between them.
%%
%% A WAYPOINT IS SOMEWHERE A SHIP CAN BE SAID TO BE. It has a name and a line of
%% character and nothing else: no market, no hinterland, no produce.
%%
%% A HARBOUR IS A WAYPOINT THAT HAPPENS TO HAVE A MARKET. That is why a route
%% below may name either kind, and why a route that passes a port is a route a
%% ship may put in at. Putting in costs time, and that is the ship's decision to
%% make rather than the map's.
%%
%% A ROUTE IS GEOGRAPHY. Which waters lie between two ports, in order. It says
%% nothing whatever about how long any of it takes, because a passage time is
%% weather and season and hull, and all three belong to the sea rather than to
%% the map. The world says WHERE. The ocean says HOW LONG. The ship says WHETHER
%% TO STOP.
%%
%% Routes are DIRECTIONAL, and both directions are written down separately. The
%% way home was not the way out: the monsoon and the trades saw to that, and a
%% world that pretends otherwise has thrown away the most interesting constraint
%% of the period. Manila to Acapulco runs north into the Kuroshio and then east
%% for weeks; Acapulco to Manila runs downwind and is far quicker, which is
%% exactly why the quicksilver goes west and the silver comes east.
%% @end
-module(tom_places).

-export([waypoints/1,
         waypoint_ids/1,
         waypoint/2,
         is_place/2,
         routes/1,
         route_ids/1,
         route/2,
         route_between/3,
         routes_from/2,
         legs/2,
         calls_at/3]).

-export_type([waypoint_id/0, waypoint/0, route_id/0, route/0, place_id/0]).

-type waypoint_id() :: atom().
-type waypoint() :: #{id := waypoint_id(),
                      name := binary(),
                      character := binary()}.

-type route_id() :: atom().
-type route() :: #{id := route_id(),
                   name := binary(),
                   from := tom_harbours:id(),
                   to := tom_harbours:id(),
                   via := [place_id()],
                   character := binary()}.

%% @doc Anywhere a route may name: a waypoint, or a harbour.
-type place_id() :: waypoint_id() | tom_harbours:id().

%% @doc Every waypoint, ordered by identifier.
-spec waypoints(tom_world:world()) -> [waypoint()].
waypoints(World) ->
    [W || {_Id, W} <- lists:sort(maps:to_list(tom_world:waypoints(World)))].

%% @doc Every waypoint's identifier.
-spec waypoint_ids(tom_world:world()) -> [waypoint_id()].
waypoint_ids(World) -> lists:sort(maps:keys(tom_world:waypoints(World))).

%% @doc Look a waypoint up.
-spec waypoint(tom_world:world(), waypoint_id()) ->
          {ok, waypoint()} | {error, unknown_waypoint}.
waypoint(World, Id) ->
    found(maps:find(Id, tom_world:waypoints(World)), unknown_waypoint).

%% @doc Whether a route may name this: a waypoint or a harbour, either will do.
-spec is_place(tom_world:world(), place_id()) -> boolean().
is_place(World, Id) ->
    maps:is_key(Id, tom_world:waypoints(World))
        orelse tom_harbours:exists(World, Id).

%% @doc Every route, ordered by identifier.
-spec routes(tom_world:world()) -> [route()].
routes(World) ->
    [R || {_Id, R} <- lists:sort(maps:to_list(tom_world:routes(World)))].

%% @doc Every route's identifier.
-spec route_ids(tom_world:world()) -> [route_id()].
route_ids(World) -> lists:sort(maps:keys(tom_world:routes(World))).

%% @doc Look a route up.
-spec route(tom_world:world(), route_id()) ->
          {ok, route()} | {error, unknown_route}.
route(World, Id) -> found(maps:find(Id, tom_world:routes(World)), unknown_route).

%% @doc The route from one port to another, if the map has one.
%%
%% Directional on purpose. Asking for the way back is a different question with
%% a different answer, and sometimes with no answer at all.
-spec route_between(tom_world:world(), tom_harbours:id(), tom_harbours:id()) ->
          {ok, route()} | {error, no_route}.
route_between(World, From, To) ->
    matched([R || R <- routes(World),
                  maps:get(from, R) =:= From, maps:get(to, R) =:= To]).

%% @doc Every route leaving a port. Where a ship at this quay may go.
-spec routes_from(tom_world:world(), tom_harbours:id()) -> [route()].
routes_from(World, From) ->
    [R || R <- routes(World), maps:get(from, R) =:= From].

%% @doc A route as the hops a ship actually makes, port to port.
%%
%% The `via' list is the water in between; the legs are the pairs. A route with
%% no waypoints is one leg, which is a ship going straight there.
-spec legs(tom_world:world(), route_id()) -> [{place_id(), place_id()}].
legs(World, Id) ->
    {ok, Route} = route(World, Id),
    Points = [maps:get(from, Route) | maps:get(via, Route)]
             ++ [maps:get(to, Route)],
    lists:zip(lists:droplast(Points), tl(Points)).

%% @doc Whether a route passes a given place, which is where a ship may put in.
-spec calls_at(tom_world:world(), route_id(), place_id()) -> boolean().
calls_at(World, Id, Place) ->
    {ok, Route} = route(World, Id),
    lists:member(Place, maps:get(via, Route)).

%% Internal

found({ok, Found}, _Missing) -> {ok, Found};
found(error, Missing)        -> {error, Missing}.

matched([Route | _]) -> {ok, Route};
matched([])          -> {error, no_route}.
