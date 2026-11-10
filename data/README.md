# Game Data

Built 2026-11-08. These files are inputs for the M1 construction core. Personal use only.

| File | What | Source |
|---|---|---|
| `construction.json` | Engine weight by rating (10–400), engine type multipliers and crits, gyro, cockpit, internal structure points by tonnage (20–100), structure/armor weights and crits, jump jet tiers, heat sinks, crit slot layout, chassis cost formula | MegaMek source (`Engine.ENGINE_RATINGS`, `Mek.getInternalForTonnage`, `MiscType`, `MekCostCalculator`), rules confirmed on Sarna |
| `equipment.json` | 724 'Mech-usable weapons, equipment, ammo and armor types: heat, damage, ranges, tons, crits, shots, BV, **C-bill cost**, **tech dates** (prototype / production / common / extinct / reintroduced) and **availability rating** per era (A–F, X) | MegaMek Java sources, dates spot-checked on Sarna |
| `stock_designs.json` | 4,263 canonical 'Mech variants with full loadouts: engine, structure, heat sinks, MP, armor by location, weapons, crits by location, design quirks, intro year. 3,375 are linked to their MUL record | MegaMek Data (`mm-data`), CC BY-NC-SA 4.0 |
| `game/items.json`, `game/designs.json`, `game/components.json`, `game/factions.json` | **What the game loads.** Every 'Mech-usable item with a stable id, plus 2,603 stock biped designs (intro year 3085 or earlier) with per-slot loadouts, sprite paths and MUL availability. Rebuild with `python3 -I tools/data_import/build_game_data.py .` | Built from the files above, `sources/mm_equipment_full.json` and `assets/megamek/units/mekset.txt` |
| `game/systems.json`, `game/merc_factions.json`, `game/force_tables.json`, `game/vehicles.json` | **Merc mode.** 3,186 canon star systems (position, owners by date, population, industry, hiring halls, the primary planet and a battlefield mix), 191 factions with colors and name changes, wars and alliances (faction hints), MegaMek force generator availability for 'Mechs and vehicles by faction and era (3019–3085), and 707 combat vehicles. Rebuild with `python3 -I tools/data_import/build_merc_data.py <mm-data> .` | MegaMek Data (`data/universe/`, `data/forcegenerator/`, `data/mekfiles/vehicles/`), CC BY-NC-SA 4.0 |
| `merc_rules.json` | Every merc-mode number: missions, pay and terms, battle odds, salaries, repair times and target numbers, part prices, procurement, markets, the bank. `_approx` marks estimates | Modelled on MekHQ / Against the Bot; hand-tuned |
| `sources/item_aliases.json` | MegaMek equipment names to item ids, written by `build_game_data.py` so the vehicle importer resolves names the same way | Generated |
| `combat_tables.json`, `rules.json`, `arenas.json`, `era_events.json`, `names.json` | Combat tables from the BattleMech Manual, economy tuning, arena themes, the timeline, name pools | Hand-written; tune freely |
| `sources/mm_equipment_full.json` | Full MegaMek equipment parse including ammo (shots per ton) | MegaMek Java sources |
| `sources/mul_battlemechs.json` | Master Unit List: 4,059 BattleMechs with intro year, BV, PV, role, tech base, and **faction availability per era** | masterunitlist.battletech.com static data, exported through the browser |

## Verification

- **Vehicles:** `tests/test_vehicles.gd` rebuilds every imported combat vehicle under the TechManual vehicle rules (engine x1.5 shielding for fusion, lift and rotor 10%, controls 5%, turret 10% of its weapons, heat sinks for energy weapons, power amplifiers on ICE vehicles, armor limit 3.5 x tons + 40). 629 of 707 match their tonnage exactly; the rest carry gear the rules don't model yet. Costs follow MegaMek's CombatVehicleCostCalculator; BV is an approximation of BV2.

- **Engine weights:** all 58 'Mech engines in the Recognition Guide stat blocks match `construction.json`, including XL, Light and Clan XL. The 3 rows that differed were hover and wheeled vehicles, which use different engine rules.
- **Internal structure:** 49 of 49 Recognition Guide 'Mechs match the points-by-tonnage table.
- **Full rebuild:** recomputing the total weight of 3015-era Inner Sphere biped stock designs gives **356 exact matches and none overweight**. The 115 that come out under weight carry items the quick check didn't count yet (Artemis, Beagle, Narc pods, command consoles, C3, comms gear).
- **Tech dates vs Sarna:** Gauss 2590 / back in 3040 · XL engine 2579 / 3035 · endo steel 2487 / 3035 · Artemis IV 2598, lost 2855, back 3035 · MASC 2740, lost 2795, back 3035 · ER large laser 2620 · LB 10-X 2595 · hatchet 3022. All agree.

## Notes for the 3015 start

- A design's "year" is when it was **introduced**, not when it can be bought. Star League designs such as the Champion, Black Knight and Kintaro carry pre-3015 dates but use lostech. For the market, use MUL era availability (era 11 = Late Succession War – LosTech, 2901–3019) and filter by equipment `extinct`/`reintroduced` dates.
- Of 286 MegaMek designs that MUL lists as available in 2901–3019, **205 are buildable with 3015 tech**: 44 light, 58 medium, 56 heavy, 46 assault. The other 81 carry lostech and could appear as rare salvage or ComStar-only machines.
- About 245 era-11 MUL entries didn't match a MegaMek file by exact name and model. Fuzzy matching is an M1 task.
- The hatchet is a 3015 prototype that enters production in 3022, a fun timeline event (Hatchetman, 3023).
