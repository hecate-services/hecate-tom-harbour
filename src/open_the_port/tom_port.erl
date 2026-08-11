%% @doc THE PORT. One process, one market, one clock, and every hull tied up at
%% the quay.
%%
%% EVERYTHING AT THIS HARBOUR SERIALISES THROUGH HERE, and that single fact is
%% what buys three of the contract's promises for nothing. Within a tick,
%% arrival order, because there is one queue. A trade is atomic, because a lift
%% off the quay and a load into a hold are two lines of one function with no
%% lock between them and nothing else running. And a handover commits exactly
%% once, because the disk write and the state change are the same message.
%%
%% THE DESKS ARE PURE AND THIS IS NOT. Each desk is a function from the port's
%% state and one payload to a reply, a new state and a list of things that must
%% happen in the world. This process is the only thing in the service holding a
%% pid, a disk or a socket, so a desk can be tested by calling it, and the order
%% of the effects is decided in ONE place: written down first, said out loud
%% second, and only then answered.
%%
%% A TICK IS NOT A CLOCK, but this is where a clock becomes one. The market
%% takes the tick each call happens at, and the tick is the instant divided by
%% the length of a tick, so it survives a restart and does not depend on how
%% long this process has been up. A clock that goes backwards STOPS the market
%% rather than rewinding it, which is the guard tom_market:settle demands and
%% the only sane reading of an NTP correction.
%%
%% WHAT SURVIVES A RESTART AND WHAT DOES NOT. Custody and receipts survive,
%% because those are what exactly-once is about, and they come back off the
%% ledger. The heaps on the quays come back by replaying the settled orders into
%% a market opened from the standing, at the ticks the orders happened at. A
%% port that has never traded therefore boots at rest, which is where it would
%% have been anyway.
%% @end
-module(tom_port).

-behaviour(gen_server).

-export([start_link/0,
         quotes/1,
         purchase/1,
         buy/1,
         sell/1,
         sail/1,
         take/1,
         berth/1,
         commission/1,
         handed/2,
         harbour/0,
         market/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-export_type([state/0, berth/0, moored/0, consigned/0, now/0, effect/0,
              outcome/0]).

%% @doc Everything this port is.
-type state() :: #{harbour := binary(),
                   ocean := binary(),
                   realm := binary(),
                   market := tom_market:market(),
                   goods := #{binary() => tom_crossing:good_id()},
                   names := #{tom_crossing:good_id() => binary()},
                   tick_ms := pos_integer(),
                   ships := #{binary() => berth()},
                   receipts := #{binary() => map()},
                   taken := #{binary() => integer()},
                   log := tom_ledger:log()}.

%% @doc One hull as this port holds it. The ship map is the hull itself; the
%% rest is what this port is doing about it.
%%
%% TWO SHAPES AND NOT ONE, because a consigned berth carries a promise a moored
%% one has not made. Writing it as one shape with an optional field would let
%% every reader of a moored berth ask who it was promised to and get nothing
%% back, which is the question the freeze exists to make unaskable.
-type berth() :: moored() | consigned().

%% @doc A hull tied up here and free to be traded out of.
-type moored() :: #{ship := tom_ship:ship(),
                    state := moored,
                    bound_for := undefined,
                    hop := integer(),
                    since := integer()}.

%% @doc A hull this port has promised away and frozen. Custody has NOT moved:
%% this port is still the custodian, at the hop the hull is still standing at,
%% and it owes the receiver a call until it gets an answer.
-type consigned() :: #{ship := tom_ship:ship(),
                       state := consigned,
                       bound_for := binary(),
                       hop := integer(),
                       since := integer(),
                       consigned_to := binary()}.

%% @doc When a desk is being asked. The tick is this port's private clock and
%% never leaves; the instant is what goes on the wire.
-type now() :: #{tick := integer(), at := integer()}.

%% @doc What a desk needs the world to do. Written down, then said out loud,
%% then acted on, in that order and never another.
-type effect() :: {record, tom_ledger:entry()}
                | {cry, binary(), map()}
                | {hand_over, binary(), integer(), binary(), map()}.

%% @doc What every desk answers: the reply, the port afterwards, and the effects.
-type outcome() :: {{ok, map()} | {error, binary()}, state(), [effect()]}.

