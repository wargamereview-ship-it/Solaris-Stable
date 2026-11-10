# Solaris Stable — Design Spec (draft v0.1, 2026-11-08)

Personal-use BattleTech fan project. Not for distribution.

## 1. Pitch

You own a small 'Mech stable on Solaris VII, beginning in **January 3015**. You hire MechWarriors, buy, build and refit 'Mechs under real construction rules, book matches in the arenas, and watch them auto-resolve. You earn purses, sponsorships and reputation, and climb the class rankings toward the Grand Championship. The calendar keeps moving, so technology, prices and the political backdrop change over the years.

**Core loop (one week = one turn):**
1. Review the stable: warrior condition, 'Mech damage, finances.
2. Run the 'Mech bay: repair, refit and design 'Mechs, all within tech and time limits.
3. Book matches: choose the arena, opponent, weight class, format and wager.
4. Resolve matches: watch the fight live in real time (pause, or up to 4× speed), or skip straight to the result and combat log.
5. Post-match: purse, salvage rights (if any), injuries, XP, fame, then sponsor reactions.
6. Advance the week: salaries, bay time, market refresh, news and events.

## 2. Pillars

1. **Construction matters.** Your 'Mech designs decide fights. A smart 3015 build should beat a careless one, and the rules are faithful enough that you can check them against your rulebooks.
2. **Deterministic, inspectable combat.** The same seed and inputs give the same fight. Every roll is logged so you can see why you lost.
3. **Scarcity.** It is the Succession Wars era. Parts are expensive, many are unavailable, and losing a 'Mech hurts.
4. **People.** Warriors have skills, quirks, contracts, injuries and ambitions. Fans love some of them.

## 3. Architecture (same pattern as hockey_gm)

```
solaris_stable/
  core/            # pure GDScript, no Node deps, headless-runnable
    data/          # loaders for JSON equipment, chassis, era tables
    construction/  # MechDesign validation: tonnage, crits, heat, BV, cost
    arena/         # procedural arena generator (heightmap + terrain cells)
    combat/        # real-time fight sim: fixed 20 Hz tick, seeded RNG, event log
    campaign/      # calendar, stable, market, rankings, events
  data/            # JSON: equipment.json, structure_table.json, engines.json,
                   # designs/*.json, arenas.json, era_events.json
  ui/              # Godot scenes: bay, roster, booking, fight viewer
  tests/           # headless test scripts (godot --headless -s)
  docs/specs/
```

- `core/` never touches the scene tree. UI only reads state and sends commands.
- Every random draw goes through one `SimRng` that the match or week passes in, which keeps runs reproducible and lets you replay a match.
- All rules numbers live in `data/` JSON, never hard-coded, so you can correct any value against your books.

## 4. 'Mech Construction (TechManual-style, Inner Sphere 3015)

A `MechDesign` is chassis tonnage plus component choices plus a per-location loadout. The validator enforces:

| Step | Rule |
|---|---|
| Tonnage | 20–100 t in 5 t steps |
| Internal structure | Standard: 10% of tonnage; per-location points from the structure table |
| Engine | Rating = tonnage × Walk MP (max 400); weight from the engine table; Run = ceil(Walk × 1.5) |
| Gyro | ceil(rating / 100) t |
| Cockpit | 3 t |
| Heat sinks | 10 come with the engine (rating/25 fit inside it free); extras cost 1 t and 1 crit each. **Singles only** until DHS are reintroduced |
| Jump jets | Up to Walk MP; weight depends on the tonnage class |
| Armor | 16 pts/t standard; head ≤ 9; other locations ≤ 2 × internal structure; rear armor splits from torso |
| Crits | 6 per head/leg, 12 per arm/torso; fixed actuators; multi-slot items stay in one location (split weapons come later) |
| Ammo | 1 t bins; CASE not available in 3015 |

Outputs: **heat profile** (alpha heat vs dissipation), **BV** (simplified), **C-bill cost**, and **bay time** to build or refit.

