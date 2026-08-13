%% @doc The hulls this port currently has at sea.
%%
%% One child per hull in passage, transient: she reaches her destination or she
%% founders, and either way the process stops normally and is gone. One that
%% crashed is started again with the same arguments, which is the same passage,
%% because the arguments are the berth and the berth is on the disk.
%%
%% Nothing about a passage lives here. Emptying this supervisor loses no ship: a
%% reboot reads the consigned berths back off the ledger and puts every one of
%% them to sea again with the leg she has left.
%% @end
-module(tom_keep_the_sea_sup).

-behaviour(supervisor).

-export([start_link/0, put_to_sea/5]).
-export([init/1]).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Put one hull to sea until Due, with the fate she drew when she sailed.
-spec put_to_sea(binary(), integer(), integer(), tom_passage:fate(), map()) ->
          supervisor:startchild_ret().
put_to_sea(Ship, Hop, Due, Fate, Payload) ->
    supervisor:start_child(?MODULE, [Ship, Hop, Due, Fate, Payload]).

init([]) ->
    {ok, {#{strategy => simple_one_for_one, intensity => 10, period => 10},
          [#{id => tom_keep_the_sea,
             start => {tom_keep_the_sea, start_link, []},
             restart => transient,
             shutdown => 5000,
             type => worker,
             modules => [tom_keep_the_sea]}]}}.
