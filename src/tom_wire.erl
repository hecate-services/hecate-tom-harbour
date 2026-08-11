%% @doc What this port says on the mesh, and what it will accept back.
%%
%% EVERY KEY THAT LEAVES HERE IS A BINARY. An atom key, a binary key and a
%% {text, Bin} of the same name collapse into ONE key on the wire, so a map
%% carrying two of them ships two and arrives with one, and macula rejects the
%% frame outright rather than guess. Nothing in this module builds a payload any
%% other way.
%%
%% AND EVERY KEY THAT ARRIVES IS ONE TOO, so there is no second way to read
%% one. macula's CBOR codec documents that an atom is encoded as text and comes
%% back as a binary, so a sender who wrote an atom key is indistinguishable here
%% from one who wrote the binary, and a fallback that looked for the atom would
%% be a branch that can never be taken. A missing field is missing.
%%
%% EVERY IDENTIFIER IS AN MRI AND STAYS A BINARY. A name off the wire is matched
%% against the names this port already declared; it is never turned into an
%% atom, because atoms are not collected and a stranger who can mint them can
%% walk the table until the node dies. There is no binary_to_atom in this
%% repository and there must never be one.
%%
%% NO TICK EVER CROSSES. A tick is this port's own clock and means nothing at
%% another service. What crosses is an instant, milliseconds since the epoch, on
%% the writer's clock, and the reader is free to disbelieve it.
%% @end
-module(tom_wire).

-export([now_ms/0,
         accept/1,
         answer/1,
         text/2,
         number/2,
         list/2,
         instance/3,
         is_harbour/1,
         procedure/2,
         fact/3,
         fact/4]).

%% The organisation every topic this game publishes under. One game, one word.
-define(ORG, <<"tom">>).

%% Version one of every fact shape below. A shape that changes gets a two, next
%% to the one, because a consumer holding the old shape is not wrong.
-define(SHAPE, 1).

%% @doc The instant, as the wire counts it.
-spec now_ms() -> integer().
now_ms() -> erlang:system_time(millisecond).

