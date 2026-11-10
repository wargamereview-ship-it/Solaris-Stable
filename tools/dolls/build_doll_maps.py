"""Turns the chosen doll art into the doll textures the game uses.

    python3 tools/dolls/build_doll_maps.py [name ...]

For each doll below: crops the art (assets/dolls/options/<src>.png) to its silhouette, writes
assets/dolls/<name>_shade.png (the art, clean alpha) and <name>_id.png (the location map:
red = location id * 20, alpha = inside), and records each location's label anchor (its deepest
point), area and bounds in assets/dolls/dolls.json.

Locations are drawn as shapes in the crop's normalized coordinates (u right, v down, 0..1); the
first rule that covers a pixel wins and anything left over is plain hull (BODY).

Line art ("lineart": white lines on black, like the 'Mech) has no alpha: its silhouette is
whatever the outer outline encloses. With "snap" its locations follow the drawing's own lines:
every panel the lines enclose goes whole to the location that covers most of it.
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OPT = os.path.join(ROOT, "assets", "dolls", "options")
OUT = os.path.join(ROOT, "assets", "dolls")

MECH_IDS = {"HD": 1, "CT": 2, "LT": 3, "RT": 4, "LA": 5, "RA": 6, "LL": 7, "RL": 8, "CTR": 9, "LTR": 10, "RTR": 11}
VEH_IDS = {"FR": 1, "LS": 2, "RS": 3, "RR": 4, "TU": 5, "RO": 6, "BODY": 7}


def rect(u0, v0, u1, v1):
    return ("poly", [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])


def poly(*pts):
    return ("poly", list(pts))


def ellipse(cx, cy, rx, ry):
    return ("ellipse", (cx - rx, cy - ry, cx + rx, cy + ry))


def band(p0, p1, w):
    """A straight strip w wide (in u units) from p0 to p1, e.g. a rotor blade."""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    n = (dx * dx + dy * dy) ** 0.5
    ox, oy = -dy / n * w / 2, dx / n * w / 2
    return ("poly", [(x0 + ox, y0 + oy), (x1 + ox, y1 + oy), (x1 - ox, y1 - oy), (x0 - ox, y0 - oy)])


def mirror(shapes):
    out = []
    for kind, data in shapes:
        if kind == "poly":
            out.append(("poly", [(1.0 - u, v) for u, v in data][::-1]))
        else:
            u0, v0, u1, v1 = data
            out.append(("ellipse", (1.0 - u1, v0, 1.0 - u0, v1)))
    return out


# the 'Mech's left half (mirrored for the right): helmet and collar ring; chest centre, abdomen and
# codpiece; chest block and waist; pauldron, arm and fist; hip plate, leg and foot
MECH_HD = [poly((0.42, 0.0), (0.58, 0.0), (0.62, 0.055), (0.62, 0.113), (0.6, 0.113), (0.6, 0.16), (0.57, 0.19),
                (0.43, 0.19), (0.4, 0.16), (0.4, 0.113), (0.38, 0.113), (0.38, 0.055))]
MECH_CT = [poly((0.4, 0.115), (0.6, 0.115), (0.6, 0.28), (0.59, 0.39), (0.56, 0.4), (0.56, 0.54), (0.44, 0.54),
                (0.44, 0.4), (0.41, 0.39), (0.4, 0.28))]
MECH_LA = [poly((0.0, 0.0), (0.27, 0.0), (0.27, 0.112), (0.217, 0.112), (0.217, 0.59), (0.0, 0.59))]
MECH_LT = [rect(0.215, 0.1, 0.5, 0.393)]
MECH_LL = [rect(0.0, 0.393, 0.5, 1.0)]

# rules: (location, [shapes]) in priority order
DOLLS = {
    # the 'Mech: white line art on black, left side on the left as on a record sheet
    "mech_front": {"src": "mech_line_01", "lineart": True, "snap": True, "view": "front", "height": 660,
                   "ids": MECH_IDS, "rear_from": (0.205, 0.105, 0.795, 0.397), "torso_top": 0.115,
                   "anchor_at": {"LA": (0.11, 0.39), "RA": (0.89, 0.39), "LT": (0.31, 0.21), "RT": (0.69, 0.21),
                                 "CT": (0.5, 0.3), "HD": (0.5, 0.08), "LL": (0.3, 0.72), "RL": (0.7, 0.72)}, "rules": [
        ("HD", MECH_HD), ("CT", MECH_CT), ("LA", MECH_LA), ("RA", mirror(MECH_LA)),
        ("LT", MECH_LT), ("RT", mirror(MECH_LT)), ("LL", MECH_LL), ("RL", mirror(MECH_LL)),
    ]},
    "veh_tracked": {"src": "tracked_01", "ids": VEH_IDS, "rules": [
        ("TU", [rect(0.465, 0.0, 0.535, 0.37), poly((0.43, 0.33), (0.57, 0.33), (0.58, 0.42), (0.42, 0.42)),
                poly((0.4, 0.38), (0.6, 0.38), (0.78, 0.44), (0.8, 0.62), (0.7, 0.705), (0.3, 0.705), (0.2, 0.62), (0.22, 0.44))]),
        ("LS", [rect(0.0, 0.0, 0.205, 1.0)]),
        ("RS", [rect(0.795, 0.0, 1.0, 1.0)]),
        ("FR", [rect(0.0, 0.0, 1.0, 0.4)]),
        ("RR", [rect(0.0, 0.72, 1.0, 1.0)]),
    ]},
    "veh_wheeled": {"src": "wheeled_01", "ids": VEH_IDS, "rules": [
        ("TU", [rect(0.47, 0.075, 0.53, 0.33), ellipse(0.5, 0.455, 0.305, 0.165)]),
        ("LS", [rect(0.0, 0.0, 0.2, 1.0)]),
        ("RS", [rect(0.8, 0.0, 1.0, 1.0)]),
        ("FR", [rect(0.0, 0.0, 1.0, 0.28)]),
        ("RR", [rect(0.0, 0.66, 1.0, 1.0)]),
    ]},
    "veh_hover": {"src": "hover_01", "ids": VEH_IDS, "rules": [
        ("TU", [rect(0.48, 0.11, 0.52, 0.3),
                poly((0.42, 0.25), (0.58, 0.25), (0.64, 0.3), (0.64, 0.46), (0.58, 0.5), (0.42, 0.5), (0.36, 0.46), (0.36, 0.3))]),
        ("FR", [rect(0.0, 0.0, 1.0, 0.235)]),
        ("RR", [rect(0.0, 0.62, 1.0, 1.0)]),
        ("LS", [rect(0.0, 0.0, 0.27, 1.0)]),
        ("RS", [rect(0.73, 0.0, 1.0, 1.0)]),
    ]},
    "veh_vtol": {"src": "vtol_01", "ids": VEH_IDS, "rules": [
        ("RO", [band((0.0, 0.1), (1.0, 0.7), 0.05), band((1.0, 0.1), (0.0, 0.7), 0.05), ellipse(0.5, 0.42, 0.035, 0.022)]),
        ("TU", [rect(0.43, 0.0, 0.57, 0.045)]),
        ("LS", [rect(0.0, 0.33, 0.405, 0.54)]),
        ("RS", [rect(0.595, 0.33, 1.0, 0.54)]),
        ("FR", [rect(0.0, 0.0, 1.0, 0.31)]),
        ("RR", [rect(0.0, 0.56, 1.0, 1.0)]),
    ]},
}


def mask_for(shapes, w, h):
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    for kind, data in shapes:
        if kind == "poly":
            d.polygon([(u * w, v * h) for u, v in data], fill=255)
        else:
            u0, v0, u1, v1 = data
            d.ellipse([u0 * w, v0 * h, u1 * w, v1 * h], fill=255)
    return np.array(img) > 127


def anchors(ids):
    """Each location's label point: among its pixels at least half as deep inside as its deepest
    one, the one nearest its centroid (so long parts like tracks get labelled mid-way)."""
    out = {}
    for k in np.unique(ids):
        k = int(k)
        if k == 0:
            continue
        m = ids == k
        ys, xs = np.nonzero(m)
        depth = np.zeros(m.shape, dtype=np.int32)
        cur = m
        d = 0
        while cur.any() and d < 800:
            depth[cur] = d
            e = cur.copy()
            e[1:, :] &= cur[:-1, :]
            e[:-1, :] &= cur[1:, :]
            e[:, 1:] &= cur[:, :-1]
            e[:, :-1] &= cur[:, 1:]
            cur = e
            d += 1
        ok = depth >= max(1, depth.max() // 2)
        cy, cx = np.nonzero(ok & m)
        j = int(np.argmin((cx - xs.mean()) ** 2 + (cy - ys.mean()) ** 2))
        out[str(k)] = {"anchor": [int(cx[j]), int(cy[j])], "area": int(m.sum()),
                       "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]}
    return out


DARK = 90  # line art: below this a pixel is background or panel, not line


def label(mask):
    """4-connected regions of a bool mask -> (labels from 1, 0 outside the mask; how many)."""
    h, w = mask.shape
    parent = [0]

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    runs = []
    prev = []
    for y in range(h):
        d = np.diff(np.concatenate(([0], mask[y].astype(np.int8), [0])))
        cur = []
        j = 0
        for x0, x1 in zip(np.nonzero(d == 1)[0].tolist(), np.nonzero(d == -1)[0].tolist()):
            rid = len(parent)
            parent.append(rid)
            while j < len(prev) and prev[j][1] <= x0:
                j += 1
            k = j
            while k < len(prev) and prev[k][0] < x1:
                ra, rb = find(prev[k][2]), find(rid)
                if ra != rb:
                    parent[max(ra, rb)] = min(ra, rb)
                k += 1
            cur.append((x0, x1, rid))
            runs.append((y, x0, x1, rid))
        prev = cur
    out = np.zeros((h, w), dtype=np.int32)
    names = {}
    for y, x0, x1, rid in runs:
        out[y, x0:x1] = names.setdefault(find(rid), len(names) + 1)
    return out, len(names)


def grow(ids, want):
    """Gives the pixels of want that have no location the one of their nearest pixel that has."""
    ids = ids.copy()
    while True:
        todo = want & (ids == 0)
        if not todo.any():
            break
        new = ids.copy()
        for near in (np.pad(ids, ((1, 0), (0, 0)))[:-1], np.pad(ids, ((0, 1), (0, 0)))[1:],
                     np.pad(ids, ((0, 0), (1, 0)))[:, :-1], np.pad(ids, ((0, 0), (0, 1)))[:, 1:]):
            pick = todo & (new == 0) & (near > 0)
            new[pick] = near[pick]
        if not (new != ids).any():
            break
        ids = new
    return ids


def lineart_rgba(path):
    """White line art on black -> RGBA: the lines as grey, the silhouette (everything the outer
    outline encloses) opaque, the outside transparent."""
    g = np.array(Image.open(path).convert("L"))
    back, _n = label(g < DARK)
    edge = np.unique(np.concatenate((back[0], back[-1], back[:, 0], back[:, -1])))
    outside = np.isin(back, edge[edge > 0])
    a = np.zeros(g.shape + (4,), dtype=np.uint8)
    a[..., 0] = a[..., 1] = a[..., 2] = np.where(outside, 0, g)
    a[..., 3] = np.where(outside, 0, 255)
    return a


def rule_ids(spec, inside, pad):
    """The location of every inside pixel, from the doll's rules (drawn in the silhouette's own
    box, without the padding)."""
    h, w = inside.shape
    iw, ih = w - 2 * pad, h - 2 * pad
    ids = np.zeros((h, w), dtype=np.int32)
    todo = inside.copy()
    for loc, shapes in spec["rules"]:
        m = np.zeros((h, w), dtype=bool)
        m[pad:pad + ih, pad:pad + iw] = mask_for(shapes, iw, ih)
        hit = m & todo
        ids[hit] = spec["ids"][loc]
        todo &= ~hit
    if "BODY" in spec["ids"]:
        ids[todo] = spec["ids"]["BODY"]
    return ids


def lineart_ids(a, spec, pad):
    """Locations for line art, worked out at the art's full size and then scaled down with it."""
    inside = a[..., 3] > 0
    ids = rule_ids(spec, inside, pad)
    g = a[..., 0]
    if spec.get("snap"):
        # every panel goes whole to the location that covers most of it, every line to the nearest panel
        panels, n = label((g < DARK) & inside)
        nloc = max(spec["ids"].values()) + 1
        votes = np.bincount((panels * nloc + ids).ravel(), minlength=(n + 1) * nloc).reshape(n + 1, nloc)
        votes[:, 0] = 0
        win = votes.argmax(axis=1)
        win[0] = 0
        ids = grow(win[panels], inside)
    if spec.get("thicken"):
        # fatten the lines so the thin ones survive being shown several times smaller
        fat = np.array(Image.fromarray(g).filter(ImageFilter.MaxFilter(spec["thicken"])))
        a[..., 0] = a[..., 1] = a[..., 2] = np.where(inside, fat, 0)
    if spec.get("height"):
        k = spec["height"] / a.shape[0]
        size = (int(round(a.shape[1] * k)), spec["height"])
        a = np.array(Image.fromarray(a, "RGBA").resize(size, Image.LANCZOS))
        ids = np.array(Image.fromarray(ids.astype(np.uint8)).resize(size, Image.NEAREST)).astype(np.int32)
        pad = max(1, int(round(pad * k)))
    a[..., 3] = np.where(ids > 0, 255, 0)
    return a, ids, pad


