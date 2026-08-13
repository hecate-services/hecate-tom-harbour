%% @doc This harbour's own processes.
%%
%% THE ORDER IS A DEPENDENCY ORDER AND NOT A PREFERENCE.
%%
%%   tom_crier               the mouth. tom_port casts its facts at it from the
%%                           moment it seeds a hull, so it is up first.
%%   tom_keep_the_sea_sup    the hulls at sea. tom_port asks it for a child as
%%                           soon as it finds a consigned berth on the disk.
%%   tom_hand_over_ship_sup  the promises. A passage that ends well asks it for a
%%                           child, and so does a desk that hands a hull on.
%%   tom_port                the market, the clock, the hulls and the disk.
%%   tom_advertiser          because it asks tom_port for the harbour's own name
%%                           and because there is no point telling the mesh this
%%                           port answers calls before it can.
%%
%% THE EARS ARE GONE. There was a tom_take_landings here, last in the order,
%% which heard the sea announce a landfall and asked the sea what it had landed
%% here. A ship presents herself now: she is a process at the port she sailed
%% from and she knocks on the far port's door herself, so there is nothing to
%% overhear, nothing to sweep for and no cursor to keep.
%%
%% one_for_one, because none of them holds a handle on another: they find
%% each other by registered name, and a cast at a name that is momentarily
%% unregistered is dropped rather than an error. A crier that dies loses the
%% facts said while it was gone, which is what the contract already permits, and
%% a port that dies rebuilds its custody and its receipts from the disk, and puts
%% every hull it finds consigned back to sea with the leg she has left.
%% @end
-module(hecate_tom_world_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10},
          [worker(tom_crier),
           nursery(tom_keep_the_sea_sup),
           nursery(tom_hand_over_ship_sup),
           worker(tom_port),
           worker(tom_advertiser)]}}.

worker(Module) ->
    #{id => Module, start => {Module, start_link, []}, restart => permanent,
      shutdown => 5000, type => worker, modules => [Module]}.

nursery(Module) ->
    #{id => Module, start => {Module, start_link, []}, restart => permanent,
      shutdown => infinity, type => supervisor, modules => [Module]}.
