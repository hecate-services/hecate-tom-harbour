%% @doc The port's one mouth. Everything this harbour says out loud goes through
%% here, in the order it was said.
%%
%% A SEPARATE PROCESS BECAUSE PUBLISHING BLOCKS. macula:publish is a call into
%% the pool with a five second deadline, and five seconds of a sulking station
%% inside tom_port would stop the market, the quotes and every hull at the quay.
%% tom_port casts and carries on.
%%
%% NO FACT IS LOAD-BEARING, so a dropped one costs a page update and never a
%% coin or a ton. Everything that must be true is established by a call with a
%% receipt or read back later from the service that owns it, which is why this
%% module has no queue, no retry and no acknowledgement. It says the thing once
%% and says so in the log if the mesh would not take it.
%%
%% THAT IS WHAT MAKES A HOUSE FREE TO BE SWITCHED OFF. A player can miss ninety
%% seconds of publications, come back, ask three questions and be exactly right.
%% Buying a delivery guarantee here would buy nothing and would put this port's
%% correctness on the mesh's availability.
%% @end
-module(tom_crier).

-behaviour(gen_server).

-export([start_link/0, cry/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Say one thing. Returns as soon as it is queued, never later.
-spec cry(binary(), map()) -> ok.
cry(Topic, Payload) -> gen_server:cast(?MODULE, {cry, Topic, Payload}).

init([]) -> {ok, []}.

handle_call(_Message, _From, State) -> {reply, {error, unknown_call}, State}.

handle_cast({cry, Topic, Payload}, State) ->
    said(Topic, shouted(Topic, Payload, hecate_om:macula_client(),
                        hecate_om_identity:realm())),
    {noreply, State};
handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(_Message, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

%% Internal

shouted(Topic, Payload, {ok, Pool}, {ok, Realm}) ->
    macula:publish(Pool, Realm, Topic, Payload);
shouted(_Topic, _Payload, _Client, _Realm) ->
    {error, no_mesh}.

said(_Topic, ok) ->
    ok;
said(Topic, {error, Why}) ->
    logger:notice("[tom_harbour] nobody heard ~ts (~p)", [Topic, Why]).
