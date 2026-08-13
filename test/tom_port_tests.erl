%% @doc The desks, tested by calling them.
%%
%% Every desk is a function from this port's state and one payload to a reply, a
%% new state and a list of things the world must do, so there is no process to
%% start, no mesh to fake and no clock to wait for. What tom_port adds is a
%% queue, a disk and a socket, and none of those change an answer.
%%
%% The state below is built from the SHIPPED standing for Macao, so these tests
%% also say that the file in priv is loadable and opens a market.
%% @end
-module(tom_port_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REALM, <<"io.macula">>).
-define(MACAO, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(LISBON, <<"mri:instance:io.macula/tom/harbour/lisbon">>).
-define(OCEAN, <<"mri:instance:io.macula/tom/ocean">>).
-define(HOUSE, <<"mri:instance:io.macula/tom/house/raf">>).
-define(STRANGER, <<"mri:instance:io.macula/tom/house/mendes">>).
-define(CLARA, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(MUSK, <<"mri:class:io.macula/tom/good/musk">>).
-define(NUTMEG, <<"mri:class:io.macula/tom/good/nutmeg">>).
-define(SAFFRON, <<"mri:class:io.macula/tom/good/saffron">>).

%% The shipped Macao ---------------------------------------------------

%% Reading the standing out of priv is the point: a test that invented its own
%% would pass while the file an operator actually deploys was unreadable.
standing() ->
    {ok, Standing} = file:consult(filename:join([code:priv_dir(hecate_tom_world),
                                                 "harbours", "macao.standing"])),
    hd(Standing).

port() -> port(#{}).

port(Ships) -> port(Ships, macao).

%% THE REAL WORLD, NOT A FIXTURE OF ONE. A passage asks the map how far it is
%% and refuses a pair of ports with no line between them, so a made-up world
%% here would be testing a map nobody sails. Macao to Lisbon is a real route of
%% 4,586 leagues and that is what these tests cross.
port(Ships, Place) ->
    Standing = standing(),
    {ok, Market} = tom_market:open(Standing),
    {ok, World} = tom_world:load_default(),
    {Goods, Names} = tom_standing:goods_index(?REALM, Standing),
    #{harbour => ?MACAO, realm => ?REALM, world => World, place => Place,
      market => Market, goods => Goods, names => Names, tick_ms => 10000,
      ships => Ships, receipts => #{}, taken => #{}, log => no_disk_in_a_test}.

clara() ->
    #{<<"ship">> => ?CLARA, <<"owner">> => ?HOUSE, <<"hold">> => 200.0,
      <<"cargo">> => #{}, <<"hop">> => 4, <<"custodian">> => ?MACAO}.

moored(Hull) ->
    #{tom_ship:id(Hull) => #{ship => Hull, state => moored,
                             bound_for => undefined, hop => tom_ship:hop(Hull),
                             since => 1000}}.

now_at() -> #{tick => 178652880, at => 1786528800000}.

order(Key, Good, Quantity) ->
    #{<<"order">> => Key, <<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
      <<"good">> => Good, <<"quantity">> => Quantity}.

%% The shipped standing ------------------------------------------------

%% The two files in priv are what makes this service runnable rather than
%% merely buildable, and they carry the worked example's own numbers, so a
%% price drifting here is a price drifting in the mechanism.
the_shipped_ports_open_and_reproduce_the_worked_example_test() ->
    {ok, Macao} = tom_market:open(standing()),
    {ok, [Lisbon0]} = file:consult(
                        filename:join([code:priv_dir(hecate_tom_world),
                                       "harbours", "lisbon.standing"])),
    {ok, Lisbon} = tom_market:open(Lisbon0),
    ?assert(near(tom_market:natural_price(Macao, musk), 12.915496650148841)),
    ?assert(near(tom_market:natural_price(Lisbon, musk), 172.89949919329271)),
    ?assert(near(tom_market:natural_price(Macao, cannon), 77.222605247318967)),
    ?assert(tom_market:natural_price(Lisbon, nutmeg)
            > tom_market:natural_price(Macao, nutmeg)).