%% How often the clock is wound on with nobody asking. The market is lazy, so
%% this costs nothing while the port is idle; what it buys is a port whose
%% quoted prices are the prices of NOW rather than the prices of the last time
%% somebody happened to call.
-define(WIND_MS, 1000).

%% Every read a desk does is against state this process already holds, so a read
%% is a memory lookup and this timeout is about the queue rather than the work.
-define(DESK_MS, 5000).

%% @doc Open the port.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc What the goods on this quay go for.
-spec quotes(map()) -> {ok, map()} | {error, binary()}.
quotes(Payload) -> ask({list_quotes, Payload}).

%% @doc What an order would cost, without moving anything.
-spec purchase(map()) -> {ok, map()} | {error, binary()}.
purchase(Payload) -> ask({quote_purchase, Payload}).

%% @doc Lift goods off the quay and into a hold, in one act.
-spec buy(map()) -> {ok, map()} | {error, binary()}.
buy(Payload) -> ask({buy_cargo, Payload}).

%% @doc Take goods out of a hold and land them on the quay, in one act.
-spec sell(map()) -> {ok, map()} | {error, binary()}.
sell(Payload) -> ask({sell_cargo, Payload}).

%% @doc Promise a hull to the ocean and freeze it.
-spec sail(map()) -> {ok, map()} | {error, binary()}.
sail(Payload) -> ask({sail_ship, Payload}).

%% @doc Take custody of a hull somebody is handing over.
-spec take(map()) -> {ok, map()} | {error, binary()}.
take(Payload) -> ask({receive_ship, Payload}).

%% @doc Where a hull is, as far as this port knows.
-spec berth(map()) -> {ok, map()} | {error, binary()}.
berth(Payload) -> ask({get_ship, Payload}).

%% @doc A house that has lost its ship takes up another hull here.
-spec commission(map()) -> {ok, map()} | {error, binary()}.
commission(Payload) -> ask({commission_ship, Payload}).

%% @doc The receiver said held. Let the hull go.
-spec handed(binary(), integer()) -> ok.
handed(Ship, Hop) -> gen_server:cast(?MODULE, {handed, Ship, Hop}).

%% @doc This port's own name, for whoever needs to say it.
-spec harbour() -> binary().
harbour() -> gen_server:call(?MODULE, harbour, ?DESK_MS).

%% @doc The market as it stands. For the health probe and for a shell.
-spec market() -> tom_market:market().
market() -> gen_server:call(?MODULE, market, ?DESK_MS).

%% gen_server

init([]) ->
    Realm = tom_standing:realm(),
    Harbour = tom_standing:harbour(),
    {ok, Standing} = tom_standing:standing(),
    {ok, Market} = tom_market:open(Standing),
    {ok, Log} = tom_ledger:open(tom_standing:data_dir(), Harbour),
    {Goods, Names} = tom_standing:goods_index(Realm, Standing),
    Fresh = #{harbour => Harbour,
              ocean => tom_standing:ocean(),
              realm => Realm,
              market => Market,
              goods => Goods,
              names => Names,
              tick_ms => tom_standing:tick_ms(),
              ships => #{},
              receipts => #{},
              taken => #{},
              log => Log},
    erlang:send_after(?WIND_MS, self(), wind),
    self() ! resume,
    {ok, wound(seeded(tom_ledger:fold(Log, fun remembered/2, Fresh)))}.

handle_call({Desk, Payload}, _From, State) ->
    answered(desk(Desk, wound(State), Payload));
handle_call(harbour, _From, State) ->
    {reply, maps:get(harbour, State), State};
handle_call(market, _From, State) ->
    {reply, maps:get(market, State), State};
handle_call(_Other, _From, State) ->
    {reply, {error, <<"unknown_call">>}, State}.

%% RULE FIVE: THE CONSIGNER DROPS THE SHIP ONLY AFTER held, and then it writes
%% its own terminal record and forgets. Both halves are here, in that order.
handle_cast({handed, Ship, Hop}, State) ->
    {noreply, released(State, Ship, Hop, maps:get(ships, State))};
handle_cast(_Other, State) ->
    {noreply, State}.

handle_info(wind, State) ->
    erlang:send_after(?WIND_MS, self(), wind),
    {noreply, wound(State)};
%% Sent to self at boot rather than done in init, because starting a hand-over
%% asks a sibling supervisor to start a child and a supervisor's own start-up is
%% not a good moment to be asking it for anything.
handle_info(resume, State) ->
    [resumed(State, Berth) || Berth <- maps:values(maps:get(ships, State)),
                              is_map_key(consigned_to, Berth)],
    {noreply, State};
