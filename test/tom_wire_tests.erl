%% @doc The wire discipline and the hull, both of which are pure.
%% @end
-module(tom_wire_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REALM, <<"io.macula">>).
-define(MACAO, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(HOUSE, <<"mri:instance:io.macula/tom/house/raf">>).
-define(CLARA, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(MUSK, <<"mri:class:io.macula/tom/good/musk">>).

%% Names ---------------------------------------------------------------

%% The class and the instance of a harbour both exist and mean different
%% things. Macao the place is reference data somebody else owns; Macao the
%% service is a process on a box that answers calls.
an_instance_is_not_a_class_test() ->
    ?assertEqual(?MACAO, tom_wire:instance(?REALM, <<"harbour">>, <<"macao">>)),
    ?assertEqual(?CLARA, tom_wire:instance(?REALM, <<"ship">>,
                                           <<"santa_clara">>)),
    ?assertEqual(instance, macula_mri:type(tom_wire:instance(?REALM,
                                                             <<"harbour">>,
                                                             <<"macao">>))),
    ?assertEqual(class,
                 macula_mri:type(<<"mri:class:io.macula/tom/harbour/macao">>)).

%% A CALL HAS TO REACH ONE HARBOUR. macula:call is first-success across a
%% pool's links and both ports advertise buy_cargo, so a name that did not carry
%% the harbour would hand a Macao order to Lisbon.
a_procedure_carries_the_harbour_test() ->
    ?assertEqual(<<"io.macula/tom/harbour/macao.buy_cargo">>,
                 tom_wire:procedure(?MACAO, <<"buy_cargo">>)),
    ?assertNotEqual(tom_wire:procedure(?MACAO, <<"buy_cargo">>),
                    tom_wire:procedure(
                      <<"mri:instance:io.macula/tom/harbour/lisbon">>,
                      <<"buy_cargo">>)).

%% AND A FACT CARRIES NO IDENTIFIER AT ALL. The harbour, the ship and the good
%% live in the payload, so a house watching a voyage subscribes to four topics
%% rather than four times the number of ports.
a_fact_carries_no_identifier_test() ->
    Topics = [tom_wire:fact(?REALM, Domain, Name)
              || {Domain, Name} <- [{<<"trade">>, <<"cargo_loaded">>},
                                    {<<"trade">>, <<"cargo_discharged">>},
                                    {<<"custody">>, <<"ship_moored">>},
                                    {<<"custody">>, <<"ship_consigned">>}]],
    ?assertEqual([<<"io.macula/tom/harbour/trade/cargo_loaded_v1">>,
                  <<"io.macula/tom/harbour/trade/cargo_discharged_v1">>,
                  <<"io.macula/tom/harbour/custody/ship_moored_v1">>,
                  <<"io.macula/tom/harbour/custody/ship_consigned_v1">>],
                 Topics),
    [?assertEqual(nomatch, binary:match(Topic, <<"macao">>))
     || Topic <- Topics].

%% A PARSE AND NOT A LOOKUP. Nagasaki is accepted although this port has never
%% heard of it; the ocean, a house, a class and a bare word are not, because
%% none of them is shaped like a harbour that might exist.
a_destination_is_parsed_not_looked_up_test() ->
    ?assert(tom_wire:is_harbour(?MACAO)),
    ?assert(tom_wire:is_harbour(
              <<"mri:instance:io.macula/tom/harbour/nagasaki">>)),
    [?assertNot(tom_wire:is_harbour(Not))
     || Not <- [?HOUSE, ?CLARA, <<"mri:instance:io.macula/tom/ocean">>,
                <<"mri:class:io.macula/tom/harbour/macao">>,
                <<"lisbon">>, <<>>, undefined, 42]].

%% Reading -------------------------------------------------------------

%% Liberal about what is missing, strict about what a field must be. A number
%% where a name belongs is not a name, and a name where a number belongs is not
%% a number, so a payload from a stranger cannot walk a wrong type inwards.
a_field_is_what_it_says_or_it_is_missing_test() ->
    Payload = #{<<"good">> => ?MUSK, <<"quantity">> => 40, <<"goods">> => [],
                <<"bad">> => not_a_binary},
    ?assertEqual(?MUSK, tom_wire:text(<<"good">>, Payload)),
    ?assertEqual(undefined, tom_wire:text(<<"bad">>, Payload)),
    ?assertEqual(undefined, tom_wire:text(<<"absent">>, Payload)),
    ?assertEqual(40.0, tom_wire:number(<<"quantity">>, Payload)),
    ?assert(is_float(tom_wire:number(<<"quantity">>, Payload))),
    ?assertEqual(undefined, tom_wire:number(<<"good">>, Payload)),
    ?assertEqual([], tom_wire:list(<<"goods">>, Payload)),
    ?assertEqual([], tom_wire:list(<<"absent">>, Payload)),
    ?assertEqual(undefined, tom_wire:text(<<"good">>, not_a_map)).

%% The hull ------------------------------------------------------------

%% A GOOD AT NOUGHT IS NOT IN THE HOLD. It leaves the map rather than sitting
%% there as a zero, or a hull grows a line every time anything is sold out of
%% it and the free space arithmetic starts summing rows that are not there.
a_good_that_runs_out_leaves_the_hold_test() ->
    Hull = hull(),
    Laden = tom_ship:load(Hull, ?MUSK, 40.0),
    ?assertEqual(40.0, tom_ship:aboard(Laden, ?MUSK)),
    ?assertEqual(160.0, tom_ship:free(Laden)),
    Part = tom_ship:unload(Laden, ?MUSK, 15.0),
    ?assertEqual(25.0, tom_ship:aboard(Part, ?MUSK)),
    Empty = tom_ship:unload(Laden, ?MUSK, 40.0),
    ?assertEqual(#{}, tom_ship:cargo(Empty)),
    ?assertEqual(0.0, tom_ship:aboard(Empty, ?MUSK)),
    ?assertEqual(200.0, tom_ship:free(Empty)).

%% THE HULL AS IT WILL BE ONCE THE RECEIVER HAS IT. The sender writes the
%% future and the receiver's acceptance makes it so, which is why a retry is
%% byte for byte the same call.
consigning_writes_the_hull_as_it_will_be_test() ->
    Hull = hull(),
    Ocean = <<"mri:instance:io.macula/tom/ocean">>,
    Handed = tom_ship:consign(Hull, Ocean),
    ?assertEqual(tom_ship:hop(Hull) + 1, tom_ship:hop(Handed)),
    ?assertEqual(Ocean, tom_ship:custodian(Handed)),
    ?assertEqual(tom_ship:owner(Hull), tom_ship:owner(Handed)),
    ?assertEqual(tom_ship:cargo(Hull), tom_ship:cargo(Handed)),
    ?assertEqual(Handed, tom_ship:consign(Hull, Ocean)).

%% What a receiver will take custody of, and what it will not. Every field is
%% required, because a hull with no hop cannot be counted and one with no hold
%% cannot be loaded, and inventing either is how a ship comes to exist twice.
a_hull_is_checked_before_it_is_taken_test() ->
    ?assert(tom_ship:is_ship(hull())),
    ?assert(tom_ship:is_ship(tom_ship:load(hull(), ?MUSK, 1.0))),
    [?assertNot(tom_ship:is_ship(Not))
     || Not <- [#{}, <<"clara">>, undefined, 42,
                maps:remove(<<"hop">>, hull()),
                maps:remove(<<"owner">>, hull()),
                maps:remove(<<"cargo">>, hull()),
                (hull())#{<<"hold">> => 0.0},
                (hull())#{<<"hold">> => <<"big">>},
                (hull())#{<<"hop">> => -1},
                (hull())#{<<"hop">> => 1.5},
                (hull())#{<<"cargo">> => #{?MUSK => -1.0}},
                (hull())#{<<"cargo">> => #{musk => 1.0}}]].

%% Off the wire ---------------------------------------------------------
%%
%% WHAT A SENDER WROTE IS NOT WHAT A RECEIVER GETS. macula ships a binary key as
%% a CBOR text string and then runs binary_to_existing_atom over it on the way
%% in, so a key whose name is already in this node's atom table arrives as an
%% ATOM and one whose name is not arrives as {text, Binary}. Both shapes turn up
%% in one payload, and which one a given key takes depends on what this node has
%% loaded rather than on what was sent.
%%
%% The shapes below were taken from a real handler answering a real call through
%% a real station, not imagined.
a_payload_off_the_wire_has_binary_keys_again_test() ->
    Wire = #{good => ?MUSK,                                %% atom key
             {text, <<"quantity">>} => 40.0,               %% text key
             {text, <<"order">>} => <<"5f2c1a">>,
             hop => 5},
    ?assertEqual(#{<<"good">> => ?MUSK,
                   <<"quantity">> => 40.0,
                   <<"order">> => <<"5f2c1a">>,
                   <<"hop">> => 5},
                 tom_wire:accept(Wire)).

%% A hull arrives inside a handover and its own keys took the same beating, so a
%% fold that stopped at the top level would hand tom_ship a map it cannot read
%% and every well-formed handover in the game would answer malformed_ship.
a_hull_inside_a_handover_is_reached_too_test() ->
    Wire = #{{text, <<"from">>} => ?MACAO,
             ship => #{{text, <<"ship">>} => ?CLARA,
                       owner => ?HOUSE,
                       {text, <<"hold">>} => 200.0,
                       cargo => #{?MUSK => 40.0},
                       hop => 5,
                       {text, <<"custodian">>} => ?MACAO}},
    Accepted = tom_wire:accept(Wire),
    ?assert(tom_ship:is_ship(maps:get(<<"ship">>, Accepted))),
    ?assertEqual(?MACAO, maps:get(<<"from">>, Accepted)),
    ?assertEqual(#{?MUSK => 40.0},
                 tom_ship:cargo(maps:get(<<"ship">>, Accepted))).

