"""Build solaris_stable/data/*.json from MegaMek sources, MUL export and hand-checked rules.

python3 -I build_data.py <scratchpad> <project_dir>
"""
import json, math, pathlib, re, sys

S = pathlib.Path(sys.argv[1]); P = pathlib.Path(sys.argv[2])
DATA = P / 'data'; DATA.mkdir(exist_ok=True)

# ---------------------------------------------------------------- construction
eng_src = (S / 'mm/megamek/src/megamek/common/equipment/Engine.java').read_text()
arr = re.search(r'ENGINE_RATINGS\s*=\s*\{([^}]*)\}', eng_src).group(1)
vals = [float(x) for x in re.findall(r'[\d.]+', arr)]
std_engine = {str(i * 5): v for i, v in enumerate(vals) if 10 <= i * 5 <= 400}

mek_src = (S / 'mm/megamek/src/megamek/common/units/Mek.java').read_text()
is_rows = re.findall(r'case (\d+) -> new int\[\] \{ (\d+), (\d+), (\d+), (\d+), (\d+) \}', mek_src)
structure = {}
for t, hd, ct, st, arm, leg in is_rows:
    t = int(t)
    if 20 <= t <= 100 and str(t) not in structure:
        structure[str(t)] = {'HD': int(hd), 'CT': int(ct), 'LT': int(st), 'RT': int(st), 'LA': int(arm), 'RA': int(arm), 'LL': int(leg), 'RL': int(leg)}

construction = {
    '_sources': {
        'engine_weight_standard': 'MegaMek Engine.ENGINE_RATINGS (mirrors TechManual Master Engine Table)',
        'internal_structure': 'MegaMek Mek.getInternalForTonnage (mirrors TechManual IS table); cross-checked vs Recognition Guide stat blocks',
        'rules': 'Sarna (Jump Jet, Gyro, Heat Sink pages) + MegaMek MiscType/MekCostCalculator',
    },
    'tonnage': {'min': 20, 'max': 100, 'step': 5,
                'classes': {'light': [20, 35], 'medium': [40, 55], 'heavy': [60, 75], 'assault': [80, 100]}},
    'engine': {
        'rating_rule': 'rating = tonnage * walkMP; 10..400 in steps of 5; runMP = ceil(walk * 1.5)',
        'standard_weight_by_rating': std_engine,
        'type_multipliers': {'standard': 1.0, 'xl_is': 0.5, 'xl_clan': 0.5, 'light': 0.75, 'compact': 1.5, 'xxl': 1 / 3},
        'type_rounding': 'weight = ceil_to_half_ton(standard_weight * multiplier)',
        'crits': {'standard': {'CT': 6}, 'xl_is': {'CT': 6, 'LT': 3, 'RT': 3}, 'xl_clan': {'CT': 6, 'LT': 2, 'RT': 2},
                  'light': {'CT': 6, 'LT': 2, 'RT': 2}, 'compact': {'CT': 3}},
        'integral_heat_sinks': 'floor(rating / 25), max 10 count toward the free 10',
        'cost_per_rating_ton_div75': {'standard': 5000, 'xl': 20000, 'light': 15000, 'compact': 10000, 'xxl': 100000},
        'cost_formula': 'base * rating * tonnage / 75',
    },
    'gyro': {'standard_weight': 'ceil(rating / 100)', 'crits': 4,
             'multipliers': {'standard': 1.0, 'xl': 0.5, 'compact': 1.5, 'heavy_duty': 2.0},
             'crits_by_type': {'standard': 4, 'xl': 6, 'compact': 2, 'heavy_duty': 4},
             'cost': '300000 * standard_gyro_weight (std); xl 750000*w*0.5; compact 400000*w*1.5; HD 500000*w*2'},
    'cockpit': {'standard': {'tons': 3, 'cost': 200000}, 'small': {'tons': 2, 'cost': 175000}},
    'internal_structure': {
        'weight': {'standard': 'ceil_to_half_ton(tonnage * 0.10)', 'endo_steel': 'ceil_to_half_ton(tonnage * 0.05)'},
        'crits': {'standard': 0, 'endo_steel_is': 14, 'endo_steel_clan': 7},
        'cost_per_ton_of_mech': {'standard': 400, 'endo_steel': 1600},
        'points_by_tonnage': structure,
    },
    'armor': {'points_per_ton': {'standard': 16, 'ferro_fibrous_is': 17.92, 'ferro_fibrous_clan': 19.2},
              'max': 'HD 9; every other location 2x its internal structure (front+rear torso combined)',
              'crits': {'standard': 0, 'ferro_fibrous_is': 14, 'ferro_fibrous_clan': 7},
              'cost_per_ton': {'standard': 10000, 'ferro_fibrous': 20000}},
    'jump_jets': {'max': 'walkMP (standard jets)', 'tons_each': {'<=55': 0.5, '60-85': 1.0, '90-100': 2.0},
                  'crits_each': 1, 'cost': '200 * tonnage * jumpMP^2'},
    'heat_sinks': {'single': {'dissipation': 1, 'tons': 1, 'crits': 1}, 'double_is': {'dissipation': 2, 'tons': 1, 'crits': 3},
                   'double_clan': {'dissipation': 2, 'tons': 1, 'crits': 2}, 'minimum': 10, 'free_weight': 10,
                   'cost': 'single 2000 each beyond 10; double 6000 each (all)'},
    'crit_slots': {'HD': 6, 'CT': 12, 'LT': 12, 'RT': 12, 'LA': 12, 'RA': 12, 'LL': 6, 'RL': 6},
    'fixed_crits': {'HD': ['Life Support', 'Sensors', 'Cockpit', 'Sensors', 'Life Support'],
                    'CT': ['Gyro x4 (after engine)'], 'arm': ['Shoulder', 'Upper Arm', 'Lower Arm (opt)', 'Hand (opt)'],
                    'leg': ['Hip', 'Upper Leg', 'Lower Leg', 'Foot']},
    'chassis_cost': {
        'life_support': 50000, 'sensors_per_ton': 2000, 'myomer_per_ton': {'standard': 2000, 'tsm': 16000},
        'actuators_per_ton': {'upper_arm': 100, 'lower_arm': 50, 'hand': 80, 'upper_leg': 150, 'lower_leg': 80, 'foot': 120},
        'final_multiplier': '1 + tonnage / 100',
    },
}
json.dump(construction, open(DATA / 'construction.json', 'w'), indent=1)

