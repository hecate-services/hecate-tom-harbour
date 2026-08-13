%% @doc Which port this instance IS, and everything it needs to be one.
%%
%% TWO INSTANCES OF THIS RELEASE ARE TWO DIFFERENT PORTS. Nothing in the image
%% says Macao, so the environment has to, and it has to say it before the market
%% opens because the market is opened from it. One variable names the harbour
%% and everything else either follows from that name or has a default that does.
%%
%% THE STANDING IS DATA AND IT IS THIS SERVICE'S OWN. It is not fetched from the
%% world service and it is not a library: goods arrive here as a map of names to
%% yields and a list of what this port produces, and every consumer of the world
%% keeps its own model of it. Shipped copies for the two ports live in
%% priv/harbours, and a file named by the environment overrides them.
%%
%% NOTHING HERE IS A PRICE, and there is nowhere to put one. A standing declares
%% a headcount, an extent of land, a rate per tick, a list of harbours and a
%% works, and tom_market refuses anything else on the way in.
%% @end
-module(tom_standing).

-export([harbour/0,
         realm/0,
         tick_ms/0,
         data_dir/0,
         standing/0,
         ships/0,
         goods_index/2]).

%% The realm every name in this game hangs under, when nobody says otherwise.
%% It is the realm NAME that goes inside an MRI, which is not the 32 byte realm
%% TAG that goes to macula, and confusing the two is the classic way to publish
%% into a realm nobody is listening to.
-define(REALM, <<"io.macula">>).

%% How long a tick of the market lasts in wall time. A voyage is a minute and a
%% half, so at ten seconds a crossing is nine ticks and a stripped quay visibly
%% refills while a ship is at sea, which is the point of having a clock at all.
-define(TICK_MS, 10000).

%% @doc This instance's own name on the mesh.
-spec harbour() -> binary().
harbour() -> tom_wire:instance(realm(), <<"harbour">>, port_name()).

%% @doc The realm name that goes inside every MRI and every topic.
-spec realm() -> binary().
realm() -> configured("TOM_REALM_NAME", realm_name, ?REALM).


%% @doc How long a tick lasts.
-spec tick_ms() -> pos_integer().
tick_ms() -> whole(configured("TOM_TICK_MS", tick_ms, ?TICK_MS)).

%% @doc Where this port keeps what it must not forget.
-spec data_dir() -> string().
data_dir() ->
    path(configured("TOM_DATA_DIR", data_dir, <<"/var/lib/hecate-tom-world">>)).

%% @doc What this port declares about itself, ready for tom_market:open/1.
-spec standing() -> {ok, tom_crossing:standing()} | {error, term()}.
standing() ->
    read_one(configured("TOM_STANDING", standing_file,
                        shipped(<<"harbours">>, port_name(), <<".standing">>))).

%% @doc The hulls this port holds at hop nought, if any.
%%
%% GENESIS, AND IT IS APPLIED ONCE. A harbour that re-seeded on every boot would
%% mint a second Santa Clara an hour after the first one sailed, so tom_port
%% applies these only for a hull its own record has never mentioned. Ship
%% building is out of scope, so this is the only way a hull comes to exist.
-spec ships() -> [tom_ship:ship()].
ships() -> read_ships(configured("TOM_SHIPS", ships_file, undefined)).

%% @doc What this port calls its goods on the mesh, both ways round.
%%
%% BUILT FROM THE NAMES THIS PORT ALREADY DECLARED, which is what lets a name
%% off the wire be resolved by comparing binaries instead of minting an atom.
%% The atoms in it were minted here, at boot, from a file this operator wrote.
-spec goods_index(binary(), tom_crossing:standing()) ->
          {#{binary() => tom_crossing:good_id()},
           #{tom_crossing:good_id() => binary()}}.
goods_index(Realm, Standing) ->
    Named = [{Good, class(Realm, Good)}
             || Good <- maps:keys(maps:get(goods, Standing))],
    {maps:from_list([{MRI, Good} || {Good, MRI} <- Named]),
     maps:from_list(Named)}.

%% Internal


class(Realm, Good) ->
    {ok, MRI} = macula_mri:new(class, Realm, [<<"tom">>, <<"good">>,
                                              atom_to_binary(Good, utf8)]),
    MRI.

%% THE HARBOUR IS THE ONE THING WITH NO DEFAULT. A port that guessed its own
%% name would advertise somebody else's procedures and take somebody else's
%% orders, so a missing name is a refusal to start rather than a fallback.
port_name() ->
    named(configured("TOM_HARBOUR", harbour, undefined)).

named(undefined) -> error(no_harbour_configured);
named(Name) -> Name.

%% The environment wins over the application env, so one image serves two ports
%% without a rebuild, which is the whole reason this service takes its identity
%% from outside itself.
configured(Var, Key, Default) ->
    chosen(os:getenv(Var), application:get_env(hecate_tom_world, Key),
           Default).

chosen(false, {ok, Value}, _Default) -> Value;
chosen(false, undefined, Default) -> Default;
chosen("", {ok, Value}, _Default) -> Value;
chosen("", undefined, Default) -> Default;
chosen(Set, _Env, _Default) -> list_to_binary(Set).

whole(Value) when is_integer(Value), Value > 0 -> Value;
whole(Value) when is_binary(Value) -> binary_to_integer(Value).

%% A path is a string to the file module whichever way the operator wrote it.
path(Value) when is_binary(Value) -> binary_to_list(Value);
path(Value) when is_list(Value) -> Value.

shipped(Kind, Name, Suffix) ->
    filename:join([code:priv_dir(hecate_tom_world), Kind,
                   <<Name/binary, Suffix/binary>>]).

read_one(Path) -> only(file:consult(path(Path)), Path).

only({ok, [Term]}, _Path) -> {ok, Term};
only({ok, Terms}, Path) -> {error, {not_one_term, Path, length(Terms)}};
only({error, Why}, Path) -> {error, {unreadable, Path, Why}}.

read_ships(undefined) -> [];
read_ships(Path) -> hulls(read_one(Path)).

%% A GENESIS THAT CANNOT BE READ STOPS THE BOOT. Dropping the hull it could not
%% understand would open a port that quietly holds no ship, which looks exactly
%% like a port whose ship has already sailed.
hulls({ok, Ships}) when is_list(Ships) ->
    checked(Ships, [Ship || Ship <- Ships, not tom_ship:is_ship(Ship)]);
hulls({ok, Other}) ->
    error({bad_genesis, not_a_list, Other});
hulls({error, Why}) ->
    error({bad_genesis, Why}).

checked(Ships, []) -> Ships;
checked(_Ships, Bad) -> error({bad_genesis, Bad}).
