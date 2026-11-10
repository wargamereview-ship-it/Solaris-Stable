"""Renders the planet portraits for the merc star map's system panel.

    blender -b --factory-startup --python tools/blender/render_planets.py -- assets/planets [type ...]

Each world type is a procedural Cycles material (height noise, a color ramp, ice caps, a cloud
shell and a lit atmosphere rim), lit by one star, rendered on a transparent background.
Three seeded variants per type: <type>_<n>.png at 512x512.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "assets/planets")
ONLY = argv[1:]
ATMO_R = 1.07
VARIANTS = int(os.environ.get("PLANET_VARIANTS", "3"))
SIZE = 512
LIGHT = Vector((0.93, 0.16, -0.33)).normalized()     # the direction the starlight travels


def C(h):
    h = h.lstrip("#")
    return tuple(int(h[k:k + 2], 16) / 255.0 for k in (0, 2, 4))


# sea = height threshold of the oceans (noise is centred on 0.5); land = ramp above it
TYPES = {
    "terran": dict(sea=0.5, scale=1.8, water=["#0b2447", "#1b4f8a", "#3b86b8"], land=["#c9b98a", "#5f8a3a", "#3d6b2c", "#7a6a4a", "#d9d5cc"],
                   dry="#a58a5a", caps=0.78, clouds=0.52, cloud_col="#ffffff", atmo="#6aa8ff", atmo_k=1.0),
    "ocean": dict(sea=0.59, scale=2.6, water=["#071c3d", "#11457e", "#2f8fbf"], land=["#d8cf9a", "#4f8a3a", "#3a6b30", "#86806a", "#e8e8e8"],
                  dry="#8aa05a", caps=0.82, clouds=0.47, cloud_col="#ffffff", atmo="#5aa0ff", atmo_k=1.15),
    "jungle": dict(sea=0.47, scale=2.0, water=["#062030", "#0c4a5a", "#1f7a7a"], land=["#6a8a2a", "#1f5a14", "#164510", "#2a4a1a", "#4a5a3a"],
                   dry="#3a7a1a", caps=0.95, clouds=0.53, cloud_col="#f4f8f4", atmo="#7ac0ff", atmo_k=1.2),
    "arid": dict(sea=0.44, scale=2.2, water=["#0d2a44", "#1e5a80", "#4a8aa8"], land=["#d6c08a", "#b09060", "#8a6a44", "#a07a52", "#e0d0b8"],
                 dry="#7a8a4a", caps=0.88, clouds=0.6, cloud_col="#ffffff", atmo="#8ab0e0", atmo_k=0.8),
    "steppe": dict(sea=0.46, scale=2.4, water=["#0c2440", "#1d4f7a", "#3c7aa0"], land=["#b8a878", "#8a8a4a", "#6a6a38", "#8a7a5a", "#e8e4dc"],
                   dry="#a08a50", caps=0.72, clouds=0.56, cloud_col="#ffffff", atmo="#7aa8f0", atmo_k=0.9),
    "desert": dict(sea=0.35, scale=2.0, water=["#2a3040", "#3a5060", "#5a7a80"], land=["#e8c890", "#d0a060", "#b8783c", "#8a5530", "#e8d4b0"],
                   dry="#c08850", caps=0.97, clouds=0.72, cloud_col="#fff4e8", atmo="#f0b878", atmo_k=0.6),
    "ice": dict(sea=0.47, scale=2.4, water=["#3a5a7a", "#6a90b0", "#9ac0d8"], land=["#d8e4ee", "#c4d4e2", "#e8f0f6", "#b0c4d6", "#ffffff"],
                dry="#a8bcd0", caps=0.35, clouds=0.6, cloud_col="#f8fbff", atmo="#a8d0ff", atmo_k=0.9, cracks=True),
    "toxic": dict(sea=0.48, scale=2.0, water=["#2a2a10", "#44461a", "#5a5a26"], land=["#8a7a34", "#6a5a22", "#4a3e1a", "#6a5a30", "#9a8a5a"],
                  dry="#7a7a26", caps=0.99, clouds=0.47, cloud_col="#c8b048", atmo="#c0c848", atmo_k=1.4, bands=True),
    "tainted": dict(sea=0.5, scale=2.3, water=["#13302a", "#24504a", "#3a6a5a"], land=["#9a9060", "#5a6a30", "#4a5226", "#6a5a3a", "#c8c4a8"],
                    dry="#8a7a40", caps=0.85, clouds=0.53, cloud_col="#e8e4c8", atmo="#a8c870", atmo_k=1.0),
    "barren": dict(sea=0.0, scale=2.6, water=["#555555", "#555555", "#555555"], land=["#8a8480", "#6e6862", "#5a5550", "#9a948c", "#b4aea6"],
                   dry="#7a6a5a", caps=1.2, clouds=0.0, cloud_col="#ffffff", atmo="#9a9a9a", atmo_k=0.12, craters=True),
    "volcanic": dict(sea=0.43, scale=2.2, water=["#ff5a10", "#ff7a20", "#ffa040"], land=["#3a2a26", "#2a201e", "#1c1616", "#4a3a34", "#6a5a50"],
                     dry="#3a2420", caps=1.2, clouds=0.62, cloud_col="#5a5050", atmo="#ff8a50", atmo_k=0.8, lava=True),
}


def inp(n, ident):
    return next(s for s in n.inputs if s.identifier == ident)


def outp(n, ident):
    return next(s for s in n.outputs if s.identifier == ident)


class NB:
    def __init__(self, name):
        self.mat = bpy.data.materials.new(name)
        if hasattr(self.mat, "use_nodes"):
            try:
                self.mat.use_nodes = True
            except Exception:
                pass
        self.nt = self.mat.node_tree
        self.nt.nodes.clear()

    def n(self, t, **kw):
        node = self.nt.nodes.new(t)
        for k, v in kw.items():
            setattr(node, k, v)
        return node

    def link(self, a, b):
        self.nt.links.new(a, b)

    def val(self, v):
        node = self.n("ShaderNodeValue")
        node.outputs[0].default_value = v
        return node.outputs[0]

    def math(self, op, a, b=None, clamp=False):
        node = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        for k, x in enumerate([a, b]):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                node.inputs[k].default_value = x
            else:
                self.link(x, node.inputs[k])
        return node.outputs[0]

    def ramp(self, fac, stops, interp="LINEAR"):
        node = self.n("ShaderNodeValToRGB")
        cr = node.color_ramp
        cr.interpolation = interp
        els = cr.elements
        els[0].position = stops[0][0]
        els[0].color = (*stops[0][1], 1.0)
        els.remove(els[1])
        for p, col in stops[1:]:
            e = els.new(p)
            e.color = (*col, 1.0)
        self.link(fac, inp(node, "Fac"))
        return outp(node, "Color")

    def mix(self, fac, a, b):
        node = self.n("ShaderNodeMix", data_type="RGBA")
        for ident, x in (("Factor_Float", fac), ("A_Color", a), ("B_Color", b)):
            s = inp(node, ident)
            if isinstance(x, tuple):
                s.default_value = (*x, 1.0) if len(x) == 3 else x
            elif isinstance(x, (int, float)):
                s.default_value = x
            else:
                self.link(x, s)
        return outp(node, "Result_Color")

    def noise(self, vec, scale, detail=12.0, rough=0.6, dist=0.0, lac=2.0):
        node = self.n("ShaderNodeTexNoise")
        inp(node, "Scale").default_value = scale
        inp(node, "Detail").default_value = detail
        inp(node, "Roughness").default_value = rough
        inp(node, "Distortion").default_value = dist
        inp(node, "Lacunarity").default_value = lac
        self.link(vec, inp(node, "Vector"))
        return node

    def coords(self, offset, scale=(1, 1, 1)):
        tc = self.n("ShaderNodeTexCoord")
        mp = self.n("ShaderNodeMapping")
        inp(mp, "Location").default_value = offset
        inp(mp, "Scale").default_value = scale
        self.link(outp(tc, "Object"), inp(mp, "Vector"))
        return outp(mp, "Vector")


def surface_material(spec, rng):
    nb = NB("surface")
    off = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    vec = nb.coords(off)
    # a low-frequency warp makes continents instead of uniform blobs
    warp = nb.noise(vec, 0.9, 3.0, 0.5)
    wv = nb.n("ShaderNodeVectorMath", operation="SCALE")
    nb.link(outp(warp, "Color"), wv.inputs[0])
    inp(wv, "Scale").default_value = 0.65
    add = nb.n("ShaderNodeVectorMath", operation="ADD")
    nb.link(vec, add.inputs[0])
    nb.link(wv.outputs[0], add.inputs[1])
    hnode = nb.noise(add.outputs[0], spec["scale"], 15.0, 0.62, 0.0, 2.1)
    h = outp(hnode, "Fac")
    sea = spec["sea"]
    w = [C(x) for x in spec["water"]]
    l = [C(x) for x in spec["land"]]
    if spec.get("craters"):
        sea = -1.0
    stops = []
    if sea > 0:
        stops += [(max(0.0, sea - 0.16), w[0]), (sea - 0.05, w[1]), (sea - 0.004, w[2])]
    s0 = max(sea, 0.0)
    stops += [(s0 + 0.002, l[0]), (s0 + 0.03, l[1]), (s0 + 0.09, l[2]), (s0 + 0.17, l[3]), (min(0.99, s0 + 0.27), l[4])]
    stops.sort(key=lambda t: t[0])
    col = nb.ramp(h, stops)
    land = nb.math("GREATER_THAN", h, sea) if sea > 0 else nb.val(1.0)
    # patches of a second ground colour (deserts, plains) over the land
    pnode = nb.noise(vec, 4.5, 6.0, 0.55)
    pm = nb.math("MULTIPLY", nb.math("MULTIPLY", nb.math("SUBTRACT", outp(pnode, "Fac"), 0.48, True), 2.2, True), land)
    col = nb.mix(pm, col, C(spec["dry"]))
    rough = nb.math("ADD", nb.math("MULTIPLY", land, 0.62), 0.28)
    height = nb.math("MULTIPLY", nb.math("MAXIMUM", nb.math("SUBTRACT", h, max(sea, 0.3)), 0.0), land)
    emis_col = None
    emis_k = None
    if spec.get("craters"):
        for sc, depth in ((5.0, 0.14), (13.0, 0.06), (30.0, 0.025)):
            vor = nb.n("ShaderNodeTexVoronoi")
            inp(vor, "Scale").default_value = sc
            nb.link(vec, inp(vor, "Vector"))
            d = outp(vor, "Distance")
            rim = nb.math("MULTIPLY", nb.math("POWER", nb.math("MINIMUM", nb.math("DIVIDE", d, 0.42), 1.0), 3.0), depth)
            height = nb.math("ADD", height, rim)
            col = nb.mix(nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, nb.math("MINIMUM", nb.math("DIVIDE", d, 0.3), 1.0)), 0.25), col, (0.38, 0.36, 0.34))
    if spec.get("cracks") or spec.get("lava"):
        cv = nb.noise(vec, 1.5, 2.0, 0.5)
        cw = nb.n("ShaderNodeVectorMath", operation="ADD")
        nb.link(vec, cw.inputs[0])
        nb.link(outp(cv, "Color"), cw.inputs[1])
        vor = nb.n("ShaderNodeTexVoronoi", feature="DISTANCE_TO_EDGE")
        inp(vor, "Scale").default_value = 4.0 if spec.get("cracks") else 6.0
        nb.link(cw.outputs[0], inp(vor, "Vector"))
        edge = nb.math("SUBTRACT", 1.0, nb.math("MINIMUM", nb.math("DIVIDE", outp(vor, "Distance"), 0.035), 1.0))
        if spec.get("cracks"):
            col = nb.mix(nb.math("MULTIPLY", edge, 0.6), col, (0.25, 0.45, 0.65))
        else:
            sea_mask = nb.math("SUBTRACT", 1.0, land)
            glow = nb.math("MAXIMUM", nb.math("MULTIPLY", edge, land), sea_mask)
            # only some regions are active: the rest of the crust has cooled
            act = nb.noise(vec, 1.2, 3.0, 0.5)
            active = nb.math("MULTIPLY", nb.math("SUBTRACT", outp(act, "Fac"), 0.44, True), 5.0, True)
            glow = nb.math("MAXIMUM", nb.math("MULTIPLY", nb.math("MULTIPLY", edge, land), active), nb.math("MULTIPLY", sea_mask, 0.42))
            emis_col = nb.ramp(glow, [(0.0, (0.0, 0.0, 0.0)), (0.4, (0.75, 0.12, 0.02)), (1.0, (1.0, 0.42, 0.08))])
            emis_k = nb.math("MULTIPLY", nb.math("POWER", glow, 1.6), 4.0)
    if spec["caps"] < 1.0:
        sep = nb.n("ShaderNodeSeparateXYZ")
        tc2 = nb.n("ShaderNodeTexCoord")
        nb.link(outp(tc2, "Object"), sep.inputs[0])
        cn = nb.noise(vec, 3.0, 6.0, 0.6)
        z = nb.math("ADD", nb.math("ABSOLUTE", sep.outputs[2]), nb.math("MULTIPLY", nb.math("SUBTRACT", outp(cn, "Fac"), 0.5), 0.35))
        cap = nb.n("ShaderNodeMapRange")
        nb.link(z, inp(cap, "Value"))
        inp(cap, "From Min").default_value = spec["caps"]
        inp(cap, "From Max").default_value = spec["caps"] + 0.05
        col = nb.mix(outp(cap, "Result"), col, (0.92, 0.95, 0.98))
        rough = nb.math("MAXIMUM", rough, outp(cap, "Result"))
    bsdf = nb.n("ShaderNodeBsdfPrincipled")
    nb.link(col, inp(bsdf, "Base Color"))
    nb.link(rough, inp(bsdf, "Roughness"))
    inp(bsdf, "Specular IOR Level").default_value = 0.6
    bump = nb.n("ShaderNodeBump")
    inp(bump, "Strength").default_value = 0.55 if spec.get("craters") else 0.35
    inp(bump, "Distance").default_value = 0.06
    nb.link(height, inp(bump, "Height"))
    nb.link(outp(bump, "Normal"), inp(bsdf, "Normal"))
    if emis_col is not None:
        nb.link(emis_col, inp(bsdf, "Emission Color"))
        nb.link(emis_k, inp(bsdf, "Emission Strength"))
    o = nb.n("ShaderNodeOutputMaterial")
    nb.link(outp(bsdf, "BSDF"), o.inputs["Surface"])
    return nb.mat


def cloud_material(spec, rng):
    nb = NB("clouds")
    off = (rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50))
    vec = nb.coords(off, (1.0, 1.0, 2.0) if spec.get("bands") else (1.0, 1.0, 1.25))
    warp = nb.noise(vec, 1.6, 4.0, 0.55)
    wv = nb.n("ShaderNodeVectorMath", operation="SCALE")
    nb.link(outp(warp, "Color"), wv.inputs[0])
    inp(wv, "Scale").default_value = 1.1
    add = nb.n("ShaderNodeVectorMath", operation="ADD")
    nb.link(vec, add.inputs[0])
    nb.link(wv.outputs[0], add.inputs[1])
    n = nb.noise(add.outputs[0], 3.2, 12.0, 0.62, 0.0, 2.2)
    lo = spec["clouds"]
    cov = nb.ramp(outp(n, "Fac"), [(lo, (0.0, 0.0, 0.0)), (lo + 0.12, (1.0, 1.0, 1.0))])
    covf = nb.n("ShaderNodeRGBToBW")
    nb.link(cov, covf.inputs[0])
    tr = nb.n("ShaderNodeBsdfTransparent")
    bsdf = nb.n("ShaderNodeBsdfPrincipled")
    inp(bsdf, "Base Color").default_value = (*C(spec["cloud_col"]), 1.0)
    inp(bsdf, "Roughness").default_value = 1.0
    inp(bsdf, "Specular IOR Level").default_value = 0.0
    mx = nb.n("ShaderNodeMixShader")
    nb.link(covf.outputs[0], mx.inputs[0])
    nb.link(outp(tr, "BSDF"), mx.inputs[1])
    nb.link(outp(bsdf, "BSDF"), mx.inputs[2])
    o = nb.n("ShaderNodeOutputMaterial")
    nb.link(mx.outputs[0], o.inputs["Surface"])
    return nb.mat


def atmo_material(spec):
    nb = NB("atmo")
    lw = nb.n("ShaderNodeLayerWeight")
    inp(lw, "Blend").default_value = 0.5
    # brightest where the line of sight grazes the planet's limb, fading out into space and
    # into a thin haze over the disc
    g = 1.0 - math.sqrt(1.0 - (1.0 / ATMO_R) ** 2)
    ramp = nb.ramp(outp(lw, "Facing"), [(0.0, (0.02, 0.02, 0.02)), (g * 0.7, (0.1, 0.1, 0.1)), (g - 0.015, (0.8, 0.8, 0.8)),
                                        (g + 0.01, (1.0, 1.0, 1.0)), (g + (1.0 - g) * 0.35, (0.3, 0.3, 0.3)), (1.0, (0.0, 0.0, 0.0))], "EASE")
    rimn = nb.n("ShaderNodeRGBToBW")
    nb.link(ramp, rimn.inputs[0])
    rim = rimn.outputs[0]
    geo = nb.n("ShaderNodeNewGeometry")
    dot = nb.n("ShaderNodeVectorMath", operation="DOT_PRODUCT")
    nb.link(outp(geo, "Normal"), dot.inputs[0])
    dot.inputs[1].default_value = tuple(-LIGHT)
    lit = nb.n("ShaderNodeMapRange")
    nb.link(dot.outputs["Value"], inp(lit, "Value"))
    inp(lit, "From Min").default_value = -0.35
    inp(lit, "From Max").default_value = 0.7
    k = spec["atmo_k"]
    fac = nb.math("MINIMUM", nb.math("MULTIPLY", rim, nb.math("MULTIPLY", outp(lit, "Result"), k)), 1.0)
    # only the near side of the shell glows (the far side's flipped normals would light the night side)
    fac = nb.math("MULTIPLY", fac, nb.math("SUBTRACT", 1.0, outp(geo, "Backfacing")))
    em = nb.n("ShaderNodeEmission")
    inp(em, "Color").default_value = (*C(spec["atmo"]), 1.0)
    inp(em, "Strength").default_value = 1.15
    tr = nb.n("ShaderNodeBsdfTransparent")
    mx = nb.n("ShaderNodeMixShader")
    nb.link(fac, mx.inputs[0])
    nb.link(outp(tr, "BSDF"), mx.inputs[1])
    nb.link(em.outputs[0], mx.inputs[2])
    o = nb.n("ShaderNodeOutputMaterial")
    nb.link(mx.outputs[0], o.inputs["Surface"])
    return nb.mat


def sphere(name, r, mat, rot):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=160, ring_count=80, radius=r)
    ob = bpy.context.active_object
    ob.name = name
    bpy.ops.object.shade_smooth()
    ob.data.materials.append(mat)
    ob.rotation_euler = rot
    return ob


def scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "HIP"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "HIP"
        sc.cycles.device = "GPU"
    except Exception as e:
        print("GPU unavailable, using CPU:", e)
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.cycles.transparent_max_bounces = 16
    sc.render.resolution_x = SIZE
    sc.render.resolution_y = SIZE
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Punchy"
    except Exception:
        pass
    world = bpy.data.worlds.new("space")
    sc.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.02, 0.025, 0.04, 1.0)
        bg.inputs[1].default_value = 0.35
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 85
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    cam.location = (0, -6.25, 0)
    cam.rotation_euler = Euler((math.pi / 2, 0, 0))
    sc.camera = cam
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 4.2
    sun_data.angle = math.radians(0.6)
    sun = bpy.data.objects.new("sun", sun_data)
    sc.collection.objects.link(sun)
    sun.rotation_euler = LIGHT.to_track_quat("-Z", "Y").to_euler()
    return sc


def render(kind, k):
    spec = TYPES[kind]
    rng = random.Random(hash((kind, k)) & 0xFFFFFFFF if False else (sum(map(ord, kind)) * 7919 + k * 104729))
    sc = scene()
    rot = Euler((math.radians(rng.uniform(-25, 25)), math.radians(rng.uniform(-20, 20)), math.radians(rng.uniform(0, 360))))
    sphere("planet", 1.0, surface_material(spec, rng), rot)
    if spec["clouds"] > 0:
        sphere("clouds", 1.012, cloud_material(spec, rng), Euler((rot.x, rot.y, rot.z + rng.uniform(0, 6.28))))
    sphere("atmo", ATMO_R, atmo_material(spec), rot)
    path = os.path.join(OUT, "%s_%d.png" % (kind, k))
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


os.makedirs(OUT, exist_ok=True)
for kind in TYPES:
    if ONLY and kind not in ONLY:
        continue
    for k in range(VARIANTS):
        render(kind, k)