**Availability:** every equipment item has `intro_year`, `extinct_year`, `reintro_year` and a rarity per faction market. In 3015, Gauss, ER lasers, DHS, Ultra ACs, CASE, Artemis and similar are lostech and unavailable (or found only as one-off salvage events).

**Refit classes:** armor or ammo swap (cheap and fast), weapon swap in the same slots (moderate), engine or structure change (expensive, takes weeks, and some changes are impossible).

## 5. Combat: Real-Time Autobattler in a Procedural Arena

Fights play out in continuous real time on an arena generated for that bout. Nothing on screen is a hex or a turn. You don't pilot: your warriors fight on the orders you gave them, and you watch.

### 5.1 Time and scale

The sim converts tabletop units, so every rules number in `data/` keeps its meaning:

| Tabletop | Real time |
|---|---|
| 1 turn | 10 s |
| 1 hex | 30 m |
| 1 MP | 3 m/s (10.8 km/h), so Walk 4 = 43 km/h |
| A weapon fires once per turn | Each weapon recycles in 10 s (`cycle_s`, tunable per weapon) |
| Heat sinks dissipate per turn | Dissipation is continuous: sinks per 10 s |
| Range in hexes | Range × 30 m (a medium laser reaches 270 m) |

Every rate scales by the same constant, so playback speed (pause, 1×, 2×, 4×) only changes how you watch, never the outcome.

### 5.2 Sim loop

- A fixed 20 Hz tick in `core/combat/`: pure GDScript, with no scene tree and no Godot physics. The same arena seed, match seed, designs, warriors and orders always produce the same fight.
- Each 'Mech has a continuous position, facing, torso twist, speed and gait (standing, walking, running, jumping, prone, shut down).
- The AI re-plans about twice a second. Movement, weapon cycles and heat update every tick.
- Headless, the sim runs far faster than real time. Every other league fight sims each week, and you can batch-run 1,000 duels to check balance.

### 5.3 BattleMech Manual rules in real time

- **Shooting:** a weapon fires once it has recycled, the target is in range and line of sight, and the heat plan allows it. Each shot rolls 2d6 against a target number made of:
  - Gunnery skill
  - Attacker gait: walk +1, run +2, jump +3
  - Target movement modifier, from the distance the target covered in the last 10 s, using the hexes-moved table
  - Range band
  - Woods and partial cover along the line of fire
  - Heat
  - Quirks
- **Hit location:** the front, left, right or rear column of the 2d6 table, picked from the actual angle between the shot and the target's facing. Missiles use the cluster hits table.
- **Damage:** armor, then internal structure, then the crit check (2d6 ≥ 8). Ammo explosions, engine, gyro and cockpit hits, and MechWarrior damage all work as on the tabletop.
- **Heat:** firing, movement (walk, run and jump heat per 10 s) and engine hits add heat. Heat scale effects kick in at the book's thresholds: slowdown, to-hit penalties, and shutdown and ammo-explosion rolls, which repeat every 10 s while above the threshold.
- **Piloting:** a piloting roll is triggered by 20+ damage within any 10 s window, by gyro or leg hits, and by landing a jump in rough terrain. A fall deals damage, and getting up takes a few seconds and another roll.
- **Physical attacks:** within about 30 m: punches, kicks, charges and death from above, each on its own 10 s cycle. An arm that punches can't fire its weapons that cycle.
- **Win conditions:** a 'Mech is destroyed, crippled (legs, engine, unconscious pilot), yields or ejects. If time runs out, the judges score damage dealt.

### 5.4 Procedural arenas

- Each bout generates a fresh layout from a seed and the arena's **theme** in `data/arenas.json`. Example themes:
  - Factory: buildings, walls, gantries
  - Jungle: dense heavy woods
  - Boreal: water, ice, ridges
  - Urban: streets, tall buildings
  - Open Bowl: rolling ground, little cover
