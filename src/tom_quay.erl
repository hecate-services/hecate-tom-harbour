%% @doc One good's stack on the quay: what is there, what it posts, what
%% happens when somebody takes some, and what an hour does to it.
%%
%% THE POSTED PRICE IS THE HEAP. A quay at its natural stock posts its natural
%% price. Strip it and the price rises, pile it up and the price falls, and
%% both ends of that are algebra rather than a clamp: the heap can never fall
%% below the reserve, so the price is finite, and it can never be pushed past
%% the godown, so the price has a floor. There is no clamp on a price anywhere
%% in this module and there must never be one, because a clamp is a number
%% somebody chose and this file is not allowed any.
%%
%% A TRADE PAYS THE PRICES IT MOVES THROUGH. The coin is the area under the
%% price curve between two heights of the heap, never the spot price times the
%% quantity. An order big enough to move the market pays for having moved it.
%% Charge spot instead and a large order is a subsidy, and the man who splits it
%% into a hundred small ones is the only one paying properly.
%%
%% THE FILL IS PARTIAL BY DEFAULT. The port fills what it can and says what it
%% filled. An error comes back only when the fill would be nothing at all. That
%% is what keeps every good buying and selling here while the godown still has
%% a roof on it.
%%
%% LEFT ALONE THE HEAP COMES BACK. Arrivals rise when the price is high and
%% offtake falls, so a stripped quay refills and a full one drains, and both
%% stop at the crossing. Both sides read THIS tick's price, so there is no lag
%% and nothing to ring: the settling condition is the single one on the
%% constants that tom_crossing:settling_rate/1 reports, and it is checked once
%% when a market opens.
%% @end
-module(tom_quay).

-export([open/1,
         re_cross/2,
         crossing/1,
         stock/1,
         at_rest/1,
         posted_price/2,
         price_band/2,
         advance/3,
         lift/3,
         land/3,
         depth/3]).

-export_type([quay/0, fill/0, reach/0]).

%% @doc One good's stack. The crossing is its structure and changes rarely, the
%% stock is its state and changes constantly.
-type quay() :: #{crossing := tom_crossing:crossing(),
                  stock := float(),
                  at_rest := boolean()}.

%% @doc What filled, what it cost or fetched, and the quay afterwards.
-type fill() :: {ok, Filled :: float(), Coin :: float(), quay()}.

%% @doc What it would take to walk the price to somewhere else.
-type reach() :: {lift, float(), float()}
               | {land, float(), float()}
               | {error, out_of_band}.

%% A quay is at rest when the stock is the natural stock. Nothing but rounding
%% is allowed inside this, and rounding is all that ever is.
-define(STILL, 1.0e-12).

%% @doc A quay opened at its natural stock, which is where it would have settled
%% anyway had it been standing there all along.
-spec open(tom_crossing:crossing()) -> quay().
open(Crossing) ->
    #{crossing => Crossing,
      stock => maps:get(natural_stock, Crossing),
      at_rest => true}.

%% @doc Swap in a new crossing, keeping the goods that are actually on the quay.
%%
%% THE ONLY WAY TO CHANGE A QUAY'S STRUCTURE, on purpose. A crossing rewritten
%% without settling first retroactively rewrites every tick since the last
%% stamp, and that error is silent, plausible and unrecoverable. The facade is
%% what enforces the ordering; this is what makes the ordering enforceable.
-spec re_cross(quay(), tom_crossing:crossing()) -> quay().
re_cross(Quay, Crossing) ->
    Stock = maps:get(stock, Quay),
    #{crossing => Crossing,
      stock => Stock,
      at_rest => still(Stock, maps:get(natural_stock, Crossing))}.

%% @doc This quay's crossing.
-spec crossing(quay()) -> tom_crossing:crossing().
crossing(Quay) -> maps:get(crossing, Quay).

%% @doc What is on the quay.
-spec stock(quay()) -> float().
stock(Quay) -> maps:get(stock, Quay).

