%% @doc What a good, a harbour or a recipe is called on the mesh.
%%
%% The names in a world file are LOCAL. raw_silk means something inside one
%% document and nothing outside it, because nothing in the atom says which
%% document, which game, or which of the two players sent it. A database gets
%% away with a bare key because the database is the coordination point. A mesh
%% has none.
%%
%% So a name that leaves this node becomes an MRI:
%%
%%   mri:class:{realm}/tom/good/raw_silk
%%   mri:class:{realm}/tom/harbour/macao
%%   mri:class:{realm}/tom/recipe/weave_silk
%%
%% class, because these are kinds of thing rather than particular ones. A
%% specific forty tons of pepper in a specific hold is an instance and will be
%% named as one when holds exist.
%%
%% The realm is the game. It cannot live in the world file, because one world
%% file serves many games and the realm is not known when the file is written.
%% That is why these are functions of a realm rather than a field.
%%
%% RESOLUTION NEVER MINTS AN ATOM. A name arriving off the mesh stays a binary
%% until it is matched against the names this world already declares, and an
%% unmatched one comes back as an error. Atoms are not garbage collected, so a
%% binary_to_atom on anything a stranger sent is a way to walk the atom table
%% until the node dies. There is no such call in here and there must never be
%% one.
%% @end
-module(tom_mri).

-export([good/2,
         harbour/2,
         recipe/2,
         resolve/2]).

-export_type([kind/0]).

%% @doc What a resolved MRI turned out to name.
-type kind() :: good | harbour | recipe.

%% @doc What a good is called on the mesh.
-spec good(macula_mri:realm(), tom_goods:id()) ->
          {ok, macula_mri:mri()} | {error, term()}.
good(Realm, Id) -> mri(Realm, <<"good">>, Id).

%% @doc What a harbour is called on the mesh.
-spec harbour(macula_mri:realm(), tom_harbours:id()) ->
          {ok, macula_mri:mri()} | {error, term()}.
harbour(Realm, Id) -> mri(Realm, <<"harbour">>, Id).

%% @doc What a recipe is called on the mesh.
-spec recipe(macula_mri:realm(), tom_recipes:id()) ->
          {ok, macula_mri:mri()} | {error, term()}.
recipe(Realm, Id) -> mri(Realm, <<"recipe">>, Id).

%% @doc Turn an MRI off the wire back into something this world knows.
%%
%% Fails closed. An MRI that is not ours, names a kind we do not have, or names
%% something this world never declared, comes back as an error and costs nothing
%% but the parse.
-spec resolve(tom_world:world(), macula_mri:mri()) ->
          {ok, {kind(), atom()}} | {error, term()}.
resolve(World, MRI) -> resolved(World, macula_mri:parse(MRI)).

%% Internal

mri(Realm, Kind, Id) when is_atom(Id) ->
    macula_mri:new(class, Realm, [<<"tom">>, Kind, atom_to_binary(Id, utf8)]).

resolved(World, {ok, #{type := class, path := [<<"tom">>, Kind, Name]}}) ->
    found(Kind, Name, index(World, Kind));
resolved(_World, {ok, _Other}) ->
    {error, not_a_tom_mri};
resolved(_World, {error, Why}) ->
    {error, Why}.

%% The index is built from names this world already declared, so matching is a
%% binary comparison and the atom it returns was minted at load time.
index(World, <<"good">>)    -> known(tom_goods:ids(World), good);
index(World, <<"harbour">>) -> known(tom_harbours:ids(World), harbour);
index(World, <<"recipe">>)  -> known(tom_recipes:ids(World), recipe);
index(_World, _Other)       -> unknown_kind.

known(Ids, Kind) ->
    maps:from_list([{atom_to_binary(Id, utf8), {Kind, Id}} || Id <- Ids]).

found(_Kind, _Name, unknown_kind) -> {error, unknown_kind};
found(_Kind, Name, Index)         -> matched(maps:find(Name, Index)).

matched({ok, Found}) -> {ok, Found};
matched(error)       -> {error, unknown_name}.
