%% @doc THE LAW: price is always circumstantial.
%%
%% Nothing in the data a market is opened with is ever a price. Not a base
%% price, not a value, not a cost. A number that says what something is WORTH is
%% forbidden. Numbers that say how much of something EXISTS, or how fast it is
%% yielded, are physical facts and are welcome.
%%
%% These are the tests that would catch somebody smuggling one back in, and the
%% tests that show the mechanism can do without: relative value emerges from
%% yields and geography, and every number in the worked example was computed by
%% the code and not by an author.
%% @end
-module(tom_law_tests).

-include_lib("eunit/include/eunit.hrl").

market(Port) ->
    {ok, Market} = tom_market:open(tom_sim:standing(Port)),
    Market.

pbar(Port, Good) -> tom_market:natural_price(market(Port), Good).

%% THERE IS NOWHERE TO PUT A PRICE. The vocabulary a market accepts is closed
%% and every word in it is a headcount, an extent of land, a rate, a list of
%% harbours or a works. Not one of them says what anything is worth.
the_vocabulary_has_no_room_for_a_price_test() ->
    ?assertEqual([census, factories, goods, hinterland, produces, town],
                 lists:sort(maps:keys(tom_sim:standing(macao)))),
    {ok, Market} = tom_market:open(tom_sim:standing(macao)),
    ?assertEqual([census, factories, goods, hinterland, produces, town],
                 lists:sort(maps:keys(tom_market:standing(Market)))),
    ?assertEqual([appetite, cover_ticks, demand_elasticity, godown_multiple,
                  harbour_fee, leak_base, leak_far, leak_near, reserve_ticks,
                  stock_sensitivity, supply_elasticity],
                 lists:sort(maps:keys(tom_market:config(Market)))).

%% A market ignores anything it was not asked for, so a price smuggled into a
%% standing under any name at all is dropped on the way in rather than used.
a_smuggled_price_does_not_survive_opening_test() ->
    Honest = tom_sim:standing(macao),
    Smuggled = Honest#{base_price => #{musk => 40.0},
                       worth => #{musk => 40.0},
                       musk_is_fine => true},
    {ok, Straight} = tom_market:open(Honest),
    {ok, Crooked} = tom_market:open(Smuggled),
    ?assertEqual(tom_market:standing(Straight), tom_market:standing(Crooked)),
    [?assertEqual(tom_market:quote(Straight, Good),
                  tom_market:quote(Crooked, Good))
     || Good <- tom_market:goods(Straight)],
    ok.

%% And no name in the source is one either. Cheap, and it catches the version of
%% this that arrives as a helpful new field rather than as an argument.
%%
%% Recursive, because the service that grew around the mechanism keeps its desks
%% in directories of their own and a scan of the top level only would have
%% stopped covering the code the moment the first one was written.
no_source_name_declares_a_price_test() ->
    Sources = filelib:wildcard(filename:join([source_dir(), "**", "*.erl"]))
        ++ filelib:wildcard(filename:join(source_dir(), "*.erl")),
    ?assert(length(Sources) >= 18),
    [?assertEqual({Path, nomatch}, {Path, re:run(read(Path), Forbidden)})
     || Path <- Sources,
        Forbidden <- ["base_price", "declared_value", "cost_of", "price_of",
                      "floor_price", "good_value", "desirability"]],
    ok.

