%% @doc The port's public surface, which is a list and must stay one.
%%
%% NO ENVIRONMENT AND NO PROCESSES. `procedures/0' is a literal, so what this
%% harbour answers to can be asserted by calling it, with no port open, no
%% station dialled and no TOM_HARBOUR set.
%% @end
-module(tom_advertiser_tests).

-include_lib("eunit/include/eunit.hrl").

%% THE KNOCK IS BACK, AND IT IS NOT A REGRESSION. This test asserted the
%% opposite for one day. It was right then: the sea announced a landfall and
%% this port went and asked for it, so a door would have been a third way in.
%%
%% DECISIONS.md called this on 2026-08-11, before the ocean was dissolved: "The
%% knocking comes back with it, and that is not a regression. It was ugly as a
%% worker pool the sea ran per undelivered landfall, and ugly again as an outbox
%% with a cursor and a taken flag, because in both shapes a delivery obligation
%% was a side table on a central actor. As the ship's own behaviour there is no
%% side table, because there is nothing beside her."
%%
%% A HARBOUR STILL HAS NO SAY IN WHETHER A SHIP TURNS UP. The desk cannot refuse
%% a well-formed hull, answers held to a repeat, and is idempotent on the ship
%% and the hop. What is advertised is a door, not a vote.
a_port_answers_a_knock_from_another_port_test() ->
    Named = [Name || {Name, _Handler} <- tom_advertiser:procedures()],
    ?assert(lists:member(<<"receive_ship">>, Named)),
    ?assert(lists:member({handle, 1},
                         tom_receive_ship:module_info(exports))).

%% EIGHT, AND EVERY ONE OF THEM ANSWERED BY A DESK IN THIS REPOSITORY. The
%% capability list the service announces is built from this one, so a procedure
%% that appears here without a desk is a promise made to the mesh that nothing
%% keeps.
a_procedure_has_a_desk_behind_it_test() ->
    Procedures = tom_advertiser:procedures(),
    ?assertEqual(8, length(Procedures)),
    ?assertEqual([<<"buy_cargo">>, <<"commission_ship">>, <<"get_ship">>,
                  <<"list_quotes">>, <<"quote_purchase">>, <<"receive_ship">>,
                  <<"sail_ship">>, <<"sell_cargo">>],
                 lists:sort([Name || {Name, _H} <- Procedures])),
    [?assert(lists:member({Function, 1}, Module:module_info(exports)))
     || {_Name, {Module, Function}} <- Procedures].
