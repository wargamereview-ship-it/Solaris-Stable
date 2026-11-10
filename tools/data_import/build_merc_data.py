"""Build the data the Mercenary Company mode loads.

    python3 -I tools/data_import/build_merc_data.py <mm-data checkout> <project>

Reads (MegaMek Data, CC BY-NC-SA 4.0):
    data/universe/planetary_systems/canon_systems/*.yml   star systems, owners by date
    data/universe/factions/*.yml                          faction names, colors, tags
    data/universe/factionhints.xml                        wars, alliances, rivalries
    data/forcegenerator/<year>.xml                        unit availability by faction and era
    data/mekfiles/vehicles/**/*.blk                       combat vehicle designs
    data/images/units/mekset.txt, units/vehicles/*.png    vehicle sprites
Plus the project's data/game/designs.json and data/sources/item_aliases.json.

Writes data/game/systems.json, merc_factions.json, force_tables.json, vehicles.json and copies
vehicle sprites into assets/megamek/units/vehicles/.
"""
import json, math, pathlib, re, shutil, sys, datetime
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

import yaml

MMD = pathlib.Path(sys.argv[1])
P = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else '.')
D = MMD / 'data'
OUT = P / 'data/game'
MIN_YEAR, MAX_YEAR = 2750, 3152
MAP_MAX_YEAR = 3152      # planet owners, hiring halls, HPGs and socio-industrial codes run on past the unit data


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


# ============================================================================ factions
factions = {}
for f in sorted((D / 'universe/factions').glob('*.yml')):
    y = yaml.safe_load(f.read_text(errors='replace'))
    if not isinstance(y, dict) or 'key' not in y:
        continue
    col = y.get('color') or {}
    years = y.get('yearsActive') or []
    start = min((int(r['start']) for r in years if isinstance(r, dict) and r.get('start')), default=None)
    end = max((int(r['end']) for r in years if isinstance(r, dict) and r.get('end')), default=None)
    if any(isinstance(r, dict) and not r.get('end') for r in years):
        end = None
    factions[y['key']] = {
        'name': y.get('name', y['key']), 'color': [col.get('red', 128), col.get('green', 128), col.get('blue', 128)],
        'tags': [str(t) for t in (y.get('tags') or [])], 'capital': y.get('capital'),
        'start': start, 'end': end, 'fallback': y.get('fallBackFactions') or [],
        'camos': y.get('camos'),
        'names': sorted([[int(k), str(v)] for k, v in (y.get('nameChanges') or {}).items()]),
    }

# The Escorpión Imperio owns worlds in the planet files but has no faction file: it is Clan Goliath Scorpion's
# empire in the deep Periphery, so it borrows that Clan's colours and tables.
if 'CEI' not in factions and 'CGS' in factions:
    factions['CEI'] = dict(factions['CGS'], name='Escorpión Imperio', capital=None, start=3080, end=None,
                           fallback=['CGS'], names=[])

# ============================================================================ relations
rel = {'wars': [], 'alliances': [], 'rivals': [], 'neutral': {}}


def ydate(s):
    return year_of(s) if s else None


root = ET.parse(D / 'universe/factionhints.xml').getroot()
for node in root:
    tag = node.tag
    if tag == 'neutral':
        exc = []
        for e in node.findall('exceptions'):
            exc.append({'factions': (e.text or '').split(','), 'start': ydate(e.get('start')), 'end': ydate(e.get('end'))})
        rel['neutral'][node.get('faction')] = exc
    elif tag in ('war', 'alliance', 'rivals'):
        s0, e0 = ydate(node.get('start')), ydate(node.get('end'))
        for p in node.findall('parties'):
            names = [x.strip() for x in (p.text or '').split(',') if x.strip()]
            entry = {'name': node.get('name'), 'parties': names,
                     'start': ydate(p.get('start')) or s0, 'end': ydate(p.get('end')) or e0}
            rel[{'war': 'wars', 'alliance': 'alliances', 'rivals': 'rivals'}[tag]].append(entry)