%% Every good this port trades has a name on the mesh and resolves back to
%% exactly one local id, which is what lets a name off the wire be matched
%% instead of turned into an atom.
every_good_has_a_name_and_resolves_back_test() ->
    #{goods := Goods, names := Names} = port(),
    ?assertEqual(maps:size(Goods), maps:size(Names)),
    ?assertEqual(musk, maps:get(?MUSK, Goods)),
    ?assertEqual(?MUSK, maps:get(musk, Names)),
    ?assertEqual(error, maps:find(?SAFFRON, Goods)).

%% Quoting -------------------------------------------------------------

%% An empty list means everything this port trades. A named list is filtered,
%% and a good this port does not trade is OMITTED rather than refused, because a
%% peer knowing goods we do not is not a fault.
list_quotes_omits_what_it_does_not_trade_test() ->
    {{ok, All}, _S1, []} = tom_list_quotes:at(port(), #{<<"goods">> => []},
                                              now_at()),
    {{ok, Some}, _S2, []} = tom_list_quotes:at(
                              port(), #{<<"goods">> => [?MUSK, ?SAFFRON]},
                              now_at()),
    ?assertEqual(?MACAO, maps:get(<<"harbour">>, All)),
    ?assertEqual(8, length(maps:get(<<"quotes">>, All))),
    ?assertMatch([#{<<"good">> := ?MUSK}], maps:get(<<"quotes">>, Some)),
    [Musk] = maps:get(<<"quotes">>, Some),
    ?assert(near(maps:get(<<"price">>, Musk), 12.915496650148841)),
    ?assert(maps:get(<<"stock">>, Musk) > 0.0).

%% THE REASON THIS DESK EXISTS. A trade pays the prices it walked through, so
%% five musk cost 14.65 apiece against a posted 12.92 and a house that
%% multiplied would commit its purse to the wrong number.
quote_purchase_is_more_than_spot_times_quantity_test() ->
    State = port(),
    {{ok, Quoted}, Same, []} = tom_quote_purchase:at(
                                 State, #{<<"good">> => ?MUSK,
                                          <<"quantity">> => 5.0}, now_at()),
    Spot = tom_market:quote(maps:get(market, State), musk),
    ?assert(maps:get(<<"coin">>, Quoted) > Spot * 5.0),
    ?assert(near(maps:get(<<"coin">>, Quoted), 73.26451395643261)),
    ?assert(maps:get(<<"price_after">>, Quoted) > Spot),
    ?assertEqual(maps:get(market, State), maps:get(market, Same)).

quote_purchase_refuses_what_it_cannot_price_test() ->
    State = port(),
    ?assertMatch({{error, <<"unknown_good">>}, _S, []},
                 tom_quote_purchase:at(State, #{<<"good">> => ?SAFFRON,
                                                <<"quantity">> => 1.0},
                                       now_at())),
    ?assertMatch({{error, <<"bad_quantity">>}, _S, []},
                 tom_quote_purchase:at(State, #{<<"good">> => ?MUSK,
                                                <<"quantity">> => <<"lots">>},
                                       now_at())).

%% Buying --------------------------------------------------------------

%% THE WHOLE OF REQUIREMENT ONE IN ONE CALL. The goods leave the quay and enter
%% the hold in one act, the price moves, and what crosses the wire afterwards is
%% a receipt.
buying_moves_the_goods_from_the_quay_into_the_hold_test() ->
    Before = port(moored(clara())),
    Was = tom_market:stock(maps:get(market, Before), musk),
    {{ok, Receipt}, After, Effects} =
        tom_buy_cargo:at(Before, order(<<"a1">>, ?MUSK, 5.0), now_at()),
    ?assertEqual(5.0, maps:get(<<"filled">>, Receipt)),
    ?assert(near(maps:get(<<"coin">>, Receipt), 73.26451395643261)),
    ?assertEqual(5.0, tom_ship:aboard(maps:get(<<"ship">>, Receipt), ?MUSK)),
    ?assert(near(tom_market:stock(maps:get(market, After), musk), Was - 5.0)),
    ?assert(maps:get(<<"price_after">>, Receipt)
            > tom_market:quote(maps:get(market, Before), musk)),
    ?assertMatch([{record, {settled_order, <<"a1">>, ?MUSK, _R}},
                  {cry, _Topic, _Fact}], Effects).

