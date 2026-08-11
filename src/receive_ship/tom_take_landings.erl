%% @doc A port that finds out for itself which ships have landed here.
%%
%% ARRIVAL IS A STATEMENT AND NOT A TRANSACTION. A harbour is infrastructure and
%% has no say in whether a ship turns up: she is this port's from the instant the
%% sea says so, whether or not this port has heard yet. So nobody knocks here any
%% more. The sea writes its landfall, announces it and lets go, and this process
%% is how the announcement becomes a hull at the quay.
%%
%% IT LISTENS AND IT ASKS, AND BOTH END AT THE SAME DESK. `tom_receive_ship:at/3'
%% is entered from exactly one place, the walk below, so the path a ship takes
%% into this port on an ordinary Tuesday is the same path she takes after this
%% container was down for a week. A recovery path that only runs after an outage
%% is a broken recovery path nobody notices.
%%
%% THE FACT IS A NUDGE AND NEVER A DELIVERY. `landfall_made_v1' carries the ship
%% as a bare identifier, not as a hull, and hearing one does exactly one thing:
%% it makes this port do its catch-up ask NOW rather than at the next tick. Three
%% reasons, in order of weight. There is then one take path and it runs on every
%% arrival. Cargo manifests stay off a broadcast topic, which matters because the
%% sea's whole claim is that it cannot miscount pepper it cannot see. And a
%% forged or stray fact carries no authority: the worst a stranger can do is make
%% this port ask its own configured ocean a question whose answer is the same as
%% it would have been. The subscription changes latency, not semantics.
%%
%% THE ASK IS A READ AND NOT A HANDSHAKE, and the difference is the whole point
%% of this module existing. Nothing is waiting on the answer. Nothing retries
%% until acknowledged. The sea stores nothing about this port and its state after
%% answering equals its state before, so two ports asking get the same page and
%% asking twice gives the same answer twice. The tick that drives it is
%% UNCONDITIONAL: it is not armed because something is outstanding and it does
%% not stop when something is acknowledged, so a port with nothing owed to it
%% asks exactly as often as one that missed a week, and gets an empty list.
%%
%% WHAT IT REMEMBERS IS IN MEMORY ONLY, AND IT IS NOT THE AUTHORITY. The
%% authority on what this port already has is `taken' in tom_port, which is
%% durable, never pruned and rebuilt from the ledger at boot. The cursor here is
%% a bandwidth bound on top of it: boot starts at nought and walks the whole
%% history of landings at this port, and every take after the first is a no-op
%% that writes nothing and says nothing. That costs one walk per restart and
%% buys no second clock in the port's ledger and no extra fsync per arrival.
%% @end
-module(tom_take_landings).

-behaviour(gen_server).

-export([start_link/0]).
-export([mine/2, asked/3, landed/1, offered/1, moved/3, gained/3, next/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% The slow tick. A crossing is about ninety seconds, so a port that missed an
%% announcement is never more than a third of a voyage behind, and the sea's one
%% process is not folding its whole voyage map for two ports every second.
-define(SWEEP_MS, 30000).

%% A burst of announcements is one thing happening. A nudge arms the look at
%% this rather than walking at once, and there is ONE timer reference in state,
%% so sweeps and pokes cannot stack.
-define(COALESCE_MS, 1000).

%% A subscription that will not bind yet is not an emergency: the pool attaches
%% a few seconds after boot and the sweep is catching up meanwhile. Re-armed
%% while and only while the subscription is missing.
-define(REBIND_MS, 5000).

%% The reading deadline rather than the handover one. Nothing is riding on this
%% answer: a page that does not come back is asked for again on the next sweep.
-define(ASK_MS, 5000).

%% One page. The sea clamps this and never refuses it.
-define(PAGE, 100).

%% How far the cursor is wound back before it is sent. `made_at' is a wall clock
%% on the sea's box and is NOT monotone, so an NTP step backwards between two
%% landings could otherwise put one behind this port's high water for ever.
%% Over-delivery is free, because taking is idempotent; under-delivery loses a
%% hull. The rewind is built to over-deliver.
-define(SLACK_MS, 60000).

