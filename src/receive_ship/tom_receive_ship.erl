%% @doc Take custody of a hull that has landed here.
%%
%% NOBODY CALLS THIS DESK. A harbour is infrastructure and has no say in whether
%% a ship turns up: she is this port's from the instant the sea says so, whether
%% or not this port has heard yet. So there is no procedure here for a stranger
%% to dial and no negotiation to be had. The one way in is tom_take_landings,
%% which hears the sea's announcement and asks the sea for what it has landed
%% here, and both halves of that end at `at/3'.
%%
%% TAKING IS THE COMMIT POINT AND IT IS DURABLE BEFORE THE REPLY. tom_port writes
%% this desk's record to the disk and only then answers. Never the other way
%% round: an answer that outran its own record would advance a cursor over a hull
%% this port is about to forget, and then the hull is nowhere.
%%
%% IDEMPOTENT ON THE SHIP AND THE HOP, AND THE ANSWER IS PERMANENT. A port that
%% has EVER recorded taking this hull at this hop or higher answers held,
%% whether or not it still has it, and writes nothing the second time. That is
%% what makes hearing an announcement, asking for the same landing, and doing
%% both, one single take, and it is why the record of a taking is never pruned.
%%
%% THE ONLY REFUSAL IS A PAYLOAD THAT IS NOT A HULL, which cannot be taken
%% custody of because there is nothing there to take. It is final rather than
%% transient: the same landing offered again will never become takeable, so the
%% walk says so out loud and steps past it rather than wedging behind it.
%% @end
-module(tom_receive_ship).

-export([at/3]).

%% @doc The desk.
-spec at(tom_port:state(), map(), tom_port:now()) -> tom_port:outcome().
at(State, Payload, Now) ->
    offered(State, Now, maps:get(<<"ship">>, Payload, undefined),
            tom_wire:text(<<"from">>, Payload)).

%% Internal

offered(State, Now, Hull, From) ->
    formed(State, Now, Hull, From, tom_ship:is_ship(Hull)).

formed(State, _Now, _Hull, _From, false) ->
    {{error, <<"malformed_ship">>}, State, []};
formed(State, Now, Hull, From, true) ->
    Hop = tom_ship:hop(Hull),
    already(State, Now, Hull, From, Hop,
            Hop =< maps:get(tom_ship:id(Hull), maps:get(taken, State), -1)).

%% A repeat is answered from the record and nothing is written or said again.
%% The instant is the instant of the answer, not of the original taking, because
%% what is being asked is whether this port holds her NOW.
already(State, #{at := At}, _Hull, _From, Hop, true) ->
    {{ok, #{<<"held">> => true, <<"hop">> => Hop, <<"at">> => At}}, State, []};
already(State, #{at := At}, Hull, From, Hop, false) ->
    Ship = tom_ship:id(Hull),
    Berthed = Hull#{<<"custodian">> => maps:get(harbour, State)},
    {{ok, #{<<"held">> => true, <<"hop">> => Hop, <<"at">> => At}},
     moored(State, Ship, Berthed, Hop, At),
     [{record, {took_ship, Ship, Hop, Berthed, consigner(From), At}},
      {cry, tom_wire:fact(maps:get(realm, State), <<"custody">>,
                          <<"ship_moored">>),
       #{<<"harbour">> => maps:get(harbour, State),
         <<"ship">> => Berthed,
         <<"from">> => consigner(From),
         <<"at">> => At}}]}.

consigner(undefined) -> <<"unnamed">>;
consigner(From) -> From.

moored(State, Ship, Hull, Hop, At) ->
    Taken = maps:get(taken, State),
    State#{taken := maps:put(Ship, Hop, Taken),
           ships := maps:put(Ship, #{ship => Hull, state => moored,
                                     bound_for => undefined, hop => Hop,
                                     since => At},
                             maps:get(ships, State))}.
