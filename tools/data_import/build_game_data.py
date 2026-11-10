"""Build the compact runtime data the Godot game loads.

    python3 -I tools/data_import/build_game_data.py .

Reads  data/equipment.json, data/sources/mm_ammo.json, data/stock_designs.json,
       data/sources/mul_battlemechs.json, assets/megamek/units/mekset.txt
Writes data/game/items.json    every 'Mech-usable weapon, ammo, misc item with a stable id
       data/game/designs.json  stock BattleMechs (biped, 20-100 tons, supported components, intro <= 3152)
                               with per-slot loadouts that reference item ids
       data/game/factions.json MUL faction id -> name
"""
import json, math, pathlib, re, sys
from collections import Counter, defaultdict

P = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.')
OUT = P / 'data/game'
OUT.mkdir(parents=True, exist_ok=True)

_MM = json.load(open(P / 'data/sources/mm_equipment_full.json'))['items']
# 'Mech-usable items first so their names win the alias lookup over battle armor / vehicle twins.
_SKIP_PATHS = ('battleArmor', 'infantry', 'bayweapons', 'capitalweapons', 'protomek', 'protos', 'aero',
               'artillery', 'tank', 'unofficial')
# Equipment the stock 'Mechs mount although MegaMek files it with artillery or ProtoMech weapons.
_KEEP = ('weapons/artillery/', 'protomekac')
_MM = [e for e in _MM if not any(s.lower() in (e.get('path') or '').lower() for s in _SKIP_PATHS)
       or any(k in (e.get('path') or '').lower() for k in _KEEP)]
_MM.sort(key=lambda e: 0 if e.get('mek') else 1)

# Numbers MegaMek keeps in parent classes the equipment parser doesn't follow (TechManual, Tactical
# Operations, Interstellar Operations). Keyed by lowercased item name, then tech base where it matters.
# Artillery ranges are in battlefield hexes: this game has no off-board fire for a 'Mech's own tubes.
OVERRIDES = {
    'arrow iv': {'IS': {'tonnage': 15, 'crits': 15}, 'CLAN': {'tonnage': 12, 'crits': 12},
                 '*': {'heat': 10, 'damage': 20, 'shortRange': 8, 'mediumRange': 20, 'longRange': 40}},
    'sniper': {'*': {'damage': 20, 'shortRange': 10, 'mediumRange': 25, 'longRange': 45}},
    'thumper': {'*': {'damage': 15, 'shortRange': 10, 'mediumRange': 25, 'longRange': 45}},
    'long tom': {'*': {'damage': 25, 'shortRange': 10, 'mediumRange': 25, 'longRange': 50}},
    'tsemp cannon': {'*': {'tonnage': 6, 'crits': 5, 'heat': 10, 'shortRange': 6, 'mediumRange': 12, 'longRange': 18}},
    'tsemp one-shot': {'*': {'tonnage': 4, 'crits': 3, 'heat': 10, 'shortRange': 6, 'mediumRange': 12, 'longRange': 18}},
    'tsemp repeating cannon': {'*': {'tonnage': 8, 'crits': 7, 'heat': 10, 'shortRange': 6, 'mediumRange': 12, 'longRange': 18}},
    'anti-battlearmor pods (b-pods)': {'*': {'tonnage': 1, 'crits': 1, 'shortRange': 1, 'mediumRange': 1, 'longRange': 1}},
    'm-pod': {'*': {'tonnage': 1, 'crits': 1, 'damage': 15, 'shortRange': 1, 'mediumRange': 2, 'longRange': 3}},
    'vehicular grenade launcher': {'*': {'tonnage': 0.5, 'crits': 1, 'shortRange': 1, 'mediumRange': 1, 'longRange': 1}},
    'plasma cannon': {'*': {'damage': 0}},
    'coolant pod': {'*': {'tonnage': 1, 'crits': 1}},
    'thunderbolt 5': {'*': {'crits': 1}}, 'thunderbolt 10': {'*': {'crits': 2}},
    'thunderbolt 15': {'*': {'crits': 3}}, 'thunderbolt 20': {'*': {'crits': 5}},
    'blue shield particle field damper': {'*': {'crits': 7}},
    'nail/rivet gun': {'*': {'tonnage': 0.5, 'crits': 1, 'shortRange': 1, 'mediumRange': 1, 'longRange': 1}},
}
# Names the stock designs use that MegaMek's own lookup lists don't carry.
EXTRA_NAMES = {'sprayer (mech)': ['MechSprayer'], 'electronic warfare (ew) equipment': ['ISElectronicWarfareEquipment'],
               'primitive prototype jump jet': ['ISPrototypeJumpJet'],
               'prototype improved jump jet': ['ISPrototypeImprovedJumpJet']}
for _e in _MM:
    _e['lookup'] = list(_e.get('lookup') or []) + EXTRA_NAMES.get(_e['name'].lower(), [])
for _e in _MM:
    _o = OVERRIDES.get(_e['name'].lower())
    if _o:
        _e.update(_o.get('*', {}))
        _e.update(_o.get(_e.get('techBase') or '', {}))
# The Arrow IV launcher comes as one entry for both tech bases; a Clan launcher is three tons lighter.
for _e in list(_MM):
    if _e['name'] == 'Arrow IV' and _e['kind'] == 'weapon' and not _e.get('techBase'):
        _is = dict(_e, techBase='IS', lookup=['ISArrowIV', 'ISArrowIVSystem', 'IS Arrow IV'], **OVERRIDES['arrow iv']['IS'])
        _cl = dict(_e, techBase='CLAN', lookup=['CLArrowIV', 'CLArrowIVSystem', 'Clan Arrow IV'], **OVERRIDES['arrow iv']['CLAN'])
        _MM.remove(_e)
        _MM += [_is, _cl]
