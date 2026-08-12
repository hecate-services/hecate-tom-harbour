%% @doc OTP application entry.
%%
%% hecate_om:boot/1 wires the mesh client, the realm identity, the capability
%% advertisement and the health endpoint, then starts this service's own tree.
%%
%% STORELESS. No store_id/0 and no data_dir/0 on the service module, so no
%% reckon-db is started and no evoq block is needed in the release config. What
%% this port must not forget goes in its own disk_log, which is four record
%% shapes and needs no cluster to hold them.
%% @end
-module(hecate_tom_world_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> hecate_om:boot(hecate_tom_world_service).

stop(_State) -> ok.
