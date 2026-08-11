%% @doc This harbour's own processes.
%%
%% THE ORDER IS A DEPENDENCY ORDER AND NOT A PREFERENCE.
%%
%%   tom_crier               the mouth. tom_port casts its facts at it from the
%%                           moment it seeds a hull, so it is up first.
%%   tom_hand_over_ship_sup  the promises. tom_port asks it for a child as soon
%%                           as it finds an unfinished consignment on the disk.
%%   tom_port                the market, the clock, the hulls and the disk.
%%   tom_advertiser          last, because it asks tom_port for the harbour's
%%                           own name and because there is no point telling the
%%                           mesh this port answers calls before it can.
%%
%% one_for_one, because none of the four holds a handle on another: they find
%% each other by registered name, and a cast at a name that is momentarily
%% unregistered is dropped rather than an error. A crier that dies loses the
%% facts said while it was gone, which is what the contract already permits, and
%% a port that dies rebuilds its custody and its receipts from the disk.
%% @end
-module(hecate_tom_harbour_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10},
          [worker(tom_crier),
           nursery(tom_hand_over_ship_sup),
           worker(tom_port),
           worker(tom_advertiser)]}}.

worker(Module) ->
    #{id => Module, start => {Module, start_link, []}, restart => permanent,
      shutdown => 5000, type => worker, modules => [Module]}.

nursery(Module) ->
    #{id => Module, start => {Module, start_link, []}, restart => permanent,
      shutdown => infinity, type => supervisor, modules => [Module]}.
