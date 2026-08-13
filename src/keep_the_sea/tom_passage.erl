%% @doc How long a crossing takes, how often one ends badly, and which one.
%%
%% THE TWO CONSTANTS OF THE SEA LIVE HERE AND NOWHERE ELSE. Ninety does not
%% appear in a desk, in a player or in the world file, in code, in a comment or
%% in a test fixture. The enforcement is not discipline, it is the wire: every
%% fact a port publishes carries an INSTANT and never a duration, so a player
%% who wanted ninety would have to subtract two of a port's own timestamps, and
%% has no reason to.
%%
%% THIS WAS THE OCEAN'S, until 2026-08-13. An ocean is not somebody you give a
%% ship to, it is where the ship is, and made a service it inherited the shape of
%% a party: custody, an archive, an outbox. What it really owned was a clock and
%% a fate, which are these two constants and the draw below, and they live at the
%% port she sailed from now. See hecate-tom-general/design/DESIGN_VOYAGE.md.
%%
%% == The draw is deterministic, and that is the whole point ==
%%
%% A bare `rand:uniform/1' would make the sea unfalsifiable. Nobody could tell a
%% run of bad luck from a sea that sinks the ships it dislikes, and the only
%% available answer would be "trust me". So the fate of a crossing is a
%% cryptographic hash of the five facts that were fixed and PUBLISHED the moment
%% the ship sailed:
%%
%%   sha256(Ship /0/ Owner /0/ From /0/ BoundFor /0/ SailedAt)
%%
%% where the separator is a single zero byte (an MRI can never contain one, so
%% no two different departures can produce the same seed by running their fields
%% together) and SailedAt is its decimal rendering in milliseconds.
%%
%%   <<Fortune:32, Weather:8, _/binary>> = that digest
%%
%%   lost when Fortune rem 10000 < hazard()
%%   pirates when lost and Weather is odd, storm when lost and Weather is even
%%
%% Thirty-two bits for the fortune rather than sixteen: 2^16 is not a multiple
%% of ten thousand, so a sixteen-bit draw would be about 17% likelier to land in
%% the first 5536 of its range than the rest, which is a real and measurable
%% thumb on the scale. At thirty-two bits the same bias is under two parts in a
%% million.
%%
%% Every one of the five inputs appears in `ship_sailed_v1'. Anybody who saw the
%% departure can call `fate/1' afterwards and check that the sea reported what
%% the arithmetic says it must. That is the sense in which the sea can be caught
%% cheating.
%%
%% ⚠ THE COST OF THAT, STATED PLAINLY: the same property means a player who
%% knows this algorithm can compute the outcome the instant the ship sails,
%% ninety seconds before the sea admits it. A port never discloses the
%% fate early (it is absent from `ship_sailed_v1' and from `get_voyage' while a
%% ship is in passage) but it cannot stop anyone from doing the arithmetic.
%% Verifiability and suspense are in tension here and verifiability won. The
%% standard repair is commit-and-reveal: draw a random salt at departure,
%% publish only its hash, and reveal the salt with the outcome. That needs one
%% new field in `ship_sailed_v1' and one in each outcome fact, so it is a change
%% to the frozen contract rather than something to slip in quietly.
%%
%% == The draw happens at SAILING, never at arrival ==
%%
%% This is what makes a passage survive a reboot. If a port drew at due_at, a
%% crash between the draw and its disk write would let the restarted port draw
%% again, and a ship could be re-rolled once per container bounce until it
%% sank or survived. Drawing once, inside the same durable write that creates
%% the consignment, makes arrival a pure function of the clock: a restarted port
%% re-reads the berth and acts, and never re-draws. See
%% `tom_sail_ship:consigned/4' for the write, and `tom_keep_the_sea' for the
%% waiting.
-module(tom_passage).

-export([passage_ms/1,
         leagues_per_minute/0,
         hazard/0,
         fate/1,
         seed/1]).

-export_type([departure/0, fate/0, cause/0]).

%% HOW FAST A SHIP GOES, AND IT IS THE ONLY TEMPO DIAL IN THE GAME. Distance is
%% the world's and comes off the map; this turns it into time and is the sea's.
%%
%% It was a flat ninety seconds for every crossing until 2026-08-13, which made
%% Macao to Nagasaki and the Manila galleon the same voyage. At 350 leagues to
%% the minute the spread the map actually has comes through:
%%
%%   macao to manila          335 leagues     under a minute
%%   macao to malacca         527             a minute and a half
%%   the Manila galleon     2,849             eight minutes
%%   the Carreira home      3,582             ten minutes
%%   the long Carreira      4,586             thirteen minutes
%%
%% A LONG VOYAGE IS SUPPOSED TO BE LONG. It is the only thing in the game a
%% player commits to and cannot take back, and the suspense is the point rather
%% than a cost to be minimised. Turn this number down when a passage has enough
%% happening in it to be watched, and up when it has not.
-define(LEAGUES_PER_MINUTE, 350).

%% How many crossings in ten thousand end badly.
%%
%% ⚠ THIS IS THE ONE NUMBER THE CONTRACT LEFT OPEN, and it is a game-feel
%% decision rather than a mechanism: it says how often a player loses everything
%% they were carrying. At 200 a trader loses roughly one voyage in fifty, so an
%% evening of twenty crossings carries about a one-in-three chance of a bad day
%% and no chance at all of a boring one. Change it here; nothing else moves.
-define(HAZARD_IN_TEN_THOUSAND, 200).

%% The five facts about a departure, all of them published in ship_sailed_v1.
-type departure() :: #{ship      := binary(),
                       owner     := binary(),
                       from      := binary(),
                       bound_for := binary(),
                       sailed_at := integer()}.

-type cause() :: storm | pirates.
-type fate()  :: arrives | {lost, cause()}.

%% @doc How long a crossing of this many leagues takes, in milliseconds.
-spec passage_ms(number()) -> pos_integer().
passage_ms(Leagues) ->
    max(1000, round(Leagues * 60_000 / ?LEAGUES_PER_MINUTE)).

%% @doc How fast a ship goes. For a shell and for a test that wants to say how
%% far she should have got.
-spec leagues_per_minute() -> pos_integer().
leagues_per_minute() -> ?LEAGUES_PER_MINUTE.

%% @doc How many crossings in ten thousand end badly.
-spec hazard() -> non_neg_integer().
hazard() ->
    ?HAZARD_IN_TEN_THOUSAND.

%% @doc What becomes of a ship that sails on these terms.
%%
%% Pure and total: the same departure always yields the same fate, on any node,
%% in any process, before or after a restart, and with no state anywhere.
-spec fate(departure()) -> fate().
fate(Departure) ->
    <<Fortune:32, Weather:8, _Rest/binary>> = crypto:hash(sha256, seed(Departure)),
    drawn(Fortune rem 10000 < hazard(), Weather).

%% @doc The exact bytes the fate is drawn from.
%%
%% Exported so that a check of the sea's honesty does not have to reconstruct
%% this module's private opinion about separators.
-spec seed(departure()) -> binary().
seed(#{ship := Ship, owner := Owner, from := From,
       bound_for := BoundFor, sailed_at := SailedAt}) ->
    iolist_to_binary([Ship, 0, Owner, 0, From, 0, BoundFor, 0,
                      integer_to_binary(SailedAt)]).

%% Internal

drawn(false, _Weather) ->
    arrives;
drawn(true, Weather) when Weather band 1 =:= 1 ->
    {lost, pirates};
drawn(true, _Weather) ->
    {lost, storm}.
