"""Carry the star map's dated planet data (owners, hiring halls, socio-industrial codes, HPGs) past the
year the rest of the merc data stops at, without touching anything else in data/game/systems.json.

    python3 -I tools/data_import/extend_systems.py <mm-data checkout> <project> [--dry-run]

Reads data/universe/planetary_systems/canon_systems/*.yml from MegaMek Data (CC BY-NC-SA 4.0).
Every system keeps its index, position, neighbours and its history up to KEEP_UNTIL exactly as
build_merc_data.py wrote them; entries dated after that, up to MAP_MAX_YEAR, are appended.
Systems are matched by id, so a save's system numbers stay valid.
"""
import datetime, json, pathlib, sys
from collections import Counter

import yaml

MMD = pathlib.Path(sys.argv[1])
P = pathlib.Path(sys.argv[2])
DRY = '--dry-run' in sys.argv
KEEP_UNTIL = 3090.0      # build_merc_data.py kept entries up to MAX_YEAR + 5
MAP_MAX_YEAR = 3152.999
SERIES = {'owners': 'faction', 'halls': 'hiringHall', 'socio': 'socioIndustrial', 'hpg': 'hpg'}


def val(x):
    """MegaMek YAML wraps sourced values as {source, value}."""
    if isinstance(x, dict) and 'value' in x:
        return x['value']
    return x


def year_of(date):
    if isinstance(date, (datetime.date, datetime.datetime)):
        d = date
    else:
        s = str(date)
        try:
            d = datetime.date.fromisoformat(s[:10])
        except ValueError:
            return float(s[:4])
    return round(d.year + (d.timetuple().tm_yday - 1) / 365.25, 3)


def history(y):
    """The dated series of a system's primary planet, as build_merc_data.py reads them."""
    slot = val(y.get('primarySlot'))
    planets = y.get('planet') or []
    pl = next((p for p in planets if val(p.get('sysPos')) == slot), planets[0] if planets else {}) or {}
    events = list(pl.get('event') or []) + list(y.get('event') or [])
    events.sort(key=lambda e: year_of(e.get('date', '2000-01-01')))
    out = {k: [] for k in SERIES}
    for e in events:
        yr = year_of(e.get('date', '2000-01-01'))
        if 'faction' in e:
            fv = val(e['faction'])
            if isinstance(fv, str):
                fv = [fv]
            out['owners'].append([yr, (fv or ['UND'])[0]])
        for k in ('halls', 'socio', 'hpg'):
            if SERIES[k] in e:
                out[k].append([yr, str(val(e[SERIES[k]]))])
    return out


src = {}
for f in sorted((MMD / 'data/universe/planetary_systems/canon_systems').glob('*.yml')):
    y = yaml.safe_load(f.read_text(errors='replace'))
    if isinstance(y, dict) and 'xcood' in y:
        src[y['id']] = y

path = P / 'data/game/systems.json'
raw = path.read_text()
doc = json.loads(raw)
assert json.dumps(doc, separators=(',', ':')) == raw, 'systems.json is not in the format this tool writes'

missing, moved, differs, added = [], [], Counter(), Counter()
for s in doc['systems']:
    y = src.get(s['id'])
    if y is None:
        missing.append(s['id'])
        continue
    if abs(float(y['xcood']) - s['x']) > 0.01 or abs(float(y['ycood']) - s['y']) > 0.01:
        moved.append(s['id'])
    h = history(y)
    for k in SERIES:
        old = [e for e in s.get(k, []) if e[0] <= KEEP_UNTIL]
        # what the source says the value was at KEEP_UNTIL, against what the game has
        at_src = None
        for e in h[k]:
            if e[0] <= KEEP_UNTIL:
                at_src = e[1]
        if old and at_src is not None and old[-1][1] != at_src:
            differs[k] += 1
        new = list(old)
        for e in h[k]:
            if KEEP_UNTIL < e[0] <= MAP_MAX_YEAR and (not new or new[-1][1] != e[1]):
                new.append(e)
                added[k] += 1
        if new or k in s:
            s[k] = new

print('systems', len(doc['systems']), 'in source', len(src), 'missing from source', len(missing), missing[:8])
print('moved', len(moved), moved[:8])
print('entries added after %d:' % KEEP_UNTIL, dict(added))
print('systems whose value at %d differs from the source (left as they are):' % KEEP_UNTIL, dict(differs))
by_year = Counter()
for s in doc['systems']:
    for e in s['owners']:
        if e[0] > KEEP_UNTIL:
            by_year[int(e[0])] += 1
print('owner changes by year:', sorted(by_year.items()))
print('hiring halls after %d:' % KEEP_UNTIL, [(s['id'], e) for s in doc['systems'] for e in s.get('halls', []) if e[0] > KEEP_UNTIL])
if not DRY:
    path.write_text(json.dumps(doc, separators=(',', ':')))
    print('wrote', path)