%% @doc Put a payload that came off the mesh back into the shape this port
%% reads: every key a binary, however it arrived.
%%
%% THIS IS NOT DEFENSIVENESS, IT IS THE CODEC. The comment above says a key that
%% arrives is a binary. That is what the SENDER wrote and it is not what the
%% RECEIVER gets. macula's CBOR codec ships a binary key as a major-3 text
%% string, and macula_frame:from_wire_envelope/1 then runs
%% binary_to_existing_atom on it: a key whose name happens to be in the
%% receiving node's atom table arrives as an ATOM, and one whose name is not
%% arrives as `{text, Binary}'. So `<<"good">>' and `<<"harbour">>' can arrive
%% in two different shapes in the same map, and WHICH ONE DEPENDS ON WHAT ELSE
%% THIS NODE HAPPENS TO HAVE LOADED. Loading a module that mentions the atom
%% `good' anywhere silently changes the shape of every payload afterwards.
%%
%% One fold at the edge is therefore the only place this can be got right, and
%% the desks downstream go on reading the binary keys they were written against.
%% It mints NO atoms: atom_to_binary only ever unmakes one the decoder already
%% had, so the atom table cannot be walked from the wire.
%%
%% Values are left alone apart from the same text unwrapping, because `true',
%% `false' and `undefined' are atoms this game means, not artefacts.
-spec accept(term()) -> term().
accept(Payload) when is_map(Payload) ->
    maps:fold(fun(Key, Value, Acc) -> Acc#{binary_key(Key) => accept(Value)} end,
              #{}, Payload);
accept(Values) when is_list(Values) ->
    [accept(Value) || Value <- Values];
accept({text, Text}) when is_binary(Text) ->
    Text;
accept(Other) ->
    Other.

%% @doc Turn a desk's answer into something a caller can still read after the
%% mesh has carried it.
%%
%% A REFUSAL'S REASON DOES NOT SURVIVE `{error, Binary}'. macula turns a
%% handler's error tuple into a BOLT#4 frame with code 0x0F, renders the reason
%% into the frame's `detail' field, and the SDK's caller path reads only the
%% code. `quay_empty', `hold_full', `not_here', `not_yours' and
%% `ship_consigned' therefore arrive at a house as one single value,
%% `{call_error, 15, unknown_error}', and a player is told their order failed
%% with no way to say why. Verified against a running station, not inferred.
%%
%% So a refusal travels as a SUCCESSFUL reply carrying the reason, which is the
%% one shape the wire preserves whole. The desks go on returning
%% `{error, Binary}' because that is what a refusal IS to this port, and the
%% translation lives here, at the edge, once.
%%
%% The final-versus-transient split still works exactly as it did: a reply is an
%% answer and a crash or a timeout is not, which is the distinction the retry
%% loops actually turn on.
-spec answer({ok, map()} | {error, binary()}) -> {ok, map()}.
answer({ok, Reply}) ->
    {ok, Reply};
answer({error, Reason}) ->
    {ok, #{<<"refused">> => Reason}}.

%% @doc A binary field, or undefined. Anything that is not text is not a name.
-spec text(binary(), map()) -> binary() | undefined.
text(Key, Payload) -> texted(field(Key, Payload)).

%% @doc A numeric field as a float, or undefined. Integers are welcome at the
%% boundary and are floats from there on, because the mechanism divides.
-spec number(binary(), map()) -> float() | undefined.
number(Key, Payload) -> numbered(field(Key, Payload)).

%% @doc A list field, or the empty list. A missing list and an empty one mean
%% the same thing to every caller here, so they are not distinguished.
-spec list(binary(), map()) -> [term()].
list(Key, Payload) -> listed(field(Key, Payload)).

%% @doc What a particular thing is called: this harbour, that ocean, one hull.
%%
%% The same path shape as a class, with instance in place of class. Macao the
%% place is reference data somebody else owns; Macao the service is a process on
%% a box that answers calls, and the two are different things with the same
%% name.
%% A name that will not validate is a configuration this port cannot run under,
%% so it stops the boot rather than being carried around as an error tuple that
%% every later caller has to remember to unwrap.
-spec instance(binary(), binary(), binary()) -> binary().
instance(Realm, Kind, Name) ->
    {ok, MRI} = macula_mri:new(instance, Realm, [?ORG, Kind, Name]),
    MRI.

%% @doc Whether an MRI names a harbour instance.
%%
%% A PARSE AND NOT A LOOKUP. This port has no directory and cannot know whether
%% Lisbon exists, only whether the name is shaped like a harbour that might. A
%% ship consigned toward a harbour that never answers stays visibly consigned,
%% which is the truth and is better than a refusal invented out of ignorance.
-spec is_harbour(term()) -> boolean().
is_harbour(MRI) when is_binary(MRI) -> harbour(macula_mri:parse(MRI));
is_harbour(_Other) -> false.

%% @doc Where a call to a particular service goes.
%%
%% ADDRESSED AT THE INSTANCE, because a call has to reach ONE harbour. Macao and
%% Lisbon both answer buy_cargo, and a pool calls first-success across its
%% links, so a name that did not carry the harbour would hand a Macao order to
%% Lisbon and the coin would be gone.
-spec procedure(binary(), binary()) -> binary().
procedure(InstanceMRI, Name) -> macula_mri:derive_procedure(InstanceMRI, Name).

%% @doc Where a fact goes.
%%
%% NO IDENTIFIER IN THE TOPIC, EVER. The harbour, the ship and the good all
%% travel in the payload. Put one in the name and a game with eight ports and a
%% hundred hulls has eight hundred topics, and a house that wants to watch its
%% own ship has to subscribe to all of them.
-spec fact(binary(), binary(), binary()) -> binary().
fact(Realm, Domain, Name) -> fact(Realm, <<"harbour">>, Domain, Name).

%% @doc Where somebody else's fact goes.
%%
%% THE APP SEGMENT IS WHOSE FACT IT IS. `fact/3' is what this port SAYS and
%% hardcodes its own segment; this is how it NAMES what another service says, so
%% that the sea's landfall is looked for under the sea's name rather than under
%% this port's. A topic built with the wrong segment is a topic nobody publishes
%% on, and subscribing to one fails in the only way that is hard to see: no
%% error, no log line, and no ship.
-spec fact(binary(), binary(), binary(), binary()) -> binary().
fact(Realm, App, Domain, Name) ->
    macula_topic:app_fact(Realm, ?ORG, App, Domain, Name, ?SHAPE).

%% Internal

%% A payload that is not a map is not a payload. It reaches here from a
%% stranger, so it is answered rather than matched against.
field(Key, Payload) when is_map(Payload) -> maps:get(Key, Payload, undefined);
field(_Key, _Payload) -> undefined.

%% An atom key is always the decoder's doing rather than a sender's: nothing in
%% this game writes one. Unmaking it is safe because the atom already exists.
binary_key({text, Text}) when is_binary(Text) -> Text;
binary_key(Key) when is_atom(Key) -> atom_to_binary(Key, utf8);
binary_key(Key) -> Key.

texted(Value) when is_binary(Value) -> Value;
texted(_Other) -> undefined.

numbered(Value) when is_number(Value) -> Value * 1.0;
numbered(_Other) -> undefined.

listed(Value) when is_list(Value) -> Value;
listed(_Other) -> [].

harbour({ok, #{type := instance, path := [?ORG, <<"harbour">>, _Name]}}) -> true;
harbour(_Other) -> false.
