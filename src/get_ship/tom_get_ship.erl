%% @doc Where a hull is, as far as this port knows.
%%
%% THIS IS HOW A HOUSE THAT WAS SWITCHED OFF FINDS ITS SHIP. It asks the ocean
%% what became of the voyage, and if the answer is that landfall was made and
%% the destination has confirmed custody, it asks the destination this. Two
%% reads, each to the service that owns the answer, and no subscription it
%% needed to have been holding.
%%
%% not_here IS AN ANSWER AND NOT AN ERROR. A port that never had the hull and a
%% port that had it last week say the same thing, which is true: neither of them
%% has it. The house learns where it went from the ocean, which keeps its voyage
%% records forever.
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
    found(Ship, maps:get(Ship, maps:get(ships, State), undefined)).

found(Ship, undefined) ->
    {ok, #{<<"state">> => <<"not_here">>, <<"ship">> => Ship}};
found(_Ship, #{state := consigned} = Berth) ->
    {ok, #{<<"state">> => <<"consigned">>,
           <<"ship">> => maps:get(ship, Berth),
           <<"bound_for">> => maps:get(bound_for, Berth),
           <<"since">> => maps:get(since, Berth)}};
found(_Ship, #{state := moored} = Berth) ->
    {ok, #{<<"state">> => <<"moored">>,
           <<"ship">> => maps:get(ship, Berth),
           <<"since">> => maps:get(since, Berth)}}.