EQ = [e for e in _MM if e['kind'] in ('weapon', 'misc')]
AMMO = [e for e in _MM if e['kind'] == 'ammo']
DESIGNS = json.load(open(P / 'data/stock_designs.json'))['designs']
MUL = json.load(open(P / 'data/sources/mul_battlemechs.json'))
MEKSET = (P / 'assets/megamek/units/mekset.txt').read_text(errors='replace')
WRECKS = {f.stem.lower(): f.name for f in (P / 'assets/megamek/units/wrecks').glob('*.png')}
MAX_YEAR = 3152

SPECIAL_DATES = {'DATE_PS': 1950, 'DATE_ES': 2100, 'DATE_NONE': None}


def yr(v):
    if isinstance(v, str):
        return SPECIAL_DATES.get(v)
    return v


def slug(s):
    return re.sub(r'[^a-z0-9]+', '_', s.lower()).strip('_')


def family(name):
    """Weapon / ammo family used to pair weapons with their ammo bins."""
    n = name.lower()
    if 'arrow iv' in n or 'arrowiv' in n: return 'arrow'
    if 'cannon' in n and ('long tom' in n or 'longtom' in n): return 'ltcannon'
    if 'cannon' in n and 'sniper' in n: return 'sncannon'
    if 'cannon' in n and 'thumper' in n: return 'thcannon'
    if 'long tom' in n or 'longtom' in n: return 'longtom'
    if n.startswith('sniper') or 'issniper' in n: return 'sniper'
    if 'thumper' in n: return 'thumper'
    if 'plasma' in n:
        return 'plcannon' if 'cannon' in n else 'hplasma' if 'heavy' in n else 'lplasma' if 'light' in n else 'plasma'
    if 'taser' in n: return 'taser'
    if 'mortar' in n: return 'mortar'
    if 'torpedo' in n or re.match(r'(cl|is)?lrt\b|lrt \d', n): return 'lrt' if 'lr' in n else 'srt'
    if re.match(r'(cl|is)?srt\b|srt \d', n): return 'srt'
    if 'heavy flamer' in n or 'heavyflamer' in n: return 'hflamer'
    if 'vehicle flamer' in n or 'flamer (vehicle)' in n or 'vehicleflamer' in n: return 'vflamer'
    if 'nail' in n and ('rivet' in n or 'gun' in n): return 'nailgun'
    if 'rifle' in n and not any(w in n for w in ('gauss', 'plasma', 'sniper', 'laser')) and \
            any(w in n for w in ('cannon', 'heavy', 'medium', 'light')): return 'riflecannon'
    if 'fluid' in n and 'gun' in n: return 'fluidgun'
    if 'chem' in n and 'laser' in n:
        return 'chemlaser' + ('l' if 'large' in n else 'm' if 'medium' in n else 's')
    if 'apds' in n or 'advanced point defense' in n: return 'apds'
    if 'coolant pod' in n: return 'coolant'
    if 'c3 remote sensor' in n or 'c3sensors' in n: return 'c3sensors'
    if 'hag' in re.split(r'[^a-z]+', n) or 'hyper-assault' in n: return 'hag'
    if 'magshot' in n: return 'magshot'
    if 'm-pod' in n or 'mpod' in n: return 'mpod'
    if 'rotary' in n: return 'rac'
    if 'ultra' in n: return 'uac'
    if re.search(r'\blb[ -]\d|lb-x|\blbx', n): return 'lbx'
    if 'hyper-velocity' in n or 'hvac' in n: return 'hvac'
    if 'light ac' in n or 'light auto' in n or n.startswith('lac'): return 'lac'
    if 'protomech' in n or 'protomek' in n: return 'pac'
    if 'ac/' in n or 'autocannon' in n or 'auto cannon' in n: return 'ac'
    if 'gauss' in n:
        if 'hyper-assault' in n or 'hag' in n: return 'hag'
        if 'anti-personnel' in n or 'ap gauss' in n: return 'apgauss'
        if 'magshot' in n: return 'magshot'
        if 'silver bullet' in n: return 'sbgauss'
        if 'improved heavy' in n: return 'ihgauss'
        if 'light' in n: return 'lgauss'
        if 'heavy' in n: return 'hgauss'
        return 'gauss'
    if 'machine gun' in n or re.search(r'\bmg\b', n):
        return 'lmg' if 'light' in n else 'hmg' if 'heavy' in n else 'mg'
    if 'streak srm' in n: return 'streak_srm'
    if 'streak lrm' in n: return 'streak_lrm'
    if 'enhanced lrm' in n or 'nlrm' in n: return 'elrm'
    if 'extended lrm' in n: return 'xlrm'
    if 'lrm' in n: return 'lrm'
    if 'srm' in n: return 'srm'
    if 'mml' in n: return 'mml'
    if 'mrm' in n: return 'mrm'
    if 'atm' in n: return 'atm'
    if 'thunderbolt' in n: return 'tbolt'
    if 'improved narc' in n or 'inarc' in n: return 'inarc'
    if 'narc' in n: return 'narc'
    if 'anti-missile' in n or re.search(r'\bams\b', n): return 'ams'
    if 'arrow iv' in n: return 'arrow'
    return None


