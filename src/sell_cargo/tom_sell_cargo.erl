%% @doc Goods out of a hold this port has custody of, and onto its quay.
%%
%% THE OTHER HALF OF THE VOYAGE, and the mirror of buy_cargo in every respect:
%% one local act, one receipt, idempotent on the order, and no opinion about
%% anybody's purse. The purse only rises here, so there is nothing to quote
%% first and nothing a seller can be surprised by that costs him.
%%
%% not_in_hold RATHER THAN A PARTIAL SALE. A hull carrying thirty tons asked to
%% discharge forty is refused whole. The GODOWN still fills partially, because a
%% full godown is a fact about the town rather than a mistake by the seller, and
%% a seller who lands what fits and keeps the rest has lost nothing.
%% @end
-module(tom_sell_cargo).

-export([handle/1, at/3]).

%% @doc The mesh handler.
-spec handle(map()) -> {ok, map()}.
handle(Payload) -> tom_wire:answer(tom_port:sell(Payload)).

%% @doc The desk.
-spec at(tom_port:state(), map(), tom_port:now()) -> tom_port:outcome().
at(State, Payload, Now) ->
    settled(State, Payload, Now,
            maps:get(tom_wire:text(<<"order">>, Payload),
                     maps:get(receipts, State), undefined)).

%% Internal

settled(State, _Payload, _Now, Receipt) when is_map(Receipt) ->
    {{ok, Receipt}, State, []};
settled(State, Payload, Now, undefined) ->
    ordered(State, Payload, Now, tom_wire:text(<<"order">>, Payload)).

ordered(State, _Payload, _Now, undefined) ->
    {{error, <<"bad_order">>}, State, []};
ordered(State, Payload, Now, Order) ->
    berthed(State, Payload, Now, Order,
            maps:get(tom_wire:text(<<"ship">>, Payload),
                     maps:get(ships, State), undefined)).

berthed(State, _Payload, _Now, _Order, undefined) ->
    {{error, <<"not_here">>}, State, []};
berthed(State, _Payload, _Now, _Order, #{state := consigned}) ->
    {{error, <<"ship_consigned">>}, State, []};
berthed(State, Payload, Now, Order, #{ship := Hull}) ->
    owned(State, Payload, Now, Order, Hull,
          tom_ship:owner(Hull) =:= tom_wire:text(<<"by">>, Payload)).

owned(State, _Payload, _Now, _Order, _Hull, false) ->
    {{error, <<"not_yours">>}, State, []};
owned(State, Payload, Now, Order, Hull, true) ->
    named(State, Payload, Now, Order, Hull,
          tom_wire:text(<<"good">>, Payload)).

named(State, _Payload, _Now, _Order, _Hull, undefined) ->
    {{error, <<"unknown_good">>}, State, []};
named(State, Payload, Now, Order, Hull, Name) ->
    traded(State, Now, Order, Hull, Name,
           maps:get(Name, maps:get(goods, State), undefined),
           tom_wire:number(<<"quantity">>, Payload)).

traded(State, _Now, _Order, _Hull, _Name, undefined, _Quantity) ->
    {{error, <<"unknown_good">>}, State, []};
traded(State, _Now, _Order, _Hull, _Name, _Good, undefined) ->
    {{error, <<"bad_quantity">>}, State, []};
traded(State, Now, Order, Hull, Name, Good, Quantity) ->
    hauled(State, Now, Order, Hull, Name, Good, Quantity,
           Quantity =< tom_ship:aboard(Hull, Name)).

hauled(State, _Now, _Order, _Hull, _Name, _Good, _Quantity, false) ->
    {{error, <<"not_in_hold">>}, State, []};
hauled(State, #{tick := Tick} = Now, Order, Hull, Name, Good, Quantity, true) ->
    landed(State, Now, Order, Hull, Name,
           tom_market:land(maps:get(market, State), Good, Quantity, Tick),
           Good).

landed(State, _Now, _Order, _Hull, _Name, {error, Why}, _Good) ->
    {{error, atom_to_binary(Why, utf8)}, State, []};
landed(State, #{at := At}, Order, Hull, Name, {ok, Filled, Coin, Market},
       Good) ->
    Lighter = tom_ship:unload(Hull, Name, Filled),
    Receipt = #{<<"order">> => Order,
                <<"discharged">> => Filled,
                <<"coin">> => Coin,
                <<"price_after">> => tom_market:quote(Market, Good),
                <<"ship">> => Lighter,
                <<"at">> => At},
    {{ok, Receipt}, stocked(State, Market, Lighter, Order, Receipt),
     [{record, {settled_order, Order, Name, Receipt}},
      {cry, tom_wire:fact(maps:get(realm, State), <<"trade">>,
                          <<"cargo_discharged">>),
       announcement(State, Lighter, Name, Receipt)}]}.

stocked(State, Market, Lighter, Order, Receipt) ->
    Ship = tom_ship:id(Lighter),
    Berth = maps:get(Ship, maps:get(ships, State)),
    State#{market := Market,
           ships := maps:put(Ship, Berth#{ship := Lighter},
                             maps:get(ships, State)),
           receipts := maps:put(Order, Receipt, maps:get(receipts, State))}.

announcement(State, Lighter, Name, Receipt) ->
    #{<<"harbour">> => maps:get(harbour, State),
      <<"ship">> => tom_ship:id(Lighter),
      <<"owner">> => tom_ship:owner(Lighter),
      <<"good">> => Name,
      <<"quantity">> => maps:get(<<"discharged">>, Receipt),
      <<"coin">> => maps:get(<<"coin">>, Receipt),
      <<"price_after">> => maps:get(<<"price_after">>, Receipt),
      <<"order">> => maps:get(<<"order">>, Receipt),
      <<"at">> => maps:get(<<"at">>, Receipt)}.
