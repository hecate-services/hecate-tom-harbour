%% @doc One promise this port has made and has not yet been released from.
%%
%% ONE WORKER PER CONSIGNED HULL, AND IT DOES NOT GIVE UP. Rule five of the
%% custody rule: the consigner retries every five seconds, forever, and resumes
%% at boot from its own record. It never un-consigns on its own initiative,
%% because the receiver may already have taken the hull and be about to say so.
%%
%% THE PAYLOAD NEVER CHANGES. Every attempt is byte for byte the call the first
%% attempt was, which is the entire dedupe mechanism: the receiver recognises a
%% repeat by the ship and the hop, and there is no second identifier for the two
%% sides to agree on. A worker that recomputed the payload each time, with a
%% fresh instant in it, would look like a new handover every five seconds.
%%
%% IT LIVES IN A PROCESS OF ITS OWN BECAUSE THE CALL BLOCKS. Fifteen seconds of
%% a dead ocean inside tom_port would freeze the market, the quotes and every
%% other hull at this quay. Nothing about this port's own state is in here; the
%% worker's only output is one cast saying the receiver said held.
%%
%% DUPLICATES ARE HARMLESS AND ARE NOT PREVENTED. Two workers on one promise
%% make two identical calls, get two identical held answers, and cast twice;
%% tom_port drops a hull it has already dropped. Machinery to stop that would
%% cost more than the thing it prevents, which is the shape of the whole
%% contract.
%% @end
-module(tom_hand_over_ship).

-behaviour(gen_server).

-export([start_link/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% A handover moves custody of a hull and its cargo, so it gets the long
%% deadline rather than the reading one.
-define(CALL_MS, 15000).

%% Between attempts. Long enough not to hammer a receiver that is down, short
%% enough that a player watching a consigned ship sees it leave.
-define(RETRY_MS, 5000).

-record(promise, {ship :: binary(),
                  hop :: integer(),
                  to :: binary(),
                  procedure :: binary(),
                  payload :: map()}).

-spec start_link(binary(), integer(), binary(), map()) ->
          {ok, pid()} | {error, term()}.
start_link(Ship, Hop, To, Payload) ->
    gen_server:start_link(?MODULE, {Ship, Hop, To, Payload}, []).

init({Ship, Hop, To, Payload}) ->
    self() ! knock,
    {ok, #promise{ship = Ship, hop = Hop, to = To,
                  procedure = tom_wire:procedure(To, <<"receive_ship">>),
                  payload = Payload}}.

handle_call(_Message, _From, Promise) -> {reply, {error, unknown_call}, Promise}.

handle_cast(_Message, Promise) -> {noreply, Promise}.

handle_info(knock, Promise) ->
    answered(Promise, replied(called(Promise, hecate_om:macula_client(),
                                     hecate_om_identity:realm())));
handle_info(_Message, Promise) ->
    {noreply, Promise}.

terminate(_Reason, _Promise) -> ok.

%% Internal

called(#promise{procedure = Procedure, payload = Payload}, {ok, Pool},
       {ok, Realm}) ->
    macula:call(Pool, Realm, Procedure, Payload, ?CALL_MS);
called(_Promise, _Client, _Realm) ->
    {error, no_mesh}.

%% A reply comes back through the same codec a request goes out through, so
%% `held' arrives as an atom key on one node and as {text, <<"held">>} on the
%% next. Reading it raw is how a receiver that HAS taken the hull gets heard as
%% a receiver that has not, and this port then knocks forever at an open door.
replied({ok, Reply}) -> {ok, tom_wire:accept(Reply)};
replied(Other)       -> Other.

%% held IS THE ONLY THING THAT RELEASES THIS PORT. Anything else, an error, a
%% timeout, a reply in a shape nobody recognises, is treated as transient,
%% because the alternative is to give up on a hull somebody may already be
%% holding. There is no final failure here by design.
answered(#promise{ship = Ship, hop = Hop} = Promise, {ok, #{<<"held">> := true}}) ->
    ok = tom_port:handed(Ship, Hop),
    logger:info("[tom_harbour] ~ts taken at hop ~w by ~ts",
                [Ship, Hop, Promise#promise.to]),
    {stop, normal, Promise};
answered(#promise{ship = Ship} = Promise, Other) ->
    logger:notice("[tom_harbour] ~ts not taken yet (~p); knocking again",
                  [Ship, Other]),
    erlang:send_after(?RETRY_MS, self(), knock),
    {noreply, Promise}.
