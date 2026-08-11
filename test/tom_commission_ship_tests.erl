-module(tom_commission_ship_tests).

-include_lib("eunit/include/eunit.hrl").

-define(HARBOUR, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(RAF, <<"mri:instance:io.macula/tom/house/raf">>).
-define(SOMEBODY_ELSE, <<"mri:instance:io.macula/tom/house/other">>).
-define(WRECK, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(NEW, <<"mri:instance:io.macula/tom/ship/santa_clara_ii">>).

empty_port() ->
    #{harbour => ?HARBOUR, realm => <<"io.macula">>, ships => #{}}.

port_holding(Ship, Owner) ->
    Hull = #{<<"ship">> => Ship, <<"owner">> => Owner, <<"hold">> => 200.0,
             <<"cargo">> => #{}, <<"hop">> => 0, <<"custodian">> => ?HARBOUR},
    (empty_port())#{ships => #{Ship => #{ship => Hull, state => moored,
                                         bound_for => undefined, hop => 0,
                                         since => 1}}}.

%% The desk is handed the port clock, which is a map and not an instant.
ask(State, Payload) ->
    tom_commission_ship:at(State, Payload, #{tick => 1, at => 1786530000000}).

%% A house whose ship went down takes up another hull and carries on. Before
%% this a loss was terminal, and a game that can only end in a dead stop leaves
%% a player holding a broken toy rather than a defeat.
a_house_with_no_ship_gets_one_test() ->
    {{ok, Reply}, _State, Effects} =
        ask(empty_port(), #{<<"house">> => ?RAF, <<"ship">> => ?NEW}),
    ?assertEqual(true, maps:get(<<"commissioned">>, Reply)),
    Hull = maps:get(<<"ship">>, Reply),
    ?assertEqual(?RAF, tom_ship:owner(Hull)),
    ?assertEqual(?NEW, tom_ship:id(Hull)),
    ?assertEqual(#{}, tom_ship:cargo(Hull)),
    ?assertEqual(0, tom_ship:hop(Hull)),
    %% On the disk and on the mesh, in that order.
    ?assertMatch([{record, {took_ship, ?NEW, 0, _, <<"commissioned">>, _}},
                  {cry, _Topic, _Payload}], Effects).

%% She arrives empty and afloat, and she is a ship by the same predicate that
%% guards genesis, so nothing downstream has to special-case a replacement.
a_commissioned_hull_is_a_ship_test() ->
    {{ok, Reply}, _S, _E} =
        ask(empty_port(), #{<<"house">> => ?RAF, <<"ship">> => ?NEW}),
    ?assert(tom_ship:is_ship(maps:get(<<"ship">>, Reply))).

%% ONE HULL PER HOUSE AT THIS QUAY. It is the only double mint a port is in a
%% position to refuse, because it cannot see what a house holds elsewhere.
a_house_that_already_has_one_here_is_refused_test() ->
    {Answer, _S, Effects} =
        ask(port_holding(?WRECK, ?RAF),
            #{<<"house">> => ?RAF, <<"ship">> => ?NEW}),
    ?assertEqual({error, <<"you_have_a_ship_here">>}, Answer),
    ?assertEqual([], Effects).

%% ASKING TWICE IS SAFE. A retry after a lost reply must not mint a second ship,
%% so the same request comes back with the same hull and nothing recorded.
asking_again_for_the_same_hull_mints_nothing_test() ->
    {{ok, Reply}, _S, Effects} =
        ask(port_holding(?NEW, ?RAF),
            #{<<"house">> => ?RAF, <<"ship">> => ?NEW}),
    ?assertEqual(false, maps:get(<<"commissioned">>, Reply)),
    ?assertEqual(?NEW, tom_ship:id(maps:get(<<"ship">>, Reply))),
    ?assertEqual([], Effects).

%% And a house cannot take up a hull under a name somebody else is using.
a_name_another_house_holds_is_refused_test() ->
    {Answer, _S, Effects} =
        ask(port_holding(?NEW, ?SOMEBODY_ELSE),
            #{<<"house">> => ?RAF, <<"ship">> => ?NEW}),
    ?assertEqual({error, <<"name_taken">>}, Answer),
    ?assertEqual([], Effects).

a_request_missing_its_parts_is_refused_test() ->
    [?assertMatch({{error, _}, _S, []}, ask(empty_port(), Payload))
     || Payload <- [#{}, #{<<"house">> => ?RAF}, #{<<"ship">> => ?NEW}]],
    ok.

%% A request that forgot to say how big gets the hold every hull in this game
%% has, rather than an argument about it or a ship with no capacity.
a_hull_with_no_stated_capacity_gets_the_usual_one_test() ->
    {{ok, Reply}, _S, _E} =
        ask(empty_port(), #{<<"house">> => ?RAF, <<"ship">> => ?NEW}),
    ?assertEqual(200.0, tom_ship:hold(maps:get(<<"ship">>, Reply))),
    {{ok, Bigger}, _S2, _E2} =
        ask(empty_port(), #{<<"house">> => ?RAF, <<"ship">> => ?NEW,
                            <<"hold">> => 350}),
    ?assertEqual(350.0, tom_ship:hold(maps:get(<<"ship">>, Bigger))).