# ============================================================================ star systems
BIOMES = ['plains', 'hills', 'forest', 'jungle', 'desert', 'badlands', 'arctic', 'urban', 'mountains', 'coast']


def biome_weights(pl, pop):
    """Battlefield terrain mix for a planet, from its water, temperature, icon and description."""
    w = {b: 0.0 for b in BIOMES}
    water = pl.get('water')
    temp = pl.get('temperature')
    icon = str(pl.get('icon') or '')
    desc = str(pl.get('desc') or '').lower()
    water = float(water) if isinstance(water, (int, float)) else 50.0
    temp = float(temp) if isinstance(temp, (int, float)) else 15.0
    life = str(pl.get('lifeForm') or '')
    w['plains'] += 1.0
    w['hills'] += 1.0
    if temp < -5 or icon.startswith('ice') or 'glacier' in desc or 'frozen' in desc or 'ice' in icon:
        w['arctic'] += 3.0
    if water < 20 or 'desert' in desc or icon.startswith('desert') or 'arid' in desc:
        w['desert'] += 2.5
        w['badlands'] += 1.5
    if water > 65 or 'ocean' in desc or 'island' in desc or 'archipelago' in desc:
        w['coast'] += 2.0
    if temp > 28 and water > 40 or 'jungle' in desc or 'rainforest' in desc:
        w['jungle'] += 2.5
    if 10 <= temp <= 30 and water >= 30 and life not in ('NONE', ''):
        w['forest'] += 2.0
    if 'mountain' in desc or 'volcan' in desc:
        w['mountains'] += 1.5
    if life in ('NONE', '') or icon.startswith('barren') or icon.startswith('rock'):
        w['badlands'] += 2.0
        w['forest'] *= 0.2
        w['jungle'] *= 0.2
    if pop and pop > 5e8:
        w['urban'] += 1.5
    elif pop and pop > 5e7:
        w['urban'] += 0.7
    else:
        w['urban'] += 0.2
    return {k: round(v, 2) for k, v in w.items() if v > 0}


systems = []
for f in sorted((D / 'universe/planetary_systems/canon_systems').glob('*.yml')):
    y = yaml.safe_load(f.read_text(errors='replace'))
    if not isinstance(y, dict) or 'xcood' not in y:
        continue
    slot = val(y.get('primarySlot'))
    planets = y.get('planet') or []
    pl = None
    for p in planets:
        if val(p.get('sysPos')) == slot:
            pl = p
            break
    if pl is None and planets:
        pl = planets[0]
    pl = pl or {}
    plv = {k: val(v) for k, v in pl.items() if k not in ('event', 'satellite', 'landmass')}
    events = list(pl.get('event') or []) + list(y.get('event') or [])
    events.sort(key=lambda e: year_of(e.get('date', '2000-01-01')))
    owners, halls, pops, socio, hpg = [], [], [], [], []
    for e in events:
        yr = year_of(e.get('date', '2000-01-01'))
        if 'faction' in e:
            fv = val(e['faction'])
            if isinstance(fv, str):
                fv = [fv]
            owners.append([yr, (fv or ['UND'])[0]])
        if 'hiringHall' in e:
            halls.append([yr, str(val(e['hiringHall']))])
        if 'population' in e:
            pops.append([yr, float(val(e['population']) or 0)])
        if 'socioIndustrial' in e:
            socio.append([yr, str(val(e['socioIndustrial']))])
        if 'hpg' in e:
            hpg.append([yr, str(val(e['hpg']))])

    def trim(seq):
        """Keep the last entry before MIN_YEAR and everything after it up to the end of MAP_MAX_YEAR."""
        before = [s for s in seq if s[0] < MIN_YEAR]
        after = [s for s in seq if MIN_YEAR <= s[0] < MAP_MAX_YEAR + 1]
        out = ([[MIN_YEAR, before[-1][1]]] if before else []) + after
        dedup = []
        for s in out:
            if not dedup or dedup[-1][1] != s[1]:
                dedup.append(s)
        return dedup

    def at(seq, year):
        v = None
        for s in seq:
            if s[0] <= year:
                v = s[1]
        return v

    pop25 = at(pops, 3025)
    rec = {
        'id': y['id'], 'name': str(val(pl.get('name')) or y['id']), 'x': float(y['xcood']), 'y': float(y['ycood']),
        'star': str(val(y.get('spectralType')) or 'G2V'),
        'owners': trim(owners), 'pop': [round(at(pops, 3025) or 0), round(at(pops, 3067) or 0)],
        'socio': trim(socio), 'hpg': trim(hpg), 'halls': trim(halls),
        'planet': {
            'water': plv.get('water'), 'temp': plv.get('temperature'), 'gravity': plv.get('gravity'),
            'atmo': plv.get('atmosphere'), 'pressure': plv.get('pressure'), 'life': plv.get('lifeForm'),
            'day': plv.get('dayLength'), 'desc': (str(plv.get('desc') or '')[:700]).strip(),
            'capital': None,
        },
        'biomes': biome_weights(plv, pop25),
    }
    for lm in pl.get('landmass') or []:
        cap = val(lm.get('capital'))
        if cap:
            rec['planet']['capital'] = str(cap)
            break
    if y.get('event'):
        for e in y['event']:
            if e.get('zenithCharge') or e.get('nadirCharge'):
                rec['recharge_station'] = True
    systems.append(rec)

