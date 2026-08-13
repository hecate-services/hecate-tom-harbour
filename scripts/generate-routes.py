import re, json, searoute as sr

W = '/home/rl/work/github.com/hecate-services/hecate-tom-world/priv/worlds/macao.world'
world = open(W).read()

pos = {}
for m in re.finditer(r'\{(?:harbour|waypoint), #\{id => (\w+),[^\n]*\n\s*at => \{([-\d.]+), ([-\d.]+)\}', world):
    pos[m.group(1)] = (float(m.group(2)), float(m.group(3)))

routes = []
for m in re.finditer(r'\{route, #\{id => (\w+), name => <<"[^"]+">>,\s*from => (\w+), to => (\w+),\s*via => \[([^\]]*)\]', world, re.S):
    rid, frm, to, via = m.groups()
    routes.append((rid, frm, to, [v.strip() for v in via.replace('\n',' ').split(',') if v.strip()]))

NO_CANALS = ["northwest", "northeast", "suez", "panama"]

def leg(a, b):
    pa, pb = pos[a], pos[b]
    r = sr.searoute([pa[1], pa[0]], [pb[1], pb[0]], units="naut", restrictions=NO_CANALS)
    return r.properties['length'] / 3, r.geometry['coordinates']

print(f"{len(routes)} routes, {len(pos)} places\n")
print(f"{'ROUTE':22}{'LEAGUES':>9}{'PTS':>6}")
out = {}
for rid, frm, to, via in routes:
    points = [frm] + via + [to]
    total, path = 0.0, []
    for a, b in zip(points, points[1:]):
        d, c = leg(a, b)
        total += d
        path.extend(c if not path else c[1:])
    out[rid] = {"leagues": round(total), "path": [[round(y,3), round(x,3)] for x, y in path]}
    print(f"{rid:22}{round(total):>9}{len(path):>6}")
json.dump(out, open('routes.json','w'))
