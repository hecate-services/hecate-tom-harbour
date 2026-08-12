%% @doc The goods of a world.
%%
%% This module is the schema and the questions you can ask. The goods
%% themselves are data, in the world file, and adding one is an edit there.
%%
%% Nothing here is a closed vocabulary. A good carries its identifier, its
%% display name and a line of character. That is all that has been decided about
%% one, and it is less than it was.
%%
%% IT DOES NOT SAY WHERE IT COMES FROM. There was an origins field and it is
%% gone, because where a good comes from is the regions of the harbours that
%% produce it. Saying it twice is how the two came to disagree: silver went on
%% claiming the Americas long after Acapulco started digging ore instead of
%% metal, and nothing noticed. origins/2 now derives the answer and cannot go
%% stale.
%%
%% An identifier is a permanent commitment. Every stored fact that names a good
%% names it by that atom.
%% @end
-module(tom_goods).

-export([all/1,
         ids/1,
         count/1,
         exists/2,
         fetch/2,
         name/2,
         character/2,
         origins/2,
         from_region/2]).

-export_type([id/0, good/0]).

%% @doc A good's permanent identifier. Data, so any atom a world declares.
-type id() :: atom().

-type good() :: #{id := id(),
                  name := binary(),
                  character := binary()}.

%% @doc Every good in a world, ordered by identifier.
-spec all(tom_world:world()) -> [good()].
all(World) -> [G || {_Id, G} <- lists:sort(maps:to_list(tom_world:goods(World)))].

%% @doc Every good's identifier.
-spec ids(tom_world:world()) -> [id()].
ids(World) -> lists:sort(maps:keys(tom_world:goods(World))).

%% @doc How many goods a world trades.
-spec count(tom_world:world()) -> non_neg_integer().
count(World) -> maps:size(tom_world:goods(World)).

%% @doc Whether a world trades this good.
-spec exists(tom_world:world(), id()) -> boolean().
exists(World, Id) -> maps:is_key(Id, tom_world:goods(World)).

%% @doc Look a good up.
-spec fetch(tom_world:world(), id()) -> {ok, good()} | {error, unknown_good}.
fetch(World, Id) -> found(maps:find(Id, tom_world:goods(World))).

%% @doc A good's display name. Crashes on a good the world does not trade.
-spec name(tom_world:world(), id()) -> binary().
name(World, Id) -> field(name, World, Id).

%% @doc One line on what makes a good different to carry.
-spec character(tom_world:world(), id()) -> binary().
character(World, Id) -> field(character, World, Id).

%% @doc Where a good comes out of the ground. Derived, never declared.
%%
%% Empty for a good no harbour produces, which is a good that only a factory
%% makes, and a factory stands wherever its recipe and its inputs are.
-spec origins(tom_world:world(), id()) -> [tom_world:region_id()].
origins(World, Id) ->
    lists:usort([tom_harbours:region(World, maps:get(id, H))
                 || H <- tom_harbours:producing(World, Id)]).

%% @doc Every good a region yields. Derived from the harbours standing in it.
-spec from_region(tom_world:world(), tom_world:region_id()) -> [good()].
from_region(World, Region) ->
    [G || G <- all(World),
          lists:member(Region, origins(World, maps:get(id, G)))].

%% Internal

found({ok, Good}) -> {ok, Good};
found(error)      -> {error, unknown_good}.

field(Key, World, Id) ->
    {ok, Good} = fetch(World, Id),
    maps:get(Key, Good).
