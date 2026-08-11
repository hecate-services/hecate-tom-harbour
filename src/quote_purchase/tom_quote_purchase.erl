%% @doc What an order would cost, without moving anything.
%%
%% THIS DESK EXISTS BECAUSE A TRADE PAYS THE PRICES IT WALKED THROUGH. The coin
%% is the area under the price curve between two heights of the heap, never the
%% posted price times the quantity, so a house CANNOT work out what an order
%% will cost from a quote and a multiplication. Lifting five musk off a resting
%% Macao costs 14.65 apiece against a posted 12.92, because it walked the price
%% to 16.18 on the way. Without this call a player commits a purse to a number
%% nobody has told him.
%%
%% THERE IS DELIBERATELY NO QUOTE FOR A SALE. A sale can only increase a purse,
%% so there is nothing to protect a player from and nothing he could be surprised
%% by that costs him anything.
%%
%% IT MOVES NOTHING. The lift runs against a copy of the market which is then
%% thrown away, so asking does not walk the price for the man behind you.
%% @end
-module(tom_quote_purchase).

-export([handle/1, at/3]).

%% @doc The mesh handler.
-spec handle(map()) -> {ok, map()}.
handle(Payload) -> tom_wire:answer(tom_port:purchase(Payload)).

%% @doc The desk.
-spec at(tom_port:state(), map(), tom_port:now()) -> tom_port:outcome().
at(State, Payload, Now) ->
    priced(State, Now, tom_wire:text(<<"good">>, Payload),
           tom_wire:number(<<"quantity">>, Payload)).

%% Internal

priced(State, _Now, undefined, _Quantity) ->
    {{error, <<"unknown_good">>}, State, []};
priced(State, _Now, _Name, undefined) ->
    {{error, <<"bad_quantity">>}, State, []};
priced(State, Now, Name, Quantity) ->
    known(State, Now, Name, Quantity,
          maps:get(Name, maps:get(goods, State), undefined)).

known(State, _Now, _Name, _Quantity, undefined) ->
    {{error, <<"unknown_good">>}, State, []};
known(State, #{tick := Tick, at := At}, Name, Quantity, Good) ->
    walked(State, Name, At,
           tom_market:lift(maps:get(market, State), Good, Quantity, Tick),
           Good).

%% The market that comes back is the one this order WOULD have left behind, and
%% it is used for the price after and then dropped on the floor.
walked(State, Name, At, {ok, Filled, Coin, Would}, Good) ->
    {{ok, #{<<"good">> => Name,
            <<"quantity">> => Filled,
            <<"coin">> => Coin,
            <<"price_after">> => tom_market:quote(Would, Good),
            <<"at">> => At}},
     State, []};
walked(State, _Name, _At, {error, Why}, _Good) ->
    {{error, atom_to_binary(Why, utf8)}, State, []}.
