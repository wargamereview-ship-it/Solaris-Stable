# Armor doll art

The armor diagrams on the targeting screen (ui/widgets/paper_doll.gd, vehicle_doll.gd, painted
by ui/widgets/doll.gdshader).

- `veh_{tracked,wheeled,hover,vtol}_*`: top-down vehicle art generated with SpriteCook
  (options/*_01.png; asset IDs in options/manifest.txt).
- `mech_front_*`, `mech_rear_*`: a white-on-black line drawing of a 'Mech, front view
  (options/mech_line_01.png). Being line art it has no alpha: the silhouette is whatever its outer
  outline encloses, its locations follow the drawing's own panel lines, and `dolls.json` marks it
  `line_art` so the shader lights its lines. The rear readout is the front's torso with the head
  cleared. (The SpriteCook 'Mech it replaced is options/mech_02.png.)
- `*_shade.png` is the art with clean alpha, `*_id.png` the location map (red = location id x 20),
  `dolls.json` each location's label point. All three come from `python3 tools/dolls/build_doll_maps.py`,
  where the locations are drawn as shapes over each image. After a rebuild, open the editor or run
  `godot --headless --path . --import` so Godot picks the new textures up.
- `options/` holds every generated candidate and is ignored by Godot (.gdignore).