# Weapon families that fire like an existing class: the family only names their ammunition.
WTYPE_OF = {'hflamer': 'flamer', 'vflamer': 'flamer', 'nailgun': 'other', 'riflecannon': 'ac', 'chemlaserl': 'laser', 'chemlaserm': 'laser', 'chemlasers': 'laser',
            'apds': 'ams', 'fluidgun': 'other', 'hplasma': 'plasma', 'lplasma': 'plasma', 'plcannon': 'plasma',
            'arrow': 'artillery', 'sniper': 'artillery', 'thumper': 'artillery', 'longtom': 'artillery',
            'ltcannon': 'artcannon', 'sncannon': 'artcannon', 'thcannon': 'artcannon'}


def weapon_type(name):
    n = name.lower()
    fam = family(name)
    if fam: return WTYPE_OF.get(fam, fam)
    if 'tsemp' in n: return 'tsemp'
    if 'b-pod' in n or 'grenade launcher' in n: return 'pod'
    if 'blazer' in n: return 'laser'
    if 'pulse' in n and 'laser' in n: return 'pulse'
    if 'laser' in n: return 'laser'
    if 'ppc' in n: return 'ppc'
    if 'flamer' in n: return 'flamer'
    if n.startswith('tag') or ' tag' in n: return 'tag'
    if 'rocket launcher' in n or re.match(r'rl\s?\d', n): return 'rl'
    return 'other'


MISSILE_DMG = {'mml': 1, 'lrm': 1, 'elrm': 1, 'xlrm': 1, 'streak_lrm': 1, 'mrm': 1, 'srm': 2, 'streak_srm': 2, 'atm': 2,
               'tbolt': 1, 'rl': 1, 'lrt': 1, 'srt': 2, 'mortar': 2, 'hag': 1}
CLUSTER_GROUP = {'mml': 5, 'lrm': 5, 'elrm': 5, 'xlrm': 5, 'streak_lrm': 5, 'mrm': 5, 'atm': 5, 'rl': 5, 'srm': 1,
                 'streak_srm': 1, 'lrt': 5, 'srt': 1, 'mortar': 1, 'hag': 5}
# Missile racks inherit their ranges from a parent class the parser doesn't follow (min, short, medium, long).
RANGE_DEFAULTS = {'mml': (6, 7, 14, 21), 'lrm': (6, 7, 14, 21), 'streak_lrm': (0, 7, 14, 21), 'elrm': (10, 12, 22, 38),
                  'xlrm': (10, 12, 22, 38), 'srm': (0, 3, 6, 9), 'streak_srm': (0, 3, 6, 9), 'mrm': (0, 3, 8, 15),
                  'atm': (4, 5, 10, 15), 'tbolt': (5, 6, 12, 18), 'rl': (0, 4, 9, 14), 'narc': (0, 3, 6, 9),
                  'inarc': (0, 4, 9, 15), 'lrt': (6, 7, 14, 21), 'srt': (0, 3, 6, 9)}
EXPLOSIVE_WEAPONS = {'gauss', 'lgauss', 'hgauss', 'ihgauss', 'sbgauss', 'hag', 'magshot', 'apgauss'}
# Ammunition that does not explode when its bin is hit.
INERT_AMMO = EXPLOSIVE_WEAPONS | {'nailgun', 'coolant', 'c3sensors', 'fluidgun', 'plasma', 'hplasma', 'lplasma', 'plcannon', 'taser'}

MISC_MAP = [  # (match on lowercased name, subtype)
    ('radical heat sink', 'radical_hs'), ('laser heat sink', 'laser_heat_sink'),
    ('compact heat sink', 'compact_heat_sink'),
    ('double heat sink', 'double_heat_sink'), ('heat sink', 'heat_sink'),
    ('improved jump jet', 'improved_jump_jet'), ('prototype jump jet', 'improved_jump_jet'), ('jump jet', 'jump_jet'),
    ('electronic warfare', 'ecm'), ('angel ecm', 'ecm'), ('bloodhound', 'probe'),
    ('ppc capacitor', 'ppc_capacitor'), ('partial wing', 'partial_wing'),
    ('actuator enhancement', 'aes'), ('apollo', 'apollo'), ('void signature', 'void_sig'),
    ('chameleon', 'chameleon'), ('retractable blade', 'retractable_blade'), ('vibroblade', 'vibroblade'),
    ('chain whip', 'chain_whip'), ('chainsaw', 'chainsaw'), ('mining drill', 'mining_drill'),
    ('wrecking ball', 'wrecking_ball'), ('backhoe', 'backhoe'), ('pile driver', 'pile_driver'),
    ('dual saw', 'dual_saw'), ('rock cutter', 'rock_cutter'), ('combine', 'combine'),
    ('shield (', 'shield'),
    ('blue shield', 'blue_shield'), ('harjel repair', 'harjel_repair'), ('harjel', 'harjel'),
    ('modular armor', 'modular_armor'), ('anti-personnel pod', 'apod'), ('laser insulator', 'laser_insulator'),
    ('booby trap', 'booby_trap'), ('chaff pod', 'chaff'),
    ('risc emergency coolant', 'coolant_system'),
    ('case ii', 'case2'), ('case', 'case'), ('artemis iv', 'artemis'), ('artemis v', 'artemis'),
    ('masc', 'masc'), ('triple strength myomer', 'tsm'), ('targeting computer', 'tc'),
    ('hatchet', 'hatchet'), ('sword', 'sword'), ('mace', 'mace'), ('guardian ecm', 'ecm'), ('ecm suite', 'ecm'),
    ('beagle active probe', 'probe'), ('active probe', 'probe'), ('c3', 'c3'), ('command console', 'command_console'),
    ('anti-missile', 'ams'), ('supercharger', 'supercharger'), ('null signature', 'stealth'),
]