# ------------------------------------------------------------------ tech dates for non-equipment components
ta = {}
for m in re.finditer(r'TechAdvancement (\w+)_TA\s*=\s*new TechAdvancement\(TechBase\.(\w+)\)(.*?);', eng_src, re.S):
    name, base, body = m.groups()
    adv = re.search(r'set(IS|Clan)?Advancement\(([^)]*)\)', body)
    av = re.findall(r'AvailabilityValue\.(\w)', body)
    if adv:
        nums = [None if x.strip() == 'DATE_NONE' else (x.strip() if not x.strip().isdigit() else int(x)) for x in adv.group(2).split(',')]
        ta['engine_' + name.lower()] = {'techBase': base, 'dates': dict(zip(['prototype', 'production', 'common', 'extinct', 'reintroduced'], nums + [None] * 5)), 'availability_SL_SW_CI_DA': av}

# ------------------------------------------------------------------ equipment
eq = json.load(open(S / 'mm_equipment.json'))['items']
keep = []
for r in eq:
    if not r.get('mek'): continue
    if r['kind'] == 'weapon' and r.get('tonnage') is None: continue
    d = r.get('is') or r.get('both') or r.get('clan')
    rec = {k: r[k] for k in ('kind', 'name', 'internalName', 'heat', 'damage', 'minRange', 'shortRange', 'mediumRange', 'longRange',
                             'tonnage', 'crits', 'shots', 'rackSize', 'bv', 'cost', 'techBase', 'techRating',
                             'availability_SL_SW_CI_DA', 'level') if k in r}
    if r.get('lookup'): rec['aliases'] = r['lookup']
    for k in ('is', 'clan', 'both'):
        if r.get(k): rec['dates_' + k] = r[k]
    rec['mm_ref'] = r.get('path') or r.get('factory')
    keep.append(rec)
structure_types = {
    'endo_steel_is': {'techBase': 'IS', 'availability_SL_SW_CI_DA': ['D', 'F', 'E', 'D'],
                      'dates_is': {'prototype': 2480, 'production': 2487, 'common': 3040, 'extinct': 2850, 'reintroduced': 3035}},
}
json.dump({'_source': 'MegaMek Java sources (weapons/*, MiscType, AmmoType, ArmorType, Engine). Dates: prototype/production/common/extinct/reintroduced. '
                      'Availability letters A (very common) .. F (very rare), X (unavailable) for eras Star League / Succession Wars / Clan Invasion / Dark Age. '
                      'Spot-checked vs Sarna: Gauss 2590/3040, XL 2579/3035, Endo 2487/3035, Artemis 2598/2855/3035, MASC 2740/2795/3035, Hatchet 3022.',
           'component_tech': {**ta, **structure_types}, 'items': keep}, open(DATA / 'equipment.json', 'w'), indent=1)

# ------------------------------------------------------------------ stock designs (MegaMek .mtf)
LOCS = {'Left Arm': 'LA', 'Right Arm': 'RA', 'Left Torso': 'LT', 'Right Torso': 'RT', 'Center Torso': 'CT', 'Head': 'HD',
        'Left Leg': 'LL', 'Right Leg': 'RL', 'Front Left Leg': 'FLL', 'Front Right Leg': 'FRL', 'Rear Left Leg': 'RLL', 'Rear Right Leg': 'RRL',
        'Center Leg': 'CL'}