- The arena is a heightmap plus terrain cells about 10 m across: light and heavy woods, rough ground, water depth, and buildings with their own structure points. 'Mechs move freely over it. The cells only set movement cost, cover and line of sight.
- **Fair starts:** duel and team arenas generate one half and mirror it, so neither side gets an edge. The generator checks that the two spawns connect and don't start in open sight of each other.
- Size follows the format. A duel arena is about 400–600 m across, roughly one tabletop map; lance events get bigger arenas.
- The arena seed is saved with the match, so any fight can be regenerated and replayed exactly.
- **The live battlefield:**
  - Buildings take damage from stray shots and explosions, then collapse into rubble.
  - Woods catch fire from flamers, Inferno rounds and explosions, and fire spreads with the wind.
  - Smoke works like woods for line of sight.
  - Each theme brings hazards: flame jets in the factory, steam vents in the canyon and boreal arenas, shock pylons in urban arenas.
  - Each bout has light and weather conditions: night or dusk, rain, snow, fog, wind.

### 5.5 Warrior AI and orders

You set orders before the bout, and the warrior's personality bends them (a hothead redlines anyway):
- **Range band:** close, the loadout's best range, or maximum.
- **Heat discipline:** conservative (chain fire, stay cool), balanced, or redline (alpha strikes).
- **Positioning:** fight from cover, circle for the rear arc, or stand and trade.
- **Targets** (team events): focus fire or spread damage.
- **Aggression and retreat:** when to press in, and when to yield or eject.

Traits also shape each warrior's behavior: how they use cover, when they jump, and how they react to a fall.

**Corner calls:** up to 3 radio orders per warrior during a live fight: press the attack, back off, flank, cool down, yield, or focus fire on a target. Each call is logged by sim tick, so a replay with the same inputs is exact.

### 5.6 Output and formats

- **Event log:** every roll with a timestamp: target number, dice, hit location, crits, heat.
- **Snapshot stream:** about 10 per second (positions, facing, heat, damage) for the viewer to play and scrub. Because the sim is deterministic, a saved fight only needs its seeds and inputs; snapshots can be rebuilt on demand.
- **Formats:** 1v1 duel by weight class (the bread and butter), 2v2 tag, 4-'Mech lance team events, and an open class (any weight).

## 6. Stable Management

**MechWarriors:** Gunnery and Piloting (tabletop scale 0–7, lower is better), plus traits (Hot-blooded, Cool Under Fire, Showboat, Iron Man…), age, morale, fame, injury and fatigue, contract (salary, length, purse share), and an affiliation that affects crowd reactions.

**'Mechs:** owned designs, their condition per location, and the bay schedule.

**Staff:** techs (more of them gives more bay hours per week; skill reduces refit failure and cost), a medic, and a PR agent (raises the sponsorship ceiling).

**Finances:** purses, wagers, sponsor stipends, merchandise from fame. Costs are salaries, parts, repairs, arena entry fees and stable upkeep. Going bankrupt ends the game.

**Rankings:** an Elo-style rating per warrior in each weight class, plus a stable ranking. The top ranks get invitations to bigger cards and the Grand Championship at the end of the season.

**Rival stables:** around 20 AI stables with budgets, house affiliations and design philosophies. They also build and refit 'Mechs with the same validator.

**Market:** weekly stock of used 'Mechs (stock designs with damage or quirks), parts and free-agent warriors. Prices follow scarcity and era.

## 7. Timeline (3015 →)

`era_events.json` drives the campaign calendar:
- **Tech gates:** items appear on the market when `year ≥ intro/reintro` and the rarity roll passes. Lostech trickles back after the late 3020s, then speeds up toward 3050.
- **Political events:** Succession Wars era news (e.g. the Fourth Succession War in 3028) changes house affiliations, crowd biases, sponsor pools, prices and warrior recruitment.
- **Aging and retirement:** warriors age, decline and retire, and new prospects enter the pool.
- **Seasons:** one Solaris season per year, ending in the Grand Championship.

The timeline now runs from 3015 to 3152 and serves both modes; its dates were checked against the Sarna.net year pages and MegaMek's data (see the README's timeline section). Entries marked `approx` have a day or month the sources leave open.