WORD_MISC = {'lance': 'lance', 'claw': 'claw', 'talons': 'talons', 'spikes': 'spikes', 'umu': 'umu',
             'turret': 'turret'}


def misc_type(name):
    n = name.lower()
    for w in re.split(r'[^a-z]+', n):
        if w in WORD_MISC:
            return WORD_MISC[w]
    for k, v in MISC_MAP:
        if k in n:
            return v
    return 'other'


# ----------------------------------------------------------------------------- items
items = {}
alias_is, alias_cl = {}, {}


def register(item, names):
    for nm in names:
        if not nm: continue
        for k in {nm.strip().lower(), nm.strip().lower().replace(' ', '')}:
            if item['tech'] in ('IS', 'ALL'):
                alias_is.setdefault(k, item['id'])
            if item['tech'] in ('CLAN', 'ALL'):
                alias_cl.setdefault(k, item['id'])


def new_id(base, tech):
    i = ('cl_' if tech == 'CLAN' else '') + slug(base)
    j, n = i, 2
    while j in items:
        j = f'{i}_{n}'; n += 1
    return j


def dates_of(e, tech):
    d = e.get('is') if tech != 'CLAN' else e.get('clan')
    d = d or e.get('both') or e.get('is') or e.get('clan') or {}
    intro = yr(d.get('production')) or yr(d.get('prototype')) or yr(d.get('common'))
    return {'intro': intro, 'proto': yr(d.get('prototype')), 'extinct': yr(d.get('extinct')),
            'reintro': yr(d.get('reintroduced'))}


for e in EQ:
    if e['kind'] == 'armor':
        continue
    tech = e.get('techBase') or 'ALL'
    it = {'id': new_id(e['name'], tech), 'name': e['name'], 'kind': e['kind'], 'tech': tech,
          'tons': e.get('tonnage'), 'crits': e.get('crits'), 'bv': e.get('bv', 0), 'cost': e.get('cost', 0),
          'rating': e.get('techRating'), 'avail': e.get('availability_SL_SW_CI_DA'), **dates_of(e, tech)}
    if e['kind'] == 'weapon':
        wt = weapon_type(e['name'])
        rack = e.get('rackSize')
        it.update({'wtype': wt, 'heat': e.get('heat', 0), 'min': e.get('minRange', 0) or 0,
                   's': e.get('shortRange', 0), 'm': e.get('mediumRange', 0), 'l': e.get('longRange', 0)})
        if not it['l'] and wt in RANGE_DEFAULTS:
            mn, s, md, lg = RANGE_DEFAULTS[wt]
            it.update({'min': 0 if tech == 'CLAN' else mn, 's': s, 'm': md, 'l': lg})
        if wt in MISSILE_DMG:
            it['rack'] = rack or 0
            it['dmg'] = MISSILE_DMG[wt]
            it['group'] = CLUSTER_GROUP.get(wt, 1)
        else:
            it['dmg'] = e.get('damage', rack or 0) or 0
            if rack: it['rack'] = rack
        fam = family(e['name'])
        if fam and fam not in ('ams',) or fam == 'ams':
            if fam:
                it['ammo'] = f"{fam}{rack or it['dmg'] or ''}{'c' if tech == 'CLAN' else ''}"
        if 'one-shot' in e['name'].lower() or '(os)' in e['name'].lower() or '(i-os)' in e['name'].lower() \
                or wt in ('mpod', 'pod'):
            it.pop('ammo', None); it['oneshot'] = True
        if wt in EXPLOSIVE_WEAPONS: it['explodes'] = True
        if wt in ('mg', 'lmg', 'hmg', 'flamer', 'ams', 'pod'): it['antipersonnel'] = True
        if fam and fam != wt: it['fam'] = fam          # the exact weapon behind a shared firing class
        if 'c3' in e['name'].lower() and 'master' in e['name'].lower(): it['c3'] = True
    else:
        it['misc'] = misc_type(e['name'])
    it['mek'] = bool(e.get('mek'))
    items[it['id']] = it
    register(it, [e['name'], e.get('internalName')] + e.get('lookup', []))

for a in AMMO:
    tech = a.get('techBase') or 'ALL'
    fam = family(a['name']) or family(a.get('internalName') or '')
    if not fam:
        continue
    rack = a.get('rackSize') or 0
    shots = a.get('shots') or 0
    half = '(1/2)' in a['name'] or 'half' in a['name'].lower()
    it = {'id': new_id(a['name'], tech), 'name': a['name'], 'kind': 'ammo', 'tech': tech, 'tons': 0.5 if half else 1.0,
          'crits': 1, 'bv': a.get('bv', 0), 'cost': a.get('cost', 0), 'rating': a.get('techRating'),
          'avail': a.get('availability_SL_SW_CI_DA'), 'shots': shots,
          'ammo': f"{fam}{rack or ''}{'c' if tech == 'CLAN' else ''}", **dates_of(a, tech)}
    it['explosive'] = fam not in INERT_AMMO  # gauss slugs, coolant and plasma foam are inert
    items[it['id']] = it
    register(it, [a['name'], a.get('internalName')] + a.get('lookup', []))

# A weapon's ammo key has to name a bin that exists. The key built above carries a Gauss rifle's
# damage (gauss15) where its ammo has none (gauss); MMLs draw on LRM ammo; Streak LRM ammo is Clan only.
_bins = {i['ammo'] for i in items.values() if i['kind'] == 'ammo'}
for i in items.values():
    k = i.get('ammo')
    if i['kind'] != 'weapon' or not k or k in _bins:
        continue
    _fam, _n, _c = re.match(r'^([a-z_]+?)(\d*)(c?)$', k).groups()
    for alt in (_fam + _c, 'lrm' + _n + _c if _fam == 'mml' else '', k + 'c'):
        if alt in _bins:
            i['ammo'] = alt
            break