%% IDEMPOTENT ON THE ORDER, AND THE REPLAY COMES FIRST. A house that died before
%% it heard the answer re-sends the same key and gets the same receipt, and the
%% quay does not move a second time.
buying_twice_on_one_order_fills_once_test() ->
    {{ok, First}, Once, _E1} = tom_buy_cargo:at(port(moored(clara())),
                                                order(<<"a1">>, ?MUSK, 5.0),
                                                now_at()),
    {{ok, Again}, Twice, Effects} = tom_buy_cargo:at(Once,
                                                     order(<<"a1">>, ?MUSK, 5.0),
                                                     now_at()),
    ?assertEqual(First, Again),
    ?assertEqual([], Effects),
    ?assertEqual(tom_market:stock(maps:get(market, Once), musk),
                 tom_market:stock(maps:get(market, Twice), musk)).

%% AND A REPLAY OUTLIVES THE SHIP. The hull has sailed and the order is still
%% answerable, because the house asking is the one that never heard the answer.
a_replay_is_answered_after_the_ship_has_gone_test() ->
    {{ok, First}, Loaded, _E} = tom_buy_cargo:at(port(moored(clara())),
                                                 order(<<"a1">>, ?MUSK, 5.0),
                                                 now_at()),
    Gone = Loaded#{ships := #{}},
    ?assertMatch({{ok, First}, _S, []},
                 tom_buy_cargo:at(Gone, order(<<"a1">>, ?MUSK, 5.0), now_at())).

%% The hold is checked whole: a hull with room for forty asked to take eighty is
%% refused rather than filled halfway, because a half-filled order is a second
%% thing for a house to reconcile.
buying_more_than_the_hold_takes_is_refused_whole_test() ->
    Small = (clara())#{<<"hold">> => 3.0},
    ?assertMatch({{error, <<"hold_full">>}, _S, []},
                 tom_buy_cargo:at(port(moored(Small)),
                                  order(<<"a1">>, ?MUSK, 5.0), now_at())).

%% A hull this port does not hold, one that is not the caller's, and a good this
%% port does not trade. Three different answers, because a house that gets one
%% word back has to know which of the three to fix.
buying_names_exactly_what_was_wrong_test() ->
    Held = port(moored(clara())),
    ?assertMatch({{error, <<"not_here">>}, _A, []},
                 tom_buy_cargo:at(port(), order(<<"a1">>, ?MUSK, 5.0),
                                  now_at())),
    ?assertMatch({{error, <<"not_yours">>}, _B, []},
                 tom_buy_cargo:at(Held, (order(<<"a1">>, ?MUSK, 5.0))#{
                                          <<"by">> => ?STRANGER}, now_at())),
    ?assertMatch({{error, <<"unknown_good">>}, _C, []},
                 tom_buy_cargo:at(Held, order(<<"a1">>, ?SAFFRON, 5.0),
                                  now_at())),
    ?assertMatch({{error, <<"bad_quantity">>}, _D, []},
                 tom_buy_cargo:at(Held, order(<<"a1">>, ?MUSK, -5.0),
                                  now_at())),
    ?assertMatch({{error, <<"bad_order">>}, _E, []},
                 tom_buy_cargo:at(Held, maps:remove(<<"order">>,
                                                    order(<<"a1">>, ?MUSK, 5.0)),
                                  now_at())).

%% Selling -------------------------------------------------------------