def build(name, spec, db):
    if spec.get("lineart"):
        a = lineart_rgba(os.path.join(OPT, spec["src"] + ".png"))
    else:
        a = np.array(Image.open(os.path.join(OPT, spec["src"] + ".png")).convert("RGBA"))
    if spec.get("mirror"):
        a = a[:, ::-1]
    solid = a[..., 3] > 128
    ys, xs = np.nonzero(solid)
    pad = 6
    x0, y0 = max(0, xs.min() - pad), max(0, ys.min() - pad)
    x1, y1 = min(a.shape[1], xs.max() + 1 + pad), min(a.shape[0], ys.max() + 1 + pad)
    a = a[y0:y1, x0:x1].copy()
    if spec.get("lineart"):
        a, ids, pad = lineart_ids(a, spec, pad)
    else:
        if spec.get("height"):
            k = spec["height"] / a.shape[0]
            a = np.array(Image.fromarray(a, "RGBA").resize((int(round(a.shape[1] * k)), spec["height"]), Image.LANCZOS))
            pad = max(1, int(round(pad * k)))
        # clean the faint haze the background removal leaves behind
        a[..., 3] = np.where(a[..., 3] < 40, 0, a[..., 3])
        ids = rule_ids(spec, a[..., 3] > 110, pad)
    h, w = a.shape[:2]
    iw, ih = w - 2 * pad, h - 2 * pad
    Image.fromarray(a, "RGBA").save(os.path.join(OUT, name + "_shade.png"))
    idimg = np.zeros((h, w, 4), dtype=np.uint8)
    idimg[..., 0] = (ids * 20).astype(np.uint8)
    idimg[..., 3] = np.where(ids > 0, 255, 0).astype(np.uint8)
    Image.fromarray(idimg, "RGBA").save(os.path.join(OUT, name + "_id.png"))
    view = spec.get("view", "top")
    entry = db.setdefault(name.rsplit("_", 1)[0] if view in ("front", "rear") else name, {})
    entry[view] = anchors(ids)
    # hand-placed label spots (normalized like the rules), snapped onto the location
    for loc, (u, v) in spec.get("anchor_at", {}).items():
        k = spec["ids"][loc]
        ys2, xs2 = np.nonzero(ids == k)
        if len(xs2) == 0:
            continue
        px, py = pad + u * iw, pad + v * ih
        j = int(np.argmin((xs2 - px) ** 2 + (ys2 - py) ** 2))
        entry[view][str(k)]["anchor"] = [int(xs2[j]), int(ys2[j])]
    entry[view + "_size"] = [w, h]
    # tells the game to light the art's own lines instead of tracing its shading (doll.gdshader)
    if spec.get("lineart"):
        entry["line_art"] = True
    else:
        entry.pop("line_art", None)
    print("built", name, w, h)
    if spec.get("rear_from"):
        build_rear(name.rsplit("_", 1)[0], a, ids, spec, entry)