# A weapon both tech bases build (artillery, mortars) takes the Clan-made rounds too.
_wkeys = {i['ammo'] for i in items.values() if i['kind'] == 'weapon' and i.get('ammo')}
for i in items.values():
    k = i.get('ammo')
    if i['kind'] == 'ammo' and k and k not in _wkeys and k.endswith('c') and k[:-1] in _wkeys:
        i['ammo'] = k[:-1]

# Fixed structural slot tags (not items).
STRUCT = {
    'shoulder': 'shoulder', 'upper arm actuator': 'upper_arm', 'lower arm actuator': 'lower_arm',
    'hand actuator': 'hand', 'hip': 'hip', 'upper leg actuator': 'upper_leg', 'lower leg actuator': 'lower_leg',
    'foot actuator': 'foot', 'life support': 'life_support', 'sensors': 'sensors', 'cockpit': 'cockpit',
    'small cockpit': 'cockpit', 'fusion engine': 'engine', 'engine': 'engine', 'gyro': 'gyro', 'xl gyro': 'gyro',
    'compact gyro': 'gyro', 'heavy duty gyro': 'gyro', 'endo steel': 'endo', 'is endo steel': 'endo',
    'clan endo steel': 'endo', 'endo-steel': 'endo', 'isendosteel': 'endo', 'clendosteel': 'endo',
    'ferro-fibrous': 'ferro', 'is ferro-fibrous': 'ferro', 'clan ferro-fibrous': 'ferro', 'isferrofibrous': 'ferro',
    'clferrofibrous': 'ferro', 'light ferro-fibrous': 'ferro', 'is light ferro-fibrous': 'ferro',
    'heavy ferro-fibrous': 'ferro', 'is heavy ferro-fibrous': 'ferro', 'islightferrofibrous': 'ferro',
    'isheavyferrofibrous': 'ferro', 'triple strength myomer': 'tsm', 'ism triple strength myomer': 'tsm',
    'istsm': 'tsm', 'tsm': 'tsm',
}
# Slots taken by the newer armors, structures and myomers use the same filler tags: the design's
# armor_type / structure / myomer says which kind they are.
for _k in ('stealth', 'is stealth', 'clan stealth', 'ferro-lamellor', 'clan ferro-lamellor', 'reactive', 'is reactive',
           'clan reactive', 'reflective', 'is reflective', 'clan reflective', 'laser-reflective', 'is laser-reflective',
           'clan laser-reflective', 'islaserreflective', 'cllaserreflective', 'ballistic-reinforced',
           'is ballistic-reinforced', 'isballisticreinforced', 'impact-resistant', 'is impact-resistant',
           'isimpactresistant', 'anti-penetrative ablation', 'is anti-penetrative ablation', 'isantipenetrativeablation',
           'heat-dissipating', 'is heat-dissipating', 'clan heat-dissipating', 'isheatdissipating',
           'ferro-fibrous prototype', 'is ferro-fibrous prototype', 'isferrofibrousprototype', 'isreactive', 'clreactive',
           'isreflective', 'clreflective', 'isstealth', 'clferrolamellor'):
    STRUCT[_k] = 'ferro'
for _k in ('endo-composite', 'is endo-composite', 'clan endo-composite', 'isendocomposite', 'clendocomposite',
           'endo steel prototype', 'is endo steel prototype', 'isendosteelprototype', 'endo-steel prototype',
           'is endo-steel prototype'):
    STRUCT[_k] = 'endo'
for _k in ('industrial triple strength myomer', 'isindustrialtsm', 'industrial tsm', 'is industrial tsm',
           'super-cooled myomer', 'is super-cooled myomer', 'issupercooledmyomer', 'scm'):
    STRUCT[_k] = 'tsm'
for _k in ('industrial cockpit', 'primitive cockpit', 'primitive industrial cockpit', 'interface cockpit',
           'ice engine', 'fuel cell engine', 'fission engine', 'fuel-cell engine', 'i.c.e. engine'):
    STRUCT[_k] = 'cockpit' if 'cockpit' in _k else 'engine'
for k in list(STRUCT):
    STRUCT[k.replace(' ', '')] = STRUCT[k]

# Canonical ids that the game code looks up by name.
def find(name, clan=False):
    return (alias_cl if clan else alias_is).get(name.lower())

CANON = {'heat_sink': find('Heat Sink'), 'double_heat_sink': find('ISDoubleHeatSink') or find('Double Heat Sink'),
         'cl_double_heat_sink': find('CLDoubleHeatSink', True), 'jump_jet': find('Jump Jet'),
         'case': find('ISCASE') or find('CASE'), 'hatchet': find('Hatchet')}

# ----------------------------------------------------------------------------- designs
ENGINES = {'fusion engine': 'standard', 'fusion engine(is)': 'standard', 'fusion (clan) engine': 'standard',
           'xl engine': 'xl', 'xl engine(is)': 'xl', 'xl (clan) engine': 'xl_clan', 'light engine': 'light',
           'light engine(is)': 'light', 'xxl engine': 'xxl', 'xxl engine(is)': 'xxl', 'xxl (clan) engine': 'xxl_clan',
           'compact engine': 'compact', 'compact engine(is)': 'compact',
           'ice engine': 'ice', 'ice engine(is)': 'ice', 'fuel cell engine': 'fuel_cell',
           'fuel cell (clan) engine': 'fuel_cell', 'fission engine': 'fission'}
