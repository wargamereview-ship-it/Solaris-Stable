# Solaris Stable

A personal-use BattleTech management game for Godot 4.7, with two modes:

- **Solaris stable:** run an arena stable on Solaris VII from January 3015 onward. You hire MechWarriors and buy or build 'Mechs under the TechManual construction rules. You book bouts with pre-fight orders, then watch them play out in real time on a procedurally generated arena.
- **Mercenary company:** a MekHQ-style campaign across the Inner Sphere. Take contracts at the hiring halls, jump from system to system, and command your lances and vehicle crews in real-time battles with pause and orders. Between battles your techs repair the damage with spare parts your logistics admin has to find.

Not for distribution. 'Mech sprites, portraits, camo and unit data come from MegaMek Data (CC BY-NC-SA 4.0). BattleTech is a trademark of The Topps Company.

## Run it

```bash
godot --path . 
```

Or open the folder in the Godot editor and press F5. The first launch takes a second or two while it validates the 4,000 stock designs.

Saves go to `~/.local/share/godot/app_userdata/Solaris Stable/saves/`. An autosave happens every week.

## Starting a game

**New Solaris stable** and **New mercenary company** open the setup screen (`ui/screens/setup.gd`): every choice in three columns, and along the bottom a summary of the game you are about to start with a rough challenge rating.

**Mercenary company**
- **Date and place:** any year from 3015 to 3150, the month, and any hiring hall open on that date. The screen names the era, who owns the world, the wars under way, what the timeline has in force and the next big event.
- **Starting force:** start from one of three packages or set it yourself: how many 'Mechs, vehicles and infantry units, how strong each is, the heaviest 'Mech allowed, crew experience from green to elite, new or second-hand gear, techs, doctors, admins and cash.
- **Opposition:** enemy strength from 50% to 130% of yours, enemy skill, how often battles come, and whether the enemy gets artillery, air strikes and infantry.
- **Economy:** contract pay, prices, how hard parts are to find, how fast techs work, upkeep.
- **World and rules:** canon news on or off, their effect on the trade on or off, IndustrialMechs on the markets, forced withdrawal for your own units, and how deadly battles are for your people.

**Solaris stable**
- **Season:** any first season from 3015 to 3150; the screen names the era and who holds Solaris VII.
- **Starting stable:** cash, MechWarriors, 'Mechs by weight class, bays, techs, fame.
- **The league:** how many rival stables and how good their warriors are.
- **Economy, world and rules:** purses, sponsors, prices, upkeep, time out injured, canon events, mercenary work.

The settings are saved with the game. A save from before the setup screen plays by the defaults.

## How a week works

