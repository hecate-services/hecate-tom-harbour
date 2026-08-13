import re, json, textwrap
W = '/home/rl/work/github.com/hecate-services/hecate-tom-world/priv/worlds/macao.world'
world = open(W).read()
routes = json.load(open('routes.json'))

def erl_path(pts):
    items = ["{%s, %s}" % (lat, lng) for lat, lng in pts]
    body = ", ".join(items)
    lines = textwrap.wrap(body, width=62, break_long_words=False)
    ind = " " * 20
    return "path => [" + ("\n" + ind).join(lines) + "],"

n = 0
for rid, data in routes.items():
    pat = re.compile(r'(\{route, #\{id => %s,.*?via => \[[^\]]*\],\n)' % rid, re.S)
    m = pat.search(world)
    assert m, rid
    world = pat.sub(lambda mm: mm.group(1) + " " * 10 + erl_path(data['path']) + "\n", world, count=1)
    n += 1

world = world.replace("""%% Routes ---------------------------------------------------------------
%%
%% A route is geography: which waters lie between two ports, in order. It says
%% nothing about how long any of it takes, because that is weather, season and
%% hull, and all three are the sea's business rather than the map's.""",
"""%% Routes ---------------------------------------------------------------
%%
%% A route is geography: which waters lie between two ports, in order. It says
%% nothing about how long any of it takes, because that is weather, season and
%% hull, and all three are the sea's business rather than the map's.
%%
%% `path' IS THE SAME ROUTE AS A LINE ON THE WATER, generated rather than typed.
%% Each pair of named points is routed over a real marine network and the pieces
%% are joined, so the line hugs coasts instead of cutting corners through them,
%% and the distance of a route is the length of its own line rather than a
%% number anybody chose.
%%
%% ⚠ REGENERATE IT WITH THE CANALS TURNED OFF. Suez opens in 1869 and Panama in
%% 1914, and a modern router will happily send the Carreira through Suez and
%% halve it, which is invisible in the output and deletes the economic reason
%% this game exists. Generated 2026-08-13 with searoute 1.6.0 and restrictions
%% [northwest, northeast, suez, panama].
%%
%% ⚠ AND THE ROUTER DOES NOT KNOW THE SEASON. It answers with the shortest water
%% and has no opinion about the monsoon, so it gives the same line both ways.
%% The DIRECTIONS are the human part: Manila to Macao goes inside the reefs
%% because the strait will not have you westbound, and that is in `via' and
%% cannot be generated. Geometry from the machine, seamanship from the record.""")

open(W, 'w').write(world)
print("baked", n, "routes;", len(open(W).read().splitlines()), "lines")