STRUCTURES = {'IS Standard': 'standard', 'Clan Standard': 'standard', 'Standard': 'standard',
              'IS Endo Steel': 'endo', 'Clan Endo Steel': 'endo_clan',
              'IS Industrial': 'industrial', 'Clan Industrial': 'industrial',
              'IS Endo-Composite': 'endo_composite', 'Clan Endo-Composite': 'endo_composite_clan',
              'IS Composite': 'composite', 'IS Reinforced': 'reinforced', 'Clan Reinforced': 'reinforced',
              'IS Endo Steel Prototype': 'endo_proto'}
ARMORS = {'Standard(Inner Sphere)': 'standard', 'Standard(Clan)': 'standard', 'Ferro-Fibrous(Inner Sphere)': 'ferro',
          'Ferro-Fibrous(Clan)': 'ferro_clan', 'Light Ferro-Fibrous(Inner Sphere)': 'light_ferro',
          'Heavy Ferro-Fibrous(Inner Sphere)': 'heavy_ferro',
          'Stealth(Inner Sphere)': 'stealth', 'Ferro-Lamellor(Clan)': 'ferro_lamellor',
          'Reflective(Inner Sphere)': 'reflective', 'Reflective(Clan)': 'reflective_clan',
          'Reactive(Inner Sphere)': 'reactive', 'Reactive(Clan)': 'reactive_clan',
          'Hardened(Inner Sphere)': 'hardened', 'Hardened(Clan)': 'hardened',
          'Heavy Industrial(Inner Sphere)': 'heavy_industrial', 'Heavy Industrial(Clan)': 'heavy_industrial',
          'Industrial(Inner Sphere)': 'industrial', 'Commercial(Inner Sphere)': 'commercial',
          'Primitive(Inner Sphere)': 'primitive', 'Ballistic-Reinforced(Inner Sphere)': 'ballistic_reinforced',
          'Impact-Resistant(Inner Sphere)': 'impact_resistant',
          'Anti-Penetrative Ablation(Inner Sphere)': 'anti_penetrative',
          'Heat-Dissipating(Inner Sphere)': 'heat_dissipating', 'Heat-Dissipating(Clan)': 'heat_dissipating',
          'Ferro-Fibrous Prototype(Inner Sphere)': 'ferro_proto'}
GYROS = {None: 'standard', 'Standard Gyro': 'standard', 'XL Gyro': 'xl', 'Compact Gyro': 'compact',
         'Heavy Duty Gyro': 'heavy_duty', 'None': 'none'}
COCKPITS = {None: 'standard', 'Standard Cockpit': 'standard', 'Small Cockpit': 'small',
            'Torso-Mounted Cockpit': 'torso', 'Command Console': 'command_console',
            'Industrial Cockpit': 'industrial', 'Primitive Cockpit': 'primitive',
            'Primitive Industrial Cockpit': 'primitive_industrial', 'Interface Cockpit': 'interface'}
HS = {'Single': 'single', 'IS Double': 'double', 'Clan Double': 'double_clan', 'Laser': 'laser',
      'Compact': 'compact'}
LOCS = ['HD', 'CT', 'LT', 'RT', 'LA', 'RA', 'LL', 'RL']

# sprite index
exact, chassis_spr = {}, {}
for line in MEKSET.splitlines():
    m = re.match(r'\s*(exact|chassis)\s+"([^"]+)"\s+"([^"]+)"', line)
    if not m: continue
    if not m.group(3).startswith('meks/'): continue     # a DropShip can share a 'Mech's name
    (exact if m.group(1) == 'exact' else chassis_spr).setdefault(m.group(2).lower(), m.group(3))
# the set lists some Clan 'Mechs under both names, "Vulture (Mad Dog)": also reachable by the first alone
exact_alt, chassis_alt = {}, {}
for src, alt in ((exact, exact_alt), (chassis_spr, chassis_alt)):
    for k, v in src.items():
        a = re.sub(r'\s*\([^)]*\)', '', k)
        if a != k: alt.setdefault(a, v)


def sprite_for(d):
    names = [d['chassis']] + ([d['clanName']] if d.get('clanName') else [])
    for c in names:
        s = exact.get(f"{c} {d['model']}".lower())
        if s: return s
    for c in names:
        s = chassis_spr.get(c.lower())
        if s: return s
    for c in names:
        s = exact_alt.get(f"{c} {d['model']}".strip().lower()) or chassis_alt.get(c.lower())
        if s: return s
    t = d['tonnage']
    return 'defaults/default_%s.png' % ('light' if t < 40 else 'medium' if t < 60 else 'heavy' if t < 80 else 'assault')


def wreck_for(d):
    for c in [d['chassis'], d.get('clanName') or '']:
        w = WRECKS.get(c.lower())
        if w: return 'wrecks/' + w
    return 'wrecks/default_mech_wreck.png'


