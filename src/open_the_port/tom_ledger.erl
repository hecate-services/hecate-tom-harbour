%% @doc What this port must not forget, on a disk, before it answers.
%%
%% ACCEPTANCE IS THE COMMIT POINT AND IT IS DURABLE BEFORE THE REPLY. Never the
%% other way round. A receiver that answers first and writes second has told a
%% consigner to let go of a ship it may be about to forget, and then the ship
%% exists nowhere, which is the one outcome the whole custody rule exists to
%% make impossible. Every write here syncs before it returns.
%%
%% FOUR THINGS ARE KEPT AND THEY ARE KEPT FOREVER.
%%
%%   took_ship      this port has custody, at this hop. Answering a repeat of a
%%                  handover it has already taken is what lets a consigner that
%%                  was down for an hour resolve itself with a retry rather than
%%                  a reconciliation call, so this record outlives the ship's
%%                  stay and is never pruned.
%%   consigned_ship this port has promised a ship away and frozen it. Custody
%%                  has NOT moved; what has changed is that this port now owes
%%                  somebody a call until it gets an answer.
%%   handed_ship    the receiver said held, so this port has let go. Written
%%                  after the answer and never before it.
%%   settled_order  a trade happened and this is exactly what was said about it.
%%                  Replayed verbatim when the same order arrives again, which
%%                  is what makes a house that died mid-order safe to restart.
%%                  It carries the good alongside the reply rather than inside
%%                  it, because the reply is a wire shape somebody else's
%%                  service is written against and this port's need to know
%%                  which quay to put the goods back on is its own business.
%%
%% A disk_log rather than an event store, and that is a scoping decision rather
%% than an oversight. What must survive a restart is CUSTODY and RECEIPTS, both
%% of which are appended once and read back in order, and OTP already has
%% exactly that with a sync that means what it says. An event store would bring
%% a cluster, a schema and a config block to hold four record shapes.
%%
%% WHAT IS DELIBERATELY NOT KEPT: the heaps on the quays. Those are rebuilt at
%% boot by replaying the settled orders into a freshly opened market, which puts
%% the goods back where they were without a second record of them.
%% @end
-module(tom_ledger).

-export([open/2, record/2, fold/3, close/1]).

-export_type([log/0, entry/0]).

%% @doc The handle. A disk_log name, which is the log itself.
-type log() :: term().

%% @doc Everything this port writes down. Business verbs in the past tense: what
%% happened, not what was changed.
%%
%% A CONSIGNMENT CARRIES HER CLOCK AND HER FATE, because both are fixed when she
%% sails and neither may be drawn again on the way back up. A port that re-rolled
%% a fate at boot would sink a ship by being restarted.
-type entry() :: {took_ship, binary(), integer(), tom_ship:ship(), binary(),
                  integer()}
               | {consigned_ship, binary(), integer(), binary(), integer(),
                  integer(), tom_passage:fate()}
               | {foundered_ship, binary(), integer(), tom_passage:cause(),
                  integer()}
               | {handed_ship, binary(), integer(), binary(), integer()}
               | {settled_order, binary(), binary(), map()}.

%% @doc Open this port's record, making the directory if it is not there.
%%
%% ONE RELEASE INSTANCE IS ONE PORT, so the log has one name and the harbour
%% only decides the file. Two ports on one box are two containers with two data
%% directories, which is also what keeps them from sharing a market.
-spec open(string(), binary()) -> {ok, log()} | {error, term()}.
open(Dir, Harbour) ->
    opened(filelib:ensure_path(Dir), Dir,
           binary_to_list(binary:replace(Harbour, [<<"/">>, <<":">>],
                                         <<"-">>, [global]))).

%% @doc Write one thing down and do not come back until it is on the disk.
-spec record(log(), entry()) -> ok.
record(Log, Entry) ->
    ok = disk_log:log(Log, Entry),
    ok = disk_log:sync(Log).

%% @doc Read everything back, oldest first.
%%
%% ORDER IS THE WHOLE POINT. A took followed by a handed means the ship left; a
%% handed followed by a took means it came back. Folding these in any other
%% order gives a port that holds a ship it gave away.
-spec fold(log(), fun((entry(), Acc) -> Acc), Acc) -> Acc.
fold(Log, Fun, Acc) -> chunked(Log, Fun, Acc, disk_log:chunk(Log, start)).

%% @doc Close it.
-spec close(log()) -> ok.
close(Log) -> disk_log:close(Log).

%% Internal

opened(ok, Dir, File) ->
    started(disk_log:open([{name, ?MODULE},
                           {file, filename:join(Dir, File ++ ".log")},
                           {format, internal},
                           {type, halt},
                           {mode, read_write}]));
opened({error, Why}, Dir, _File) ->
    {error, {no_data_dir, Dir, Why}}.

%% A log that was not closed cleanly is repaired and opened, because the
%% alternative is a port that will not start after a power cut. The records lost
%% to a truncated tail are records whose reply never reached anybody, so a
%% consigner will send them again.
started({ok, Name}) -> {ok, Name};
started({repaired, Name, _Recovered, _Bad}) -> {ok, Name};
started({error, Why}) -> {error, Why}.

chunked(_Log, _Fun, Acc, eof) ->
    Acc;
chunked(Log, Fun, Acc, {Continuation, Entries}) ->
    chunked(Log, Fun, lists:foldl(Fun, Acc, Entries),
            disk_log:chunk(Log, Continuation));
chunked(Log, Fun, Acc, {Continuation, Entries, _Bad}) ->
    chunked(Log, Fun, lists:foldl(Fun, Acc, Entries),
            disk_log:chunk(Log, Continuation)).
