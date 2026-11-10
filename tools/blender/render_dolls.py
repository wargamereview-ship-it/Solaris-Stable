"""Renders the armor-doll silhouettes: a generic 'Mech per weight class (front and rear views) and a
top-down model of each vehicle type, with and without a turret.

    blender -b --factory-startup --python tools/blender/render_dolls.py -- assets/dolls [name ...]

Every model is built from beveled primitives, each tagged with the location it belongs to. Two
renders per view:
  <name>_shade.png  Cycles, lit grey clay with the detail (the doll shader tints it per location)
  <name>_id.png     the location map: red = location id * 20, alpha = inside the silhouette
plus dolls.json with each location's label anchor (the deepest point inside it), area and bounds.
The front view faces you (the 'Mech's left arm on the right of the picture); the rear view is from behind.
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "assets/dolls")
ONLY = argv[1:]

MECH_IDS = {"HD": 1, "CT": 2, "LT": 3, "RT": 4, "LA": 5, "RA": 6, "LL": 7, "RL": 8}
REAR_IDS = dict(MECH_IDS, CT=9, LT=10, RT=11)
VEH_IDS = {"FR": 1, "LS": 2, "RS": 3, "RR": 4, "TU": 5, "RO": 6, "BODY": 7}
LEVELS = [0.0, 0.5, 1.0]
MECH_RES = (520, 588)
VEH_RES = (260, 340)


MATS = {}
PARTS = []


def id_color(k):
    return (LEVELS[k % 3], LEVELS[(k // 3) % 3], LEVELS[(k // 9) % 3], 1.0)


def materials():
    MATS.clear()
    for name, col, rough, metal in (("clay", (0.6, 0.615, 0.635), 0.42, 0.35), ("trim", (0.34, 0.35, 0.37), 0.5, 0.45),
                                    ("dark", (0.045, 0.047, 0.05), 0.4, 0.3), ("glass", (0.02, 0.03, 0.04), 0.06, 0.0)):
        m = bpy.data.materials.new(name)
        try:
            m.use_nodes = True
        except Exception:
            pass
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (*col, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if name == "glass":
            bsdf.inputs["Specular IOR Level"].default_value = 1.0
        MATS[name] = m


def part(loc, center, dims, mat="clay", bevel=0.07, rot=(0.0, 0.0, 0.0), shape="box", segs=28,
         top=(1.0, 1.0), bottom=(1.0, 1.0), front=(1.0, 1.0), lean=0.0):
    """A primitive tagged with its location. top/bottom scale the upper/lower face (x, y),
    front scales the face towards the camera (x, z), lean shifts the top face along -Y (forward)."""
    if shape == "box":
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    elif shape == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=0.5, depth=1.0, location=center)
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs // 2, radius=0.5, location=center)
    ob = bpy.context.active_object
    for v in ob.data.vertices:
        c = v.co
        if c.z > 0.01:
            c.x *= top[0]
            c.y *= top[1]
            c.y -= lean
        elif c.z < -0.01:
            c.x *= bottom[0]
            c.y *= bottom[1]
        if c.y < -0.01:
            c.x *= front[0]
            c.z *= front[1]
    ob.scale = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.rotation_euler = Euler(rot)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(32))
    except Exception:
        bpy.ops.object.shade_smooth()
    if bevel > 0 and shape != "sphere":
        m = ob.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = 3
        m.limit_method = "ANGLE"
        m.angle_limit = math.radians(40)
    ob.data.materials.append(MATS[mat])
    ob["loc"] = loc
    PARTS.append(ob)
    return ob


Y90 = (math.pi / 2, 0.0, 0.0)      # a cylinder's axis along Y (towards the front camera)
X90 = (0.0, math.pi / 2, 0.0)      # along X


# ------------------------------------------------------------------ 'Mechs

def build_mech():
    """A 100-ton assault 'Mech after the Atlas: skull head set low between domed shoulders, a barrel
    chest over a ribbed waist, LRM and SRM racks in the left torso, the AC/20 muzzle in the right,
    huge fists, X-plated thighs, knee discs and clawed feet. It faces -Y; +X is its left side."""
    for sx, leg, arm, tor in ((1, "LL", "LA", "LT"), (-1, "RL", "RA", "RT")):
        hx = 1.5 * sx
        # foot: a wide wedge with three toes and a heel
        part(leg, (hx + 0.08 * sx, -0.35, 0.34), (2.25, 2.9, 0.68), "trim", 0.16, top=(0.82, 0.72))
        for tx in (-0.7, 0.0, 0.7):
            part(leg, (hx + 0.08 * sx + tx, -1.95, 0.26), (0.6, 1.05, 0.52), "clay", 0.12, top=(0.8, 0.6), lean=0.12)
        part(leg, (hx, 1.3, 0.3), (0.95, 0.8, 0.55), "clay", 0.1, top=(0.8, 0.7))
        part(leg, (hx, 0.0, 0.95), (1.1, 1.1, 1.5), "trim", 0.0, rot=X90, shape="cyl")
        for px in (-0.55, 0.55):
            part(leg, (hx + px, -0.7, 1.3), (0.22, 0.22, 1.1), "dark", 0.0, shape="cyl", segs=12)
        # shin: a flared boot with a forward greave and armored sides
        part(leg, (hx, 0.05, 2.55), (1.75, 1.7, 3.2), "clay", 0.16, top=(0.84, 0.88))
        part(leg, (hx, -0.95, 2.7), (1.7, 0.42, 2.9), "clay", 0.14, top=(0.82, 1.0), front=(0.9, 0.96), lean=0.08)
        part(leg, (hx, -1.18, 2.85), (0.34, 0.14, 2.3), "clay", 0.05, top=(0.6, 1.0))
        for side in (-1, 1):
            part(leg, (hx + side * 0.92, 0.0, 2.5), (0.3, 1.45, 2.6), "trim", 0.08, top=(1.0, 0.85))
        for k in range(3):
            part(leg, (hx, -1.17, 1.55 + k * 0.3), (1.0, 0.05, 0.08), "dark", 0.0)
        # knee: big discs both sides and a cap
        for side in (-1, 1):
            part(leg, (hx + side * 0.92, 0.0, 4.45), (1.5, 1.5, 0.34), "trim", 0.0, rot=(0, math.pi / 2, 0), shape="cyl", segs=40)
            part(leg, (hx + side * 1.1, 0.0, 4.45), (0.7, 0.7, 0.1), "clay", 0.0, rot=(0, math.pi / 2, 0), shape="cyl", segs=28)
        part(leg, (hx, -0.8, 4.5), (1.45, 0.8, 1.0), "clay", 0.2, front=(0.85, 0.85))
        # thigh, tapering to the knee, with the X-marked plate
        part(leg, (hx, 0.0, 6.05), (1.75, 1.85, 2.4), "clay", 0.18, bottom=(0.86, 0.9))
        part(leg, (hx, -1.0, 6.15), (1.5, 0.26, 1.9), "clay", 0.1, bottom=(0.88, 1.0), front=(0.92, 0.94))
        for a in (36.0, -36.0):
            part(leg, (hx, -1.15, 6.15), (0.13, 0.05, 2.0), "trim", 0.01, rot=(0, math.radians(a), 0))
        part(leg, (hx * 0.8, 0.0, 7.35), (1.35, 1.35, 1.1), "trim", 0.0, rot=X90, shape="cyl", segs=32)
        # side torso: deep, wider at the top, with an angled front and a sloped belly plate
        tx = 2.1 * sx
        part(tor, (tx, 0.1, 9.7), (1.75, 2.5, 2.7), "clay", 0.22, bottom=(0.82, 0.86), top=(1.0, 0.94))
        part(tor, (tx, -1.28, 9.95), (1.5, 0.32, 2.05), "clay", 0.1, bottom=(0.84, 1.0), front=(0.92, 0.94))
        part(tor, (tx * 0.97, -0.95, 8.42), (1.45, 0.6, 0.5), "trim", 0.08, rot=(math.radians(-32), 0, 0), top=(1.0, 1.0))
        part(tor, (tx, 1.38, 9.8), (1.45, 0.3, 2.0), "clay", 0.08)
        for k in range(4):
            part(tor, (tx, 1.55, 9.15 + k * 0.4), (1.1, 0.06, 0.1), "dark", 0.0)
        if sx == 1:
            # LRM 10 high beside the head, SRM 6 below it
            part(tor, (2.08, -1.55, 10.45), (1.0, 0.55, 1.5), "trim", 0.08, front=(0.94, 0.96))
            for c in (-0.23, 0.23):
                for r in range(5):
                    part(tor, (2.08 + c, -1.85, 9.88 + r * 0.28), (0.2, 0.2, 0.08), "dark", 0.0, rot=Y90, shape="cyl", segs=12)
            part(tor, (2.25, -1.5, 9.12), (0.7, 0.48, 1.0), "trim", 0.07, front=(0.92, 0.95))
            for c in (-0.15, 0.15):
                for r in range(3):
                    part(tor, (2.25 + c, -1.76, 8.82 + r * 0.3), (0.17, 0.17, 0.08), "dark", 0.0, rot=Y90, shape="cyl", segs=12)
        else:
            # the AC/20: housing, barrel and muzzle out of the right torso
            part(tor, (-2.15, -1.45, 9.85), (1.25, 0.65, 1.25), "trim", 0.14, front=(0.86, 0.86))
            part(tor, (-2.15, -2.1, 9.85), (0.82, 0.82, 1.25), "trim", 0.0, rot=Y90, shape="cyl", segs=36)
            part(tor, (-2.15, -2.75, 9.85), (1.0, 1.0, 0.2), "clay", 0.02, rot=Y90, shape="cyl", segs=36)
            part(tor, (-2.15, -2.86, 9.85), (0.54, 0.54, 0.06), "dark", 0.0, rot=Y90, shape="cyl", segs=24)
            part(tor, (-1.5, -1.05, 11.22), (0.52, 0.52, 0.14), "glass", 0.0, rot=Y90, shape="cyl", segs=20)
            part(tor, (-1.5, -0.95, 11.22), (0.66, 0.66, 0.12), "trim", 0.0, rot=Y90, shape="cyl", segs=20)
        # shoulder: a huge rounded pauldron hunched over the arm, with a dome and a lower rim
        ax = 3.62 * sx
        part(arm, (ax, 0.0, 10.95), (2.2, 2.6, 2.0), "clay", 0.65, bottom=(0.92, 0.95))
        part(arm, (ax, 0.0, 11.75), (2.1, 2.45, 1.05), "clay", 0.0, shape="sphere", segs=48)
        part(arm, (ax + 0.05 * sx, -0.12, 10.02), (2.3, 2.55, 0.34), "trim", 0.1)
        part(arm, (ax - 0.78 * sx, -1.08, 11.0), (0.26, 0.26, 0.26), "dark", 0.0, shape="sphere", segs=12)
        # upper arm, elbow, the massive forearm with its laser, and the fist
        part(arm, (ax, 0.0, 9.2), (1.25, 1.3, 1.8), "trim", 0.1)
        part(arm, (ax, 0.0, 8.42), (1.2, 1.2, 1.15), "trim", 0.0, rot=(0, math.pi / 2, 0), shape="cyl", segs=32)
        part(arm, (ax + 0.04 * sx, -0.2, 7.05), (1.95, 2.05, 2.55), "clay", 0.2, bottom=(0.9, 0.92))
        part(arm, (ax + 0.04 * sx, -1.27, 7.15), (1.6, 0.28, 2.1), "clay", 0.08, bottom=(0.9, 1.0), front=(0.92, 0.94))
        for k in range(2):
            part(arm, (ax + 0.04 * sx, -1.43, 6.62 + k * 0.95), (1.1, 0.05, 0.09), "dark", 0.0)
        part(arm, (ax + 1.05 * sx, -0.75, 7.45), (0.3, 0.3, 1.05), "trim", 0.0, rot=Y90, shape="cyl", segs=12)
        part(arm, (ax + 1.05 * sx, -1.3, 7.45), (0.16, 0.16, 0.05), "glass", 0.0, rot=Y90, shape="cyl", segs=10)
        part(arm, (ax + 0.04 * sx, -0.4, 5.25), (1.55, 1.6, 1.2), "trim", 0.18, bottom=(0.9, 0.9))
        for kx in (-0.54, -0.18, 0.18, 0.54):
            part(arm, (ax + 0.04 * sx + kx, -1.2, 5.38), (0.31, 0.36, 0.6), "clay", 0.07, bottom=(0.9, 0.9))
        part(arm, (ax - 0.76 * sx, -0.82, 5.3), (0.32, 0.55, 0.78), "clay", 0.07)
    # pelvis, the ribbed waist and the barrel chest
    part("CT", (0, 0.0, 7.55), (2.7, 2.0, 1.05), "trim", 0.16, bottom=(0.85, 0.9))
    part("CT", (0, -1.08, 7.32), (1.4, 0.32, 1.2), "clay", 0.12, bottom=(0.7, 1.0), lean=-0.1)
    for k in range(3):
        part("CT", (0, 0.0, 8.12 + k * 0.33), (2.15, 1.8, 0.3), "trim", 0.08)
        part("CT", (0, -0.96, 8.12 + k * 0.33), (1.85 - k * 0.0, 0.22, 0.26), "clay", 0.06)
    part("CT", (0, 0.0, 10.0), (2.65, 2.7, 2.5), "clay", 0.24, bottom=(0.86, 0.9))
    for side in (-1, 1):
        # the chest's V of armor plates
        part("CT", (side * 0.52, -1.4, 10.2), (1.0, 0.38, 1.85), "clay", 0.1, rot=(0, 0, math.radians(-14 * side)), bottom=(0.86, 1.0))
    part("CT", (0, -1.32, 9.05), (2.3, 0.45, 0.66), "clay", 0.08, rot=(math.radians(-26), 0, 0), top=(1.0, 1.0), bottom=(0.84, 1.0))
    for k in range(3):
        part("CT", (0, -1.68, 9.72 + k * 0.28), (0.5, 0.06, 0.09), "dark", 0.0)
    part("CT", (0, 1.65, 10.0), (2.3, 0.75, 2.05), "clay", 0.14)
    for k in range(6):
        part("CT", (-0.8 + k * 0.32, 2.07, 10.0), (0.09, 0.22, 1.65), "dark", 0.0)
    # the skull, set low and forward between the shoulders
    part("HD", (0, 0.1, 11.2), (1.0, 1.0, 0.6), "trim", 0.0, shape="cyl", segs=24)
    part("HD", (0, -0.75, 11.55), (1.45, 1.5, 1.25), "clay", 0.36, bottom=(0.82, 0.9))
    part("HD", (0, -0.58, 11.98), (1.42, 1.45, 0.82), "clay", 0.0, shape="sphere", segs=48)
    for ex in (-0.34, 0.34):
        part("HD", (ex, -1.5, 11.8), (0.46, 0.3, 0.34), "dark", 0.0, rot=(0, math.radians(-18 if ex < 0 else 18), 0), shape="sphere", segs=20)
    part("HD", (0, -1.56, 11.5), (0.2, 0.12, 0.24), "dark", 0.0, rot=(0, math.radians(45), 0))
    for ex in (-0.57, 0.57):
        part("HD", (ex, -1.38, 11.4), (0.34, 0.3, 0.5), "clay", 0.08, bottom=(0.8, 1.0))
    for k in range(6):
        part("HD", (-0.35 + k * 0.14, -1.53, 11.13), (0.09, 0.14, 0.26), "clay", 0.02)
    part("HD", (0, -1.4, 10.98), (0.95, 0.34, 0.2), "trim", 0.05)
    part("HD", (0, -1.46, 12.14), (1.12, 0.26, 0.18), "clay", 0.06)
    part("LT", (1.25, 0.3, 12.0), (0.08, 0.08, 2.1), "dark", 0.0, shape="cyl", segs=8)
    part("LT", (1.48, 0.48, 11.72), (0.06, 0.06, 1.35), "dark", 0.0, shape="cyl", segs=8)


# ------------------------------------------------------------------ vehicles

def build_vehicle(kind, turret):
    if kind == "tracked":
        for sx, loc in ((-1, "LS"), (1, "RS")):
            part(loc, (sx * 1.78, 0, 0.55), (0.78, 6.7, 1.1), "trim", 0.2)
            for k in range(24):
                part(loc, (sx * 1.78, -3.15 + k * 0.274, 1.11), (0.7, 0.11, 0.06), "dark", 0.0)
            part(loc, (sx * 1.6, 0.25, 1.12), (0.42, 5.3, 0.14), "clay", 0.05)
        part("BODY", (0, 0, 0.82), (2.8, 5.8, 1.0), "clay", 0.12)
        part("FR", (0, 2.6, 0.98), (2.9, 1.4, 0.62), "clay", 0.14, rot=(math.radians(-16), 0, 0))
        for hx in (-1.05, 1.05):
            part("FR", (hx, 3.28, 1.0), (0.24, 0.24, 0.12), "glass", 0.0, rot=Y90, shape="cyl", segs=12)
        part("RR", (0, -2.55, 1.02), (2.8, 1.2, 0.52), "clay", 0.12)
        for k in range(5):
            part("RR", (0, -2.1 - k * 0.2, 1.3), (2.0, 0.08, 0.06), "dark", 0.0)
        for ex in (-0.9, 0.9):
            part("RR", (ex, -3.1, 1.15), (0.3, 0.3, 0.3), "dark", 0.0, shape="cyl", segs=12)
        if turret:
            part("TU", (0, 0.15, 1.68), (2.15, 2.5, 0.75), "clay", 0.24)
            part("TU", (0, -1.05, 1.66), (1.7, 0.9, 0.6), "clay", 0.14)
            part("TU", (0, 2.75, 1.72), (0.3, 0.3, 3.3), "trim", 0.0, rot=Y90, shape="cyl")
            part("TU", (0, 4.45, 1.72), (0.46, 0.46, 0.5), "dark", 0.0, rot=Y90, shape="cyl")
            part("TU", (0.6, -0.25, 2.12), (0.6, 0.6, 0.26), "clay", 0.04, shape="cyl")
            part("TU", (-0.62, 0.55, 2.1), (0.35, 0.9, 0.2), "trim", 0.04)
        else:
            part("BODY", (0, -0.1, 1.45), (2.2, 2.6, 0.5), "clay", 0.16)
            part("BODY", (0.5, -0.3, 1.75), (0.6, 0.6, 0.2), "trim", 0.04, shape="cyl")
            for gx in (-0.5, 0.5):
                part("FR", (gx, 3.35, 1.06), (0.22, 0.22, 1.3), "trim", 0.0, rot=Y90, shape="cyl", segs=12)
    elif kind == "wheeled":
        for wy in (-2.1, -0.7, 0.7, 2.1):
            for sx in (-1, 1):
                part("BODY", (sx * 1.38, wy, 0.55), (1.05, 1.05, 0.5), "dark", 0.04, rot=X90, shape="cyl")
        part("BODY", (0, 0, 1.0), (2.5, 6.2, 0.9), "clay", 0.35)
        part("FR", (0, 2.65, 1.06), (2.45, 1.35, 0.86), "clay", 0.42)
        for hx in (-0.85, 0.85):
            part("FR", (hx, 3.3, 1.05), (0.26, 0.26, 0.1), "glass", 0.0, rot=Y90, shape="cyl", segs=12)
        part("RR", (0, -2.7, 1.06), (2.45, 1.2, 0.86), "clay", 0.38)
        for sx, loc in ((-1, "LS"), (1, "RS")):
            part(loc, (sx * 1.3, 0, 1.08), (0.3, 3.9, 0.72), "clay", 0.08)
            part(loc, (sx * 1.48, 0, 1.2), (0.1, 3.2, 0.22), "trim", 0.03)
        if turret:
            part("TU", (0, 0.1, 1.7), (1.7, 1.9, 0.62), "clay", 0.22)
            part("TU", (0, 2.1, 1.72), (0.22, 0.22, 2.4), "trim", 0.0, rot=Y90, shape="cyl")
            part("TU", (0.45, -0.35, 2.06), (0.45, 0.45, 0.2), "clay", 0.03, shape="cyl")
        else:
            part("BODY", (0, -0.4, 1.55), (1.4, 1.6, 0.25), "trim", 0.08)
            part("BODY", (0, 0.4, 1.6), (0.55, 0.55, 0.3), "clay", 0.03, shape="cyl")
            part("FR", (0, 1.2, 1.62), (0.14, 0.14, 1.4), "dark", 0.0, rot=Y90, shape="cyl", segs=10)
    elif kind == "hover":
        part("BODY", (0, 0, 0.3), (4.0, 6.6, 0.6), "dark", 0.7)
        part("BODY", (0, 0, 0.85), (3.0, 5.8, 0.8), "clay", 0.55)
        part("FR", (0, 2.3, 0.98), (3.0, 1.5, 0.6), "clay", 0.5, rot=(math.radians(-12), 0, 0))
        for sx, loc in ((-1, "LS"), (1, "RS")):
            part(loc, (sx * 1.62, -0.1, 0.95), (0.55, 3.4, 0.62), "clay", 0.22)
        part("RR", (0, -2.45, 0.98), (2.85, 1.5, 0.6), "clay", 0.32)
        for fx in (-0.72, 0.72):
            part("RR", (fx, -2.45, 1.22), (1.02, 1.02, 0.2), "dark", 0.0, shape="cyl", segs=32)
            for k in range(5):
                part("RR", (fx, -2.45, 1.32), (0.9, 0.12, 0.04), "trim", 0.0, rot=(0, 0, k * math.pi / 5 + 0.3))
            part("RR", (fx, -2.45, 1.36), (0.24, 0.24, 0.06), "clay", 0.0, shape="cyl", segs=12)
        if turret:
            part("TU", (0, 0.25, 1.55), (1.55, 1.7, 0.55), "clay", 0.22)
            part("TU", (0, 2.0, 1.58), (0.2, 0.2, 2.1), "trim", 0.0, rot=Y90, shape="cyl")
        else:
            part("BODY", (0, 0.2, 1.38), (1.6, 2.0, 0.3), "trim", 0.1)
            part("BODY", (0.4, -0.2, 1.58), (0.5, 0.5, 0.2), "clay", 0.03, shape="cyl")
    elif kind == "vtol":
        part("BODY", (0, 0.2, 1.0), (1.55, 3.8, 1.3), "clay", 0.0, shape="sphere", segs=40)
        part("FR", (0, 1.95, 0.95), (1.22, 1.9, 1.0), "clay", 0.0, shape="sphere", segs=40)
        part("FR", (0, 1.75, 1.42), (0.78, 1.25, 0.5), "glass", 0.0, shape="sphere", segs=32)
        for sx, loc in ((-1, "LS"), (1, "RS")):
            part(loc, (sx * 1.35, 0.2, 0.9), (1.5, 0.75, 0.16), "clay", 0.05)
            part(loc, (sx * 2.05, 0.35, 0.78), (0.36, 0.36, 1.35), "trim", 0.0, rot=Y90, shape="cyl")
            part(loc, (sx * 2.05, 1.05, 0.78), (0.2, 0.2, 0.08), "dark", 0.0, rot=Y90, shape="cyl", segs=12)
        part("RR", (0, -2.7, 1.12), (0.42, 0.42, 3.6), "clay", 0.0, rot=Y90, shape="cyl")
        part("RR", (0, -4.25, 1.12), (1.9, 0.45, 0.1), "clay", 0.04)
        part("RR", (0, -4.45, 1.5), (0.12, 0.7, 0.9), "clay", 0.03)
        part("BODY", (0.25, -4.55, 1.55), (0.95, 0.95, 0.05), "dark", 0.0, rot=(0, math.pi / 2, 0), shape="cyl", segs=20)
        part("BODY", (0, 0.25, 1.78), (0.5, 0.5, 0.4), "trim", 0.0, shape="cyl")
        if turret:
            part("TU", (0, 2.95, 0.72), (0.6, 0.6, 0.6), "trim", 0.0, shape="sphere")
            for gx in (-0.12, 0.12):
                part("TU", (gx, 3.45, 0.72), (0.1, 0.1, 0.7), "dark", 0.0, rot=Y90, shape="cyl", segs=8)


# ------------------------------------------------------------------ scene and rendering

def scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PARTS.clear()
    materials()
    sc = bpy.context.scene
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "HIP"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "HIP"
        sc.cycles.device = "GPU"
    except Exception as e:
        print("GPU unavailable:", e)
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.dither_intensity = 0.0
    world = bpy.data.worlds.new("w")
    sc.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.5, 0.55, 0.62, 1.0)
        bg.inputs[1].default_value = 0.12
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    sc.collection.objects.link(cam)
    sc.camera = cam
    target = bpy.data.objects.new("target", None)
    sc.collection.objects.link(target)
    lights = {}
    for name, energy, size in (("key", 4200.0, 5.0), ("rim", 3400.0, 4.0), ("fill", 260.0, 14.0)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = size
        lo = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(lo)
        con = lo.constraints.new("TRACK_TO")
        con.target = target
        con.track_axis = "TRACK_NEGATIVE_Z"
        con.up_axis = "UP_Y"
        lights[name] = lo
    return sc, cam, target, lights


def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in PARTS:
        ev = ob.evaluated_get(dg)
        for c in ev.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def load_px(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)[::-1].copy()


def save_px(path, a):
    h, w, _ = a.shape
    img = bpy.data.images.new("out", w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(a[::-1]).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def anchors(ids):
    out = {}
    for k in np.unique(ids):
        k = int(k)
        if k == 0:
            continue
        m = ids == k
        ys, xs = np.nonzero(m)
        cur = m
        for _ in range(400):
            e = cur.copy()
            e[1:, :] &= cur[:-1, :]
            e[:-1, :] &= cur[1:, :]
            e[:, 1:] &= cur[:, :-1]
            e[:, :-1] &= cur[:, 1:]
            if not e.any():
                break
            cur = e
        cy, cx = np.nonzero(cur)
        mx, my = cx.mean(), cy.mean()
        j = int(np.argmin((cx - mx) ** 2 + (cy - my) ** 2))
        out[str(k)] = {"anchor": [int(cx[j]), int(cy[j])], "area": int(m.sum()),
                       "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]}
    return out


def render_view(sc, cam, target, lights, name, view, res, idmap):
    lo, hi = bounds()
    sc.render.resolution_x, sc.render.resolution_y = res
    aspect = res[0] / res[1]
    if view == "top":
        cy = (lo.y + hi.y) / 2
        cx = (lo.x + hi.x) / 2
        cam.location = (cx, cy, 40.0)
        cam.rotation_euler = Euler((0, 0, 0))
        cam.data.ortho_scale = max((hi.y - lo.y) * 1.08, (hi.x - lo.x) * 1.08 / aspect)
        target.location = (cx, cy, 0.8)
        lights["key"].location = (cx - 9, cy + 9, 22)
        lights["rim"].location = (cx + 10, cy - 12, 8)
        lights["fill"].location = (cx + 12, cy + 4, 16)
    else:
        cz = (lo.z + hi.z) / 2
        cam.data.ortho_scale = max((hi.z - lo.z) * 1.05, (hi.x - lo.x) * 1.05 / aspect)
        side = -1 if view == "front" else 1
        cam.location = (0, 40.0 * side, cz)
        cam.rotation_euler = Euler((math.pi / 2, 0, 0 if view == "front" else math.pi))
        target.location = (0, 0, cz)
        # the key light high on the viewer's left in both views
        lights["key"].location = (-13 * -side, 10 * side, cz + 11)
        lights["rim"].location = (10 * -side, -13 * side, cz + 9)
        lights["fill"].location = (14 * -side, 12 * side, cz - 3)
    shade_tmp = os.path.join(OUT, "_tmp_shade.png")
    id_tmp = os.path.join(OUT, "_tmp_id.png")
    # the shading pass
    sc.render.engine = "CYCLES"
    sc.view_settings.view_transform = "AgX"
    for look in ("AgX - Punchy", "Punchy", "AgX - Medium High Contrast"):
        try:
            sc.view_settings.look = look
            break
        except Exception:
            pass
    sc.render.filepath = shade_tmp
    bpy.ops.render.render(write_still=True)
    # the location map
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.render_aa = "OFF"
    sh = sc.display.shading
    sh.light = "FLAT"
    sh.color_type = "OBJECT"
    sh.show_object_outline = False
    sh.show_cavity = False
    sh.show_shadows = False
    sc.view_settings.view_transform = "Standard"
    for ob in PARTS:
        ob.color = id_color(idmap[ob["loc"]])
    sc.render.filepath = id_tmp
    bpy.ops.render.render(write_still=True)
    shade = load_px(shade_tmp)
    raw = load_px(id_tmp)
    q = np.where(raw[..., :3] < 0.37, 0, np.where(raw[..., :3] < 0.87, 1, 2))
    ids = (q[..., 0] + 3 * q[..., 1] + 9 * q[..., 2]).astype(np.int32)
    ids[raw[..., 3] < 0.5] = 0
    idimg = np.zeros(raw.shape, dtype=np.float32)
    idimg[..., 0] = ids * 20.0 / 255.0
    idimg[..., 3] = (ids > 0).astype(np.float32)
    save_px(os.path.join(OUT, name + "_shade.png"), shade)
    save_px(os.path.join(OUT, name + "_id.png"), idimg)
    os.remove(shade_tmp)
    os.remove(id_tmp)
    print("RENDERED", name)
    return anchors(ids)


os.makedirs(OUT, exist_ok=True)
db_path = os.path.join(OUT, "dolls.json")
db = json.load(open(db_path)) if os.path.exists(db_path) else {}
for key in ("mech",):
    if ONLY and key not in ONLY:
        continue
    sc, cam, target, lights = scene()
    build_mech()
    front = render_view(sc, cam, target, lights, key + "_front", "front", MECH_RES, MECH_IDS)
    rear = render_view(sc, cam, target, lights, key + "_rear", "rear", MECH_RES, REAR_IDS)
    db[key] = {"size": list(MECH_RES), "front": front, "rear": rear}
for kind in ("tracked", "wheeled", "hover", "vtol"):
    for tur in (False, True):
        key = "veh_%s%s" % (kind, "_t" if tur else "")
        if ONLY and key not in ONLY:
            continue
        sc, cam, target, lights = scene()
        build_vehicle(kind, tur)
        db[key] = {"size": list(VEH_RES), "top": render_view(sc, cam, target, lights, key, "top", VEH_RES, VEH_IDS)}
with open(db_path, "w") as f:
    json.dump(db, f, indent=1, sort_keys=True)
print("WROTE", db_path)
