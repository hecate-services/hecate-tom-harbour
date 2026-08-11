%% @doc A hull, its hold, and what is in it. This port's own model of a thing
%% somebody else's service also models.
%%
%% THE SHIP IS THE UNIT OF CUSTODY AND THE CARGO IS INSIDE IT. Cargo never
%% travels on its own: it crosses a quay, which is one local act inside one
%% process, and between quays it moves only inside a hull. So "the cargo exists
%% exactly once" reduces to "the hull exists exactly once", and there is one
%% handover protocol in the whole game moving one kind of object.
%%
%% CARGO HAS NO NAME. Forty tons of pepper in a hold is interchangeable with any
%% other forty tons, so it is a quantity under a good's class name and it is
%% identified by identifying the hull. Giving it an identity would create a
%% second thing that has to exist exactly once, which is the whole problem the
%% custody rule exists to have only once.
%%
%% A GOOD AT NOUGHT IS NOT IN THE HOLD. It leaves the map rather than sitting
%% there as a zero, because a hold that lists what it does not carry is a hold
%% that grows a line every time anything is ever sold out of it.
%%
%% OWNER IS NOT CUSTODIAN. The owner holds title and never changes. The
%% custodian is whoever physically has the thing right now and changes at every
%% handover. A house is never a custodian at any moment of a voyage, which is
%% why it can be killed at any instant without the cargo being at risk.
%% @end
-module(tom_ship).

-export([id/1,
         owner/1,
         hold/1,
         cargo/1,
         hop/1,
         custodian/1,
         free/1,
         aboard/2,
         is_ship/1,
         load/3,
         unload/3,
         consign/2]).

-export_type([ship/0]).

%% @doc A hull as it travels: every key a binary, every quantity a float, every
%% identifier an MRI, and the hop an integer.
-type ship() :: #{binary() => term()}.

%% @doc Which hull.
-spec id(ship()) -> binary().
id(Ship) -> maps:get(<<"ship">>, Ship).

%% @doc Whose it is. Title, not custody.
-spec owner(ship()) -> binary().
owner(Ship) -> maps:get(<<"owner">>, Ship).

%% @doc Capacity, in tons.
-spec hold(ship()) -> float().
hold(Ship) -> maps:get(<<"hold">>, Ship).

%% @doc What is in it: a good's class name to tons.
-spec cargo(ship()) -> #{binary() => float()}.
cargo(Ship) -> maps:get(<<"cargo">>, Ship).

%% @doc The custody counter. One higher at every handover and never otherwise.
-spec hop(ship()) -> integer().
hop(Ship) -> maps:get(<<"hop">>, Ship).

%% @doc Who has it right now.
-spec custodian(ship()) -> binary().
custodian(Ship) -> maps:get(<<"custodian">>, Ship).

%% @doc Space left.
-spec free(ship()) -> float().
free(Ship) ->
    hold(Ship) - lists:sum(maps:values(cargo(Ship))).

%% @doc How much of one good is aboard.
-spec aboard(ship(), binary()) -> float().
aboard(Ship, Good) -> maps:get(Good, cargo(Ship), 0.0).

%% @doc Whether a map off the wire is a hull this port can take custody of.
%%
%% CHECKED BECAUSE IT ARRIVES FROM A STRANGER, and a handover that cannot be
%% understood cannot be accepted: the custody rule says a receiver must never
%% refuse a WELL FORMED handover, and this is what decides which ones those are.
%% Every field is required, because a hull with no hop cannot be counted and one
%% with no hold cannot be loaded, and inventing either is how a ship comes to
%% exist twice.
-spec is_ship(term()) -> boolean().
is_ship(#{<<"ship">> := Id, <<"owner">> := Owner, <<"hold">> := Hold,
          <<"cargo">> := Cargo, <<"hop">> := Hop, <<"custodian">> := Who})
  when is_binary(Id), is_binary(Owner), is_binary(Who),
       is_number(Hold), Hold > 0, is_integer(Hop), Hop >= 0,
       is_map(Cargo) ->
    lists:all(fun tons/1, maps:to_list(Cargo));
is_ship(_Other) ->
    false.

%% @doc Put goods in the hold.
-spec load(ship(), binary(), float()) -> ship().
load(Ship, Good, Quantity) ->
    Ship#{<<"cargo">> := maps:put(Good, aboard(Ship, Good) + Quantity,
                                  cargo(Ship))}.

%% @doc Take goods out of the hold. A good that runs out leaves the map.
-spec unload(ship(), binary(), float()) -> ship().
unload(Ship, Good, Quantity) ->
    Ship#{<<"cargo">> := remaining(cargo(Ship), Good,
                                   aboard(Ship, Good) - Quantity)}.

%% @doc The hull as it WILL be once the receiver has it: one hop higher, in the
%% receiver's hands.
%%
%% The sender writes the future and the receiver's acceptance is what makes it
%% so. That is why a retry is byte for byte the same call, and why the receiver
%% can tell a repeat from a new handover by the hop alone, with no second
%% identifier to agree on.
-spec consign(ship(), binary()) -> ship().
consign(Ship, To) -> Ship#{<<"hop">> := hop(Ship) + 1, <<"custodian">> := To}.

%% Internal

tons({Good, Quantity}) ->
    is_binary(Good) andalso is_number(Quantity) andalso Quantity > 0.

remaining(Cargo, Good, Left) when Left > 0.0 -> Cargo#{Good => Left};
remaining(Cargo, Good, _Left) -> maps:remove(Good, Cargo).
