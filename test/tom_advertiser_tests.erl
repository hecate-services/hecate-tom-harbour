%% @doc The port's public surface, which is a list and must stay one.
%%
%% NO ENVIRONMENT AND NO PROCESSES. `procedures/0' is a literal, so what this
%% harbour answers to can be asserted by calling it, with no port open, no
%% station dialled and no TOM_HARBOUR set.
%% @end
-module(tom_advertiser_tests).

-include_lib("eunit/include/eunit.hrl").

%% A HARBOUR IS INFRASTRUCTURE AND HAS NO SAY IN WHETHER A SHIP TURNS UP. It
%% does not accept her, it receives her, and she is this port's from the moment
%% the sea says so. So there is no door to knock at any more: `receive_ship' is
%% a desk this port enters by itself, off the sea's announcement and off its own
%% catch-up ask, and it is not a procedure a stranger can call.
%%
%% The two halves of the deletion are asserted together on purpose. Leaving the
%% handler exported while dropping the advertisement would leave a live entry
%% point nothing calls and nothing tests, which is exactly the shape of code
%% that comes back.
a_port_no_longer_answers_a_knock_test() ->
    Named = [Name || {Name, _Handler} <- tom_advertiser:procedures()],
    ?assertNot(lists:member(<<"receive_ship">>, Named)),
    ?assertNot(lists:member({handle, 1},
                            tom_receive_ship:module_info(exports))).

%% SEVEN, AND EVERY ONE OF THEM ANSWERED BY A DESK IN THIS REPOSITORY. The
%% capability list the service announces is built from this one, so a procedure
%% that appears here without a desk is a promise made to the mesh that nothing
%% keeps.
a_procedure_has_a_desk_behind_it_test() ->
    Procedures = tom_advertiser:procedures(),
    ?assertEqual(7, length(Procedures)),
    ?assertEqual([<<"buy_cargo">>, <<"commission_ship">>, <<"get_ship">>,
                  <<"list_quotes">>, <<"quote_purchase">>, <<"sail_ship">>,
                  <<"sell_cargo">>],
                 lists:sort([Name || {Name, _H} <- Procedures])),
    [?assert(lists:member({Function, 1}, Module:module_info(exports)))
     || {_Name, {Module, Function}} <- Procedures].