%% VALUES ARE NOT KEYS. `true' is what a receiver said and `undefined' is what
%% a sender left out, and turning either into a binary would lose the answer.
%% A quantity stays a float and an MRI stays a binary, both of which the codec
%% already carries whole.
accepting_a_payload_leaves_its_values_alone_test() ->
    ?assertEqual(#{<<"held">> => true, <<"hop">> => 5, <<"price">> => 12.9155,
                   <<"harbour">> => ?MACAO, <<"bound_for">> => undefined,
                   <<"quotes">> => [#{<<"good">> => ?MUSK}]},
                 tom_wire:accept(#{held => true,
                                   {text, <<"hop">>} => 5,
                                   price => 12.9155,
                                   {text, <<"harbour">>} => ?MACAO,
                                   bound_for => undefined,
                                   quotes => [#{good => ?MUSK}]})).

%% NOT ONE ATOM IS MINTED. Everything here goes the other way, from an atom the
%% decoder already had to a binary, so nothing a stranger sends can walk the
%% atom table until the node dies.
accepting_a_payload_mints_no_atom_test() ->
    Before = erlang:system_info(atom_count),
    _ = tom_wire:accept(#{{text, <<"a_name_no_module_in_this_release_uses">>}
                          => <<"x">>}),
    ?assertEqual(Before, erlang:system_info(atom_count)).

%% A refusal's reason -------------------------------------------------------
%%
%% `{error, Binary}' DOES NOT CARRY ITS REASON ACROSS. macula turns it into a
%% BOLT#4 frame with code 0x0F, renders the reason into the frame's `detail',
%% and the SDK's caller path reads only the code. quay_empty, hold_full,
%% not_here and the rest all arrive at a house as one indistinguishable value.
%% So a refusal travels as a reply, which is the shape the wire keeps whole.
a_refusal_travels_as_a_reply_test() ->
    ?assertEqual({ok, #{<<"refused">> => <<"hold_full">>}},
                 tom_wire:answer({error, <<"hold_full">>})),
    ?assertEqual({ok, #{<<"refused">> => <<"not_yours">>}},
                 tom_wire:answer({error, <<"not_yours">>})).

%% And a receipt is untouched, because a reply that already said yes has nothing
%% to translate and a wrapper around it would be a second shape to read.
an_answer_that_said_yes_is_left_alone_test() ->
    Receipt = #{<<"order">> => <<"5f2c1a">>, <<"coin">> => 581.42},
    ?assertEqual({ok, Receipt}, tom_wire:answer({ok, Receipt})).

hull() ->
    #{<<"ship">> => ?CLARA, <<"owner">> => ?HOUSE, <<"hold">> => 200.0,
      <<"cargo">> => #{}, <<"hop">> => 4, <<"custodian">> => ?MACAO}.
