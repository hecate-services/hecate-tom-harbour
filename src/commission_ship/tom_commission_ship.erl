%% @doc A house that has lost its ship takes up another hull here.
%%
%% A WRECK COSTS THE CARGO AND THE VOYAGE, NOT THE GAME. Ship building is out of
%% scope, so before this a loss was terminal: once she sank nothing could ever
%% happen again and the page sat there with a fully armed helm refusing every
%% press. A game that can only end in a dead stop leaves a player holding a
%% broken toy rather than a defeat.
%%
%% THE HULL IS FREE, AND THAT IS NOT GENEROSITY. There is nowhere to get a price
%% from. Price is always circumstantial, it comes out of a market or it does not
%% exist, and there is no market in hulls, so any figure written here would be
%% the one invented number in a game that has refused to invent them. The loss is
%% real without one: a full hold bought at Macao and lost off the Cape is a
%% serious sum, and the crossing is gone as well. When hulls have a market this
%% should cost money, and then the number comes from where every other number
%% comes from.
%%
%% ONE HULL PER HOUSE AT THIS QUAY, and that is the whole guard. This port cannot
%% know what a house holds at another port, so it refuses only what it can see:
%% it will not give a second hull to a house whose ship is already lying here.
%% Combined with a house that asks only when its own record says it has none,
%% that is enough for people who know each other, and it is stated rather than
%% pretended.
%%
%% ASKING TWICE IS SAFE. A house that asks again for a hull it already has back
%% gets the same answer, because a retry after a lost reply must not mint a
%% second ship.
%% @end
-module(tom_commission_ship).

-export([handle/1, at/3]).

%% @doc The mesh handler.
-spec handle(map()) -> {ok, map()}.
handle(Payload) -> tom_wire:answer(tom_port:commission(Payload)).

%% @doc The desk.
-spec at(tom_port:state(), map(), tom_port:now()) -> tom_port:outcome().
at(State, Payload, Now) ->
    asked(State,
          tom_wire:text(<<"house">>, Payload),
          tom_wire:text(<<"ship">>, Payload),
          tom_wire:number(<<"hold">>, Payload),
          Now).

%% Internal

asked(State, undefined, _Ship, _Hold, _Now) ->
    {{error, <<"bad_house">>}, State, []};
asked(State, _House, undefined, _Hold, _Now) ->
    {{error, <<"bad_ship">>}, State, []};
asked(State, House, Ship, Hold, Now) ->
    already(maps:get(Ship, maps:get(ships, State), undefined),
            State, House, Ship, tons(Hold), Now).

%% She is already here and she is theirs. Say so and mint nothing.
already(#{ship := Hull}, State, House, _Ship, _Hold, _Now) ->
    hers(tom_ship:owner(Hull) =:= House, State, Hull);
already(undefined, State, House, Ship, Hold, Now) ->
    spare(afloat_for(State, House), State, House, Ship, Hold, Now).

hers(true, State, Hull) ->
    {{ok, #{<<"state">> => <<"moored">>, <<"ship">> => Hull,
            <<"commissioned">> => false}}, State, []};
hers(false, State, _Hull) ->
    {{error, <<"name_taken">>}, State, []}.

%% A HOUSE WITH A HULL LYING HERE DOES NOT NEED ANOTHER. It is the only double
%% mint this port is in a position to refuse, and it refuses it.
spare(true, State, _House, _Ship, _Hold, _Now) ->
    {{error, <<"you_have_a_ship_here">>}, State, []};
spare(false, State, House, Ship, Hold, Now) ->
    launched(State, hull(House, Ship, Hold, maps:get(harbour, State)), Now).

launched(State, Hull, Now) ->
    {{ok, #{<<"state">> => <<"moored">>, <<"ship">> => Hull,
            <<"commissioned">> => true}},
     State,
     [{record, {took_ship, tom_ship:id(Hull), 0, Hull, <<"commissioned">>, Now}},
      {cry, tom_wire:fact(maps:get(realm, State), <<"custody">>,
                          <<"ship_moored">>),
       #{<<"harbour">> => maps:get(harbour, State),
         <<"ship">> => Hull,
         <<"from">> => <<"commissioned">>,
         <<"at">> => Now}}]}.

hull(House, Ship, Hold, Harbour) ->
    #{<<"ship">> => Ship, <<"owner">> => House, <<"hold">> => Hold,
      <<"cargo">> => #{}, <<"hop">> => 0, <<"custodian">> => Harbour}.

afloat_for(State, House) ->
    lists:any(fun(#{ship := Hull}) -> tom_ship:owner(Hull) =:= House end,
              maps:values(maps:get(ships, State))).

%% A hull with no capacity is not a ship, and a request that forgot to say gets
%% the same hold every hull in this game has rather than an argument about it.
tons(Hold) when is_number(Hold), Hold > 0 -> float(Hold);
tons(_Not_a_capacity)                     -> 200.0.