ARMOR_KEYS = {'LA': 'LA', 'RA': 'RA', 'LT': 'LT', 'RT': 'RT', 'CT': 'CT', 'HD': 'HD', 'LL': 'LL', 'RL': 'RL',
              'RTL': 'LT_rear', 'RTR': 'RT_rear', 'RTC': 'CT_rear', 'FLL': 'FLL', 'FRL': 'FRL', 'RLL': 'RLL', 'RRL': 'RRL', 'CL': 'CL'}
mul = json.load(open(P / 'data/sources/mul_battlemechs.json'))
mul_by_id = {}
# MUL export has public ids; .mtf files carry numeric "mul id". Match by name+model instead.
mul_key = {((m['name'] or '').strip().lower(), (m['model'] or '').strip().lower()): m for m in mul['battlemechs']}
designs = []
for f in sorted((S / 'mmd/data/mekfiles/meks').rglob('*.mtf')):
    txt = f.read_text(errors='replace')
    kv = {}
    for line in txt.splitlines():
        if ':' in line and not line.startswith('#'):
            k, _, v = line.partition(':')
            if k.strip().lower() in ('chassis', 'model', 'mul id', 'config', 'techbase', 'era', 'rules level', 'role', 'mass', 'engine',
                                     'structure', 'myomer', 'heat sinks', 'walk mp', 'jump mp', 'armor', 'source', 'gyro', 'cockpit', 'clanname') \
                    and k.strip().lower() not in kv:
                kv[k.strip().lower()] = v.strip()
    armor = {}
    for m in re.finditer(r'^(\w+) armor:(\d+)', txt, re.M):
        if m.group(1) in ARMOR_KEYS: armor[ARMOR_KEYS[m.group(1)]] = int(m.group(2))
    crits = {}
    for m in re.finditer(r'^(' + '|'.join(map(re.escape, LOCS)) + r'):\n((?:.*\n){1,12})', txt, re.M):
        slots = [s.strip() for s in m.group(2).splitlines()][:12 if LOCS[m.group(1)] not in ('HD', 'LL', 'RL') else 12]
        crits[LOCS[m.group(1)]] = slots
    weapons = []
    wm = re.search(r'^Weapons:(\d+)\n((?:.*\n){0,60})', txt, re.M)
    if wm:
        weapons = [l.strip() for l in wm.group(2).splitlines()[:int(wm.group(1))]]
    quirks = re.findall(r'^quirk:(\S+)', txt, re.M)
    chassis, model = kv.get('chassis', ''), kv.get('model', '')
    m_rec = mul_key.get((chassis.lower(), model.lower()))
    designs.append({
        'chassis': chassis, 'model': model, 'clanName': kv.get('clanname'), 'mulId': kv.get('mul id'),
        'mul': {'id': m_rec['id'], 'intro': m_rec['intro'], 'bv': m_rec['bv'], 'role': m_rec['role']} if m_rec else None,
        'config': kv.get('config'), 'techBase': kv.get('techbase'), 'year': int(kv['era']) if kv.get('era', '').isdigit() else kv.get('era'),
        'rulesLevel': kv.get('rules level'), 'role': kv.get('role'), 'tonnage': float(kv.get('mass', 0)),
        'engine': kv.get('engine'), 'structure': kv.get('structure'), 'myomer': kv.get('myomer'), 'gyro': kv.get('gyro'), 'cockpit': kv.get('cockpit'),
        'heatSinks': kv.get('heat sinks'), 'walk': int(kv.get('walk mp', 0) or 0), 'jump': int(kv.get('jump mp', 0) or 0),
        'armorType': kv.get('armor'), 'armor': armor, 'weapons': weapons, 'crits': crits, 'quirks': quirks,
        'source': kv.get('source'), 'mtf': str(f.relative_to(S / 'mmd/data/mekfiles/meks')),
    })
json.dump({'_source': 'MegaMek Data (github.com/MegaMek/mm-data), CC BY-NC-SA 4.0 — personal use. "year" = MegaMek era/intro year; "mul" = matched Master Unit List record.',
           'designs': designs}, open(DATA / 'stock_designs.json', 'w'))

yrs = [d for d in designs if isinstance(d['year'], int)]
print('construction.json: engines', len(std_engine), 'IS rows', len(structure))
print('equipment.json:', len(keep), 'items')
print('stock_designs.json:', len(designs), 'designs;', sum(1 for d in yrs if d['year'] <= 3015), 'with year <= 3015;',
      sum(1 for d in designs if d['mul']), 'matched to MUL')
