%% @doc The promises this port is currently keeping.
%%
%% One child per consigned hull, transient: a worker that got its answer stops
%% normally and is gone, and one that crashed is started again with the same
%% arguments, which is the same promise. Nothing about a promise lives here,
%% because the promise itself is on the disk.
%% @end
-module(tom_hand_over_ship_sup).

-behaviour(supervisor).

-export([start_link/0, start_handing/4]).
-export([init/1]).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Start knocking on a receiver's door about one hull.
-spec start_handing(binary(), integer(), binary(), map()) ->
          supervisor:startchild_ret().
start_handing(Ship, Hop, To, Payload) ->
    supervisor:start_child(?MODULE, [Ship, Hop, To, Payload]).

init([]) ->
    {ok, {#{strategy => simple_one_for_one, intensity => 10, period => 10},
          [#{id => tom_hand_over_ship,
             start => {tom_hand_over_ship, start_link, []},
             restart => transient,
             shutdown => 5000,
             type => worker,
             modules => [tom_hand_over_ship]}]}}.