handle_info(_Other, State) ->
    {noreply, State}.

terminate(_Reason, State) -> tom_ledger:close(maps:get(log, State)).

%% The desks

desk(list_quotes, State, Payload) -> tom_list_quotes:at(State, Payload, now_at(State));
desk(quote_purchase, State, Payload) -> tom_quote_purchase:at(State, Payload, now_at(State));
desk(buy_cargo, State, Payload) -> tom_buy_cargo:at(State, Payload, now_at(State));
desk(sell_cargo, State, Payload) -> tom_sell_cargo:at(State, Payload, now_at(State));
desk(sail_ship, State, Payload) -> tom_sail_ship:at(State, Payload, now_at(State));
desk(receive_ship, State, Payload) -> tom_receive_ship:at(State, Payload, now_at(State));
desk(get_ship, State, Payload) -> tom_get_ship:at(State, Payload, now_at(State));
desk(commission_ship, State, Payload) ->
    tom_commission_ship:at(State, Payload, now_at(State)).

%% THE ORDER OF THESE THREE IS THE CONTRACT. On the disk, then on the mesh, then
%% in the answer. A reply that outran its own record is a promise this port
%% cannot keep after a power cut.
answered({Reply, State, Effects}) ->
    {reply, Reply, lists:foldl(fun apply_effect/2, State, Effects)}.

apply_effect({record, Entry}, State) ->
    ok = tom_ledger:record(maps:get(log, State), Entry),
    State;
apply_effect({cry, Topic, Payload}, State) ->
    ok = tom_crier:cry(Topic, Payload),
    State;
apply_effect({hand_over, Ship, Hop, To, Payload}, State) ->
    _ = tom_hand_over_ship_sup:start_handing(Ship, Hop, To, Payload),
    State.

%% The clock

now_at(State) ->
    At = tom_wire:now_ms(),
    #{tick => tick_of(State, At), at => At}.

%% A CLOCK GOING BACKWARDS STOPS THE MARKET, it does not rewind it. tom_market
%% refuses a tick earlier than the one it stands at, and it is right to: a
%% market that quietly accepted one would produce plausible prices for the rest
%% of the game. An NTP correction is not a reason to reprice a port.
tick_of(#{market := Market, tick_ms := Ms}, At) -> max(tom_market:tick(Market), At div Ms).

wound(State) -> settled(State, now_at(State)).

settled(#{market := Market} = State, #{tick := Tick}) ->
    State#{market := tom_market:settle(Market, Tick)}.

%% Boot

%% THE FOLD IS THE WHOLE OF WHAT THIS PORT REMEMBERS. Oldest first, so a hull
%% taken, given away and taken back again ends where it ended.
remembered({took_ship, Ship, Hop, Hull, _From, At}, State) ->
    moored(highest(State, Ship, Hop), Ship, Hull, Hop, At);
remembered({consigned_ship, Ship, Hop, To, BoundFor, At}, State) ->
    frozen(State, Ship, Hop, To, BoundFor, At);
remembered({handed_ship, Ship, _Hop, _To, _At}, State) ->
    State#{ships := maps:remove(Ship, maps:get(ships, State))};
remembered({settled_order, Order, Good, Reply}, State) ->
    replayed(State#{receipts := maps:put(Order, Reply,
                                         maps:get(receipts, State))},
             Good, Reply).

moored(State, Ship, Hull, Hop, At) ->
    State#{ships := maps:put(Ship, #{ship => Hull, state => moored,
                                     bound_for => undefined, hop => Hop,
                                     since => At},
                             maps:get(ships, State))}.

frozen(State, Ship, Hop, To, BoundFor, At) ->
    Berth = maps:get(Ship, maps:get(ships, State)),
    State#{ships := maps:put(Ship, Berth#{state := consigned,
                                          bound_for := BoundFor,
                                          hop := Hop,
                                          since := At,
                                          consigned_to => To},
                             maps:get(ships, State))}.

%% RULE FOUR: the answer to a handover is permanent, so what is kept is the
%% HIGHEST hop this port ever took, and a repeat at that hop or below is held.
highest(State, Ship, Hop) ->
    Taken = maps:get(taken, State),
    State#{taken := maps:put(Ship, max(Hop, maps:get(Ship, Taken, -1)), Taken)}.