%% @doc Whether a tick would do anything at all.
-spec at_rest(quay()) -> boolean().
at_rest(Quay) -> maps:get(at_rest, Quay).

%% @doc What the good goes for right now.
-spec posted_price(tom_crossing:config(), quay()) -> float().
posted_price(Config, #{crossing := Crossing, stock := Stock}) ->
    maps:get(natural_price, Crossing)
        * math:pow(maps:get(anchor, Crossing)
                   / (Stock + maps:get(reserve, Crossing)),
                   maps:get(stock_sensitivity, Config)).

%% @doc The lowest and highest this good can be driven to here.
-spec price_band(tom_crossing:config(), quay()) -> {float(), float()}.
price_band(Config, Quay) ->
    {Floor, Ceiling} = tom_crossing:band_factors(Config),
    Pbar = maps:get(natural_price, crossing(Quay)),
    {Pbar * Floor, Pbar * Ceiling}.

%% @doc Let N ticks happen.
%%
%% Lazy, because a port with sixty seven goods should not do sixty seven goods
%% of arithmetic because somebody looked at it. An idle quay costs nothing, and
%% one idle past the settling horizon costs one comparison, because the natural
%% stock is a fixed point and landing on it is exact.
-spec advance(tom_crossing:config(), quay(), non_neg_integer()) -> quay().
advance(_Config, Quay, 0) ->
    Quay;
advance(_Config, #{at_rest := true} = Quay, _N) ->
    Quay;
advance(Config, Quay, N) when is_integer(N), N > 0 ->
    settled(Config, Quay, N, N >= tom_crossing:settling_horizon(Config)).

%% @doc Take goods off the quay. The price rises as they go.
-spec lift(tom_crossing:config(), quay(), number()) ->
          fill() | {error, quay_empty}.
lift(Config, Quay, Requested) ->
    lifted(Config, Quay, room(Requested * 1.0, maps:get(stock, Quay))).

%% @doc Put goods on the quay. The price falls as they land.
-spec land(tom_crossing:config(), quay(), number()) ->
          fill() | {error, godown_full}.
land(Config, Quay, Requested) ->
    Crossing = crossing(Quay),
    Space = maps:get(capacity, Crossing) - maps:get(stock, Quay),
    landed(Config, Quay, room(Requested * 1.0, Space)).

%% @doc What it would take to walk the price to a given number.
%%
%% The single most useful thing to tell a trader, because it is the market's
%% resistance stated as a quantity and a purse rather than as a shape. Inverting
%% the posted price and integrating gives, with the shipped constants,
%%
%%   doubling a price costs one natural stock's worth at the natural price
%%
%% which a seventeenth century factor could hold in his head, and which no
%% invariant-product market can say at all.
-spec depth(tom_crossing:config(), quay(), float()) -> reach().
depth(Config, Quay, ToPrice) ->
    {Floor, Ceiling} = price_band(Config, Quay),
    in_band(Config, Quay, ToPrice, ToPrice >= Floor andalso ToPrice =< Ceiling).

%% Internal

still(Stock, Natural) -> abs(Stock - Natural) < ?STILL * Natural.

settled(_Config, Quay, _N, true) ->
    Quay#{stock := maps:get(natural_stock, crossing(Quay)), at_rest := true};
settled(Config, Quay, N, false) ->
    rested(cranked(Config, Quay, N)).

cranked(_Config, Quay, 0) -> Quay;
cranked(Config, Quay, N) -> cranked(Config, ticked(Config, Quay), N - 1).

%% One tick. No upper clamp: the godown governs landing, and a restructure can
%% leave more on the quay than the godown holds, in which case the tick must
%% drain it rather than delete it. The lower guard is belt and braces, since
%% near empty the arrivals run at twice the throughput against an offtake of a
%% twelfth of it and the heap climbs away from nothing on its own.
ticked(Config, Quay) ->
    Crossing = crossing(Quay),
    Price = posted_price(Config, Quay),
    Quay#{stock := max(0.0, maps:get(stock, Quay)
                       + arrivals(Config, Crossing, Price)
                       - offtake(Config, Crossing, Price))}.

