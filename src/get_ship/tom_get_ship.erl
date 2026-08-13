%% @doc Where a hull is, as far as this port knows.
%%
%% THIS IS HOW A PLAYER WHO WAS SWITCHED OFF FINDS THEIR SHIP, and since the
%% ocean dissolved it is the ONLY question they have to ask. A hull at sea is
%% still this port's: custody does not move until the far port says held, so the
%% port she sailed from answers for her the whole way across and says where she
%% is bound and when she is due.
%%
%% not_here IS AN ANSWER AND NOT AN ERROR. A port that never had the hull and a
%% port that had it last week say the same thing, which is true: neither of them
%% has it. Ask the ports a player trades with and the one holding her answers;
%% when two answer, the higher hop wins.
%%
%% ANYONE MAY ASK. There is no ownership check, deliberately, and it is a
%% decision rather than an omission: what is tied up at a quay is visible from
%% the quay. The writes are checked, because moving somebody else's goods is
%% different from looking at them.
%% @end
-module(tom_get_ship).

-export([handle/1, at/3]).

%% @doc The mesh handler.
-spec handle(map()) -> {ok, map()}.
handle(Payload) -> tom_wire:answer(tom_port:berth(Payload)).

%% @doc The desk.
-spec at(tom_port:state(), map(), tom_port:now()) -> tom_port:outcome().
at(State, Payload, _Now) ->
    {asked(State, tom_wire:text(<<"ship">>, Payload)), State, []}.

%% Internal

%% A REQUEST WITH NO HULL IN IT IS NOT not_here. Echoing back what was not sent
%% would put an atom on a wire where every value is a binary, and would tell a
%% caller with a bug in it that its ship had gone.
asked(_State, undefined) ->
    {error, <<"bad_ship">>};
asked(State, Ship) ->
    found(State, Ship, maps:get(Ship, maps:get(ships, State), undefined)).

found(_State, Ship, undefined) ->
    {ok, #{<<"state">> => <<"not_here">>, <<"ship">> => Ship}};
%% AT SEA, AND THIS PORT SAYS SO. She is under way, this port is still her
%% custodian, and it knows when she is due because it wrote that down when she
%% sailed. An INSTANT and never a duration: how long a crossing takes is the
%% sea's constant and subtracting two of this port's timestamps to recover it is
%% the leak that putting `due_at' on the wire exists to prevent.
%% THE LINE COMES WITH HER, so a house that has been switched off for a week
%% asks one question and can draw the voyage it missed. It is the port's to send:
%% the route is the world's, this port carries the world, and a player links
%% nothing of ours.
found(State, _Ship, #{state := consigned} = Berth) ->
    {ok, #{<<"state">> => <<"in_passage">>,
           <<"ship">> => maps:get(ship, Berth),
           <<"bound_for">> => maps:get(bound_for, Berth),
           <<"due_at">> => maps:get(due_at, Berth),
           <<"sailed_at">> => maps:get(since, Berth),
           <<"path">> => line(State, maps:get(bound_for, Berth)),
           <<"since">> => maps:get(since, Berth)}};
found(_State, _Ship, #{state := moored} = Berth) ->
    {ok, #{<<"state">> => <<"moored">>,
           <<"ship">> => maps:get(ship, Berth),
           <<"since">> => maps:get(since, Berth)}}.

%% The line she is on, rebuilt from the map rather than kept on the berth: it is
%% the same line every time and a copy per hull would be a copy to go stale.
line(State, BoundFor) ->
    drawn(tom_places:route_between(maps:get(world, State), maps:get(place, State),
                                   tom_wire:local(BoundFor))).

drawn({ok, Route})   -> tom_wire:path(Route);
drawn({error, _Why}) -> [].
