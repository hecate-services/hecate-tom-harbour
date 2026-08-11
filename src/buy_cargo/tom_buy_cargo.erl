%% @doc Goods off this quay and into a hold this port already has custody of.
%%
%% THERE IS NO WAREHOUSE. You buy INTO a hull. The goods go from the quay
%% straight into the named ship, which is tied up here, in one local act inside
%% one process. That is what makes the whole of "buy in port A" a single
%% transaction with no shared library and no two-phase commit: the only thing
%% that crosses the wire afterwards is a receipt, and the only thing the house
%% does with it is move its own number.
%%
%% IDEMPOTENT ON THE ORDER, AND THE REPLAY COMES FIRST. Before the ship is
%% looked for, before the good is resolved, before anything: if this order has
%% been settled, the stored receipt is handed back verbatim. A repeat must be
%% answerable after the hull has sailed, because the house that is repeating it
%% is a house that died before it heard the first answer.
%%
%% THE PURSE IS NOT CHECKED HERE AND NEVER WILL BE. This port does not own it.
%% The house asks quote_purchase, decides against its own coin, and commits. A
%% harbour that held an opinion about somebody else's money would need to be
%% told about it, and then there would be two copies of the one number in the
%% game that has to be right.
%%
%% not_yours IS A CHECK AGAINST A MISTAKE, NOT AN ATTACKER. It is unsigned. Two
%% people who know each other are playing, and the value of the check is that a
%% fat-fingered ship name is refused instead of loading somebody else's hull.
%% @end
-module(tom_buy_cargo).

-export([handle/1, at/3]).

%% @doc The mesh handler.
-spec handle(map()) -> {ok, map()}.
handle(Payload) -> tom_wire:answer(tom_port:buy(Payload)).

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
berthed(State, Payload, Now, Order, #{state := consigned}) ->
    consigned(State, Payload, Now, Order);
berthed(State, Payload, Now, Order, #{ship := Hull}) ->
    owned(State, Payload, Now, Order, Hull,
          tom_ship:owner(Hull) =:= tom_wire:text(<<"by">>, Payload)).

%% A frozen hull is answered ship_consigned rather than not_yours, so a house
%% that raced its own sail order learns which of the two happened.
consigned(State, _Payload, _Now, _Order) ->
    {{error, <<"ship_consigned">>}, State, []}.

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
    stowed(State, Now, Order, Hull, Name, Good, Quantity,
           Quantity =< tom_ship:free(Hull)).

%% THE HOLD IS CHECKED BEFORE THE QUAY. A hull with forty tons of room asked to
%% take eighty is refused whole rather than filled halfway, because the contract
%% says hold_full and because a half-filled order is a second thing for a house
%% to reconcile. The QUAY still fills partially, since a thin quay is a fact
%% about the market rather than a mistake by the buyer.
stowed(State, _Now, _Order, _Hull, _Name, _Good, _Quantity, false) ->
    {{error, <<"hold_full">>}, State, []};
stowed(State, #{tick := Tick} = Now, Order, Hull, Name, Good, Quantity, true) ->
    loaded(State, Now, Order, Hull, Name,
           tom_market:lift(maps:get(market, State), Good, Quantity, Tick),
           Good).

loaded(State, _Now, _Order, _Hull, _Name, {error, Why}, _Good) ->
    {{error, atom_to_binary(Why, utf8)}, State, []};
loaded(State, #{at := At}, Order, Hull, Name, {ok, Filled, Coin, Market},
       Good) ->
    Laden = tom_ship:load(Hull, Name, Filled),
    Receipt = #{<<"order">> => Order,
                <<"filled">> => Filled,
                <<"coin">> => Coin,
                <<"price_after">> => tom_market:quote(Market, Good),
                <<"ship">> => Laden,
                <<"at">> => At},
    {{ok, Receipt}, stocked(State, Market, Laden, Order, Name, Receipt),
     [{record, {settled_order, Order, Name, Receipt}},
      {cry, tom_wire:fact(maps:get(realm, State), <<"trade">>,
                          <<"cargo_loaded">>),
       announcement(State, Laden, Name, Receipt)}]}.

stocked(State, Market, Laden, Order, _Name, Receipt) ->
    Ship = tom_ship:id(Laden),
    Berth = maps:get(Ship, maps:get(ships, State)),
    State#{market := Market,
           ships := maps:put(Ship, Berth#{ship := Laden},
                             maps:get(ships, State)),
           receipts := maps:put(Order, Receipt, maps:get(receipts, State))}.

%% THE FACT IS NAMED FOR WHAT HAPPENED TO THE SHIP, not for what happened to the
%% quay. This port's own vocabulary calls it a lift, because that is what the
%% heap did; an outsider watching a voyage cares that a hold got fuller. The two
%% vocabularies are free to diverge and this is where they do.
announcement(State, Laden, Name, Receipt) ->
    #{<<"harbour">> => maps:get(harbour, State),
      <<"ship">> => tom_ship:id(Laden),
      <<"owner">> => tom_ship:owner(Laden),
      <<"good">> => Name,
      <<"quantity">> => maps:get(<<"filled">>, Receipt),
      <<"coin">> => maps:get(<<"coin">>, Receipt),
      <<"price_after">> => maps:get(<<"price_after">>, Receipt),
      <<"order">> => maps:get(<<"order">>, Receipt),
      <<"at">> => maps:get(<<"at">>, Receipt)}.
