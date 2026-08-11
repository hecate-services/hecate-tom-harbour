%% @doc Take custody of a hull somebody is handing over.
%%
%% ACCEPTANCE IS THE COMMIT POINT AND IT IS DURABLE BEFORE THE REPLY. tom_port
%% writes this desk's record to the disk and only then answers. Never the other
%% way round: an answer that outran its own record tells a consigner to let go
%% of a hull this port is about to forget, and then the hull is nowhere.
%%
%% IDEMPOTENT ON THE SHIP AND THE HOP, AND THE ANSWER IS PERMANENT. A port that
%% has EVER recorded taking this hull at this hop or higher answers held,
%% whether or not it still has it. That is what lets a consigner that was down
%% for an hour resolve itself with a retry instead of a reconciliation call, and
%% it is why the record of a taking is never pruned.
%%
%% THERE IS NO REFUSAL FOR A WELL FORMED HANDOVER, and that is not politeness,
%% it is the custody rule. A receiver that invented one would strand a hull
%% between two custodians, with the consigner having promised it away and
%% nobody having taken it. The only thing answered with an error here is a
%% payload that is not a hull at all, which cannot be taken custody of because
%% there is nothing to take.
%%
%% `to' IS INFORMATIONAL. The procedure is addressed at this instance and only
%% this instance advertises it, so whoever answers IS the receiver. The custodian
%% written down is this port's own name, because that is the fact.
%% @end
-module(tom_receive_ship).

-export([handle/1, at/3]).

%% @doc The mesh handler.
-spec handle(map()) -> {ok, map()}.
handle(Payload) -> tom_wire:answer(tom_port:take(Payload)).

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
%% the consigner is asking whether this port holds it NOW.
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
