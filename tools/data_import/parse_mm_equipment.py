"""Extract equipment stats + tech advancement dates from MegaMek Java sources.

Usage: python3 -I parse_mm_equipment.py <megamek/src/megamek/common dir> <out.json>
Reads source text only (never executes it).
"""
import json, re, sys, pathlib

root = pathlib.Path(sys.argv[1])
out_path = sys.argv[2]

NUM = r'(-?[\d.]+)'
FIELDS = {
    'heat': rf'\bheat\s*=\s*{NUM}', 'damage': rf'\bdamage\s*=\s*{NUM}',
    'minRange': rf'\bminimumRange\s*=\s*{NUM}', 'shortRange': rf'\bshortRange\s*=\s*{NUM}',
    'mediumRange': rf'\bmediumRange\s*=\s*{NUM}', 'longRange': rf'\blongRange\s*=\s*{NUM}',
    'tonnage': rf'\btonnage\s*=\s*{NUM}', 'crits': rf'\bcriticalSlots\s*=\s*{NUM}',
    'bv': rf'\bbv\s*=\s*{NUM}', 'cost': rf'\bcost\s*=\s*{NUM}',
    'rackSize': rf'\brackSize\s*=\s*{NUM}', 'shots': rf'\bshots\s*=\s*{NUM}',
}
DATE_NONE = None

def dates(s):
    out = []
    for tok in s.split(','):
        tok = tok.strip()
        if tok in ('DATE_NONE', ''): out.append(None)
        elif tok in ('DATE_PS', 'DATE_ES'): out.append(tok)  # pre-spaceflight / early spaceflight
        else:
            try: out.append(int(tok))
            except ValueError: out.append(tok)
    return dict(zip(['prototype', 'production', 'common', 'extinct', 'reintroduced'], out + [None] * 5))

def tech(block):
    t = {}
    if m := re.search(r'setTechBase\(\s*TechBase\.(\w+)', block): t['techBase'] = m.group(1)
    if m := re.search(r'setTechRating\(\s*TechRating\.(\w+)', block): t['techRating'] = m.group(1)
    if m := re.search(r'setAvailability\(([^)]*)\)', block):
        t['availability_SL_SW_CI_DA'] = re.findall(r'AvailabilityValue\.(\w+)', m.group(1))
    for key, meth in (('is', 'setISAdvancement'), ('clan', 'setClanAdvancement'), ('both', 'setAdvancement')):
        if m := re.search(meth + r'\(([^)]*)\)', block): t[key] = dates(m.group(1))
    if m := re.search(r'setStaticTechLevel\(\s*SimpleTechLevel\.(\w+)', block): t['level'] = m.group(1)
    return t

def scalars(block):
    d = {}
    for k, pat in FIELDS.items():
        if m := re.search(pat, block):
            v = float(m.group(1)); d[k] = int(v) if v.is_integer() else v
    return d

items = []
# Weapons: one class per file, constructor body holds the stats
for f in sorted((root / 'weapons').rglob('*.java')):
    src = f.read_text(errors='replace')
    cls = f.stem
    m = re.search(r'public\s+' + re.escape(cls) + r'\s*\(\s*\)\s*\{(.*?)\n    \}', src, re.S)
    if not m: continue
    body = m.group(1)
    nm = re.search(r'\bname\s*=\s*"([^"]+)"', body)
    if not nm: continue
    rec = {'kind': 'weapon', 'class': cls, 'path': str(f.relative_to(root)), 'name': nm.group(1)}
    if im := re.search(r'setInternalName\("([^"]+)"', body): rec['internalName'] = im.group(1)
    rec['lookup'] = re.findall(r'addLookupName\("([^"]+)"', body)
    rec['mek'] = not re.search(r'battlearmor|infantry|bay|capital|aero|protomek|artillery', rec['path'], re.I)
    rec.update(scalars(body)); rec.update(tech(body))
    items.append(rec)

# MiscType: static create* factory methods
for fname, kind in (('equipment/MiscType.java', 'misc'), ('equipment/AmmoType.java', 'ammo'), ('equipment/ArmorType.java', 'armor')):
    p = root / fname
    if not p.exists(): continue
    src = p.read_text(errors='replace')
    for m in re.finditer(r'(?:public|private|protected) static \w+ (create\w+)\s*\([^)]*\)\s*\{(.*?)\n    \}', src, re.S):
        body = m.group(2)
        nm = re.search(r'\.name\s*=\s*"([^"]+)"', body) or re.search(r'setInternalName\("([^"]+)"', body) or re.search(r'addLookupName\("([^"]+)"', body)
        if not nm: continue
        rec = {'kind': kind, 'factory': m.group(1), 'name': nm.group(1),
               'mek': bool(re.search(r'F_MEK_EQUIPMENT|F_MEK_WEAPON', body)) or kind == 'armor'}
        if im := re.search(r'setInternalName\("([^"]+)"', body): rec['internalName'] = im.group(1)
        rec['lookup'] = re.findall(r'addLookupName\("([^"]+)"', body)
        rec.update(scalars(body)); rec.update(tech(body))
        items.append(rec)

json.dump({'source': 'MegaMek (github.com/MegaMek/megamek), parsed from Java source; dates = [prototype, production, common, extinct, reintroduced]',
           'items': items}, open(out_path, 'w'), indent=1)
print(len(items), 'items;', sum(i['kind'] == 'weapon' for i in items), 'weapons;',
      sum(i['kind'] == 'misc' for i in items), 'misc;', sum(i['kind'] == 'ammo' for i in items), 'ammo')