arrivals(Config, Crossing, Price) ->
    maps:get(supply, Crossing)
        * math:pow(Price, maps:get(supply_elasticity, Config))
        + maps:get(inelastic_supply, Crossing).

offtake(Config, Crossing, Price) ->
    maps:get(demand, Crossing)
        * math:pow(Price, -maps:get(demand_elasticity, Config))
        + maps:get(inelastic_demand, Crossing).

rested(Quay) ->
    Quay#{at_rest := still(maps:get(stock, Quay),
                           maps:get(natural_stock, crossing(Quay)))}.

room(Requested, Available) -> max(0.0, min(Requested, Available)).

lifted(_Config, _Quay, Quantity) when Quantity =< 0.0 ->
    {error, quay_empty};
lifted(Config, Quay, Quantity) ->
    Crossing = crossing(Quay),
    Stock = maps:get(stock, Quay),
    High = Stock + maps:get(reserve, Crossing),
    Gross = integral(Config, Crossing, High - Quantity, High),
    {ok, Quantity, Gross * (1.0 + maps:get(harbour_fee, Config)),
     stirred(Quay, Stock - Quantity)}.

landed(_Config, _Quay, Quantity) when Quantity =< 0.0 ->
    {error, godown_full};
landed(Config, Quay, Quantity) ->
    Crossing = crossing(Quay),
    Stock = maps:get(stock, Quay),
    Low = Stock + maps:get(reserve, Crossing),
    Gross = integral(Config, Crossing, Low, Low + Quantity),
    {ok, Quantity, Gross * (1.0 - maps:get(harbour_fee, Config)),
     stirred(Quay, Stock + Quantity)}.

%% The fee is what closes the round trip. Without it a lift followed at once by
%% a land is EXACTLY break even, because the integral is path independent, and
%% a market you can walk in and out of for nothing is a machine for turning
%% patience into money.
stirred(Quay, Stock) -> Quay#{stock := Stock, at_rest := false}.

integral(Config, Crossing, Low, High) ->
    Exponent = 1.0 - maps:get(stock_sensitivity, Config),
    maps:get(integral_scale, Crossing)
        * (math:pow(High, Exponent) - math:pow(Low, Exponent)).

in_band(_Config, _Quay, _ToPrice, false) ->
    {error, out_of_band};
in_band(Config, Quay, ToPrice, true) ->
    Now = posted_price(Config, Quay),
    toward(Config, Quay, Now, ToPrice, direction(ToPrice, Now)).

direction(To, Now) when To > Now -> up;
direction(To, Now) when To < Now -> down;
direction(_To, _Now) -> level.

toward(Config, Quay, Now, To, up) ->
    Crossing = crossing(Quay),
    {lift, heap_at(Config, Crossing, Now) - heap_at(Config, Crossing, To),
     coin_between(Config, Crossing, Now, To)
     * (1.0 + maps:get(harbour_fee, Config))};
toward(Config, Quay, Now, To, down) ->
    Crossing = crossing(Quay),
    {land, heap_at(Config, Crossing, To) - heap_at(Config, Crossing, Now),
     coin_between(Config, Crossing, To, Now)
     * (1.0 - maps:get(harbour_fee, Config))};
toward(_Config, _Quay, _Now, _To, level) ->
    {lift, 0.0, 0.0}.

%% The posted price read backwards: what the heap must stand at for the good to
%% go for that.
heap_at(Config, Crossing, Price) ->
    maps:get(anchor, Crossing)
        * math:pow(maps:get(natural_price, Crossing) / Price,
                   1.0 / maps:get(stock_sensitivity, Config)).

coin_between(Config, Crossing, Low, High) ->
    integral(Config, Crossing,
             heap_at(Config, Crossing, High), heap_at(Config, Crossing, Low)).
