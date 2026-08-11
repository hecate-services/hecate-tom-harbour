%% @doc What this harbour will answer to, and where.
%%
%% ADDRESSED AT THIS INSTANCE, EVERY ONE OF THEM. Macao and Lisbon both answer
%% buy_cargo, and macula:call is first-success across a pool's links, so a
%% procedure name that did not carry the harbour would deliver a Macao order to
%% Lisbon and the coin would be gone with no way to tell whose fault it was.
%% derive_procedure/2 exists for exactly this and costs nothing at eight ports.
%%
%% SEVEN PROCEDURES, AND NOT ONE OF THEM IS AN ARRIVAL. A harbour is
%% infrastructure and has no say in whether a ship turns up, so there is no door
%% here for the sea to knock at: `receive_ship' is a desk this port enters by
%% itself, off the sea's announcement and off its own catch-up ask, and it is not
%% something a stranger can call. Everything below is a thing a HOUSE asks this
%% port to do.
%%
%% IT DIALS OUT AND RETRIES. A hecate service opens no port and waits for
%% nobody: it connects to a station over QUIC and advertises through that. Until
%% the pool and the realm are both up there is nothing to advertise on, so this
%% keeps trying, and a station link that dies takes the advertisement with it
%% and gets it back on the next attempt.
%% @end
-module(tom_advertiser).

-behaviour(gen_server).

-export([start_link/0, procedures/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(RETRY_MS, 5000).

%% Whether the last attempt got everything up. Not a subscription reference:
%% macula's advertise has nothing to hand back and nothing to cancel.
-record(pitch, {advertised = false :: boolean()}).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Every procedure this harbour answers, and who answers it.
%%
%% The name is what a caller says; the handler is the desk that owns it. A desk
%% appears here exactly once and nowhere else, so this list IS the harbour's
%% public surface and adding to it is a deliberate act.
-spec procedures() -> [{binary(), {module(), atom()}}].
procedures() ->
    [{<<"list_quotes">>, {tom_list_quotes, handle}},
     {<<"quote_purchase">>, {tom_quote_purchase, handle}},
     {<<"buy_cargo">>, {tom_buy_cargo, handle}},
     {<<"sell_cargo">>, {tom_sell_cargo, handle}},
     {<<"sail_ship">>, {tom_sail_ship, handle}},
     {<<"get_ship">>, {tom_get_ship, handle}},
     {<<"commission_ship">>, {tom_commission_ship, handle}}].

init([]) ->
    self() ! advertise,
    {ok, #pitch{}}.

handle_call(_Message, _From, Pitch) -> {reply, {error, unknown_call}, Pitch}.

handle_cast(_Message, Pitch) -> {noreply, Pitch}.

handle_info(advertise, Pitch) ->
    {noreply, pitched(Pitch, hecate_om:macula_client(),
                      hecate_om_identity:realm())};
handle_info(_Message, Pitch) ->
    {noreply, Pitch}.

terminate(_Reason, _Pitch) -> ok.

%% Internal

pitched(Pitch, {ok, Pool}, {ok, Realm}) ->
    Harbour = tom_port:harbour(),
    judged(Pitch, Harbour,
           [macula:advertise(Pool, Realm, tom_wire:procedure(Harbour, Name),
                             fun_for(Handler), #{})
            || {Name, Handler} <- procedures()]);
pitched(Pitch, _Client, _Realm) ->
    retry(Pitch).

%% macula takes a one-argument fun or a {Module, Function} pair; the pair is
%% used, because a fun captured at advertise time pins this module's version and
%% a desk that is upgraded underneath one goes on answering with the old code.
fun_for({Module, Function}) -> {Module, Function}.

judged(Pitch, Harbour, Answers) ->
    accepted(Pitch, Harbour, lists:all(fun(Answer) -> Answer =:= ok end,
                                       Answers)).

accepted(Pitch, Harbour, true) ->
    logger:info("[tom_harbour] ~ts is open, answering ~w procedures",
                [Harbour, length(procedures())]),
    Pitch#pitch{advertised = true};
accepted(Pitch, _Harbour, false) ->
    retry(Pitch).

retry(Pitch) ->
    erlang:send_after(?RETRY_MS, self(), advertise),
    Pitch#pitch{advertised = false}.
