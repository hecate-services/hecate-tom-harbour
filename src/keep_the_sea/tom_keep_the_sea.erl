%% @doc One hull at sea, waiting out her leg.
%%
%% This exists so a ship can be somewhere that is not a port, without a service
%% owning the sea.
%%
%% ONE PROCESS PER HULL IN PASSAGE, at the port she sailed from, for the leg she
%% is on. She is nobody's guest: Macao is done with her and Lisbon has not got
%% her. Hosting is not owning, and the two must not be run together again: this
%% port is only the host of the process, and custody is the berth's, frozen at
%% the hop she left at, until the far port says held.
%%
%% SHE SLEEPS AND THEN SHE DOES ONE OF TWO THINGS. If her fate was `arrives' she
%% asks the promise machinery to knock at the far port, which is the same
%% machinery that has always moved a hull between two parties and which retries
%% for ever. If it was `{lost, Cause}' she tells this port she foundered.
%%
%% THE FATE IS NOT DRAWN HERE. It was drawn at sailing, in the same durable write
%% that froze the berth, and this process is handed the answer. Drawing it here
%% would mean a crash between the draw and the disk let a restarted port draw
%% again, and a ship could be re-rolled once per container bounce until she sank.
%% See tom_passage.
%%
%% SHE CAN BE LATE AND NEVER EARLY. A port that was down for an hour comes back
%% up, finds a hull whose leg ended forty minutes ago and acts at once, which is
%% right: the sea did not stop while the machine was off, and the instant she was
%% due is on the disk. A negative wait is not an error, it is a ship that has
%% been waiting.
%%
%% NOTHING OF THIS PORT'S STATE IS IN HERE. The only outputs are a start_child at
%% the promise nursery and one cast, so a crash costs the sleep and nothing else:
%% the supervisor starts her again from the same berth and she works out from the
%% clock how much of her leg is left.
%% @end
-module(tom_keep_the_sea).

-behaviour(gen_server).

-export([start_link/5]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(passage, {ship :: binary(),
                  hop :: integer(),
                  bound_for :: binary(),
                  fate :: tom_passage:fate(),
                  payload :: map()}).

%% @doc Put one hull to sea until Due, with the fate she drew when she sailed.
-spec start_link(binary(), integer(), binary(), tom_passage:fate(), map()) ->
          {ok, pid()} | {error, term()}.
start_link(Ship, Hop, Due, Fate, Payload) ->
    gen_server:start_link(?MODULE, {Ship, Hop, Due, Fate, Payload}, []).

init({Ship, Hop, Due, Fate, Payload}) ->
    #{<<"bound_for">> := BoundFor} = Payload,
    erlang:send_after(left(Due), self(), make_landfall),
    {ok, #passage{ship = Ship, hop = Hop, bound_for = BoundFor,
                  fate = Fate, payload = Payload}}.

handle_call(_Message, _From, Passage) -> {reply, {error, unknown_call}, Passage}.

handle_cast(_Message, Passage) -> {noreply, Passage}.

handle_info(make_landfall, Passage) ->
    {stop, normal, arrived(Passage#passage.fate, Passage)};
handle_info(_Message, Passage) ->
    {noreply, Passage}.

terminate(_Reason, _Passage) -> ok.

%% Internal

%% Never below zero, because send_after will not take a negative and a ship that
%% is overdue is not an error. See the header.
left(Due) -> max(0, Due - tom_wire:now_ms()).

arrived(arrives, #passage{ship = Ship, hop = Hop, bound_for = BoundFor,
                          payload = Payload} = Passage) ->
    logger:info("[tom_harbour] ~ts is off ~ts and asking to come alongside",
                [Ship, BoundFor]),
    _ = tom_hand_over_ship_sup:start_handing(Ship, Hop, BoundFor, Payload),
    Passage;
arrived({lost, Cause}, #passage{ship = Ship, hop = Hop,
                                bound_for = BoundFor} = Passage) ->
    logger:notice("[tom_harbour] ~ts was lost to ~ts, bound for ~ts",
                  [Ship, Cause, BoundFor]),
    ok = tom_port:foundered(Ship, Hop, Cause),
    Passage.