%% A settled order carries the hull as it was afterwards, so the fold restores
%% the cargo from the same record that restores the receipt, and the quay is
%% put back by replaying the trade into the market at the tick it happened.
replayed(State, Good, Reply) ->
    quayed(shipped(State, maps:get(<<"ship">>, Reply, undefined)), Good, Reply).

shipped(State, undefined) ->
    State;
shipped(State, Hull) ->
    reberthed(State, maps:get(tom_ship:id(Hull), maps:get(ships, State),
                              undefined), Hull).

reberthed(State, undefined, _Hull) ->
    State;
reberthed(State, Berth, Hull) ->
    State#{ships := maps:put(tom_ship:id(Hull), Berth#{ship := Hull},
                             maps:get(ships, State))}.

quayed(State, Good, #{<<"at">> := At} = Reply) ->
    moved(State, maps:get(Good, maps:get(goods, State), undefined),
          filled(Reply), tick_of(State, At)).

filled(#{<<"filled">> := Quantity}) -> {lift, Quantity};
filled(#{<<"discharged">> := Quantity}) -> {land, Quantity}.

moved(State, undefined, _What, _Tick) ->
    State;
moved(State, Good, {lift, Quantity}, Tick) ->
    restocked(State, tom_market:lift(maps:get(market, State), Good, Quantity,
                                     Tick));
moved(State, Good, {land, Quantity}, Tick) ->
    restocked(State, tom_market:land(maps:get(market, State), Good, Quantity,
                                     Tick)).

%% A replay that no longer fits the quay is not worth crashing the port for: the
%% coin was paid at the time and the receipt is what a house will read back. The
%% heap is a best effort and says so.
restocked(State, {ok, _Filled, _Coin, Market}) -> State#{market := Market};
restocked(State, {error, _Why}) -> State.

%% GENESIS IS APPLIED ONLY TO A HULL THIS PORT HAS NEVER HEARD OF. A port that
%% re-seeded on every boot would mint a second Santa Clara an hour after the
%% first one sailed, which is the classic way to break exactly-once with a
%% configuration file.
seeded(State) ->
    lists:foldl(fun launch/2, State,
                [Hull || Hull <- tom_standing:ships(),
                         not maps:is_key(tom_ship:id(Hull),
                                         maps:get(taken, State))]).

launch(Hull, State) ->
    At = tom_wire:now_ms(),
    Berthed = Hull#{<<"hop">> => 0, <<"custodian">> => maps:get(harbour, State)},
    ok = tom_ledger:record(maps:get(log, State),
                           {took_ship, tom_ship:id(Hull), 0, Berthed,
                            <<"genesis">>, At}),
    ok = tom_crier:cry(tom_wire:fact(maps:get(realm, State), <<"custody">>,
                                     <<"ship_moored">>),
                       #{<<"harbour">> => maps:get(harbour, State),
                         <<"ship">> => Berthed,
                         <<"from">> => <<"genesis">>,
                         <<"at">> => At}),
    moored(highest(State, tom_ship:id(Hull), 0), tom_ship:id(Hull), Berthed, 0,
           At).

%% Letting go

resumed(State, Berth) ->
    tom_hand_over_ship_sup:start_handing(
      tom_ship:id(maps:get(ship, Berth)), maps:get(hop, Berth),
      maps:get(consigned_to, Berth),
      tom_sail_ship:handover(State, Berth)).

released(State, Ship, Hop, Ships) ->
    let_go(State, Ship, Hop, maps:get(Ship, Ships, undefined)).

let_go(State, _Ship, _Hop, undefined) ->
    State;
let_go(State, Ship, Hop, Berth) ->
    ok = tom_ledger:record(maps:get(log, State),
                           {handed_ship, Ship, Hop,
                            maps:get(consigned_to, Berth), tom_wire:now_ms()}),
    State#{ships := maps:remove(Ship, maps:get(ships, State))}.

%% THE ONE PLACE A PAYLOAD COMES IN FROM THE MESH. All seven desks are reached
%% through here, so this is where a payload is put back into the shape the desks
%% read: binary keys, whatever the codec did to them on the way. See
%% tom_wire:accept/1 for what the codec does and why it is not the same twice.
ask({Desk, Payload}) ->
    gen_server:call(?MODULE, {Desk, tom_wire:accept(Payload)}, ?DESK_MS).
