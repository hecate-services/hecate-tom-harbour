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

-export([position/2,
         leagues/3,
         waypoints/1,
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

-export_type([waypoint_id/0, waypoint/0, route_id/0, route/0, place_id/0,
              position/0]).

%% @doc Where something is, in degrees. Latitude north of the equator is
%% positive and longitude east of Greenwich is positive, which is the only
%% convention anybody uses and is worth saying once.
%%
%% A HARBOUR'S POSITION IS WHERE THE PORT IS. It has nothing whatever to do with
%% which machine runs it: Macao is at 22 degrees north whether its process is on
%% one box today and another tomorrow, and the box's own whereabouts never appear
%% on this map.
-type position() :: {number(), number()}.

-type waypoint_id() :: atom().
-type waypoint() :: #{id := waypoint_id(),
                      name := binary(),
                      at := position(),
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

%% @doc Where a place is, whichever kind it is.
%%
%% A route names harbours and waters in one list, so anything asking how far it
%% is between two points on a route has to be able to ask either kind the same
%% question.
-spec position(tom_world:world(), place_id()) -> {ok, position()} | {error, term()}.
position(World, Id) ->
    sited(waypoint(World, Id), harbour_at(World, Id)).

%% @doc How far it is between two places, in leagues.
%%
%% THE ONE NUMBER NOBODY WROTE DOWN. A leg's length is the distance between its
%% ends, which is a fact about the earth rather than a judgement about the game,
%% so Macao to Nagasaki is short because it IS short and the galleon is long
%% because the Pacific is. That is the same rule the market runs on: a price
%% comes out of a market or it does not exist, and a distance comes off the map
%% or it does not exist.
%%
%% ⚠ HOW LONG THAT TAKES IS NOT HERE AND MUST NOT COME HERE. Leagues are the
%% map's; leagues per hour are the sea's, and they live at the port she sailed
%% from. A world that knew how fast a ship went would be deciding the tempo of
%% the game from a data file.
%%
%% Great circle, because the earth is round and the Manila galleon is nine
%% thousand leagues of proof. A flat subtraction of longitudes would make the
%% Pacific crossing longer than it is and would break outright at the
%% antimeridian, which that route crosses.
-spec leagues(tom_world:world(), place_id(), place_id()) ->
          {ok, float()} | {error, term()}.
leagues(World, From, To) ->
    apart(position(World, From), position(World, To)).

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

sited({ok, Waypoint}, _Harbour)  -> {ok, maps:get(at, Waypoint)};
sited({error, _}, {ok, Harbour}) -> {ok, maps:get(at, Harbour)};
sited({error, _}, error)         -> {error, no_such_place}.

harbour_at(World, Id) -> maps:find(Id, tom_world:harbours(World)).

apart({ok, From}, {ok, To}) -> {ok, haversine(From, To)};
apart({error, _} = Err, _)  -> Err;
apart(_, {error, _} = Err)  -> Err.

%% A LEAGUE IS THREE NAUTICAL MILES, 5556 metres, which is what the period meant
%% by one at sea. The earth's mean radius is 6371 km, so it is 1146.7 leagues,
%% and that is the only number in this file that is a convention rather than a
%% measurement.
%%
%% Checked against a distance somebody can look up: Macao to Nagasaki is about
%% 350 leagues and the Manila galleon is about 2600. A radius in the wrong unit
%% is invisible until you compare one, because every route stays in proportion.
-define(EARTH_LEAGUES, 1146.7).

haversine({Lat1, Lng1}, {Lat2, Lng2}) ->
    P1 = Lat1 * math:pi() / 180,
    P2 = Lat2 * math:pi() / 180,
    DP = (Lat2 - Lat1) * math:pi() / 180,
    DL = (Lng2 - Lng1) * math:pi() / 180,
    A = math:sin(DP / 2) * math:sin(DP / 2)
        + math:cos(P1) * math:cos(P2) * math:sin(DL / 2) * math:sin(DL / 2),
    ?EARTH_LEAGUES * 2 * math:atan2(math:sqrt(A), math:sqrt(1 - A)).

found({ok, Found}, _Missing) -> {ok, Found};
found(error, Missing)        -> {error, Missing}.

matched([Route | _]) -> {ok, Route};
matched([])          -> {error, no_route}.
