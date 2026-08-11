%% @doc The port that finds out for itself, tested by calling it.
%%
%% THE DECISIONS ARE PURE AND THE PROCESS IS GLUE. Six functions carry the whole
%% of what this slice decides: whether a fact is about this port, what to ask
%% for, what came back, what to offer the desk, where the cursor goes and when
%% to look again. None of them reads a clock, holds a pid or opens a socket, so
%% every one of them is tested here by calling it, and the gen_server around
%% them is left to tom_boot_tests where it is started for real.
%%
%% THE ONE THING NO TEST HERE COVERS is a hull actually crossing the mesh, which
%% only scripts/play-the-loop.sh can show. What is covered is the whole of the
%% decision that used to be a knock.
%% @end
-module(tom_take_landings_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REALM, <<"io.macula">>).
-define(MACAO, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(LISBON, <<"mri:instance:io.macula/tom/harbour/lisbon">>).
-define(OCEAN, <<"mri:instance:io.macula/tom/ocean">>).
-define(HOUSE, <<"mri:instance:io.macula/tom/house/raf">>).
-define(CLARA, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(MUSK, <<"mri:class:io.macula/tom/good/musk">>).

%% The module's own rewind, restated here so that changing it is a deliberate
%% act with a red test in front of it rather than a silent widening.
-define(SLACK_MS, 60000).

%% Arriving ------------------------------------------------------------

%% THE WHOLE CHANGE, IN ONE TEST. A hull leaves Macao laden, the sea carries it,
%% and Lisbon takes it without anybody having called Lisbon. What used to reach
%% this desk through a procedure a stranger dialled now reaches it through an
%% answer this port asked for, and the desk cannot tell the difference, which is
%% the point: arrival is a statement, and a port finds out by looking.
a_landing_becomes_a_take_with_nobody_calling_test() ->
    {{ok, _Bought}, Loaded, _E1} = tom_buy_cargo:at(macao(moored(clara())),
                                                    order(<<"a1">>, 5.0),
                                                    now_at()),
    {{ok, _Sailed}, _Frozen, Effects} =
        tom_sail_ship:at(Loaded, #{<<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
                                   <<"bound_for">> => ?LISBON}, now_at()),
    [_Record, _Cry, {hand_over, _S, _H, ?OCEAN, Consigned}] = Effects,
    %% What the sea does to the hull it was handed: one more hop, and the
    %% destination is the custodian from the moment the sea says so.
    Landed = tom_ship:consign(maps:get(<<"ship">>, Consigned), ?LISBON),
    {[Landing], false} = tom_take_landings:landed(page([Landed], false)),
    {{ok, Reply}, Lisbon, Taken} =
        tom_receive_ship:at(lisbon(), tom_take_landings:offered(Landing),
                            now_at()),
    ?assertEqual(true, maps:get(<<"held">>, Reply)),
    ?assertEqual(6, maps:get(<<"hop">>, Reply)),
    ?assertMatch([{record, {took_ship, ?CLARA, 6, _Hull, ?OCEAN, _At}},
                  {cry, _Topic, _Fact}], Taken),
    %% And the pepper is at the far end, in a hull Lisbon is the custodian of.
    Berth = maps:get(?CLARA, maps:get(ships, Lisbon)),
    ?assertEqual(5.0, tom_ship:aboard(maps:get(ship, Berth), ?MUSK)),
    ?assertEqual(?LISBON, tom_ship:custodian(maps:get(ship, Berth))),
    ?assertEqual(6, maps:get(?CLARA, maps:get(taken, Lisbon))).

%% `from' IS THE PREVIOUS CUSTODIAN, WHICH IS THE SEA. The origin port travels
%% as `sailed_from' and is not fed to the desk: what goes in the durable record
%% and out in ship_moored_v1 is who this port took her FROM, and naming Macao
%% there would read better and quietly change what a committed record means.
what_is_offered_to_the_desk_is_the_hull_and_the_consigner_test() ->
    Landing = landing(arriving(6), 5000),
    ?assertEqual(#{<<"ship">> => arriving(6), <<"from">> => ?OCEAN},
                 tom_take_landings:offered(Landing)),
    ?assertEqual(?MACAO, maps:get(<<"sailed_from">>, Landing)),
    ?assertNot(maps:is_key(<<"sailed_from">>,
                           tom_take_landings:offered(Landing))).

%% Hearing -------------------------------------------------------------

%% A FACT DOES NOT ARRIVE IN THE SHAPE IT WAS SENT. macula ships a binary key as
%% a CBOR text string and then atomises what this node happens to have loaded,
%% so `bound_for' turns up as an atom or as {text, Binary} depending on the
%% receiving node. Reading one raw makes this port deaf to every announcement
%% while the sea visibly publishes them, so the fold at the edge is what the
%% first assertion below is really about.
a_fact_bound_for_this_port_is_recognised_test() ->
    Wire = #{ocean => ?OCEAN,
             {text, <<"ship">>} => ?CLARA,
             hop => 6,
             {text, <<"bound_for">>} => ?LISBON,
             from => ?MACAO},
    ?assert(tom_take_landings:mine(tom_wire:accept(Wire), ?LISBON)),
    ?assertNot(tom_take_landings:mine(Wire, ?LISBON)),
    ?assertNot(tom_take_landings:mine(tom_wire:accept(Wire), ?MACAO)),
    [?assertNot(tom_take_landings:mine(Not, ?LISBON))
     || Not <- [#{}, #{<<"bound_for">> => 42}, not_a_map, undefined]].

%% Asking --------------------------------------------------------------

%% THE CURSOR IS REWOUND ON THE WAY OUT, EVERY TIME. `made_at' is a wall clock
%% on the sea's box and is not monotone: an NTP step backwards between two
%% landings would otherwise put one behind this port's high water for good, and
%% a ship that is never asked for is a ship that is never taken. Over-delivery
%% costs nothing, because taking is idempotent; under-delivery loses a hull.
an_ask_rewinds_behind_what_it_already_has_test() ->
    ?assertEqual(#{<<"harbour">> => ?LISBON, <<"since">> => 0,
                   <<"limit">> => 100},
                 tom_take_landings:asked(?LISBON, 0, 100)),
    Cursor = #{<<"at">> => 1786528800000, <<"ship">> => ?CLARA,
               <<"hop">> => 6},
    ?assertEqual(#{<<"harbour">> => ?LISBON,
                   <<"since">> => #{<<"at">> => 1786528800000 - ?SLACK_MS,
                                    <<"ship">> => <<>>, <<"hop">> => 0},
                   <<"limit">> => 100},
                 tom_take_landings:asked(?LISBON, Cursor, 100)),
    %% <<>> sorts before every real MRI and 0 is the lowest hop, so the rewound
    %% cursor is strictly below every landing at or after that instant.
    Early = tom_take_landings:asked(?LISBON, Cursor#{<<"at">> => 42}, 100),
    ?assertEqual(#{<<"at">> => 0, <<"ship">> => <<>>, <<"hop">> => 0},
                 maps:get(<<"since">>, Early)).

%% Reading the answer --------------------------------------------------

%% A READ THAT CAME BACK WRONG IS AN EMPTY PAGE, NOT A CRASH. The sea is another
%% service on another box and this port has no say in what it sends; the one
%% thing that must not happen is the listener dying and taking its subscription
%% with it, because then the port goes deaf until somebody restarts it.
an_answer_this_port_cannot_read_is_an_empty_page_test() ->
    [?assertEqual({[], false}, tom_take_landings:landed(Not))
     || Not <- [{ok, #{}},
                {ok, #{<<"landings">> => not_a_list}},
                {ok, #{<<"refused">> => <<"malformed_request">>}},
                {ok, not_a_map},
                {error, timeout},
                {error, no_mesh}]],
    %% A landing that is not a map cannot name a ship, so it is not a landing.
    ?assertEqual({[], true},
                 tom_take_landings:landed(
                   {ok, #{<<"landings">> => [<<"clara">>, 42],
                          <<"more">> => true}})),
    ?assertEqual({[landing(arriving(6), 5000)], false},
                 tom_take_landings:landed(page([arriving(6)], false))).

%% The cursor ----------------------------------------------------------

%% THE CURSOR ONLY EVER WALKS OVER WHAT WAS TAKEN, which is why the sea's own
%% notion of where the page ended is deliberately ignored: it names the frontier
%% the sea reached, and this port may only claim what its own desk answered for.
%%
%% The three replies are three different futures. A hull taken advances it. A
%% landing whose ship is not a hull can never become takeable, so refusing to
%% advance would let one bad row block every later ship for ever: it is walked
%% past and said out loud. Anything else is transient, so the walk stops and the
%% ordinary sweep offers the same landing again.
the_cursor_advances_over_what_was_taken_and_nothing_else_test() ->
    Landing = landing(arriving(6), 5000),
    Cursor = #{<<"at">> => 1000, <<"ship">> => ?CLARA, <<"hop">> => 5},
    ?assertEqual({go, #{<<"at">> => 5000, <<"ship">> => ?CLARA,
                        <<"hop">> => 6}},
                 tom_take_landings:moved(Cursor, Landing,
                                         {ok, #{<<"held">> => true,
                                                <<"hop">> => 6,
                                                <<"at">> => 5000}})),
    ?assertEqual({go, Cursor},
                 tom_take_landings:moved(Cursor, Landing,
                                         {error, <<"malformed_ship">>})),
    [?assertEqual({stop, Cursor}, tom_take_landings:moved(Cursor, Landing, No))
     || No <- [{error, no_port}, {error, timeout}, {ok, #{}}, no_answer]].

%% Looking again -------------------------------------------------------

%% THIS IS THE ASSERTION THAT SAYS THERE IS NO RETRY LOOP. A failure does not
%% shorten the cadence and a success does not lengthen it: the only thing that
%% brings the next ask forward is a page the sea said had more behind it AND
%% that this port walked to the end of. Everything else, including every kind of
%% failure, lands on the same unconditional sweep as a port with nothing owed to
%% it, and nothing anywhere waits for an acknowledgement.
a_failure_does_not_shorten_the_cadence_test() ->
    ?assertEqual(look, tom_take_landings:next(true, go)),
    ?assertEqual(sweep, tom_take_landings:next(false, go)),
    ?assertEqual(sweep, tom_take_landings:next(true, stop)),
    ?assertEqual(sweep, tom_take_landings:next(false, stop)),
    %% An empty page and a refused one arrive here as the same pair, which is
    %% what makes "the sea is down" and "there is nothing for you" cost the
    %% same: one ask every sweep, for ever, either way.
    {[], More} = tom_take_landings:landed({error, no_mesh}),
    ?assertEqual(sweep, tom_take_landings:next(More, go)).

%% AND THIS IS THE ASSERTION THAT SAYS THE HURRY CANNOT SPIN. Walking a backlog
%% page by page is only safe while each page moves the cursor. A page that says
%% there is more behind it and yet leaves the cursor exactly where it was, an
%% empty one, or one whose landings were every one of them unreadable, would
%% otherwise be asked for again at once, and the identical request would fetch
%% the identical answer for ever, as fast as the sea can answer. The sea owns
%% what it sends and this port must accept it; accepting it into an unbounded
%% loop is not accepting it.
a_page_that_gained_no_ground_never_hurries_test() ->
    Cursor = #{<<"at">> => 5000, <<"ship">> => ?CLARA, <<"hop">> => 6},
    Later = #{<<"at">> => 9000, <<"ship">> => ?CLARA, <<"hop">> => 7},
    ?assert(tom_take_landings:gained(true, 0, Cursor)),
    ?assert(tom_take_landings:gained(true, Cursor, Later)),
    ?assertNot(tom_take_landings:gained(true, Cursor, Cursor)),
    ?assertNot(tom_take_landings:gained(true, 0, 0)),
    ?assertNot(tom_take_landings:gained(false, Cursor, Later)),
    %% Composed, which is how the walk asks the question: more behind it and
    %% ground gained is the ONLY way to look again without waiting.
    ?assertEqual(sweep,
                 tom_take_landings:next(
                   tom_take_landings:gained(true, Cursor, Cursor), go)),
    ?assertEqual(look,
                 tom_take_landings:next(
                   tom_take_landings:gained(true, Cursor, Later), go)).

%% Helpers -------------------------------------------------------------

macao(Ships) -> harbour(?MACAO, <<"macao">>, Ships).

lisbon() -> harbour(?LISBON, <<"lisbon">>, #{}).

%% Built from the SHIPPED standing, so a file in priv that stopped loading fails
%% here rather than in a container nobody is watching.
harbour(MRI, Name, Ships) ->
    {ok, [Standing]} = file:consult(
                         filename:join([code:priv_dir(hecate_tom_harbour),
                                        "harbours", <<Name/binary,
                                                      ".standing">>])),
    {ok, Market} = tom_market:open(Standing),
    {Goods, Names} = tom_standing:goods_index(?REALM, Standing),
    #{harbour => MRI, ocean => ?OCEAN, realm => ?REALM, market => Market,
      goods => Goods, names => Names, tick_ms => 10000, ships => Ships,
      receipts => #{}, taken => #{}, log => no_disk_in_a_test}.

clara() ->
    #{<<"ship">> => ?CLARA, <<"owner">> => ?HOUSE, <<"hold">> => 200.0,
      <<"cargo">> => #{}, <<"hop">> => 4, <<"custodian">> => ?MACAO}.

arriving(Hop) ->
    (clara())#{<<"hop">> => Hop, <<"custodian">> => ?LISBON}.

moored(Hull) ->
    #{tom_ship:id(Hull) => #{ship => Hull, state => moored,
                             bound_for => undefined, hop => tom_ship:hop(Hull),
                             since => 1000}}.

%% One row of the sea's answer, as the sea sends it: the whole hull, the
%% previous custodian, where she sailed from, and the instant that orders the
%% page.
landing(Hull, At) ->
    #{<<"ocean">> => ?OCEAN,
      <<"ship">> => Hull,
      <<"from">> => ?OCEAN,
      <<"sailed_from">> => ?MACAO,
      <<"bound_for">> => ?LISBON,
      <<"hop">> => tom_ship:hop(Hull),
      <<"sailed_at">> => At - 90000,
      <<"made_at">> => At,
      <<"at">> => At}.

page(Hulls, More) ->
    {ok, #{<<"harbour">> => ?LISBON,
           <<"landings">> => [landing(Hull, 5000) || Hull <- Hulls],
           <<"more">> => More}}.

now_at() -> #{tick => 178652880, at => 1786528800000}.

order(Key, Quantity) ->
    #{<<"order">> => Key, <<"by">> => ?HOUSE, <<"ship">> => ?CLARA,
      <<"good">> => ?MUSK, <<"quantity">> => Quantity}.