%% APPETITE IS A CURRENCY UNIT AND NOTHING ELSE. Scaling it scales every price
%% by the same power and moves no ratio at all, which is exactly what choosing
%% to count in reals rather than in taels does.
appetite_is_a_currency_unit_test() ->
    Market = market(macao),
    Fourfold = maps:merge(tom_crossing:defaults(), #{appetite => 120.0}),
    {ok, Rich} = tom_market:open(tom_sim:standing(macao), Fourfold),
    Factor = math:pow(4.0, 1.0 / 1.8),
    [?assert(near(tom_market:quote(Rich, Good),
                  tom_market:quote(Market, Good) * Factor))
     || Good <- tom_market:goods(Market)],
    ?assert(near(tom_market:in_terms_of(Rich, musk, rice),
                 tom_market:in_terms_of(Market, musk, rice))).

%% MUSK AND RICE DO NOT COST THE SAME, and the difference is eight hundredfold
%% at their home ports, out of a yield ratio of eight hundred to one compressed
%% by the exponent to ninety six. Nobody wrote either number.
musk_and_rice_do_not_cost_the_same_test() ->
    Ratio = pbar(macao, musk) / pbar(ayutthaya, rice),
    ?assert(near_enough(Ratio, 96.49)),
    ?assert(near_enough(tom_market:in_terms_of(market(lisbon), musk, rice),
                        63.54)).

%% THE WORKED EXAMPLE, reproduced. The design quotes these to about four
%% figures, so they are asserted to two parts in a thousand; the exact values
%% this implementation produces are locked separately below.
the_worked_example_test() ->
    [?assert(near_enough(pbar(Port, Good), Quoted))
     || {Port, Good, Quoted} <- [{macao, musk, 12.9155},
                                 {ayutthaya, rice, 0.13380},
                                 {banda, nutmeg, 0.75294},
                                 {ternate, nutmeg, 2.47862},
                                 {lisbon, nutmeg, 8.55245},
                                 {ternate, rice, 0.80671},
                                 {lisbon, rice, 2.72128},
                                 {lisbon, musk, 172.777},
                                 {macao, cannon, 77.219},
                                 {macao, copper, 13.212},
                                 {macao, quicksilver, 7.942},
                                 {callao, quicksilver, 57.269},
                                 {callao, silver_ore, 0.1120},
                                 {macao, silver_ore, 1.9967}]],
    Musk = tom_market:crossing(market(macao), musk),
    ?assert(near_enough(maps:get(throughput, Musk), 1.66951)),
    ?assert(near_enough(maps:get(natural_stock, Musk), 13.3561)),
    Cannon = tom_market:crossing(market(macao), cannon),
    ?assert(near_enough(maps:get(throughput, Cannon), 0.136559)),
    ?assert(near_enough(maps:get(natural_stock, Cannon), 1.09247)).

%% A lock, so that a change to the mechanism has to be a change somebody meant.
the_worked_example_is_locked_test() ->
    ?assert(near(pbar(macao, musk), 12.915496650148841)),
    ?assert(near(pbar(ayutthaya, rice), 0.13384831451202825)),
    ?assert(near(pbar(macao, cannon), 77.222605247318967)),
    ?assert(near(pbar(lisbon, musk), 172.89949919329271)).

%% THE TRADE. Lifting five musk off a resting Macao pays more than spot because
%% it moved the price, and every one of these came out of the integral.
the_trade_test() ->
    Market = market(macao),
    {ok, Filled, Coin, After} = tom_market:lift(Market, musk, 5, 0),
    ?assertEqual(5.0, Filled),
    ?assert(near_enough(Coin, 73.2591)),
    ?assert(near_enough(Coin / 5.0, 14.652)),
    ?assert(near_enough(tom_market:quote(After, musk), 16.1814)),
    ?assert(near_enough(tom_market:stock(After, musk), 8.3561)),
    {ok, _, Back, _} = tom_market:land(After, musk, 5, 0),
    ?assert(near_enough(Back, 70.3861)),
    ?assert(abs(100.0 * (Coin - Back) / Coin - 3.92157) < 1.0e-4).

%% GEOGRAPHY, EMERGING. Nutmeg is cheapest where it grows, three times that at
%% a neighbour in the same sea, eleven times that after a voyage. The only input
%% is how many harbours produce it and whether they are near.
nutmeg_is_dearer_the_further_it_goes_test() ->
    ?assert(pbar(banda, nutmeg) < pbar(ternate, nutmeg)),
    ?assert(pbar(ternate, nutmeg) < pbar(lisbon, nutmeg)),
    ?assert(near_enough(pbar(ternate, nutmeg) / pbar(banda, nutmeg), 3.291)),
    ?assert(near_enough(pbar(lisbon, nutmeg) / pbar(banda, nutmeg), 11.36)).

%% THE GALLEON, emerging. Mercury is worth carrying east to west and silver west
%% to east, both in the same hulls, and nobody declared either leg.
the_galleon_is_full_both_ways_test() ->
    ?assert(near_enough(pbar(callao, quicksilver) / pbar(macao, quicksilver),
                        7.208)),
    ?assert(near_enough(pbar(macao, silver_ore) / pbar(callao, silver_ore),
                        17.82)).

%% THE FOUNDRY STRANGLES ITSELF. Its buying lifts its input price and its
%% selling depresses its output price, and both are permanent structure rather
%% than a wobble in a heap, because it shifted the crossing.
the_foundry_strangles_itself_test() ->
    Before = market(macao),
    After = tom_market:raise_factory(Before, 0, tom_sim:foundry()),
    ?assert(tom_market:natural_price(After, cannon)
            < tom_market:natural_price(Before, cannon)),
    ?assert(tom_market:natural_price(After, copper)
            > tom_market:natural_price(Before, copper)),
    ?assert(near_enough(tom_market:natural_price(After, cannon), 51.45)),
    ?assert(abs(tom_market:natural_price(After, copper) - 15.18) < 0.03),
    Shelf = maps:get(natural_stock, tom_market:crossing(After, cannon)),
    ?assert(near_enough(Shelf, 1.929)).

%% A SURVEYED COUNT OF NOUGHT IS NOT SCARCITY, AND THAT IS ON PURPOSE. A port
%% that looked and found nobody has established that the good has no geography
%% at all, which is what cannon are: made in a factory, produced by no harbour,
%% and priced off the rate a village smith manages. Among the goods that DO come
%% from somewhere, it is the port that has heard of one distant producer that
%% pays most, and the price falls back as more facts arrive.
facts_arriving_move_the_price_test() ->
    Ignorant = tom_market:sight_harbour(market(lisbon), 0, #{}),
    One = tom_market:sight_harbour(bare(lisbon), 0, #{nutmeg => far}),
    Again = fun(_N, Acc) ->
                    tom_market:sight_harbour(Acc, 0, #{nutmeg => far})
            end,
    Four = lists:foldl(Again, One, lists:seq(1, 3)),
    ?assert(tom_market:natural_price(One, nutmeg)
            > tom_market:natural_price(Four, nutmeg)),
    ?assert(near(tom_market:natural_price(Four, nutmeg),
                 tom_market:natural_price(Ignorant, nutmeg))),
    ?assert(near(pbar(lisbon, cannon), grown(lisbon, cannon))).

%% LEARNING ONLY EVER MAKES A GOOD CHEAPER. A port that has not surveyed a good
%% quotes the dearest price it will ever quote for it, because the only supply
%% it knows of is what turns up with no source at all, and every harbour it
%% hears about after that adds to the trickle.
%%
%% The old arrangement had ignorance and "surveyed, nobody makes it" share one
%% value, so a first sighting sent nutmeg at Lisbon UP by a factor of thirteen.
%% Two ports learning at different times then quoted prices thirteen apart with
%% nothing between them but a lost packet, and the profit was in trading with
%% whichever one was behind.
knowing_more_never_makes_a_good_dearer_test() ->
    Walk = fun(Where, [Last | _] = Seen) ->
                   [tom_market:sight_harbour(Last, 0, #{nutmeg => Where})
                    | Seen]
           end,
    Markets = lists:foldl(Walk, [bare(lisbon)], [far, far, near, far]),
    Prices = [tom_market:natural_price(M, nutmeg)
              || M <- lists:reverse(Markets)],
    ?assertEqual(Prices, lists:reverse(lists:sort(Prices))),
    ?assert(hd(Prices) > lists:last(Prices) * 2.0).

%% A good the port itself grows is never a trickle, whatever the census says.
what_a_port_grows_is_never_scarce_there_test() ->
    ?assert(pbar(banda, nutmeg) < pbar(lisbon, nutmeg) / 10),
    ?assert(pbar(ayutthaya, rice) < pbar(lisbon, rice) / 10),
    ?assert(pbar(macao, musk) < pbar(lisbon, musk) / 10).

%% The same port with nothing surveyed at all: it knows what it grows and
%% nothing whatever about anybody else.
bare(Port) ->
    Standing = tom_sim:standing(Port),
    {ok, Market} = tom_market:open(Standing#{census => #{}}),
    Market.

%% What a good would go for at a port that grew it. Clause two of the abundance
%% says a good nobody anywhere produces goes for exactly this, wherever you
%% stand, because there is no geography for a trickle to cross.
grown(Port, Good) ->
    Standing = tom_sim:standing(Port),
    Produces = [Good | maps:get(produces, Standing)],
    {ok, Market} = tom_market:open(Standing#{produces => Produces}),
    tom_market:natural_price(Market, Good).

source_dir() ->
    filename:join(code:lib_dir(hecate_tom_world), "src").

read(Path) ->
    {ok, Bin} = file:read_file(Path),
    Bin.

near(A, B) -> abs(A - B) =< 1.0e-9 * max(abs(A), abs(B)).

%% The design quotes its worked example to about four figures, and two of its
%% numbers are out by a part in a thousand where it rounded early.
near_enough(A, B) -> abs(A - B) =< 2.0e-3 * abs(B).
