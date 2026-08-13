%% @doc The port as a running service: it boots, it trades, it is killed, and it
%% comes back knowing what it did.
%%
%% THIS IS THE TEST THAT USES THE DISK. Everything else in this repository is a
%% function, and a function cannot tell you whether a port that was switched off
%% mid-voyage still owes anybody anything. Here the application is started for
%% real, against a real ledger in a real directory, stopped, and started again
%% on the same directory.
%%
%% The mesh is deliberately absent. No station seeds are configured, so
%% hecate_om hands back no client, the crier says so in the log and the
%% advertiser keeps retrying. NOTHING ELSE CHANGES, which is the point of no
%% fact being load-bearing: a port with no mesh trades, records and recovers
%% exactly as one with a mesh does.
%% @end
-module(tom_boot_tests).

-include_lib("eunit/include/eunit.hrl").

-define(HOUSE, <<"mri:instance:io.macula/tom/house/raf">>).
-define(CLARA, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(MUSK, <<"mri:class:io.macula/tom/good/musk">>).
-define(LISBON, <<"mri:instance:io.macula/tom/harbour/lisbon">>).

boot_test_() ->
    {setup, fun open_a_port/0, fun close_the_port/1,
     fun(Dir) ->
             [{"a port that has never traded boots at rest",
               fun() -> boots_at_rest() end},
              {"genesis puts one hull at the quay",
               fun() -> genesis_seeds_once() end},
              {"a trade moves the quay and the hold together",
               fun() -> a_trade_lands_in_the_hold() end},
              {"and survives being switched off",
               fun() -> survives_a_restart(Dir) end},
              {"a hull at sea goes back to sea after a restart",
               fun() -> a_promise_survives_a_restart(Dir) end},
              {"the mesh edge reads a payload shaped the way one arrives",
               fun() -> the_edge_reads_a_wire_payload() end},
              {"and hands a refusal back with its reason on it",
               fun() -> the_edge_answers_with_a_reason() end}]
     end}.

%% Fixture

open_a_port() ->
    Dir = filename:join(["/tmp", "tom_boot_tests",
                         integer_to_list(erlang:unique_integer([positive]))]),
    os:putenv("TOM_HARBOUR", "macao"),
    os:putenv("TOM_DATA_DIR", Dir),
    os:putenv("TOM_SHIPS", filename:join([code:priv_dir(hecate_tom_world),
                                          "ships", "macao.ships"])),
    %% hecate_om's health listener is switched off for the run. It binds a fixed
    %% port, so a box already running any other hecate service fails the boot
    %% with eaddrinuse, and the endpoint is hecate_om's code rather than this
    %% service's: there is nothing about this port it would prove.
    ok = application:load(hecate_om),
    ok = application:set_env(hecate_om, health_port, 0),
    {ok, _Started} = application:ensure_all_started(hecate_tom_world),
    Dir.

close_the_port(Dir) ->
    ok = application:stop(hecate_tom_world),
    os:unsetenv("TOM_HARBOUR"),
    os:unsetenv("TOM_DATA_DIR"),
    os:unsetenv("TOM_SHIPS"),
    file:del_dir_r(Dir).

%% A port nobody has touched holds its natural stock of everything, whatever the
%% wall clock says, because a quay at rest is a fixed point and settling to now
%% costs one comparison per good.
boots_at_rest() ->
    Market = tom_port:market(),
    ?assert(tom_market:tick(Market) > 0),
    [?assert(tom_quay:at_rest(tom_market:quay(Market, Good)))
     || Good <- tom_market:goods(Market)],
    ?assert(near(tom_market:quote(Market, musk), 12.915496650148841)).

%% The hull in priv/ships is here, at hop nought, in this port's custody.
genesis_seeds_once() ->
    {ok, Berth} = tom_port:berth(#{<<"ship">> => ?CLARA}),
    ?assertEqual(<<"moored">>, maps:get(<<"state">>, Berth)),
    Hull = maps:get(<<"ship">>, Berth),
    ?assertEqual(0, tom_ship:hop(Hull)),
    ?assertEqual(?HOUSE, tom_ship:owner(Hull)),
    ?assertEqual(200.0, tom_ship:hold(Hull)),
    ?assertEqual(#{}, tom_ship:cargo(Hull)).

%% One call, and the goods are off the quay and in the hold.
a_trade_lands_in_the_hold() ->
    {ok, Receipt} = tom_port:buy(#{<<"order">> => <<"boot-1">>,
                                   <<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                                   <<"good">> => ?MUSK,
                                   <<"quantity">> => 5.0}),
    ?assertEqual(5.0, maps:get(<<"filled">>, Receipt)),
    ?assert(maps:get(<<"coin">>, Receipt) > 0.0),
    ?assertEqual(5.0, tom_ship:aboard(maps:get(<<"ship">>, Receipt), ?MUSK)),
    ?assert(tom_market:stock(tom_port:market(), musk) < 13.0).

%% THE ONE THAT MATTERS. Kill the whole application and start it again on the
%% same directory. The receipt replays identically, so a house that never heard
%% the first answer cannot be charged twice; the cargo is still in the hold; the
%% quay is still short what was lifted off it; and genesis does NOT mint a
%% second Santa Clara over the top of the first.
survives_a_restart(Dir) ->
    Before = tom_market:stock(tom_port:market(), musk),
    {ok, First} = tom_port:buy(order(<<"boot-2">>, 3.0)),
    ok = application:stop(hecate_tom_world),
    {ok, _Again} = application:ensure_all_started(hecate_tom_world),
    ?assertEqual(Dir, os:getenv("TOM_DATA_DIR")),
    {ok, Replayed} = tom_port:buy(order(<<"boot-2">>, 3.0)),
    ?assertEqual(First, Replayed),
    {ok, Berth} = tom_port:berth(#{<<"ship">> => ?CLARA}),
    Hull = maps:get(<<"ship">>, Berth),
    ?assertEqual(8.0, tom_ship:aboard(Hull, ?MUSK)),
    ?assertEqual(0, tom_ship:hop(Hull)),
    ?assert(near(tom_market:stock(tom_port:market(), musk), Before - 3.0)).

%% A hull at sea is still frozen after a restart, still this port's custody at
%% the old hop, and back at sea with the leg she has left. It never
%% un-consigns on its own initiative, because the receiver may already have it.
a_promise_survives_a_restart(_Dir) ->
    {ok, Sailed} = tom_port:sail(#{<<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                                   <<"bound_for">> => ?LISBON}),
    ?assertEqual(1, maps:get(<<"hop">>, Sailed)),
    ?assertMatch({error, <<"ship_consigned">>},
                 tom_port:buy(order(<<"boot-3">>, 1.0))),
    ok = application:stop(hecate_tom_world),
    {ok, _Again} = application:ensure_all_started(hecate_tom_world),
    {ok, Berth} = tom_port:berth(#{<<"ship">> => ?CLARA}),
    ?assertEqual(<<"in_passage">>, maps:get(<<"state">>, Berth)),
    ?assertEqual(?LISBON, maps:get(<<"bound_for">>, Berth)),
    %% Still at the OLD hop: a consignment is not a hop and custody has not
    %% moved. The hull the far port will be offered is one higher, and that map
    %% is built fresh from this berth every time it is retried.
    ?assertEqual(0, tom_ship:hop(maps:get(<<"ship">>, Berth))),
    ?assertMatch({error, <<"ship_consigned">>},
                 tom_port:buy(order(<<"boot-4">>, 1.0))),
    %% AND SHE IS BACK AT SEA. The berth carried her due instant and her fate
    %% across the restart, so the passage resumed with what was left of her leg
    %% and nothing was re-drawn.
    ?assertMatch([_Hull], supervisor:which_children(tom_keep_the_sea_sup)).

%% THE DESKS ARE ENTERED THROUGH `handle/1' AND NOTHING ELSE ENTERS THEM. Every
%% other test in this file calls `tom_port' directly with the binary keys the
%% contract is written in, which is exactly the shape a payload does NOT have by
%% the time it reaches a handler: macula ships a binary key as a CBOR text
%% string and atomises what it can on the way in. So these two go through the
%% mesh edge with the shape a real call has, and they are the tests that fail if
%% the fold at the edge is taken away.
%%
%% Both are chosen to move nothing: a read and a refusal. The ship is consigned
%% by the time they run, and it stays that way.
the_edge_reads_a_wire_payload() ->
    ?assertMatch({ok, #{<<"state">> := <<"in_passage">>}},
                 tom_get_ship:handle(#{{text, <<"ship">>} => ?CLARA})),
    ?assertMatch({ok, #{<<"state">> := <<"in_passage">>}},
                 tom_get_ship:handle(#{ship => ?CLARA})).

%% A REFUSAL'S REASON HAS TO SURVIVE, and `{error, Binary}' does not carry one:
%% macula renders it into a BOLT#4 frame's `detail' and the SDK's caller path
%% reads only the code, so every refusal arrives at a house as the same value.
%% The reason rides in a reply instead.
the_edge_answers_with_a_reason() ->
    Stranger = <<"mri:instance:io.macula/tom/ship/nao_da_prata">>,
    ?assertEqual({ok, #{<<"refused">> => <<"not_here">>}},
                 tom_buy_cargo:handle(
                   #{{text, <<"order">>} => <<"boot-edge">>,
                     by => ?HOUSE,
                     {text, <<"ship">>} => Stranger,
                     good => ?MUSK,
                     {text, <<"quantity">>} => 1.0})).

%% Helpers

order(Key, Quantity) ->
    #{<<"order">> => Key, <<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
      <<"good">> => ?MUSK, <<"quantity">> => Quantity}.

near(A, B) -> abs(A - B) =< 1.0e-9 * max(abs(A), abs(B)).
