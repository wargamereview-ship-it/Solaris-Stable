"""Draws the 'Mech armor doll: an original flat, hard-edged silhouette in the spirit of a record
sheet's armor diagram (left side on the left, as on a record sheet), plus the rear torso.

    python3 tools/dolls/draw_mech_doll.py

Writes assets/dolls/mech_front_{shade,id}.png and mech_rear_{shade,id}.png and the "mech" entry of
assets/dolls/dolls.json, the same format build_doll_maps.py writes for the vehicles. The shade
image is flat grey plates with panel lines, which the targeting shader turns into line work.
Shapes are in a 200 x 230 design space (x right, y down).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_doll_maps import MECH_IDS, OUT, anchors  # noqa: E402

W, H = 200, 230
K = 2.6          # texels per design unit in the output
SS = 4           # supersampling for the shade image

# the left half (viewer's left = the 'Mech's left); the right half mirrors it. One connected body:
# finned shoulders over long arms with hands, side torsos flanking a centre torso that runs down to
# the crotch, the head set into a notch at its top, legs spread in an A-stance onto broad feet.
LEFT = {
    "LA": [(42, 42), (40, 30), (32, 22), (26, 28), (18, 22), (10, 28), (4, 40), (4, 56), (6, 60), (6, 104), (4, 108),
           (6, 112), (6, 150), (4, 154), (4, 170), (10, 178), (28, 178), (34, 170), (34, 154), (32, 150), (32, 112),
           (34, 108), (32, 104), (32, 60), (42, 54)],
    "LT": [(42, 40), (78, 36), (78, 122), (50, 122), (42, 112)],
    "LL": [(46, 124), (78, 124), (78, 128), (84, 150), (84, 158), (80, 166), (74, 200), (76, 208), (82, 214), (84, 226),
           (30, 226), (26, 216), (30, 208), (32, 200), (36, 166), (34, 158), (40, 142)],
}
CENTRE = {
    "CT": [(78, 34), (84, 34), (84, 44), (116, 44), (116, 34), (122, 34), (122, 128), (116, 150), (84, 150), (78, 128)],
    "HD": [(86, 8), (114, 8), (120, 16), (121, 32), (116, 43), (84, 43), (79, 32), (80, 16)],
}
REAR_CT = [(78, 34), (122, 34), (122, 128), (116, 150), (84, 150), (78, 128)]
MIRROR = {"RA": "LA", "RT": "LT", "RL": "LL"}
FRONT_ORDER = ["LL", "RL", "LA", "RA", "LT", "RT", "CT", "HD"]

# panel detail per location: lines [(x0, y0), (x1, y1)] and dark / light patches (polygons), left side
DETAIL_LINES = {
    "HD": [[(84, 36), (116, 36)]],
    "CT": [[(84, 62), (116, 62)], [(82, 96), (118, 96)], [(100, 48), (100, 60)], [(86, 104), (100, 116), (114, 104)],
           [(90, 124), (110, 124)], [(90, 130), (110, 130)], [(92, 136), (108, 136)]],
    "LT": [[(44, 76), (78, 74)], [(46, 98), (78, 98)], [(58, 98), (58, 120)]],
    "LA": [[(6, 56), (32, 56)], [(10, 28), (40, 36)], [(6, 108), (32, 108)], [(6, 152), (32, 152)], [(10, 160), (10, 172)],
           [(16, 158), (16, 176)], [(22, 158), (22, 176)], [(28, 160), (28, 172)]],
    "LL": [[(42, 140), (82, 146)], [(46, 200), (74, 200)], [(34, 208), (78, 208)], [(30, 218), (82, 218)],
           [(52, 172), (49, 196)], [(66, 172), (65, 196)]],
}
DETAIL_DARK = {
    "HD": [[(88, 16), (112, 16), (110, 27), (90, 27)]],
    "LT": [[(48, 44), (72, 42), (72, 68), (48, 69)]],
    "LL": [[(40, 156), (80, 156), (78, 168), (42, 168)]],
}
DETAIL_LIGHT = {
    "LT": [[(51, 47), (56, 47), (56, 52), (51, 52)], [(58, 47), (63, 47), (63, 52), (58, 52)], [(65, 46), (70, 46), (70, 51), (65, 51)],
           [(51, 55), (56, 55), (56, 60), (51, 60)], [(58, 55), (63, 55), (63, 60), (58, 60)], [(65, 54), (70, 54), (70, 59), (65, 59)],
           [(51, 63), (56, 63), (56, 67), (51, 67)], [(58, 63), (63, 63), (63, 67), (58, 67)], [(65, 62), (70, 62), (70, 66), (65, 66)]],
    "LL": [[(44, 159), (78, 159), (77, 165), (45, 165)]],
}


def mirror(pts):
    return [(W - x, y) for x, y in pts]


def shape(loc, rear=False):
    if rear and loc == "CT":
        return REAR_CT
    if loc in LEFT:
        return LEFT[loc]
    if loc in MIRROR:
        return mirror(LEFT[MIRROR[loc]])
    return CENTRE[loc]


def parts_for(loc):
    """(lines, dark, light) for a location, mirrored for the right side."""
    src = MIRROR.get(loc, loc)
    f = mirror if loc in MIRROR else (lambda p: p)
    return ([f(l) for l in DETAIL_LINES.get(src, [])], [f(p) for p in DETAIL_DARK.get(src, [])],
            [f(p) for p in DETAIL_LIGHT.get(src, [])])


def draw(locs, ids, box, rear=False):
    """Renders locs (in draw order) inside box = (x0, y0, x1, y1) of the design space."""
    x0, y0, x1, y1 = box
    w, h = int(round((x1 - x0) * K)), int(round((y1 - y0) * K))

    def tx(pts, k):
        return [((x - x0) * k, (y - y0) * k) for x, y in pts]
    idimg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    di = ImageDraw.Draw(idimg)
    for loc in locs:
        di.polygon(tx(shape(loc, rear), K), fill=(ids[loc] * 20, 0, 0, 255))
    k2 = K * SS
    sh = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    for loc in locs:
        m = Image.new("L", sh.size, 0)
        ImageDraw.Draw(m).polygon(tx(shape(loc, rear), k2), fill=255)
        # a plate: lit from the top, a dark rim and a light inner bevel
        grad = Image.linear_gradient("L").resize(sh.size)
        grad = grad.point(lambda v: int(205 - v * 0.22))
        plate = Image.merge("RGBA", (grad, grad, grad, m))
        sh.alpha_composite(plate)
        inner = m.filter(ImageFilter.MinFilter(int(2.4 * k2) | 1))
        inner2 = inner.filter(ImageFilter.MinFilter(int(0.9 * k2) | 1))
        ring = Image.eval(Image.merge("L", (inner,)), lambda v: v)
        line = Image.new("L", sh.size, 0)
        line.paste(255, mask=ring)
        line.paste(0, mask=inner2)
        sh.paste((120, 120, 120, 255), mask=line)
        dr = ImageDraw.Draw(sh)
        lines, dark, light = parts_for(loc) if not rear else ([], [], [])
        for p in dark:
            dr.polygon(tx(p, k2), fill=(70, 70, 72, 255))
        for p in light:
            dr.polygon(tx(p, k2), fill=(150, 150, 152, 255))
        for l in lines:
            dr.line(tx(l, k2), fill=(110, 110, 112, 255), width=max(2, int(0.9 * k2)))
        edge = m.filter(ImageFilter.MaxFilter(int(1.2 * k2) | 1))
        outl = Image.new("L", sh.size, 0)
        outl.paste(255, mask=edge)
        outl.paste(0, mask=m.filter(ImageFilter.MinFilter(int(1.2 * k2) | 1)))
        sh.paste((40, 40, 42, 255), mask=outl)
    sh = sh.resize((w, h), Image.LANCZOS)
    return sh, idimg


def main():
    path = os.path.join(OUT, "dolls.json")
    db = json.load(open(path)) if os.path.exists(path) else {}
    entry = {}
    sh, idimg = draw(FRONT_ORDER, MECH_IDS, (0, 0, W, H))
    sh.save(os.path.join(OUT, "mech_front_shade.png"))
    idimg.save(os.path.join(OUT, "mech_front_id.png"))
    ids = np.round(np.array(idimg)[..., 0] / 20.0).astype(np.int32)
    ids[np.array(idimg)[..., 3] < 128] = 0
    entry["front"] = anchors(ids)
    entry["front_size"] = list(sh.size)
    # the rear torso: the same three plates seen from behind (left still on the left)
    rear_ids = {"LT": MECH_IDS["LTR"], "RT": MECH_IDS["RTR"], "CT": MECH_IDS["CTR"]}
    sh2, id2 = draw(["LT", "RT", "CT"], rear_ids, (38, 30, 162, 154), rear=True)
    sh2.save(os.path.join(OUT, "mech_rear_shade.png"))
    id2.save(os.path.join(OUT, "mech_rear_id.png"))
    ids2 = np.round(np.array(id2)[..., 0] / 20.0).astype(np.int32)
    ids2[np.array(id2)[..., 3] < 128] = 0
    entry["rear"] = anchors(ids2)
    entry["rear_size"] = list(sh2.size)
    db["mech"] = entry
    with open(path, "w") as f:
        json.dump(db, f, indent=1, sort_keys=True)
    print("front", sh.size, "rear", sh2.size)


if __name__ == "__main__":
    main()
