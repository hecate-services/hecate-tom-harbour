%% @doc The hecate_om contract: what this service is, and what it may do.
%%
%% SIX CALLBACKS, ALL REQUIRED, resolved by name on a live node, which is why
%% the behaviour attribute is here: it turns a forgotten one into a compile
%% error rather than an undef in a container nobody is watching.
%%
%% THE CAPABILITIES ARE INSTANCE-ADDRESSED, like the procedures they name. Two
%% harbours in one realm both answer buy_cargo, and a capability list that said
%% only "buy_cargo" would tell a looker-up that either would do. The harbour is
%% in the name because the harbour is the point.
%% @end
-module(hecate_tom_harbour_service).

-behaviour(hecate_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).

info() ->
    #{name => <<"hecate-tom-harbour">>,
      version => <<"0.2.0">>,
      description => <<"TOM, Traders of Macao: one port and its market">>}.

start(_Opts) -> hecate_tom_harbour_sup:start_link().

stop(_State) -> ok.

%% GREEN MEANS THE MARKET ANSWERS. A dark mesh is deliberately NOT a health
%% failure: this port keeps its market, its hulls and its record whether or not
%% a station is reachable, and reporting sick because a peer is down would have
%% an operator restarting the one process that is working.
%%
%% What is checked is the thing that would actually be broken: tom_port holding
%% a market it can quote from. If that is gone, every call this service
%% advertises is going to time out.
health() -> alive(catch tom_market:tick(tom_port:market())).

%% WHAT THIS HARBOUR ANNOUNCES IT CAN DO. Each entry is a promise that something
%% answers, and every one of them is answered by a desk in this repository.
capabilities() ->
    [#{name => tom_wire:procedure(tom_standing:harbour(), Name), version => 1}
     || {Name, _Handler} <- tom_advertiser:procedures()].

%% THE AUTHORITY THIS SERVICE ASKS FOR, and deliberately nothing else. It
%% publishes four facts and answers seven calls, all under its own harbour's
%% name, and it subscribes to nothing at all: facts flow one way, from the
%% always-on services to a player's page.
identity_spec() ->
    #{scope => <<"hecate-tom-harbour">>,
      actions => [<<"publish">>, <<"advertise">>, <<"call">>],
      resources => [tom_standing:harbour(),
                    tom_wire:fact(tom_standing:realm(), <<"trade">>,
                                  <<"cargo_loaded">>),
                    tom_wire:fact(tom_standing:realm(), <<"trade">>,
                                  <<"cargo_discharged">>),
                    tom_wire:fact(tom_standing:realm(), <<"custody">>,
                                  <<"ship_moored">>),
                    tom_wire:fact(tom_standing:realm(), <<"custody">>,
                                  <<"ship_consigned">>)],
      ttl_days => 30}.

%% Internal

alive(Tick) when is_integer(Tick) -> ok;
alive(Other) -> {down, Other}.