%% What is being watched, what is being asked, and how far the asking has got.
%% `since' is 0 or the last landing this port's own desk answered held for. It is
%% never built from the sea's idea of where the page ended.
-type state() :: #{harbour := binary(),
                   topic := binary(),
                   procedure := binary(),
                   sub := reference() | undefined,
                   look := reference() | undefined,
                   since := cursor()}.

-type cursor() :: 0 | #{binary() => term()}.

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Whether an announcement is about a ship landing HERE.
%%
%% No check on who published it and none on which ship, because it costs nothing
%% to be nudged by a stranger and the answer to the ask is the same either way.
-spec mine(term(), binary()) -> boolean().
mine(Payload, Harbour) -> tom_wire:text(<<"bound_for">>, Payload) =:= Harbour.

%% @doc What this port asks the sea for.
-spec asked(binary(), cursor(), pos_integer()) -> map().
asked(Harbour, Since, Limit) ->
    #{<<"harbour">> => Harbour,
      <<"since">> => rewound(Since),
      <<"limit">> => Limit}.

%% @doc One page of the sea's answer: the landings this port can read, and
%% whether there is more behind them.
%%
%% AN ANSWER THIS PORT CANNOT READ IS AN EMPTY PAGE AND NEVER A CRASH. The sea is
%% another service on another box and this port has no say in what it sends; the
%% one thing that must not happen is this process dying and taking its
%% subscription with it, because then the port is deaf until somebody restarts
%% it. An empty list is an answer, and so is a refusal.
-spec landed(term()) -> {[map()], boolean()}.
landed({ok, Answer}) when is_map(Answer) ->
    {[Landing || Landing <- tom_wire:list(<<"landings">>, Answer),
                 is_map(Landing)],
     maps:get(<<"more">>, Answer, false) =:= true};
landed(_Unreadable) ->
    {[], false}.

%% @doc What one landing looks like to the desk.
%%
%% `from' IS THE PREVIOUS CUSTODIAN, WHICH IS THE SEA. That is what goes in the
%% durable `took_ship' record and out again in `ship_moored_v1', and it is the
%% truth: this port took her from the ocean. The origin port travels as
%% `sailed_from' and is deliberately not fed to the desk, because naming Macao
%% there would read better and would silently change what a committed record
%% means.
-spec offered(map()) -> map().
offered(Landing) ->
    #{<<"ship">> => maps:get(<<"ship">>, Landing, undefined),
      <<"from">> => maps:get(<<"from">>, Landing, undefined)}.

%% @doc Where the cursor goes after one landing was offered to the desk.
%%
%% IT ONLY EVER WALKS OVER WHAT WAS TAKEN. The sea's own frontier is ignored: it
%% names where the page ended, and this port may only claim what its own desk
%% answered for.
%%
%% Two failures, and telling them apart is what keeps this port from wedging. A
%% landing whose ship is not a hull can NEVER become takeable, so it is walked
%% past; refusing to advance would let one bad row block every later ship for
%% ever. Anything else is transient, so the walk stops with the cursor untouched
%% and the ordinary sweep offers the same landing again.
-spec moved(cursor(), map(), term()) -> {go | stop, cursor()}.
moved(_Cursor, Landing, {ok, #{<<"held">> := true}}) ->
    {go, #{<<"at">> => maps:get(<<"at">>, Landing, 0),
           <<"ship">> => tom_ship:id(maps:get(<<"ship">>, Landing)),
           <<"hop">> => maps:get(<<"hop">>, Landing, 0)}};
moved(Cursor, _Landing, {error, <<"malformed_ship">>}) ->
    {go, Cursor};
moved(Cursor, _Landing, _NoAnswer) ->
    {stop, Cursor}.

%% @doc Whether there is more behind this page AND this port got anywhere
%% reading it.
%%
%% THE SECOND HALF IS WHAT STOPS A SPIN, and it is not defensiveness. The
%% immediate re-look exists to walk a backlog page by page, and it is only safe
%% while each page moves the cursor: an empty page that still says there is more
%% behind it, or one whose landings were every one of them unreadable, leaves the
%% cursor exactly where it was, so asking again at once sends the identical
%% request and fetches the identical answer, for ever, as fast as the sea can
%% answer. The sea owns the content of what it sends and this port has to accept
%% it, but accepting it into an unbounded loop is not accepting it. A page that
%% gained no ground waits for the ordinary sweep like every other outcome.
-spec gained(boolean(), cursor(), cursor()) -> boolean().
gained(More, Before, After) -> More andalso After =/= Before.

%% @doc When to look again.
%%
%% THIS IS WHERE THE ABSENCE OF A RETRY LOOP LIVES. The only thing that brings
%% the next ask forward is a page the sea said had more behind it AND that this
%% port walked to the end of. Every other outcome, including every kind of
%% failure, lands on the same unconditional sweep as a port with nothing owed to
%% it. A failure never shortens the cadence, and nothing stops when somebody
%% acknowledges, because nobody is acknowledging anything.
-spec next(boolean(), go | stop) -> look | sweep.
next(true, go) -> look;
next(_More, _Walked) -> sweep.

%% gen_server

%% NO WORK IN INIT. The supervisor is waiting on this and the first ask can take
%% the reading deadline, so the walk is sent to self and happens after the tree
%% is up. tom_port is already registered and its ledger fold is already finished
%% by the time this starts, because one_for_one starts children in order.
init([]) ->
    self() ! bind,
    self() ! look,
    {ok, #{harbour => tom_standing:harbour(),
           topic => tom_wire:fact(tom_standing:realm(), <<"ocean">>,
                                  <<"voyage">>, <<"landfall_made">>),
           procedure => tom_wire:procedure(tom_standing:ocean(),
                                           <<"landings_at">>),
           sub => undefined,
           look => undefined,
           since => 0}}.

handle_call(_Message, _From, State) -> {reply, {error, unknown_call}, State}.

handle_cast(_Message, State) -> {noreply, State}.

handle_info(bind, State) ->
    {noreply, listening(State, bound(hecate_om:macula_client(),
                                     hecate_om_identity:realm(),
                                     maps:get(topic, State)))};
handle_info(look, State) ->
    {noreply, walked(State#{look := undefined})};
handle_info({macula_event, Ref, _Topic, Payload, _Meta}, State) ->
    {noreply, heard(State, Ref, tom_wire:accept(Payload))};
%% The pool dropped the subscription. Without this clause one reconnect silences
%% this port for good, and the sweep would be the only thing left keeping the
%% game moving.
handle_info({macula_event_gone, _Ref, _Reason}, State) ->
    {noreply, rebind(State#{sub := undefined})};
handle_info(_Message, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.

%% Listening

%% Matching the pair is what keeps a mesh-less boot away from macula:subscribe/4,
%% whose guards want a pid and exactly 32 bytes of realm tag. The try is for the
%% misconfigured realm, so a bad tag costs a log line rather than a supervisor
%% restart loop that eventually takes the whole service down.
bound({ok, Pool}, {ok, Realm}, Topic) ->
    try macula:subscribe(Pool, Realm, Topic, self())
    catch Class:Reason -> {error, {Class, Reason}}
    end;
bound(_Client, _Realm, _Topic) ->
    {error, no_mesh}.

listening(State, {ok, Ref}) ->
    logger:info("[tom_harbour] ~ts is listening for landfalls",
                [maps:get(harbour, State)]),
    State#{sub := Ref};
listening(State, {error, Why}) ->
    logger:notice("[tom_harbour] not listening for landfalls yet (~p)", [Why]),
    rebind(State).

%% Only armed while something is unbound, so a fully bound port is not waking up
%% every five seconds for the rest of the game.
rebind(State) ->
    _ = erlang:send_after(?REBIND_MS, self(), bind),
    State.

heard(State, Ref, Payload) ->
    nudged(State, Ref =:= maps:get(sub, State)
           andalso mine(Payload, maps:get(harbour, State))).

nudged(State, true) -> timed(State, ?COALESCE_MS);
nudged(State, false) -> State.

%% Asking

%% ONE PAGE PER LOOK, AND THE WALK IS SERIALISED IN THIS PROCESS. The ask runs
%% here rather than in tom_port, which would freeze the market, the quotes and
%% every hull at the quay for the deadline. While it is in flight, facts merely
%% queue in this mailbox and nothing is lost.
-spec walked(state()) -> state().
walked(State) ->
    paged(State, landed(ask(State))).

paged(State, {Landings, More}) ->
    Before = maps:get(since, State),
    {Walked, Cursor} = lists:foldl(fun taken/2, {go, Before}, Landings),
    timed(State#{since := Cursor},
          when_of(next(gained(More, Before, Cursor), Walked))).

taken(Landing, {go, Cursor}) ->
    moved(Cursor, Landing, noted(Landing, offer(Landing)));
taken(_Landing, {stop, Cursor}) ->
    {stop, Cursor}.

ask(#{procedure := Procedure, harbour := Harbour, since := Since}) ->
    called(Procedure, asked(Harbour, Since, ?PAGE),
           hecate_om:macula_client(), hecate_om_identity:realm()).

%% AN ASK THAT RAISES MUST LAND ON THE SWEEP LIKE ANY OTHER FAILURE. macula's
%% call guards want a pid and exactly 32 bytes of realm tag, and the call itself
%% is a gen_server call into the pool, which exits the caller if the pool goes
%% down underneath it. That is the ordinary reconnect, not an exotic case, and
%% unwrapped it would kill the one process in this service holding a
%% subscription. Failing here has to cost the same as an empty page.
called(Procedure, Payload, {ok, Pool}, {ok, Realm}) ->
    try replied(macula:call(Pool, Realm, Procedure, Payload, ?ASK_MS))
    catch Class:Reason -> unasked(Class, Reason)
    end;
called(_Procedure, _Payload, _Client, _Realm) ->
    {error, no_mesh}.

unasked(Class, Reason) ->
    logger:notice("[tom_harbour] the sea would not say what it landed here "
                  "(~p:~p); looking again on the sweep", [Class, Reason]),
    {error, {Class, Reason}}.

%% A reply comes back through the same codec the request went out through, so
%% the hulls inside it arrive with atom keys or {text, Binary} keys depending on
%% what this node happens to have loaded. Reading one raw would answer
%% malformed_ship for every well-formed landing in the game.
replied({ok, Reply}) -> {ok, tom_wire:accept(Reply)};
replied(Other) -> Other.

%% Taking

%% THE DESK IS ENTERED THROUGH tom_port, which serialises it against everything
%% else at this quay and writes the record before it answers. The call is
%% wrapped because a wedged port must cost a log line and a stopped walk rather
%% than this process's death and its subscription with it.
offer(Landing) ->
    try tom_port:take(offered(Landing))
    catch Class:Reason -> untaken(Class, Reason)
    end.

untaken(Class, Reason) ->
    logger:notice("[tom_harbour] the port would not take a landing (~p:~p); "
                  "stopping the walk here", [Class, Reason]),
    {error, {Class, Reason}}.

noted(Landing, {error, <<"malformed_ship">>} = Refused) ->
    logger:notice("[tom_harbour] the sea landed something that is not a hull "
                  "here (~p); walking past it", [maps:get(<<"ship">>, Landing,
                                                          undefined)]),
    Refused;
noted(_Landing, Reply) ->
    Reply.

%% Looking again

when_of(look) -> 0;
when_of(sweep) -> ?SWEEP_MS.

%% ONE TIMER, so a burst of nudges and a sweep cannot stack into a queue of
%% walks. Arming cancels whatever was armed, which is what makes coalescing a
%% property of this process rather than of how fast the sea publishes.
timed(#{look := Ref} = State, Ms) ->
    _ = cancelled(Ref),
    State#{look := erlang:send_after(Ms, self(), look)}.

cancelled(undefined) -> false;
cancelled(Ref) -> erlang:cancel_timer(Ref).

rewound(0) ->
    0;
rewound(Cursor) ->
    #{<<"at">> => max(0, maps:get(<<"at">>, Cursor, 0) - ?SLACK_MS),
      <<"ship">> => <<>>,
      <<"hop">> => 0}.