1. **Office**: shows what needs attention, such as unbooked warriors, damaged 'Mechs, title shots and expiring contracts.
2. **Fight Card**: lists the bouts offered to you. Pick one to see a scouting report (the opponent's skills, traits and full record sheet). Then choose a warrior and a 'Mech and set their orders:
   - range
   - heat discipline
   - positioning
   - when to yield
   You can also place a wager.
3. **Fight night**: **Watch live** runs the fight in the arena viewer as you watch, and gives you 3 corner calls per warrior: press the attack, back off, flank, cool down, yield, or focus fire on a target. **Simulate** resolves the bout instantly with no calls.
4. **'Mech Bay**: repair battle damage, refit in the designer, build new 'Mechs, and buy bays, techs, medics and simulator pods.
5. **Market**: lists used 'Mechs for sale, free-agent MechWarriors and the parts in stock. Lostech is unavailable until it's rediscovered. Star League relics and, after 3050, Clan salvage sometimes appear.
6. **Advance week**: unwatched bouts and the rest of the card are simulated. Then salaries, sponsors, repairs, injuries, the market, news and timeline events all update.

**Bout formats:**
- Duels by weight class and open class.
- Tag teams: 2v2 in one weight class, once you own two 'Mechs in that class.
- Lance battles: 4v4 under a tonnage cap, once you have four warriors and four 'Mechs.
- Free-for-alls: you against up to five rival stables. Last one standing takes half the purse.

Each bout comes with its arena's conditions: night or dusk (floodlit arenas and burning terrain soften the penalty), rain, snow, fog that limits line of sight, or wind that throws off missiles. When you book, you can load alternate ammo, depending on the year:
- Inferno SRMs.
- LB-X cluster rounds.
- Armor-piercing and precision autocannon rounds.

Every 6 weeks each weight-class champion defends against the top contender. In weeks 49–51, the top eight warriors by rating fight the Grand Championship.

**Mercenary Work:** some weeks a House agent or a broker on Solaris wants two to four 'Mechs for a short job off-world: a raid, garrison duty, a pirate hunt, a relief. The tab lists the offers with the fee, the advance and the enemy to expect. The fighters you send are away for two to four weeks (no bouts, no bay work), fight one battle at the end and come home as it left them: damaged, wounded, more experienced, and paid in full only if they held the field. A 'Mech that goes down on a field the enemy keeps is gone.

## Mercenary company mode

Pick **New mercenary company** on the main menu and set the company up on the setup screen (see Starting a game). The spec is in `docs/specs/merc_mode.md`.

**Time** passes a day at a time. **Next day** steps one day; **Advance to next event** runs until something needs you: a battle, an arrival, a contract starting or ending, the start of a month.

**The tabs:**
- **Command**: where you are, the contract, battles waiting, the state of the force, recent events.
- **Battles**: the briefing for each battle (objective, battlefield, enemy, deadline), which units to deploy, then **Command the battle** or **Auto-resolve**. After a victory, pick your share of the salvage here.
- **Contracts**: offers at this world. Each lists employer, mission (the 12 Against the Bot mission types), enemy, world, length, pay, and the terms: command rights, salvage, straight support, battle loss compensation, transport, advance and signing bonus. You get one negotiation roll per clause, on your best admin's negotiation skill.
- **Star Map**: all 3,186 canon systems colored by owner on today's date, from 2750 to 3152. Borders move as the timeline goes on. Select a system for its world data and the jump route, days and transport cost.
- **Lances (TO&E)**: lances, their roles on contract (Fight, Defend, Scout, Training, Reserve) and who crews each unit.
- **Personnel**: MechWarriors, vehicle crews, techs, doctors, admins, AsTech and medic pools. Spend XP on skills; injuries heal faster with enough doctors.
- **Hangar**: damage on every unit as MekHQ-style repair jobs, each with minutes, a target number and the part it needs. Wrecks can be stripped for parts or sold. **Refit** sends a 'Mech to the mech lab or a vehicle to the vehicle workshop.
- **Parts & Supply**: the warehouse, the shopping list (rolled weekly against availability, your logistics admin and the world) and deliveries on the way.
- **Market**: 'Mechs, vehicles, infantry and people for hire on this world, drawn from MegaMek's availability tables for the owner faction and the year.
- **Solaris VII**: while the company is on the Game World and not under contract, the promoters offer five duels. Pick a 'Mech and its MechWarrior, set the corner orders, then watch the fight in the arena viewer or take the result. Walk-ons fight for a fraction of a stable's purse, and the damage and the wounds come home with you.
- **Finances**: the monthly bill (salaries, maintenance, overhead, food and housing), contract pay, the ledger, and bank loans.
- **News**: the Inner Sphere's news, what the times do to the trade today, and the wars under way (see The timeline).

**On a contract**, every Monday each lance with a combat role may draw a battle; the mission's tempo and the enemy's morale set the odds. Missing a battle's deadline counts as a defeat. Victories raise the contract score and lower enemy morale. At the end the contract is a success, a partial success or a failure, which moves your rating (A* to F); the rating sets how many contracts appear and how well they pay.

**Battle types:** Standup Fight, Breakthrough, Base Attack, Base Defense, Hold the Line, Chase, Recon, Probe, Ambush, and monthly Major Battles on assault, relief and guerrilla contracts. Battlefields are 1.2 to 1.5 km of plains, hills, forest, jungle, desert, badlands, tundra, city outskirts, mountain passes or coastline, picked from the contract planet's climate, with roads, rivers and towns.

**Vehicles:** 1,106 MegaMek combat vehicles from 2470 to 3152 (tracked, wheeled, hover, VTOL), 918 of them rebuilt to the exact ton under the TechManual vehicle rules. They fight under Total Warfare vehicle rules:
- no transfer between locations; losing any location destroys the vehicle,
- motive system damage, from minor up to immobilized (hovercraft sink in deep water),
- vehicle critical hits: crew stunned, driver and commander hits, turret jams and locks, engine and fuel tank hits, ammunition explosions,
- turrets that track their target, side arcs for side-mounted weapons,
- VTOLs that fly over the trees, take rotor hits at a tenth of the damage and crash when the rotor goes,
- terrain limits: wheeled vehicles stay out of woods and rough ground, tracked vehicles out of heavy woods and water, hovercraft cross water but not woods.

**Refits:** the lab's parts list holds every weapon and piece of equipment in production on today's date. Ordering a refit sets aside what the warehouse has and puts the rest on the shopping list; the techs start once every part is in, and the unit is out of action until they finish. The Hangar shows what the refit still waits for and how far it is, and you can cancel it. A vehicle keeps its hull, engine, drive and turret: a refit changes what it carries, where, and how the armor is spread.

**Infantry and battle armour:** 15 units in `data/infantry.json`: foot, motorized, jump and mechanized platoons with rifles, machine guns, lasers, SRMs or flamers, and battle armour squads (IS Standard from 3050, Infiltrator Mk II from 3060, and the Clans' Elemental). They are bought on the market, crewed and assigned to lances like any other unit.
- A platoon's fire falls off as its troopers do; a squad loses a suit at a time.
- Weapons built to fight 'Mechs do little to infantry (damage divided by 10, missiles by 5); machine guns, flamers and other burst-fire weapons cut them down, and a platoon in the open takes double.
- Infantry next to a 'Mech make leg attacks; battle armour is harder to hit.
- A platoon or squad down to under a third of its strength breaks and leaves the field.
- Afterwards the Hangar lists replacements (troopers, suits, suit armor) in place of repairs.

**Off-board support:** on some battles you get artillery fire missions and air strikes, as many as the contract's command rights give (Integrated 2 and 1, House 1 and 1, Liaison 1 and none, Independent none), with one more of each for a Major Battle. The briefing lists yours and warns of the enemy's.
- **Artillery**: click the target. Three shells land 20 seconds later within 30 m of it; each does 20 damage at the point of impact and 10 out to 45 m, to anyone, wrecks buildings and can set woods on fire.
- **Air strike**: press where the run starts and drag along it. Twelve seconds later a fighter strafes a strip 240 m long and 30 m wide.
- Pending missions show on the map with a countdown, the enemy's in red: "INCOMING!" is the time to move.
- The enemy has its own on defended objectives and in major battles (pirates never, Clans air only, mercenaries artillery only).

## Designs and equipment

`data/game/` holds 4,024 biped BattleMechs and 1,106 combat vehicles from the Age of War to 3152, imported from MegaMek's unit files. A design reaches the markets and the enemy's forces only if the game's own construction rules rebuild it to the exact ton (3,916 'Mechs, 918 vehicles).

**Chassis parts** beyond the standard ones:
- **Armor:** ferro-fibrous (light, heavy, Clan, prototype), stealth, ferro-lamellor, laser-reflective, reactive, hardened, ballistic-reinforced, impact-resistant, anti-penetrative ablation, heat-dissipating, and the industrial, heavy industrial, commercial and primitive grades.
  - Reflective halves energy damage and doubles falls, physical blows and blast. Reactive halves missiles and blast. Ballistic-reinforced halves ballistic and missile damage. Ferro-lamellor takes a point off every five. Impact-resistant takes a third off physical damage. Hardened makes each point soak two and costs a point of running speed.
  - Stealth armor makes shots from medium range +1 and from long range +2 while the 'Mech's ECM works, for 10 heat a turn. Null-signature, void-signature and chameleon systems do the same kind of thing.
- **Structure:** endo steel, endo-composite, composite (takes damage twice as fast), reinforced (half as fast), industrial.
- **Engines:** XL, light, compact, XXL, plus combustion, fuel cell and fission for IndustrialMechs (no free heat sinks to speak of, power amplifiers for energy weapons, no heat from walking).
- **Cockpits and gyros:** small, torso-mounted, command console, industrial (+1 to hit), primitive, interface (no gyro).
- **Heat sinks and myomer:** single, double, laser, compact; triple-strength, industrial triple-strength (always on), super-cooled (no movement heat).

**Weapons** that need rules of their own:
- **Artillery on a 'Mech or vehicle** (Arrow IV, Sniper, Thumper, Long Tom): the shell is fired at the ground under the target and lands a few seconds later; a miss scatters. Artillery cannons hit directly and splash whoever stands next to the target.
- **Plasma rifles and cannons** put heat on a 'Mech and extra damage on anything else. **TSEMP cannons and 'Mech tasers** scramble the target's targeting for a turn or knock its weapons off line. **Hyper-assault Gauss rifles** roll on the cluster table, better up close. **'Mech mortars, torpedoes** (water only), **Magshots, ProtoMech autocannons, chemical lasers, heavy flamers, M-pods, rifles** all fire.
- **A-pods, B-pods and grenade launchers** go off at infantry making a leg attack.

**Gear:** PPC capacitors, partial wings (more jump, more cooling), improved jump jets, actuator enhancement, Apollo fire control, combined ECM and probe suites, Blue Shield, shields and modular armor, HarJel repair, coolant pods and emergency coolant, booby traps, and the hand weapons: claws, lances, retractable blades, vibroblades, talons, chain whips and the IndustrialMech tools.

The numbers are in `data/combat_tables.json` under `armor_types`, `structure_types`, `gear` and `physical`.

**Not in yet:** quad, tripod, LAM and QuadVee chassis (203 designs), 'Mechs under 20 or over 100 tons, patchwork armor, support vehicles, and WiGE and naval vehicles. A handful of items are carried as weight with no effect of their own: 'Mech turrets, UMUs, chaff pods, fluid and nail guns, and working gear such as cargo space and lift hoists.

## The timeline

`data/era_events.json` holds 99 dated events from 3015 to 3152: the Fourth Succession War, the Clan invasion, the FedCom Civil War, the Jihad, the Republic's long peace, Gray Monday, and the fall of Terra to Clan Wolf. Both modes read it.

**In the stable game** an event makes the news in its week, with a line on how it looks from Solaris City, and takes effect for a set number of weeks. The Office lists what is in force.
- Wars raise parts prices, pull warriors back to their House regiments, fill the arenas for grudge matches, and bring more and better-paid Mercenary Work.
- The end of a war sends veterans to the free agent pool.
- Solaris's own history is in it: the Marik raid of 3020, Justin Xiang's season, the riots of 3062, the Blakist occupation of 3068 to 3071, the Wolf Empire's arrival in 3145.

**In the mercenary game** news arrives day by day, and the big events stop **Advance to next event**. The **News** tab keeps it all, with what is in force today and the wars under way.
- **Events** change the trade for a number of days: contract pay, how many contracts are on offer, who is hiring (after 3029 the Draconis Combine all but stops, until Takashi Kurita dies in 3054), parts and unit prices, how hard parts are to find, and how many people are looking for work.
- **Wars** come from MegaMek's faction data. An employer at war with the enemy named in a contract pays 10% more, and a faction at war on its border offers more work. Wars the timeline has no entry of its own for are announced from that data.
- **Front lines**: each month, the worlds that changed owner and the hiring halls that opened or closed, from the planets' ownership dates. If the world you stand on or fight for changes hands, the clock stops.
- Effects are worked out from the date, not stored: a company founded in 3029 pays wartime prices from its first day.

The star map follows all the way: planet owners, hiring halls and HPGs in `data/game/systems.json` run to 3152 (the Republic's wall, the Wolf Empire around Solaris, the Draconis Combine on New Avalon). So do the 'Mech and vehicle designs and the unit availability tables, with eras for 3100, 3131, 3145 and 3150: markets and enemy forces field the designs of their day.

## Commanding a battle

- **Space**: pause or resume. **1x / 2x / 4x**: speed.
- **Left-click** a unit, or **drag a box**, to select. **Shift** adds. **1-6** selects a lance; **Ctrl+A** or **Select all** selects everyone.
- **Right-click**: on the ground to move (a group spreads into a line), on an enemy to attack it, on a building to shell it. A move order onto a map edge you may leave (your own, or the breakthrough edge) takes the unit off the battlefield.
- **H** hold position, **F** fight freely (the AI decides), **W** withdraw. The panel also sets range (close, optimal, long), heat discipline and jump jets.
- **Mouse wheel** zooms, **middle-drag** or the arrow keys and A/S/D pan. Double-click a unit card to jump to it.
- **Artillery** and **Air strike** in the Support panel arm a call: left-click the target (press and drag for the strafing run), right-click or Esc to cancel.
- **Let the AI finish** hands your units to the AI, which goes for the objective and calls the support you have left, and runs the battle to the end.

Enemies you can't see are hidden; a faded marker shows where they were last spotted. Crippled units on both sides fall back to their own edge (Total Warfare forced withdrawal), and an enemy force breaks once it has lost about two thirds of its strength. Orders are recorded by tick, so a battle replays exactly.

After the battle: damage stays on your units, warriors pick up injuries and XP, and if you hold the field you recover your wrecks and get your share of the enemy's. Lose the field and whatever you left behind is gone.

## Fight viewer controls

- Space: pause or resume
- 1x / 2x / 4x / 8x: playback speed
- Slider: scrub to any moment
- Mouse wheel: zoom
- Right-drag: pan
- "Camera" button: switch between following the action and showing the whole arena

The log at the bottom lists every roll: the target number, the dice, the hit location and any crits. While the fight is live, corner-call buttons sit on your warriors' panels. You can scrub back to rewatch, but calls only go out at the live edge.

**What you'll see in fights:**
- **Physical attacks:** punches, kicks, hatchets, charges, death from above, pushes into hazards or walls, and clubs ripped from heavy woods or rubble.
- **Equipment:** MASC sprints (and the hip-wrecking failures), triple-strength myomer, ECM bubbles, C3 networks sharing range, and Narc beacons.
- **The arena:** buildings that collapse into rubble, woods that catch fire and spread with the wind, and each arena's hazards: flame jets in the Factory, steam vents in the canyon and boreal arenas, and shock pylons in the urban arenas.

## Look and feel

- **Interface:** Fira Sans and Fira Sans Condensed, with Hack for numbers and Font Awesome icons (assets/fonts). Screens sit on an animated backdrop with a top bar, an icon nav rail, cards and stat chips, all built by `ui/ui.gd`.
- **Title screen:** a live AI battle on a random battlefield, filmed by a slow camera (`ui/fight/attract_view.gd`).
- **Battlefields:** terrain is painted by a shader (`ui/fight/terrain.gdshader`): blended ground, hill shading and contours, water with shores, building shadows, fire, ash and night. Trees, 2.5D buildings, explosions, debris, smoke and screen shake come on top. The command view has a minimap: click or drag it to move the camera.
- **Towns and cities:** `core/arena/settlement.gd` lays settlements out the way places grow. Villages follow their road, with a church and a farm down a lane. Towns turn the road into a straight main street lined with shops, around a square with a church or hall. Cities sit on a street grid with avenues: towers downtown, then apartment blocks and shops, then houses, plus an industrial quarter, parks, parking and a civic plaza. There are also stand-alone industrial works and military compounds for base objectives. The Solaris Urban arena is a dense downtown and the Factory is an industrial park, both still mirrored for fairness.
- **Buildings:** 15 types, each with its own construction factor in the Total Warfare bands (light up to 15, medium up to 40, heavy up to 90, hardened up to 150): house, row house, shop, apartment block, office block, tower, warehouse, factory hall, storage tank, silo, barn, church, civic hall, hangar and bunker. Each type has its own walls and roof (`ui/fight/town_view.gd`), and windows light up at night. Streets have lane lines, sidewalks, crosswalks and street lights; there are also parking bays with cars, paved plazas with fountains, hedges and park paths.
- **Star map:** a starfield, faction territories rendered on the GPU with lit borders, faction names, and animated routes and markers. The system panel shows a planet render matched to the world's climate: 11 types, 3 variants each, rendered in Blender by `tools/blender/render_planets.py`.
- **Armor dolls:** every 'Mech and vehicle doll is a targeting-computer readout. Each location glows green, amber or red by the armor it has left, with a thin inner trace for its structure. Destroyed locations flicker, stripped armor blinks and hits flash (`ui/widgets/doll.gdshader`). The art and location maps are in `assets/dolls/` (see its README) and are rebuilt by `tools/dolls/build_doll_maps.py`.
- **Mech lab:** one workbench screen (`ui/designer/designer.gd`). Gauges across the top for the four budgets: tonnage, crit slots, heat and armor. The frame and the armor doll on the left, one card per location laid out like the 'Mech's body in the middle, the parts list on the right, and the legality checks, the quote and the order button along the bottom. Drag a part from the list onto a location, from one location to another, or back onto the list to take it off. The vehicle workshop (`ui/designer/vehicle_lab.gd`) is the same bench for a combat vehicle.

## Layout

```
core/           pure GDScript sim, no scene tree
  data/         GameData: loads every rules number from data/
  construction/ MechDesign + Construction (weights, crits, heat, cost, BV)
  arena/        Arena + ArenaGenerator (procedural, mirrored for fairness)
  combat/       CombatSim (20 Hz real-time, BattleMech Manual rules), CombatAI, CombatMech
  campaign/     Campaign (week loop, market, card, rankings, events, saves), Stable, Warrior, OwnedMech
  vehicle/      VehicleDesign + VehicleConstruction (TechManual vehicle rules)
  merc/         MercCampaign (days, contracts, travel, battles, salvage), StarMap, ForceGen, MercPerson,
                MercUnit, MercRepair (repair jobs and parts)
data/           JSON rules: construction, combat tables, economy, arenas, timeline, names
data/game/      compact items/designs built by tools/data_import/build_game_data.py; systems, factions,
                force tables and vehicles built by tools/data_import/build_merc_data.py
ui/             Godot screens: menu, hub tabs, designer, fight viewer; ui/merc/ the merc hub and tabs;
                ui/fight/command_view.gd the pause-and-command battle view
assets/megamek/ sprites, portraits, camo (see its README)
assets/fonts/   UI fonts and icons (OFL / their own licenses, see its README)
assets/planets/ planet renders for the star map
assets/dolls/   armor doll art, location maps and label anchors
tools/          data importers; tools/blender (planet renders), tools/dolls (doll location maps)
tests/          headless tests and windowed screenshot scripts
```

## Tests

```bash
godot --headless --path . -s tests/test_construction.gd
```

```bash
godot --headless --path . -s tests/test_combat.gd
```

```bash
godot --headless --path . -s tests/test_combat_features.gd
```

```bash
godot --headless --path . -s tests/test_team_campaign.gd
```

```bash
godot --headless --path . -s tests/test_campaign.gd -- 60
```

```bash
godot --headless --path . -s tests/test_ui.gd
```

```bash
godot --headless --path . -s tests/test_clicks.gd
```

```bash
godot --headless --path . -s tests/test_vehicles.gd
```

```bash
godot --headless --path . -s tests/test_merc_combat.gd
```

```bash
godot --headless --path . -s tests/test_merc_campaign.gd -- 400
```

```bash
godot --headless --path . -s tests/test_merc_ui.gd
```

```bash
godot --headless --path . -s tests/test_merc_refit.gd
```

```bash
godot --headless --path . -s tests/test_merc_arena.gd
```

```bash
godot --headless --path . -s tests/test_stable_jobs.gd
```

```bash
godot --headless --path . -s tests/test_infantry.gd
```

```bash
godot --headless --path . -s tests/test_support.gd
```

```bash
godot --headless --path . -s tests/test_timeline.gd
```

```bash
godot --headless --path . -s tests/test_equipment.gd
```

```bash
godot --headless --path . -s tests/test_setup.gd
```

The UI tests start new games and so overwrite the autosave slots. Run them with `XDG_DATA_HOME=/some/empty/dir` in front to keep your saves.

- **Construction**: rebuilds all 4,024 stock designs. 3,916 match their tonnage exactly, and BV matches the MUL for the classics.
- **Combat**: arena symmetry, determinism (same seed, same fight) and balance batches.
- **Combat features**: 2v2, 4v4 and six-'Mech melees, exact replays of corner calls, charges, death from above, clubs, fire, collapses, hazards, night and fog, alternate ammo, MASC, C3, Narc and ECM.
- **Team campaign**: booking and resolving tag, lance and free-for-all bouts, rival team bouts, and save/load.
- **Campaign**: plays N weeks with an auto-manager, then round-trips a save and load.
- **UI**: clicks through every screen, the designer and a watched fight.
- **Clicks**: real mouse clicks on SpinBox arrows, slot buttons and navigation. Guards against rebuilding a screen inside the clicked control's own signal, which crashed Godot.
- **Vehicles**: rebuilds the 1,106 imported combat vehicles under the vehicle construction rules (918 exact).
- **Merc combat**: a battlefield for every biome, 'Mechs against tanks, hovercraft and VTOLs, move/attack/withdraw orders, reinforcements, a base-attack objective, and an exact replay of recorded orders.
- **Merc campaign**: runs a company for N days with an auto-manager taking contracts and auto-resolving battles, then round-trips a save.
- **Merc UI**: the new-company form, every merc tab, the star map, a contract, a live battle with orders, the results and salvage.
- **Merc refit**: a 'Mech or vehicle refit: the quote, the order, the parts search, delivery, the techs' work, the swap of the design, cancelling, and a save round trip.
- **Merc arena**: a company on Solaris VII: the fight card, who may enter, the duel, the purse, the damage, the card closing under contract or off-world.
- **Stable jobs**: a stable hiring its fighters out: offers, who may go, the advance, the weeks away, the battle on return, the pay.
- **Infantry**: platoons and battle armour squads: data, damage rules, leg attacks, whole battles against 'Mechs and vehicles.
- **Support**: fire missions and air strikes: who gets them, what they hit, the enemy's fire control, exact replays.
- **Equipment**: a design that builds to the ton for every newer chassis part, what each armor and structure type does to damage, stealth, the weapons and gear that have rules of their own, and forty duels between designs made after 3085.
- **Setup**: what a custom start gives you in both modes, and that each campaign setting changes what it says it changes.
- **Timeline**: the event data (dates, known effects, real war and faction names), events firing on their date in both modes, their effects, wars and front lines from the data, the years after 3085, and saves.

`tests/screenshots.gd`, `screenshots_features.gd`, `screenshots_merc.gd`, `screenshots_ui.gd`, `screenshots_terrain.gd`, `screenshots_dolls.gd` and `screenshots_designer.gd` run the game in a window and save screenshots (`godot --path . -s tests/<script>.gd -- <out_dir>`).

## Tuning

Every number lives in `data/`:
- `rules.json`: economy, purses, fame, injuries, market; `hire_out` for a stable's mercenary work
- `combat_tables.json`: hit locations, cluster hits, to-hit modifiers, heat scale; vehicle hit locations, motive damage and vehicle criticals; `infantry` (damage against and from infantry, leg attacks) and `support` (artillery and air strike delay, damage, radius, scatter)
- `merc_rules.json`: everything in the merc mode (missions, pay, terms, battle odds, salaries, repair times, parts, procurement, markets, the bank); `operations.support` (who gets how much off-board support) and `solaris` (arena purses for a company)
- `infantry.json`: the infantry platoons and battle armour squads
- `arenas.json`: arena themes and the named arenas. A battlefield's `settlements` list picks what stands on it (`city`, `town`, `village`, `industrial`).
- `era_events.json`: the timeline. Each event has a date, a title and a text, an optional line for the stable game (`solaris`), and its effects in each mode (`stable`, `merc`). The file's `_note` lists every field.
- `merc_rules.json` → `timeline`: wartime pay, how much more a faction at war hires, the length of the monthly front report

The timeline's dates were checked against the Sarna.net year pages and MegaMek's war and ownership data. An event marked `"approx": true` has a day or month the sources leave open, and `"fiction": true` marks the one invented for the game (the 3025 purse rise). The size of each effect is a game-balance choice, not canon. The arena lore was written from general knowledge, so check it against your sourcebooks.
