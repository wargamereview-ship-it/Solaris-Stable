"""Cross-check construction.json against (1) Recognition Guide stat blocks, (2) MegaMek 3015 stock designs.

python3 -I crosscheck.py <project_dir>
"""
import json, math, pathlib, re, sys
from collections import Counter

P = pathlib.Path(sys.argv[1])
C = json.load(open(P / 'data/construction.json'))
EQ = json.load(open(P / 'data/equipment.json'))['items']
half = lambda x: math.ceil(x * 2 - 1e-9) / 2
std = {int(k): v for k, v in C['engine']['standard_weight_by_rating'].items()}
MULT = {'': 1.0, 'standard': 1.0, 'fusion': 1.0, 'xl': 0.5, 'xl (c)': 0.5, 'light': 0.75, 'compact': 1.5, 'xxl': 1 / 3, 'xxl (c)': 1 / 3}

def engine_wt(rating, kind):
    return half(std[rating] * MULT.get(kind.lower().strip(), 1.0))

# ------------------------------------------------------------------ 1. Recognition Guides
print('== Recognition Guide stat blocks')
ok = bad = 0; bad_ex = []
is_ok = is_bad = 0
for rg in ('rg_vol1_classics', 'rg_vol2_ilclan'):
    txt = (P / f'reference/text/{rg}.txt').read_text(errors='replace')
    for blk in re.split(r'(?=Mass: \d+ tons)', txt)[1:]:
        blk = blk[:6000]
        ton = int(re.match(r'Mass: (\d+)', blk).group(1))
        if ton > 100: continue
        m = re.search(r'Engine:\s+(\d+)\s*([A-Za-z() ]*?)\s{2,}([\d.]+)', blk)
        if m and 'Mech' not in blk[:0]:
            rating, kind, mass = int(m.group(1)), m.group(2).strip(), float(m.group(3))
            if rating in std and kind.lower() in MULT:
                exp = engine_wt(rating, kind)
                if abs(exp - mass) < 1e-6: ok += 1
                else: bad += 1; bad_ex.append((ton, rating, kind, mass, exp))
        # IS table: Head / Center Torso / R/L Torso / R/L Arm / R/L Leg (numbers after label: IS then armor)
        row = C['internal_structure']['points_by_tonnage'].get(str(ton))
        lab = {'Head': 'HD', 'Center Torso': 'CT', 'R/L Torso': 'LT', 'R/L Arm': 'LA', 'R/L Leg': 'LL'}
        got = {}
        for label, key in lab.items():
            mm = re.search(r'\n\s*' + re.escape(label) + r'\s{2,}(\d+)\s', blk)
            if mm: got[key] = int(mm.group(1))
        if row and len(got) == 5:
            if all(row[k] == v for k, v in got.items()): is_ok += 1
            else: is_bad += 1
print(f'  engine weights: {ok} match, {bad} differ', bad_ex[:6])
print(f'  internal structure rows: {is_ok} match, {is_bad} differ')

# ------------------------------------------------------------------ 2. full weight rebuild of 3015 stock designs
print('== Full weight rebuild of MegaMek stock designs (year <= 3015, Inner Sphere, biped)')
by_name = {}
for e in EQ:
    if e.get('techBase') in ('IS', 'ALL', None):
        for n in [e['name'], e.get('internalName')] + e.get('aliases', []):
            if n: by_name.setdefault(n.lower(), e)
designs = json.load(open(P / 'data/stock_designs.json'))['designs']
res = Counter(); diffs = []
for d in designs:
    if not isinstance(d['year'], int) or d['year'] > 3015 or d['techBase'] != 'Inner Sphere' or d['config'] != 'Biped': continue
    ton = int(d['tonnage'])
    m = re.match(r'(\d+)\s+(.*?)\s*Engine', d['engine'] or '')
    if not m: res['skip_engine'] += 1; continue
    rating, kind = int(m.group(1)), m.group(2).replace('Fusion', '').strip()
    if kind and kind.lower() not in MULT: res['skip_engine_type'] += 1; continue
    w = engine_wt(rating, kind)
    w += half(ton * (0.05 if 'endo' in (d['structure'] or '').lower() else 0.10))
    w += math.ceil(rating / 100)                    # standard gyro
    w += 3                                          # standard cockpit
    hs = int(re.match(r'(\d+)', d['heatSinks']).group(1)); w += max(0, hs - 10)
    w += d['jump'] * (0.5 if ton <= 55 else 1.0 if ton <= 85 else 2.0)
    pts = sum(d['armor'].values()); per_ton = 17.92 if 'ferro' in (d['armorType'] or '').lower() else 16
    w += half(pts / per_ton)
    unknown = []
    for wline in d['weapons']:
        name = wline.split(',')[0].strip()
        name = re.sub(r'^\d+\s+', '', name)
        e = by_name.get(name.lower()) or by_name.get(('IS ' + name).lower())
        if e and e.get('tonnage') is not None: w += e['tonnage']
        else: unknown.append(name)
    # ammo + other equipment from crits (non-weapon, non-structural)
    for loc, slots in d['crits'].items():
        for s in slots:
            sl = s.lower()
            if 'ammo' in sl: w += 0.5 if 'half' in sl else 1.0
            elif sl in ('case', 'iscase'): w += 0.5
    if unknown: res['unknown_equipment'] += 1; continue
    if abs(w - ton) < 1e-6: res['exact'] += 1
    elif w < ton: res['under (spare tonnage / unmodelled items)'] += 1; diffs.append((d['chassis'], d['model'], ton, w))
    else: res['OVER'] += 1; diffs.append((d['chassis'], d['model'], ton, w))
print(' ', dict(res))
print('  sample mismatches:', diffs[:12])