# neighbours within one jump (30 ly)
grid = defaultdict(list)
for i, s in enumerate(systems):
    grid[(int(s['x'] // 30), int(s['y'] // 30))].append(i)
for i, s in enumerate(systems):
    gx, gy = int(s['x'] // 30), int(s['y'] // 30)
    nb = []
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for j in grid.get((gx + dx, gy + dy), []):
                if j == i:
                    continue
                o = systems[j]
                d = math.hypot(o['x'] - s['x'], o['y'] - s['y'])
                if d <= 30.0:
                    nb.append([j, round(d, 2)])
    nb.sort(key=lambda t: t[1])
    s['nb'] = nb

json.dump({'_source': 'MegaMek Data planetary systems (CC BY-NC-SA 4.0)', 'systems': systems},
          open(OUT / 'systems.json', 'w'), separators=(',', ':'))
json.dump({'_source': 'MegaMek Data factions and faction hints (CC BY-NC-SA 4.0)', 'factions': factions,
           'relations': rel}, open(OUT / 'merc_factions.json', 'w'), separators=(',', ':'))
print('systems', len(systems), 'factions', len(factions), 'wars', len(rel['wars']), 'alliances', len(rel['alliances']))
print('hiring halls', [s['id'] for s in systems if s['halls']])

# ============================================================================ vehicles
ALIAS = json.load(open(P / 'data/sources/item_aliases.json'))
ITEMS = json.load(open(OUT / 'items.json'))['items']
MEKSET = (MMD / 'data/images/units/mekset.txt').read_text(errors='replace')
exact, chassis_spr = {}, {}
for line in MEKSET.splitlines():
    m = re.match(r'\s*(exact|chassis)\s+"([^"]+)"\s+"([^"]+)"', line)
    if m:
        (exact if m.group(1) == 'exact' else chassis_spr).setdefault(m.group(2).lower(), m.group(3))
WRECKS = {f.stem.lower(): f.name for f in (P / 'assets/megamek/units/wrecks').glob('*.png')}

ENGINE = {0: 'fusion', 1: 'ice', 2: 'xl', 3: 'xxl', 4: 'light', 5: 'compact', 6: 'fuel_cell', 7: 'fission'}
MOTION = {'Tracked': 'tracked', 'Wheeled': 'wheeled', 'Hover': 'hover', 'VTOL': 'vtol'}
# MegaMek's armor type numbers (EquipmentType.T_ARMOR_*) for the kinds a combat vehicle carries
ARMOR = {0: 'standard', 1: 'ferro', 2: 'reactive', 3: 'reflective', 4: 'hardened', 5: 'light_ferro', 6: 'heavy_ferro',
         16: 'ferro_lamellor', 22: 'stealth', 26: 'ballistic_reinforced'}
LOCS_TANK = ['FR', 'RS', 'LS', 'RR', 'TU']
LOCS_VTOL = ['FR', 'RS', 'LS', 'RR', 'RO', 'TU']
EQ_LOC = {'Front': 'FR', 'Right': 'RS', 'Left': 'LS', 'Rear': 'RR', 'Turret': 'TU', 'Body': 'BD', 'Rotor': 'RO'}
# vehicle-only equipment with no 'Mech twin: carried as dead weight (tons) so weight checks still add up
DEAD_WEIGHT = {'ismastmount': 0.5, 'mast mount': 0.5, 'clmastmount': 0.5, 'is vehicular stealth': 0.0,
               'vehicular stealth': 0.0, 'clan vehicular stealth': 0.0,'infantry compartment': None, 'cargo': None, 'cargo (1 ton)': 1.0, 'cargo (0.5 tons)': 0.5,
               'searchlight': 0.5, 'armored chassis': None, 'communications equipment': None,
               'bridge layer (light)': 5.0, 'bridge layer (medium)': 10.0, 'bridge layer (heavy)': 20.0,
               'vehicular mine dispenser': 0.5, 'ismine dispenser': 0.5, 'troop space': None,
               'is ammo mine dispenser': 0.5, 'standard seat': 0.075, 'pillion seat': 0.025,
               'liquid storage': None, 'ammo container': None, 'field kitchen': 3.0, 'mash core component': 3.5,
               'refrigerated cargo container': None, 'insulated cargo container': None, 'isbattlearmorhandles': 0.0,
               'iscargotransport': None, 'clcargotransport': None, 'isspotter': 0.0, 'lift hoist': 3.0,
               'isliftHoist': 3.0, 'hitch': 0.0, 'is vehicle flamer ammo': 1.0, 'clan vehicle flamer ammo': 1.0,
               'is vehicle flamer ammo (1/2)': 0.5}


def blk(path):
    out, key, buf = {}, None, []
    for raw in path.read_text(errors='replace').splitlines():
        line = raw.strip()
        if line.startswith('#'):
            continue
        m = re.match(r'^<(/?)([^<>]+)>$', line)
        if m:
            if m.group(1) == '/':
                if key is not None:
                    out[key] = buf
                key, buf = None, []
            else:
                key, buf = m.group(2), []
            continue
        if key is not None and line:
            buf.append(line)
    return out


def resolve(name, clan):
    s = name.strip()
    size = None
    m = re.search(r':SIZE:([\d.]+)', s)
    if m:
        size = float(m.group(1))
        s = s[:m.start()]
    s = re.sub(r':OMNI$', '', s).strip()
    s = re.sub(r'\s*\(OMNIPOD\)', '', s, flags=re.I).strip()
    s = re.sub(r'\s*\(ST\)$', '', s).strip()
    s = re.sub(r'\s*\((T|split)\)$', '', s, flags=re.I).strip()
    if s.endswith('(R)'):
        s = s[:-3].strip()
    key = s.lower()
    for tail in (' artemis-capable', ' artemis v-capable', ' narc-capable', ' (clan)'):
        key = key.replace(tail, '')
    if key in DEAD_WEIGHT or key.replace(' ', '') in DEAD_WEIGHT:
        t = DEAD_WEIGHT.get(key, DEAD_WEIGHT.get(key.replace(' ', '')))
        return ('dead', size if t is None else t)
    want_clan = clan or key.startswith('cl') or key.startswith('clan ')
    if key.startswith('is'):
        want_clan = False
    first, second = (ALIAS['clan'], ALIAS['is']) if want_clan else (ALIAS['is'], ALIAS['clan'])
    key2 = key
    if re.match(r'cl[a-z]', key) and not key.startswith('clan'):
        key2 = 'clan ' + key[2:]
    elif re.match(r'is[a-z]', key):
        key2 = 'is ' + key[2:]
    iid = (first.get(key) or second.get(key) or first.get(key.replace(' ', '')) or second.get(key.replace(' ', ''))
           or first.get(key2) or second.get(key2))
    if not iid and key.endswith(' - full'):
        iid = first.get(key[:-7]) or second.get(key[:-7])
    if not iid and key.endswith(' - half'):
        k2 = key[:-7]
        iid = first.get(k2 + ' (1/2)') or first.get(k2 + ' half') or second.get(k2 + ' (1/2)')
    if not iid and 'vehicle flamer' in key:
        iid = 'flamer_vehicle' if 'ammo' not in key else None
    if not iid:
        # special artillery rounds (homing, cluster) are loaded like the standard ones here
        k3 = re.sub(r'\s*(homing|cluster)\s*', '', key)
        iid = first.get(k3) or second.get(k3) or first.get(k3.replace(' ', '')) or second.get(k3.replace(' ', ''))
    return ('item', iid) if iid else None


def sprite_for(name, model, motion, tons):
    s = exact.get(f'{name} {model}'.strip().lower()) or chassis_spr.get(name.lower())
    if s:
        return s
    if motion == 'vtol':
        return 'defaults/default_vtol.png'
    if motion == 'hover':
        return 'defaults/default_hover.png'
    if motion == 'wheeled':
        return 'defaults/default_wheeled_heavy.png' if tons >= 50 else 'defaults/default_wheeled.png'
    return 'defaults/default_tracked_assault.png' if tons >= 80 else (
        'defaults/default_tracked_heavy.png' if tons >= 50 else 'defaults/default_tracked.png')


def wreck_for(name, motion):
    w = WRECKS.get(name.lower())
    if w:
        return 'wrecks/' + w
    return 'wrecks/default_vtol_wreck.png' if motion == 'vtol' else 'wrecks/default_tank_wreck.png'


def suspension(motion, tons):
    if motion == 'hover':
        for lim, f in ((10, 40), (20, 85), (30, 130), (40, 175), (50, 235)):
            if tons <= lim:
                return f
        return 235
    if motion == 'vtol':
        for lim, f in ((10, 50), (20, 95), (30, 140)):
            if tons <= lim:
                return f
        return 140
    if motion == 'wheeled':
        return 20
    return 0


vehicles, skipped, unresolved = [], Counter(), Counter()
for f in sorted((D / 'mekfiles/vehicles').rglob('*.blk')):
    b = blk(f)
    ut = (b.get('UnitType') or [''])[0]
    if ut not in ('Tank', 'VTOL'):
        skipped['type ' + ut] += 1
        continue
    motion = MOTION.get((b.get('motion_type') or [''])[0])
    if not motion:
        skipped['motion'] += 1
        continue
    try:
        year = int((b.get('year') or ['9999'])[0])
        tons = float((b.get('tonnage') or ['0'])[0])
        cruise = int((b.get('cruiseMP') or ['0'])[0])
    except ValueError:
        skipped['bad number'] += 1
        continue
    if year > MAX_YEAR:
        skipped['year'] += 1
        continue
    if tons != int(tons) or tons > (100 if motion == 'tracked' else 80 if motion == 'wheeled' else 50 if motion == 'hover' else 30):
        skipped['tonnage'] += 1
        continue
    eng = ENGINE.get(int((b.get('engine_type') or ['0'])[0]))
    if eng is None:
        skipped['engine'] += 1
        continue
    at = ARMOR.get(int((b.get('armor_type') or ['0'])[0]))
    if at is None:
        skipped['armor type'] += 1
        continue
    if b.get('internal_type') and int(b['internal_type'][0]) not in (0, -1):
        skipped['structure'] += 1
        continue
    arm = [int(x) for x in b.get('armor', [])]
    if ut == 'VTOL':
        if len(arm) not in (5, 6):
            skipped['armor layout'] += 1
            continue
        locs = LOCS_VTOL[:len(arm)]
    else:
        if len(arm) not in (4, 5):
            skipped['armor layout'] += 1
            continue
        locs = LOCS_TANK[:len(arm)]
    ttype = (b.get('type') or ['IS'])[0]
    clan = 'Clan' in ttype and 'IS Chassis' not in ttype
    equip, dead, ok = [], 0.0, True
    for sect, loc in EQ_LOC.items():
        for line in b.get(f'{sect} Equipment', []):
            r = resolve(line, clan)
            if r is None:
                unresolved[line] += 1
                ok = False
                continue
            if r[0] == 'dead':
                dead += float(r[1] or 0)
            else:
                if loc == 'RO':
                    loc = 'BD'
                equip.append([r[1], 'TU' if (loc == 'TU' and len(arm) > (4 if ut == 'Tank' else 5)) else loc])
    if not ok:
        skipped['unresolved item'] += 1
        continue
    # troop and cargo space: dead weight in the fight, but it has to be in the weight check
    for line in b.get('transporters', []):
        parts = line.split(':')
        kind = parts[0].strip().lower()
        try:
            amount = float(parts[1]) if len(parts) > 1 else 0.0
        except ValueError:
            amount = 0.0
        if kind in ('troopspace', 'cargobay', 'liquidcargobay', 'insulatedcargobay', 'refrigeratedcargobay'):
            dead += amount * (1.0 if kind in ('troopspace', 'cargobay') else 1.0 / 0.91 if kind == 'liquidcargobay' else 1.15)
        elif kind == 'standardseats':
            dead += amount * 0.075
        elif kind == 'pillionseats':
            dead += amount * 0.025
        elif kind == '1stclassquarters':
            dead += amount * 10.0
        elif kind == '2ndclassquarters':
            dead += amount * 7.0
    for e in equip:
        it = ITEMS.get(e[0], {})
        if it.get('kind') == 'misc' and it.get('misc') in ('jump_jet', 'masc', 'tsm', 'hatchet', 'sword', 'mace'):
            ok = False
    if not ok:
        skipped['mech-only item'] += 1
        continue
    name = (b.get('Name') or [''])[0]
    model = (b.get('Model') or [''])[0]
    rating = max(10, cruise * int(tons) - suspension(motion, tons))
    if rating % 5:
        rating += 5 - rating % 5
    if rating > 400:
        skipped['engine > 400'] += 1
        continue
    armor = dict(zip(locs, arm))
    quirks = [q for q in b.get('quirks', [])]
    vehicles.append({
        'id': f'{name} {model}'.strip(), 'chassis': name, 'model': model, 'kind': 'vehicle', 'type': ut.lower(),
        'motion': motion, 'tons': int(tons), 'cruise': cruise, 'engine': {'rating': rating, 'type': eng},
        'armor_type': at, 'armor': armor, 'equipment': equip, 'dead_weight': round(dead, 3),
        'turret': 'TU' in armor, 'year': year, 'tech': 'Clan' if clan else ('Mixed' if 'Mixed' in ttype else 'IS'),
        'role': (b.get('role') or [None])[0], 'mul': int(b['mul id:'][0]) if b.get('mul id:') else None,
        'omni': bool(b.get('omni')), 'quirks': quirks,
        'sprite': sprite_for(name, model, motion, tons), 'wreck': wreck_for(name, motion),
    })

ids = Counter(v['id'] for v in vehicles)
seen, vfinal = set(), []
for v in vehicles:
    if ids[v['id']] > 1:
        v['id'] = f"{v['id']} ({v['tech']})"
    if v['id'] in seen:
        continue
    seen.add(v['id'])
    vfinal.append(v)
json.dump({'_source': 'MegaMek mm-data vehicle files (CC BY-NC-SA 4.0)', 'vehicles': vfinal},
          open(OUT / 'vehicles.json', 'w'), separators=(',', ':'))
print('vehicles kept', len(vfinal), 'skipped', dict(skipped))
print('unresolved vehicle items (top)', unresolved.most_common(30))
print('vehicle sprites', Counter('default' if v['sprite'].startswith('defaults') else 'found' for v in vfinal))

# copy the sprites the vehicles use, plus the vehicle fallback sprites
dst = P / 'assets/megamek/units'
(dst / 'vehicles').mkdir(parents=True, exist_ok=True)
need = {v['sprite'] for v in vfinal}
for sp in need | {f'defaults/default_{k}.png' for k in ('tracked', 'tracked_heavy', 'tracked_assault', 'wheeled',
                                                      'wheeled_heavy', 'hover', 'vtol')}:
    src = MMD / 'data/images/units' / sp
    if src.exists():
        (dst / sp).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst / sp)

# ============================================================================ force tables
DESIGNS = json.load(open(OUT / 'designs.json'))['designs']
mech_ids = {d['id'] for d in DESIGNS}
mech_by_cm = {}
for d in DESIGNS:
    mech_by_cm[(d['chassis'].lower(), d['model'].lower())] = d['id']
    if d.get('clan_name'):
        mech_by_cm[(d['clan_name'].lower(), d['model'].lower())] = d['id']
veh_by_cm = {(v['chassis'].lower(), v['model'].lower()): v['id'] for v in vfinal}


def parse_avail(text):
    out = {}
    for tok in (text or '').split(','):
        tok = tok.strip()
        if not tok:
            continue
        parts = tok.split('!')
        key = parts[0]
        if ':' in key:
            k, v = key.split(':', 1)
            v = v.rstrip('+-')
            try:
                out[k] = float(v)
            except ValueError:
                pass
        else:
            vals = []
            for p in parts[1:]:
                if ':' in p:
                    try:
                        vals.append(float(p.split(':', 1)[1].rstrip('+-')))
                    except ValueError:
                        pass
            if vals:
                out[key] = round(sum(vals) / len(vals), 2)
    return out


tables = {}
matched, missed = Counter(), Counter()
for f in sorted((D / 'forcegenerator').glob('*.xml')):
    try:
        era = int(f.stem)
    except ValueError:
        continue
    if era < 3015 or era > MAX_YEAR:
        continue
    r = ET.parse(f).getroot()
    units = r.find('units')
    out = []
    for ch in units.findall('chassis'):
        ut = ch.get('unitType')
        if ut not in ('Mek', 'Tank', 'VTOL'):
            continue
        name = ch.get('name')
        models = []
        for mo in ch.findall('model'):
            mname = mo.get('name') or ''
            key = (name.lower(), mname.lower())
            did = mech_by_cm.get(key) if ut == 'Mek' else veh_by_cm.get(key)
            if not did:
                missed[ut] += 1
                continue
            matched[ut] += 1
            av = parse_avail((mo.find('availability').text if mo.find('availability') is not None else ''))
            roles = (mo.find('roles').text if mo.find('roles') is not None else '') or ''
            models.append({'id': did, 'avail': av, 'roles': roles})
        if not models:
            continue
        av = parse_avail(ch.find('availability').text if ch.find('availability') is not None else '')
        out.append({'chassis': name, 'type': {'Mek': 'mech', 'Tank': 'vehicle', 'VTOL': 'vehicle'}[ut],
                    'avail': av, 'models': models})
    tables[str(era)] = out
json.dump({'_source': 'MegaMek Data force generator (CC BY-NC-SA 4.0)', 'eras': tables},
          open(OUT / 'force_tables.json', 'w'), separators=(',', ':'))
print('force table eras', sorted(tables), 'models matched', dict(matched), 'missed', dict(missed))
