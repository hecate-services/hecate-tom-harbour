%% @doc The harbours of a world.
%%
%% This module defines the map a harbour is and the questions you can ask about
%% one. The harbours themselves are instances of that map, in the world file.
%%
%% Every harbour has a market, and every good can be bought and sold in it at
%% the going price. There is therefore no list of what a harbour stocks and no
%% list of what it will buy, because both answers are "all of them". The only
%% thing declared is what is PLENTIFUL, which produces/2 answers. Plentiful is
%% cheap; everything else is dear until somebody sails it in.
%%
%% Demand is derived from that, never declared. wanting/2 is the complement of
%% producing/2: a harbour is short of whatever it does not make. Once prices
%% exist this coarse split becomes a number, and a harbour that has been flooded
%% with pepper will stop being short of pepper without anybody editing a file.
%%
%% A world holds a pool of harbours. A game uses some of them. Which box a
%% harbour's service runs on and which station it dials has nothing to do with
%% any of this.
%% @end
-module(tom_harbours).

-export([all/1,
         ids/1,
         count/1,
         exists/2,
         fetch/2,
         name/2,
         character/2,
         region/2,
         produces/2,
         plentiful/3,
         in_region/2,
         producing/2,
         wanting/2]).

-export_type([id/0, harbour/0]).

%% @doc A harbour's permanent identifier.
-type id() :: atom().

-type harbour() :: #{id := id(),
                     name := binary(),
                     region := tom_world:region_id(),
                     at := tom_places:position(),
                     character := binary(),
                     produces := [tom_goods:id()]}.

%% @doc Every harbour in a world, ordered by identifier.
-spec all(tom_world:world()) -> [harbour()].
all(World) ->
    [H || {_Id, H} <- lists:sort(maps:to_list(tom_world:harbours(World)))].

%% @doc Every harbour's identifier.
-spec ids(tom_world:world()) -> [id()].
ids(World) -> lists:sort(maps:keys(tom_world:harbours(World))).

%% @doc How many harbours the pool holds.
-spec count(tom_world:world()) -> non_neg_integer().
count(World) -> maps:size(tom_world:harbours(World)).

%% @doc Whether the world has this harbour.
-spec exists(tom_world:world(), id()) -> boolean().
exists(World, Id) -> maps:is_key(Id, tom_world:harbours(World)).

%% @doc Look a harbour up.
-spec fetch(tom_world:world(), id()) ->
          {ok, harbour()} | {error, unknown_harbour}.
fetch(World, Id) -> found(maps:find(Id, tom_world:harbours(World))).

%% @doc A harbour's display name. Crashes on a harbour the world does not have.
-spec name(tom_world:world(), id()) -> binary().
name(World, Id) -> field(name, World, Id).

%% @doc One line on what the place is like.
-spec character(tom_world:world(), id()) -> binary().
character(World, Id) -> field(character, World, Id).

%% @doc Where in the world a harbour sits.
-spec region(tom_world:world(), id()) -> tom_world:region_id().
region(World, Id) -> field(region, World, Id).

%% @doc What is plentiful here, and therefore cheap.
%%
%% Everything else still trades, at whatever the market says. An empty list is
%% legitimate: a pure entrepot makes nothing of its own.
-spec produces(tom_world:world(), id()) -> [tom_goods:id()].
produces(World, Id) -> field(produces, World, Id).

%% @doc Whether a good is plentiful at a harbour.
-spec plentiful(tom_world:world(), id(), tom_goods:id()) -> boolean().
plentiful(World, Id, Good) -> lists:member(Good, produces(World, Id)).

%% @doc Every harbour in a region.
-spec in_region(tom_world:world(), tom_world:region_id()) -> [harbour()].
in_region(World, Region) ->
    [H || H <- all(World), maps:get(region, H) =:= Region].

%% @doc Every harbour where a good is plentiful. Where to go and load it.
-spec producing(tom_world:world(), tom_goods:id()) -> [harbour()].
producing(World, Good) ->
    [H || H <- all(World), lists:member(Good, maps:get(produces, H))].

%% @doc Every harbour where a good is scarce. Where to go and sell it.
%%
%% Derived, never declared. Demand is not a list of goods a harbour will accept,
%% because a harbour will accept anything. It is the absence of abundance, so
%% this is exactly the complement of producing/2 and the two partition the pool.
%% Once prices exist, this coarse split becomes a number.
-spec wanting(tom_world:world(), tom_goods:id()) -> [harbour()].
wanting(World, Good) ->
    [H || H <- all(World), not lists:member(Good, maps:get(produces, H))].

%% Internal

found({ok, Harbour}) -> {ok, Harbour};
found(error)         -> {error, unknown_harbour}.

field(Key, World, Id) ->
    {ok, Harbour} = fetch(World, Id),
    maps:get(Key, Harbour).