mul_by_id = {m['id']: m for m in MUL['battlemechs']}
out, skipped, unresolved = [], Counter(), Counter()
for d in DESIGNS:
    if d['config'] not in ('Biped', 'Biped OmniMek'):
        skipped['config'] += 1; continue
    if not isinstance(d['year'], int) or d['year'] > MAX_YEAR:
        skipped['year'] += 1; continue
    m = re.match(r'(\d+)\s+(.*)$', d['engine'] or '')
    etype = ENGINES.get(m.group(2).strip().lower()) if m else None
    st, ar = STRUCTURES.get(d['structure']), ARMORS.get(d['armorType'])
    gy, ck = GYROS.get(d['gyro']), COCKPITS.get(d['cockpit'])
    hsm = re.match(r'(\d+)\s+(.*)$', d['heatSinks'] or '')
    hst = HS.get(hsm.group(2).strip()) if hsm else None
    myo = {'Standard': 'standard', 'Triple-Strength': 'tsm', 'Industrial Triple-Strength': 'industrial_tsm',
           'Super-Cooled': 'super_cooled'}.get(d['myomer'])
    if not (20 <= d['tonnage'] <= 100) or d['tonnage'] % 5:
        skipped['tonnage'] += 1; continue
    bad = [k for k, v in (('engine', etype), ('structure', st), ('armor', ar), ('gyro', gy), ('cockpit', ck),
                          ('heatsinks', hst), ('myomer', myo)) if v is None]
    if bad:
        skipped['unsupported_' + bad[0]] += 1; continue
    clan_pref = d['techBase'] in ('Clan', 'Mixed (Clan Chassis)')
    slots, ok = {}, True
    for loc in LOCS:
        row = []
        for raw in d['crits'].get(loc, []):
            s = raw.strip()
            if s in ('-Empty-', ''):
                row.append(''); continue
            rear = False
            s = re.sub(r'\s*\(OMNIPOD\)', '', s, flags=re.I)
            s = re.sub(r'\s*\(armored\)', '', s, flags=re.I)
            size = re.search(r':SIZE:([\d.]+)', s)
            s = re.sub(r':SIZE:[\d.]+', '', s)
            if s.endswith('(R)'):
                rear = True; s = s[:-3].strip()
            s = re.sub(r'\s*\((T|split)\)$', '', s, flags=re.I)
            key = s.lower()
            for tail in (' artemis-capable', ' artemis v-capable', ' narc-capable', ' (clan)'):
                key = key.replace(tail, '')
            if re.match(r'cl[a-z]', key) and not key.startswith('clan'):
                key2 = 'clan ' + key[2:]
            elif re.match(r'is[a-z]', key):
                key2 = 'is ' + key[2:]
            else:
                key2 = key
            if key in STRUCT or key.replace(' ', '') in STRUCT:
                row.append(STRUCT.get(key) or STRUCT[key.replace(' ', '')]); continue
            want_clan = clan_pref
            if key.startswith('cl') or key.startswith('clan '): want_clan = True
            elif key.startswith('is'): want_clan = False
            first, second = (alias_cl, alias_is) if want_clan else (alias_is, alias_cl)
            iid = (first.get(key) or second.get(key) or first.get(key.replace(' ', '')) or
                   second.get(key.replace(' ', '')) or first.get(key2) or second.get(key2))
            if not iid and key.endswith(' - full'):
                iid = first.get(key[:-7]) or second.get(key[:-7])
            if not iid and key.endswith(' - half'):
                k2 = key[:-7]
                iid = first.get(k2 + ' (1/2)') or first.get(k2 + ' half') or second.get(k2 + ' (1/2)')
            if not iid and (key.startswith('is ') or key.startswith('clan ')):
                k4 = key.split(' ', 1)[1]
                iid = first.get(k4) or second.get(k4)
            if not iid:
                # special rounds (homing, cluster) are loaded like the standard ones here
                k3 = re.sub(r'\s*(homing|cluster)\s*', '', key)
                iid = first.get(k3) or second.get(k3) or first.get(k3.replace(' ', '')) or second.get(k3.replace(' ', ''))
            if not iid:
                unresolved[s] += 1; ok = False; row.append('?'); continue
            if size and items[iid].get('tons') is None:
                # cargo, liquid storage, fuel: the design says how many tons; one crit slot per ton
                tons_ = float(size.group(1))
                vid = '%s_%st' % (iid, ('%g' % tons_).replace('.', '_'))
                if vid not in items:
                    items[vid] = dict(items[iid], id=vid, name='%s (%g t)' % (items[iid]['name'], tons_), tons=tons_,
                                      crits=max(1, math.ceil(tons_)))
                iid = vid
            row.append(iid + ('@R' if rear else ''))
        slots[loc] = row
    if not ok:
        skipped['unresolved_item'] += 1; continue
    arm = d['armor']
    armor = {loc: arm.get(loc, 0) for loc in LOCS}
    for loc in ('CT', 'LT', 'RT'):
        armor[loc + 'R'] = arm.get(loc + '_rear', 0)
    mulrec = mul_by_id.get((d.get('mul') or {}).get('id')) if d.get('mul') else None
    rec = {
        'id': f"{d['chassis']} {d['model']}".strip(), 'chassis': d['chassis'], 'model': d['model'],
        'clan_name': d.get('clanName'), 'tons': int(d['tonnage']),
        'tech': {'Inner Sphere': 'IS', 'Clan': 'Clan'}.get(d['techBase'], 'Mixed'),
        'omni': 'Omni' in d['config'], 'year': d['year'], 'role': d.get('role'),
        'bv': (d.get('mul') or {}).get('bv'), 'engine': {'rating': int(m.group(1)), 'type': etype},
        'structure': st, 'armor_type': ar, 'gyro': gy, 'cockpit': ck, 'myomer': myo,
        'hs': {'count': int(hsm.group(1)), 'type': hst}, 'walk': d['walk'], 'jump': d['jump'],
        'armor': armor, 'slots': slots, 'quirks': d.get('quirks') or [],
        'sprite': sprite_for(d), 'wreck': wreck_for(d),
        'avail': {str(k): v for k, v in (mulrec or {}).get('avail', {}).items()} if mulrec else {},
    }
    out.append(rec)

ids = Counter(r['id'] for r in out)
for r in out:
    if ids[r['id']] > 1:
        r['id'] = f"{r['id']} ({r['tech']})"
