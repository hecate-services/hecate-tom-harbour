%% @doc The recipes of a world.
%%
%% A recipe says what a factory eats and what it makes. This module defines the
%% map a recipe is; the recipes themselves are instances of it, in the world
%% file, and adding one is an edit there.
%%
%% A recipe is three physical facts: what goes in, what comes out, and how long
%% a batch takes. Nothing on it is money. What a batch costs in wages and fuel is
%% itself a price, and prices emerge from trade rather than being written down by
%% anybody, so a fixed money number here would be an island of central planning
%% in a market game.
%%
%% A recipe is never retuned, reformulated or retired either. You cannot
%% un-invent a process. A better one is a NEW recipe published alongside the old,
%% and the old keeps working for whoever holds a copy. So which gunpowder recipe
%% you hold starts to matter, not merely whether you can make gunpowder, and two
%% recipes making the same good by different means is normal rather than a
%% mistake.
%%
%% Three more things are settled and worth stating, because they are what keep
%% the economy from being a money printer:
%%
%% A factory arbitrages against its own market. Its buying lifts the input price
%% and its selling depresses the output price, so it strangles itself at
%% equilibrium unless somebody ships the inputs in and the outputs out. That is
%% the whole reason factories are in the game: they convert a price differential
%% into a standing demand for shipping.
%%
%% Building a factory destroys the recipe copy it was built from. A recipe is
%% cargo, so knowledge travels and diffuses, but each copy raises one factory
%% and then it is gone.
%%
%% The town owns the factory. The Harbour Master funds it and takes the tax on
%% the traffic it draws. If he owned the output he would be a trader, and the
%% two roles would blur into one.
%%
%% A factory is capacity, not a machine tied to one product. It runs any recipe
%% it holds and can feed. So what a factory costs to raise belongs to factories
%% and not to recipes, and it is a bill in timber and ironwork rather than in
%% coin, which means building one generates trade exactly as running one does.
%% @end
-module(tom_recipes).

-export([all/1,
         ids/1,
         count/1,
         exists/2,
         fetch/2,
         name/2,
         character/2,
         inputs/2,
         outputs/2,
         ticks/2,
         eating/2,
         making/2,
         manufactured/1,
         raw/1]).

-export_type([id/0, recipe/0]).

%% @doc A recipe's permanent identifier. Also what a traded copy will name.
-type id() :: atom().

-type recipe() :: #{id := id(),
                    name := binary(),
                    character := binary(),
                    inputs := #{tom_goods:id() => pos_integer()},
                    outputs := #{tom_goods:id() => pos_integer()},
                    ticks := pos_integer()}.

%% @doc Every recipe in a world, ordered by identifier.
-spec all(tom_world:world()) -> [recipe()].
all(World) ->
    [R || {_Id, R} <- lists:sort(maps:to_list(tom_world:recipes(World)))].

%% @doc Every recipe's identifier.
-spec ids(tom_world:world()) -> [id()].
ids(World) -> lists:sort(maps:keys(tom_world:recipes(World))).

%% @doc How many recipes a world knows.
-spec count(tom_world:world()) -> non_neg_integer().
count(World) -> maps:size(tom_world:recipes(World)).

%% @doc Whether a world knows this recipe.
-spec exists(tom_world:world(), id()) -> boolean().
exists(World, Id) -> maps:is_key(Id, tom_world:recipes(World)).

%% @doc Look a recipe up.
-spec fetch(tom_world:world(), id()) -> {ok, recipe()} | {error, unknown_recipe}.
fetch(World, Id) -> found(maps:find(Id, tom_world:recipes(World))).

%% @doc A recipe's display name. Crashes on a recipe the world does not know.
-spec name(tom_world:world(), id()) -> binary().
name(World, Id) -> field(name, World, Id).

%% @doc One line on what the trade is.
-spec character(tom_world:world(), id()) -> binary().
character(World, Id) -> field(character, World, Id).

%% @doc What one batch eats.
-spec inputs(tom_world:world(), id()) -> #{tom_goods:id() => pos_integer()}.
inputs(World, Id) -> field(inputs, World, Id).

%% @doc What one batch makes.
-spec outputs(tom_world:world(), id()) -> #{tom_goods:id() => pos_integer()}.
outputs(World, Id) -> field(outputs, World, Id).

%% @doc How long one batch takes.
-spec ticks(tom_world:world(), id()) -> pos_integer().
ticks(World, Id) -> field(ticks, World, Id).

%% @doc Every recipe that eats a good. Who bids for it.
-spec eating(tom_world:world(), tom_goods:id()) -> [recipe()].
eating(World, Good) ->
    [R || R <- all(World), maps:is_key(Good, maps:get(inputs, R))].

%% @doc Every recipe that makes a good. Where it can come from besides the earth.
-spec making(tom_world:world(), tom_goods:id()) -> [recipe()].
making(World, Good) ->
    [R || R <- all(World), maps:is_key(Good, maps:get(outputs, R))].

%% @doc Every good some recipe makes.
-spec manufactured(tom_world:world()) -> [tom_goods:id()].
manufactured(World) ->
    lists:usort(lists:flatmap(fun(R) -> maps:keys(maps:get(outputs, R)) end,
                              all(World))).

%% @doc Every good no recipe makes. It comes out of the ground or it does not
%% come at all.
-spec raw(tom_world:world()) -> [tom_goods:id()].
raw(World) -> tom_goods:ids(World) -- manufactured(World).

%% Internal

found({ok, Recipe}) -> {ok, Recipe};
found(error)        -> {error, unknown_recipe}.

field(Key, World, Id) ->
    {ok, Recipe} = fetch(World, Id),
    maps:get(Key, Recipe).