def build_rear(base, a, ids, spec, entry):
    """The rear torso readout: the front's torso crop with its locations swapped for the rear
    armor ones; the head and limbs drop out, and the head's lines inside the torso box are cleared."""
    ID = spec["ids"]
    u0, v0, u1, v1 = spec["rear_from"]
    h, w = ids.shape
    y0, y1, x0, x1 = int(v0 * h), int(v1 * h), int(u0 * w), int(u1 * w)
    a2 = a[y0:y1, x0:x1].copy()
    i2 = ids[y0:y1, x0:x1].copy()
    out = np.zeros_like(i2)
    out[i2 == ID["CT"]] = ID["CTR"]
    out[i2 == ID["LT"]] = ID["LTR"]
    out[i2 == ID["RT"]] = ID["RTR"]
    head = i2 == ID["HD"]
    # only the part of the head that sits inside the torso box becomes torso; the rest drops out
    rows = np.arange(i2.shape[0])[:, None] + y0
    head &= rows >= int(spec.get("torso_top", 0.0) * h)
    out[head] = ID["CTR"]
    a2[head, 0:3] = 0
    keep = out > 0
    a2[~keep, 3] = 0
    Image.fromarray(a2, "RGBA").save(os.path.join(OUT, base + "_rear_shade.png"))
    idimg = np.zeros(a2.shape, dtype=np.uint8)
    idimg[..., 0] = (out * 20).astype(np.uint8)
    idimg[..., 3] = np.where(keep, 255, 0).astype(np.uint8)
    Image.fromarray(idimg, "RGBA").save(os.path.join(OUT, base + "_rear_id.png"))
    entry["rear"] = anchors(out)
    entry["rear_size"] = [a2.shape[1], a2.shape[0]]
    print("built", base + "_rear", a2.shape[1], a2.shape[0])


def main(only=None):
    path = os.path.join(OUT, "dolls.json")
    db = json.load(open(path)) if os.path.exists(path) else {}
    for name, spec in DOLLS.items():
        if only and name not in only:
            continue
        build(name, spec, db)
    with open(path, "w") as f:
        json.dump(db, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    import sys
    main(sys.argv[1:] or None)