## 8. Milestones

**Status (2026-11-08): M1–M6 are built.** Also built: team bouts (2v2 tag, 4v4 lance under a tonnage cap, free-for-all melee), live corner calls, destructible and hazardous arenas with night and weather, and full physical combat with MASC, TSM, ECM, C3, Narc and alternate ammo. `README.md` covers how to run it and the test commands.

| # | Milestone | Done when |
|---|---|---|
| M1 | **Construction core** | Equipment, structure and engine data load; you can build a 3015 IS design in JSON, and the validator accepts it, rejects illegal builds, and reports tonnage, crits, heat, cost and BV. A test suite reproduces a few stock designs exactly. |
| M2 | **Arena + duel sim (headless)** | The generator builds a fair arena for each theme from a seed. Two designs + two warriors + orders + seeds → a real-time fight, its event log, snapshots and a result. Batch-run 1,000 duels to sanity-check balance (e.g. a stock heavy should usually beat a stock light). |
| M3 | **Bay UI** | Godot 'Mech bay screen: pick tonnage, engine, armor and weapons by location, with live validation and a heat/crit readout. |
| M4 | **Fight viewer** | Renders the generated arena and plays the fight from the snapshot stream with placeholder 'Mechs: camera, pause, 1–4× speed, scrubbing, per-'Mech damage diagram and heat bar, combat log. |
| M5 | **Stable + week loop** | Roster, finances, booking, weekly advance, market, AI stables simming in the background. |
| M6 | **Timeline & season** | Era events, tech gating, rankings, the Grand Championship, aging. |
| Later | Rivalries and grudges, fighter collectives, thrown fights, road trips to other game worlds, Solaris scrip, sponsors with goals, printable record sheets, rival stables that design their own 'Mechs, training and staff. |

## 9. Sources

The user supplied rulebooks are indexed in [`reference/README.md`](../../reference/README.md), with searchable text in `reference/text/`.

| Need | Source | Status |
|---|---|---|
| Combat rules (to-hit, hit location, crits, heat, PSRs, physicals, terrain) | BattleMech Manual | ✅ Covered |
| Weapon stats (heat, damage, ranges, tons, crits, ammo/ton) | BattleMech Manual tables | ✅ Covered; transcribe to `data/equipment.json` |
| Design Quirks (chassis personality) | BattleMech Manual | ✅ Covered; good autobattler material |
| Solaris, stables, eras, Houses, currency | BattleTech: Universe | ✅ Covered (Solaris itself is brief) |
| Chassis history, manufacturers, notable (Solaris) pilots | Recognition Guides 1 & 2 | ✅ Covered (flavor) |
| Construction tables (engine weight, IS points, JJ weight, armor/ton, costs) | MegaMek source, confirmed on Sarna → `data/construction.json` | ✅ Verified vs Recognition Guides |
| 3015-legal stock designs (LCT-1V, AS7-D…) | MegaMek `mm-data` + MUL → `data/stock_designs.json` | ✅ 205 designs buildable and on sale in 3015 |
| Tech intro/extinction/reintro years, C-bill costs, rarity | MegaMek, spot-checked on Sarna → `data/equipment.json` | ✅ Covered |
| Faction availability per era | MUL → `data/sources/mul_battlemechs.json` | ✅ Covered |

**Market rarity:** MegaMek's per-era availability letters (A very common … F very rare, X unavailable) map directly onto market stock odds for the Succession Wars, Clan Invasion and later eras.

## 10. Decisions and open questions

- **Viewer: top-down 2D** with MegaMek's unit sprites, which are grayscale and tinted per stable color or House camo by a shader. Decided 2026-11-08 at the user's request to use the MegaMek sprites.
- **Losing a 'Mech:** most bouts end in a yield (about 70%). Warriors yield once their center torso is breached. A destroyed 'Mech (about 11% of duels) becomes a wreck: you rebuild it for 40% of its cost or scrap it. Grudge matches are to the death.
- Open: should the player ever pilot a fight (an optional manual mode), or stay pure autobattler?
