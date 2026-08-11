%% @doc What the goods on this quay go for, right now.
%%
%% A GOOD THIS PORT DOES NOT TRADE IS OMITTED RATHER THAN REFUSED. That is the
%% same stance tom_market:sight_harbour takes: a peer may know goods we do not,
%% and hearing about one is not a fault. A caller asking for eight goods at a
%% port that trades six gets six rows and can see which two are missing.
%%
%% NO ERROR RETURN AT ALL, therefore. There is nothing a caller can get wrong
%% here except the shape of the payload, and a payload with no goods list means
%% every good, which is what a page opening for the first time wants.
%% @end
-module(tom_list_quotes).

-export([handle/1, at/3]).

%% @doc The mesh handler. Runs in the station link's process and asks the port.
-spec handle(map()) -> {ok, map()}.
handle(Payload) -> tom_wire:answer(tom_port:quotes(Payload)).

%% @doc The desk. Pure: state in, reply out, nothing moved.
-spec at(tom_port:state(), map(), tom_port:now()) -> tom_port:outcome().
at(State, Payload, #{at := At}) ->
    {{ok, #{<<"harbour">> => maps:get(harbour, State),
            <<"at">> => At,
            <<"quotes">> => [posted(State, Good) || Good <- asked(State,
                                                                 Payload)]}},
     State, []}.

%% Internal

%% An empty list means every good this port trades. Anything else is resolved
%% against the names this port declared, and a name that does not match is
%% dropped rather than turned into an atom.
asked(State, Payload) -> wanted(State, tom_wire:list(<<"goods">>, Payload)).

wanted(State, []) ->
    tom_market:goods(maps:get(market, State));
wanted(State, Names) ->
    Goods = maps:get(goods, State),
    [Good || Name <- Names, is_binary(Name),
             {ok, Good} <- [maps:find(Name, Goods)]].

posted(State, Good) ->
    Market = maps:get(market, State),
    #{<<"good">> => maps:get(Good, maps:get(names, State)),
      <<"price">> => tom_market:quote(Market, Good),
      <<"stock">> => tom_market:stock(Market, Good)}.
