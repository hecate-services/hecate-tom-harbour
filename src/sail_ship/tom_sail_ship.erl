%% @doc Promise a hull to the ocean, and freeze it until the ocean has it.
%%
%% A CONSIGNMENT IS NOT A HOP. Writing it down does not move custody. It does
%% two things: it FREEZES the hull, so nothing can be bought into it, sold out
%% of it or consigned a second time, and it OBLIGES this port to keep calling
%% the ocean until it gets an answer. This port stays the custodian, at the old
%% hop, for as long as that takes. If the ocean is down for an hour the hull sits
%% here for an hour, visibly consigned, which is the truth and is better than
%% pretending it left.
%%
%% NO IDEMPOTENCY KEY, BECAUSE THE HULL'S OWN STATE IS THE KEY. Called again
%% with the same destination while consigned, it answers the same thing. Called
%% with a different destination, already_bound: the promise has been made and
%% the payload the ocean is being retried with cannot change underneath it, or
%% the retry would stop being byte for byte the same call and the receiver could
%% no longer tell a repeat from a new handover.
%%
%% bad_destination IS A PARSE AND NOT A LOOKUP. This port has no directory and
%% cannot know whether Lisbon exists, only whether the name is shaped like a
%% harbour instance that might. Refusing on ignorance would ground every ship
%% bound for a port this one has not been told about.
%% @end
-module(tom_sail_ship).

-export([handle/1, at/3, handover/2]).

%% @doc The mesh handler.
-spec handle(map()) -> {ok, map()}.
handle(Payload) -> tom_wire:answer(tom_port:sail(Payload)).

%% @doc The desk.
-spec at(tom_port:state(), map(), tom_port:now()) -> tom_port:outcome().
at(State, Payload, Now) ->
    berthed(State, Payload, Now,
            maps:get(tom_wire:text(<<"ship">>, Payload),
                     maps:get(ships, State), undefined)).

%% @doc The payload the ocean is being asked to take, rebuilt from a berth.
%%
%% USED AT BOOT TO PICK UP AN UNFINISHED PROMISE, and it must reconstruct the
%% call BYTE FOR BYTE, because that identity is the whole of how the receiver
%% dedupes. Everything it needs is on the frozen berth, which is why the berth
%% keeps the consigned hop and destination rather than only the fact of being
%% frozen.
-spec handover(tom_port:state(), tom_port:consigned()) -> map().
handover(State, Berth) ->
    #{<<"from">> => maps:get(harbour, State),
      <<"to">> => maps:get(consigned_to, Berth),
      <<"bound_for">> => maps:get(bound_for, Berth),
      <<"ship">> => tom_ship:consign(maps:get(ship, Berth),
                                     maps:get(consigned_to, Berth))}.

%% Internal

berthed(State, _Payload, _Now, undefined) ->
    {{error, <<"not_here">>}, State, []};
berthed(State, Payload, Now, #{ship := Hull} = Berth) ->
    owned(State, Payload, Now, Berth,
          tom_ship:owner(Hull) =:= tom_wire:text(<<"by">>, Payload)).

owned(State, _Payload, _Now, _Berth, false) ->
    {{error, <<"not_yours">>}, State, []};
owned(State, Payload, Now, Berth, true) ->
    bound(State, Now, Berth, tom_wire:text(<<"bound_for">>, Payload)).

bound(State, Now, Berth, Destination) ->
    addressed(State, Now, Berth, Destination, tom_wire:is_harbour(Destination)).

addressed(State, _Now, _Berth, _Destination, false) ->
    {{error, <<"bad_destination">>}, State, []};
addressed(State, Now, #{state := consigned} = Berth, Destination, true) ->
    again(State, Now, Berth, Destination,
          maps:get(bound_for, Berth) =:= Destination);
addressed(State, Now, Berth, Destination, true) ->
    consigned(State, Now, Berth, Destination).

%% The same order twice is the same answer, from the berth rather than from a
%% stored receipt: a frozen hull already carries the hop the ocean will hold and
%% the instant it was promised.
again(State, _Now, Berth, Destination, true) ->
    {{ok, #{<<"ship">> => tom_ship:id(maps:get(ship, Berth)),
            <<"hop">> => maps:get(hop, Berth),
            <<"bound_for">> => Destination,
            <<"consigned_to">> => maps:get(consigned_to, Berth),
            <<"at">> => maps:get(since, Berth)}},
     State, []};
again(State, _Now, _Berth, _Destination, false) ->
    {{error, <<"already_bound">>}, State, []}.

consigned(State, #{at := At}, Berth, Destination) ->
    Hull = maps:get(ship, Berth),
    Ship = tom_ship:id(Hull),
    Ocean = maps:get(ocean, State),
    Hop = tom_ship:hop(Hull) + 1,
    Frozen = Berth#{state := consigned, bound_for := Destination, hop := Hop,
                    since := At, consigned_to => Ocean},
    {{ok, #{<<"ship">> => Ship,
            <<"hop">> => Hop,
            <<"bound_for">> => Destination,
            <<"consigned_to">> => Ocean,
            <<"at">> => At}},
     State#{ships := maps:put(Ship, Frozen, maps:get(ships, State))},
     [{record, {consigned_ship, Ship, Hop, Ocean, Destination, At}},
      {cry, tom_wire:fact(maps:get(realm, State), <<"custody">>,
                          <<"ship_consigned">>),
       #{<<"harbour">> => maps:get(harbour, State),
         <<"ship">> => Ship,
         <<"hop">> => Hop,
         <<"to">> => Ocean,
         <<"bound_for">> => Destination,
         <<"at">> => At}},
      {hand_over, Ship, Hop, Ocean, handover(State, Frozen)}]}.