seen = set()
final = []
for r in out:
    if r['id'] in seen: continue
    seen.add(r['id']); final.append(r)

used = set()
for r in final:
    for row in r['slots'].values():
        for s in row:
            if s and s.split('@')[0] in items: used.add(s.split('@')[0])

json.dump({'_source': 'Built by tools/data_import/build_game_data.py from MegaMek data (CC BY-NC-SA 4.0)',
           'canonical': CANON, 'items': items}, open(OUT / 'items.json', 'w'), separators=(',', ':'))
json.dump({'_source': 'MegaMek mm-data stock designs + MUL availability (CC BY-NC-SA 4.0)', 'max_year': MAX_YEAR,
           'designs': final}, open(OUT / 'designs.json', 'w'), separators=(',', ':'))
json.dump({'eras': MUL['eras'], 'factions': {str(f['id']): f['name'] for f in MUL['factions']}},
          open(OUT / 'factions.json', 'w'), indent=1)

print('items', len(items), 'used by designs', len(used))
print('designs kept', len(final), 'skipped', dict(skipped))
print('unresolved crit names (top)', unresolved.most_common(25))
print('canonical', CANON)
print('sprites: exact/chassis/default', Counter('default' if r['sprite'].startswith('defaults') else 'found' for r in final))

# ----------------------------------------------------------------------------- component tech dates
# Construction components (engines, structure, armor, gyros, cockpits, sinks, myomer) with Inner Sphere
# market dates. 'clan_only' parts never appear on Inner Sphere markets except as post-3050 salvage.
CT_ = json.load(open(P / 'data/equipment.json'))['component_tech']


def ct(key):
    d = CT_[key].get('dates') or CT_[key].get('dates_is') or {}
    return {'intro': yr(d.get('production')) or yr(d.get('prototype')), 'extinct': yr(d.get('extinct')),
            'reintro': yr(d.get('reintroduced'))}


def from_item(iid):
    it = items[iid]
    return {'intro': it['intro'], 'extinct': it['extinct'], 'reintro': it['reintro']}


tsm = next(i for i in items.values() if i.get('misc') == 'tsm' and i['tech'] != 'CLAN')
components = {
    'engine': {'standard': {'intro': 2100}, 'xl': ct('engine_is_xl'), 'xl_clan': {'clan_only': True},
               'light': ct('engine_light_fusion'), 'compact': ct('engine_compact_fusion'),
               'xxl': ct('engine_is_xxl'), 'xxl_clan': {'clan_only': True},
               'ice': {'intro': 2100}, 'fuel_cell': {'intro': 2300}, 'fission': {'intro': 2470}},
    'structure': {'standard': {'intro': 2100}, 'endo': ct('endo_steel_is'), 'endo_clan': {'clan_only': True},
                  'industrial': {'intro': 2350}, 'endo_composite': {'intro': 3067},
                  'endo_composite_clan': {'clan_only': True}, 'composite': {'intro': 3061},
                  'reinforced': {'intro': 3057}, 'endo_proto': {'intro': 2471, 'extinct': 2571}},
    'armor': {'standard': {'intro': 2100}, 'ferro': {'intro': 2571, 'extinct': 2810, 'reintro': 3040},
              'ferro_clan': {'clan_only': True}, 'light_ferro': {'intro': 3067}, 'heavy_ferro': {'intro': 3069},
              'stealth': {'intro': 3063}, 'ferro_lamellor': {'clan_only': True}, 'reflective': {'intro': 3061},
              'reflective_clan': {'clan_only': True}, 'reactive': {'intro': 3063},
              'reactive_clan': {'clan_only': True}, 'hardened': {'intro': 3047},
              'heavy_industrial': {'intro': 2460}, 'industrial': {'intro': 2439}, 'commercial': {'intro': 2300},
              'primitive': {'intro': 2290}, 'ballistic_reinforced': {'intro': 3131},
              'impact_resistant': {'intro': 3103}, 'anti_penetrative': {'intro': 3114},
              'heat_dissipating': {'intro': 3123}, 'ferro_proto': {'intro': 2557, 'extinct': 2571}},
    'gyro': {'standard': {'intro': 2100}, 'xl': {'intro': 3067}, 'compact': {'intro': 3068},
             'heavy_duty': {'intro': 3067}, 'none': {'intro': 3074}},
    'cockpit': {'standard': {'intro': 2100}, 'small': {'intro': 3067}, 'torso': {'intro': 3053},
                'industrial': {'intro': 2469}, 'primitive': {'intro': 2430},
                'primitive_industrial': {'intro': 2300}, 'interface': {'intro': 3074},
                'command_console': {'intro': 2631, 'extinct': 2850, 'reintro': 3030}},
    'hs': {'single': {'intro': 2100}, 'double': from_item('double_heat_sink'), 'double_clan': {'clan_only': True},
           'laser': {'clan_only': True}, 'compact': {'intro': 3058}},
    'myomer': {'standard': {'intro': 2100}, 'tsm': {'intro': tsm['intro'], 'extinct': tsm['extinct'],
                                                     'reintro': tsm['reintro']},
               'industrial_tsm': {'intro': 3045}, 'super_cooled': {'intro': 3132}},
}
json.dump(components, open(OUT / 'components.json', 'w'), indent=1)
print('components', json.dumps(components)[:400])

# ----------------------------------------------------------------------------- name aliases for other importers
# build_merc_data.py resolves vehicle equipment names with the same lookup tables.
json.dump({'is': alias_is, 'clan': alias_cl}, open(P / 'data/sources/item_aliases.json', 'w'), separators=(',', ':'))
