# Data import scripts

These rebuild `data/*.json` from upstream sources. They read source text only and never execute it.

1. Blobless clones with sparse checkout: `MegaMek/megamek` (`megamek/src/megamek/common/{weapons,equipment,units,cost}`) and `MegaMek/mm-data` (`data/mekfiles/meks/**/*.mtf`).
2. Export the MUL to `data/sources/mul_battlemechs.json` through the browser (the site is behind Cloudflare).
3. `python3 -I parse_mm_equipment.py <megamek>/megamek/src/megamek/common <scratch>/mm_equipment.json`
4. `python3 -I build_data.py <scratch> <project>`, which expects `<scratch>/mm`, `<scratch>/mmd` and `<scratch>/mm_equipment.json`
5. `python3 -I crosscheck.py <project>` checks the tables against the Recognition Guide stat blocks and stock designs
6. `python3 -I extend_systems.py <mm-data> <project>` carries the star map's planet owners, hiring halls, HPGs and socio-industrial codes from 3090 to 3152. It needs only `data/universe/planetary_systems` from `MegaMek/mm-data`, matches systems by id and leaves everything else in `data/game/systems.json` as it is, so saves keep working. `--dry-run` reports without writing. (`build_merc_data.py` now keeps the same years, `MAP_MAX_YEAR`, if the merc data is ever rebuilt whole.)

7. The unit data runs to 3152. `python3 -I build_game_data.py <project>` rebuilds items and 'Mech designs from `data/stock_designs.json` (its `MAX_YEAR`); `python3 -I build_merc_data.py <mm-data> <project>` rebuilds vehicles, availability tables, planets and factions and needs `data/mekfiles/vehicles`, `data/forcegenerator`, `data/images/units` and `data/universe` from `MegaMek/mm-data`. Run them in that order: the second reads the first one's items and designs. `OVERRIDES` in `build_game_data.py` holds the equipment numbers MegaMek keeps in parent classes the parser does not follow.