selling_moves_the_goods_out_of_the_hold_onto_the_quay_test() ->
    Laden = tom_ship:load(clara(), ?NUTMEG, 40.0),
    Before = port(moored(Laden)),
    Was = tom_market:stock(maps:get(market, Before), nutmeg),
    {{ok, Receipt}, After, Effects} =
        tom_sell_cargo:at(Before, order(<<"b1">>, ?NUTMEG, 40.0), now_at()),
    ?assertEqual(40.0, maps:get(<<"discharged">>, Receipt)),
    ?assert(maps:get(<<"coin">>, Receipt) > 0.0),
    ?assertEqual(0.0, tom_ship:aboard(maps:get(<<"ship">>, Receipt), ?NUTMEG)),
    ?assertEqual(#{}, tom_ship:cargo(maps:get(<<"ship">>, Receipt))),
    ?assert(near(tom_market:stock(maps:get(market, After), nutmeg), Was + 40.0)),
    ?assert(maps:get(<<"price_after">>, Receipt)
            < tom_market:quote(maps:get(market, Before), nutmeg)),
    ?assertMatch([{record, {settled_order, <<"b1">>, ?NUTMEG, _R}},
                  {cry, _Topic, _Fact}], Effects).

selling_what_is_not_aboard_is_refused_test() ->
    Laden = tom_ship:load(clara(), ?NUTMEG, 10.0),
    ?assertMatch({{error, <<"not_in_hold">>}, _S, []},
                 tom_sell_cargo:at(port(moored(Laden)),
                                   order(<<"b1">>, ?NUTMEG, 40.0), now_at())),
    ?assertMatch({{error, <<"not_in_hold">>}, _T, []},
                 tom_sell_cargo:at(port(moored(clara())),
                                   order(<<"b1">>, ?MUSK, 1.0), now_at())).

%% A ROUND TRIP LOSES THE FEE AND NOTHING ELSE, which is what stops a player
%% turning patience into money by walking in and out of one quay.
buying_and_selling_the_same_lot_back_loses_only_the_fee_test() ->
    {{ok, Bought}, Loaded, _E1} = tom_buy_cargo:at(port(moored(clara())),
                                                   order(<<"a1">>, ?MUSK, 5.0),
                                                   now_at()),
    {{ok, Sold}, _Back, _E2} = tom_sell_cargo:at(Loaded,
                                                 order(<<"b1">>, ?MUSK, 5.0),
                                                 now_at()),
    Paid = maps:get(<<"coin">>, Bought),
    Got = maps:get(<<"coin">>, Sold),
    ?assert(Got < Paid),
    ?assert(abs((Paid - Got) / Paid - 2 * 0.02 / 1.02) < 1.0e-12).

%% Sailing -------------------------------------------------------------

%% THE FREEZE IS THE WHOLE POINT OF A CONSIGNMENT. Custody has not moved and
%% this port is still the custodian at the old hop, but nothing can be bought
%% into the hull, sold out of it or promised to anybody else.
sailing_freezes_the_ship_and_sends_her_to_sea_test() ->
    {{ok, Reply}, After, Effects} =
        tom_sail_ship:at(port(moored(clara())),
                         #{<<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                           <<"bound_for">> => ?LISBON}, now_at()),
    ?assertEqual(5, maps:get(<<"hop">>, Reply)),
    %% CONSIGNED TO THE FAR PORT AND NOT TO A SEA. One leg, one crossing of the
    %% wire, and a hop that means the leg rather than a count of custodians.
    ?assertEqual(?LISBON, maps:get(<<"consigned_to">>, Reply)),
    ?assertEqual(?LISBON, maps:get(<<"bound_for">>, Reply)),
    ?assert(maps:get(<<"due_at">>, Reply) > maps:get(<<"at">>, Reply)),
    ?assertMatch([{record, {consigned_ship, ?CLARA, 5, ?LISBON, _At, _Due,
                            _Fate}},
                  {cry, _Topic, _Fact},
                  {put_to_sea, ?CLARA, 5, _Due2, _Fate2, _Payload}], Effects),
    [?assertMatch({{error, <<"ship_consigned">>}, _S, []}, Refused)
     || Refused <- [tom_buy_cargo:at(After, order(<<"a1">>, ?MUSK, 1.0),
                                     now_at()),
                    tom_sell_cargo:at(After, order(<<"b1">>, ?MUSK, 1.0),
                                      now_at())]],
    ok.

%% THE HANDOVER PAYLOAD IS THE SHIP AS IT WILL BE. One hop higher, in the
%% receiver's hands, so a retry is byte for byte the same call and the receiver
%% can dedupe on the ship and the hop with no second identifier.
the_handover_payload_is_the_ship_as_it_will_be_test() ->
    {{ok, _Reply}, _After, Effects} =
        tom_sail_ship:at(port(moored(clara())),
                         #{<<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                           <<"bound_for">> => ?LISBON}, now_at()),
    [_Record, _Cry, {put_to_sea, _Ship, _Hop, _Due, _Fate, Payload}] = Effects,
    Hull = maps:get(<<"ship">>, Payload),
    ?assertEqual(5, tom_ship:hop(Hull)),
    ?assertEqual(?LISBON, tom_ship:custodian(Hull)),
    ?assertEqual(?LISBON, maps:get(<<"bound_for">>, Payload)),
    ?assertEqual(?MACAO, maps:get(<<"from">>, Payload)),
    ?assert(tom_ship:is_ship(Hull)).

%% The hull's own state is the key, so the same order twice is the same answer
%% and a different destination is refused rather than quietly re-promised.
sailing_twice_is_idempotent_and_a_new_destination_is_refused_test() ->
    {{ok, _First}, Frozen, _E} =
        tom_sail_ship:at(port(moored(clara())),
                         #{<<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                           <<"bound_for">> => ?LISBON}, now_at()),
    %% The repeat answers from the berth, which carries no due_at in its reply
    %% because it is the same promise rather than a second departure.
    ?assertMatch({{ok, #{<<"hop">> := 5}}, _S, []},
                 tom_sail_ship:at(Frozen,
                                  #{<<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                                    <<"bound_for">> => ?LISBON}, now_at())),
    ?assertMatch({{error, <<"already_bound">>}, _T, []},
                 tom_sail_ship:at(Frozen,
                                  #{<<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                                    <<"bound_for">> => ?MACAO}, now_at())).

%% A PARSE AND NOT A LOOKUP. This port has no directory, so a well-formed
%% harbour name it has never heard of is accepted and a name that is not shaped
%% like a harbour at all is not.
sailing_somewhere_that_is_not_a_harbour_is_refused_test() ->
    Sail = fun(Where) ->
                   tom_sail_ship:at(port(moored(clara())),
                                    #{<<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                                      <<"bound_for">> => Where}, now_at())
           end,
    [?assertMatch({{error, <<"bad_destination">>}, _S, []}, Sail(Where))
     || Where <- [?OCEAN, ?HOUSE, <<"lisbon">>, undefined,
                  <<"mri:class:io.macula/tom/harbour/lisbon">>]],
    ?assertMatch({{ok, _R}, _T, _E},
                 Sail(<<"mri:instance:io.macula/tom/harbour/nagasaki">>)).

%% Receiving -----------------------------------------------------------

%% THE COMMIT POINT. The record is the effect tom_port writes to the disk before
%% it answers, and the answer is held.
receiving_takes_custody_and_says_so_test() ->
    Arriving = (clara())#{<<"hop">> => 6, <<"custodian">> => ?MACAO},
    {{ok, Reply}, After, Effects} =
        tom_receive_ship:at(port(), handover(Arriving), now_at()),
    ?assertEqual(true, maps:get(<<"held">>, Reply)),
    ?assertEqual(6, maps:get(<<"hop">>, Reply)),
    ?assertMatch([{record, {took_ship, ?CLARA, 6, _Hull, ?OCEAN, _At}},
                  {cry, _Topic, _Fact}], Effects),
    ?assertMatch(#{state := moored}, maps:get(?CLARA, maps:get(ships, After))),
    ?assertEqual(6, maps:get(?CLARA, maps:get(taken, After))).

%% RULE FOUR, AND IT IS WHAT MAKES A CONSIGNER'S RETRY SAFE. A port that ever
%% took this hull at this hop or higher answers held, whether or not it still
%% has it, and writes nothing the second time.
receiving_the_same_handover_twice_is_held_and_writes_nothing_test() ->
    Arriving = (clara())#{<<"hop">> => 6, <<"custodian">> => ?MACAO},
    {{ok, First}, Once, _E} = tom_receive_ship:at(port(), handover(Arriving),
                                                  now_at()),
    {{ok, Again}, Twice, Effects} = tom_receive_ship:at(Once,
                                                        handover(Arriving),
                                                        now_at()),
    ?assertEqual(maps:get(<<"held">>, First), maps:get(<<"held">>, Again)),
    ?assertEqual(6, maps:get(<<"hop">>, Again)),
    ?assertEqual([], Effects),
    ?assertEqual(maps:get(ships, Once), maps:get(ships, Twice)).

%% AND IT ANSWERS FOR A HULL THAT HAS SINCE SAILED AGAIN, which is the case the
%% permanence is for: a consigner that was down for an hour resolves itself with
%% a retry rather than a reconciliation call nobody wrote.
receiving_answers_held_for_a_ship_long_gone_test() ->
    Arriving = (clara())#{<<"hop">> => 6, <<"custodian">> => ?MACAO},
    {{ok, _First}, Once, _E} = tom_receive_ship:at(port(), handover(Arriving),
                                                   now_at()),
    Sailed = Once#{ships := #{}},
    ?assertMatch({{ok, #{<<"held">> := true, <<"hop">> := 6}}, _S, []},
                 tom_receive_ship:at(Sailed, handover(Arriving), now_at())),
    Older = (clara())#{<<"hop">> => 5, <<"custodian">> => ?MACAO},
    ?assertMatch({{ok, #{<<"held">> := true, <<"hop">> := 5}}, _T, []},
                 tom_receive_ship:at(Sailed, handover(Older), now_at())).

%% The one thing that is not a well-formed handover. A payload that is not a
%% hull cannot be taken custody of, because there is nothing there to take.
receiving_something_that_is_not_a_ship_is_refused_test() ->
    [?assertMatch({{error, <<"malformed_ship">>}, _S, []},
                  tom_receive_ship:at(port(), #{<<"from">> => ?OCEAN,
                                                <<"ship">> => Not}, now_at()))
     || Not <- [#{}, <<"santa_clara">>, undefined,
                maps:remove(<<"hop">>, clara()),
                (clara())#{<<"hold">> => <<"big">>}]],
    ok.

%% Looking -------------------------------------------------------------

%% not_here IS AN ANSWER AND NOT AN ERROR. A port that never had the hull and
%% one that had it last week say the same true thing.
get_ship_says_which_of_three_things_is_true_test() ->
    Empty = port(),
    Held = port(moored(clara())),
    {{ok, Nowhere}, _A, []} = tom_get_ship:at(Empty, #{<<"ship">> => ?CLARA},
                                              now_at()),
    {{ok, Alongside}, _B, []} = tom_get_ship:at(Held, #{<<"ship">> => ?CLARA},
                                                now_at()),
    {{ok, _Sail}, Frozen, _E} =
        tom_sail_ship:at(Held, #{<<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                                 <<"bound_for">> => ?LISBON}, now_at()),
    {{ok, Promised}, _C, []} = tom_get_ship:at(Frozen, #{<<"ship">> => ?CLARA},
                                               now_at()),
    ?assertEqual(<<"not_here">>, maps:get(<<"state">>, Nowhere)),
    ?assertEqual(<<"moored">>, maps:get(<<"state">>, Alongside)),
    ?assertEqual(clara(), maps:get(<<"ship">>, Alongside)),
    %% SHE IS AT SEA AND THIS PORT SAYS SO, with the instant she is due, which
    %% is what lets a player who was switched off find her by asking one port.
    ?assertEqual(<<"in_passage">>, maps:get(<<"state">>, Promised)),
    ?assertEqual(?LISBON, maps:get(<<"bound_for">>, Promised)),
    ?assert(is_integer(maps:get(<<"due_at">>, Promised))),
    %% And a request with no hull named in it is a bug in the caller rather
    %% than a ship that has gone.
    ?assertMatch({{error, <<"bad_ship">>}, _D, []},
                 tom_get_ship:at(Held, #{}, now_at())),
    %% Still at the OLD hop, because a consignment is not a hop and this port is
    %% still the custodian.
    ?assertEqual(4, tom_ship:hop(maps:get(<<"ship">>, Promised))).

%% The voyage ----------------------------------------------------------

%% THE WHOLE DELIVERABLE, minus the ocean and the purse. Buy musk cheap at
%% Macao, which grows it, sail, arrive at Lisbon, which is a voyage away from
%% every producer, sell it there. Five tons cost 73.26 at Macao and two of them
%% fetch 178.20 at Lisbon, and nobody wrote either number: Macao is 12.92
%% because it grows musk and Lisbon is 172.90 because one distant harbour does.
a_cargo_bought_here_sells_for_more_at_the_far_end_test() ->
    {{ok, Bought}, Loaded, _E1} = tom_buy_cargo:at(port(moored(clara())),
                                                   order(<<"a1">>, ?MUSK, 5.0),
                                                   now_at()),
    {{ok, _Sailed}, Frozen, Effects} =
        tom_sail_ship:at(Loaded, #{<<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                                   <<"bound_for">> => ?LISBON}, now_at()),
    %% SHE CROSSES THE WIRE ONCE, Macao to Lisbon. The payload her passage will
    %% present is built at departure and is the same bytes every attempt, which
    %% is the whole of how the far port dedupes.
    [_R, _C, {put_to_sea, _S, _H, _Due, _Fate, Payload}] = Effects,
    {{ok, _Held}, Lisbon, _E2} = tom_receive_ship:at(lisbon(),
                                                     Payload#{<<"from">> =>
                                                                  ?MACAO},
                                                     now_at()),
    {{ok, Sold}, After, _E3} = tom_sell_cargo:at(Lisbon,
                                                 order(<<"b1">>, ?MUSK, 2.0),
                                                 now_at()),
    ?assert(near(maps:get(<<"coin">>, Bought), 73.26451395643261)),
    ?assert(near(maps:get(<<"coin">>, Sold), 178.20242057191592)),
    ?assert(maps:get(<<"coin">>, Sold) > maps:get(<<"coin">>, Bought) * 2.0),
    ?assertEqual(2.0, maps:get(<<"discharged">>, Sold)),
    ?assertEqual(3.0, tom_ship:aboard(maps:get(<<"ship">>, Sold), ?MUSK)),
    %% One hop, and Macao is no longer the custodian of anything.
    ?assertEqual(5, tom_ship:hop(maps:get(<<"ship">>, Sold))),
    ?assertMatch(#{state := consigned}, maps:get(?CLARA,
                                                 maps:get(ships, Frozen))),
    ?assertEqual(#{}, maps:get(ships, After#{ships := #{}})).

%% AND THE FAR END IS SHALLOW, which is the mechanism being honest rather than a
%% fault. Lisbon's musk quay holds a quarter of a ton at rest because almost no
%% musk arrives there, so its godown takes two and a half tons and no more, and
%% a trader who fills a two hundred ton hull with musk cannot sell it in one
%% visit. The fill is partial and says so.
a_shallow_quay_takes_what_it_can_and_says_what_it_took_test() ->
    Laden = tom_ship:load(clara(), ?MUSK, 5.0),
    Lisbon = (lisbon())#{ships := moored(Laden)},
    {{ok, Sold}, _After, _E} = tom_sell_cargo:at(Lisbon,
                                                 order(<<"b1">>, ?MUSK, 5.0),
                                                 now_at()),
    ?assert(near(maps:get(<<"discharged">>, Sold), 2.5448518478434186)),
    ?assert(maps:get(<<"discharged">>, Sold) < 5.0),
    ?assert(tom_ship:aboard(maps:get(<<"ship">>, Sold), ?MUSK) > 2.0),
    ?assertMatch({{error, <<"godown_full">>}, _S, []},
                 tom_sell_cargo:at(element(2, tom_sell_cargo:at(
                                               Lisbon,
                                               order(<<"b1">>, ?MUSK, 5.0),
                                               now_at())),
                                   order(<<"b2">>, ?MUSK, 1.0), now_at())).

%% Helpers

handover(Hull) ->
    #{<<"from">> => ?OCEAN, <<"to">> => ?MACAO, <<"bound_for">> => ?MACAO,
      <<"ship">> => Hull}.

lisbon() ->
    {ok, [Standing]} = file:consult(
                         filename:join([code:priv_dir(hecate_tom_world),
                                        "harbours", "lisbon.standing"])),
    {ok, Market} = tom_market:open(Standing),
    {ok, World} = tom_world:load_default(),
    {Goods, Names} = tom_standing:goods_index(?REALM, Standing),
    #{harbour => ?LISBON, realm => ?REALM, world => World, place => lisbon,
      market => Market, goods => Goods, names => Names, tick_ms => 10000,
      ships => #{}, receipts => #{}, taken => #{}, log => no_disk_in_a_test}.

near(A, B) -> abs(A - B) =< 1.0e-9 * max(abs(A), abs(B)).
