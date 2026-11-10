# Mercenary Company mode

A second campaign mode beside the Solaris stable: run a mercenary company in the style of MekHQ's
Against the Bot, with every battle fought in real time on an open battlefield. Same engine, data,
sprites, construction rules and 'Mech designer as the arena game.

**Status (2026-11-09): built.** Everything in sections 1–4 is in the game and covered by the
merc tests, with these simplifications:
- vehicle crews are one commander record plus a crewman count, not individual people;
- jump recharge is a flat 7 days and in-system transit comes from the star's spectral class;
- refits in the merc mode, unit quality, turnover and DropShip ownership are not built (see Later);
- pay, salaries, repair times, part prices and procurement numbers are estimates (`_approx` in
  `data/merc_rules.json`), not book values; vehicle BV is an approximation of BV2.

Decided with the user (2026-11-09):
- **Pause and command.** Battles run in real time. You can pause at any moment, select 'Mechs or
  whole lances, and order them to move, attack a target, hold or withdraw. The AI still handles
  aiming, heat, footwork and physical attacks. Any battle can be auto-resolved instead.
- **'Mechs plus vehicles.** Tracked, wheeled, hover and VTOL combat vehicles fight on both sides,
  built under TechManual vehicle rules and damaged under Total Warfare vehicle rules.

## 1. The strategic layer

### 1.1 Time
Day by day. **Advance day** or **Advance to next event** (stops when a battle is ready, the company
arrives somewhere, a contract starts or ends, a part arrives, repairs finish, or a month begins).
- Daily: travel, repairs, healing, deliveries, procurement rolls.
- Weekly (Mondays): battle generation for every lance on a combat role; maintenance.
- Monthly (the 1st): payroll and overhead, contract installments, markets refresh.

### 1.2 Star map
3,186 canon star systems from MegaMek Data: position (light years), owner by date, population,
industry ratings, spectral type and the primary planet (water, temperature, gravity, atmosphere,
description). Borders shift as the ownership events in the data come due. Hiring halls (Galatea,
Outreach, Solaris VII, Herotitus, Westerhand, Noisiel and others) come and go by date.

Travel: JumpShip jumps of up to 30 light years along an A* route. Each jump takes the recharge time
(7 days) and each end costs in-system transit time by star class (about 3–12 days). The company
charters transport; the cost per jump depends on how many 'Mechs, vehicles and people move.
Contracts reimburse part of the transport to and from the job.

### 1.3 Contracts (Against the Bot)
- Contract markets at hiring halls (more offers, better terms) and at border worlds; refreshed monthly.
- Employers are the factions active at that date; the enemy comes from the faction's wars and
  rivalries (MegaMek faction hints), or pirates and rebels.
- Mission types with AtB length, pay and tempo: Garrison, Cadre, Security, Riot, Planetary Assault,
  Relief, Guerrilla Warfare, Pirate Hunting, Diversionary Raid, Objective Raid, Recon Raid, Extraction Raid.
- Terms: base pay (from the company's combat value, mission, employer, reputation), length,
  advance payment, signing bonus, command rights (Integrated / House / Liaison / Independent),
  salvage rights (% or exchange), straight support %, battle loss compensation %, transport %.
- Negotiation: one try per clause, rolled against your best admin's negotiation skill.
- Command rights decide how often allied employer troops fight beside you and whether you may
  decline battles.

### 1.4 Operations
- On the contract world, lances take roles: **Fight, Defend, Scout, Training, Reserve.**
- Each Monday each lance on a combat role may draw a battle (chance from role × contract tempo ×
  enemy morale). The battle type comes from the role's table. A battle has a deadline; missing it
  counts as a defeat.
- Contract score: victories raise it and lower enemy morale; defeats do the opposite. At the end the
  contract is a success, partial success or failure, which changes reputation and the employer's view.

### 1.5 Reputation
A Dragoons-style rating (A*, A, B, C, D, F) from experience, command, tech support, contract record
and debt. It sets how many contracts appear and how well they pay.

## 2. Battles

### 2.1 Battlefields
Open ground, 1–1.6 km wide, generated from the planet: plains, hills, badlands, forest, jungle,
desert, arctic, urban, mountains, coast. Roads, rivers, towns and woods. Not mirrored.
Light and weather follow the planet and the hour. Deployment zones sit on the map edges.

### 2.2 Scenario types (objectives)
- **Standup / Engagement:** destroy or rout the enemy.
- **Hold the Line / Base Defense:** keep the marked buildings standing until time runs out.
- **Base Attack:** destroy the marked enemy buildings.
- **Breakthrough:** get half your force off the enemy edge.
- **Chase:** stop the enemy from escaping off your edge.
- **Recon / Probe:** bring a unit near each marked point, then withdraw.
- **Ambush:** start with the enemy in the open at close range.
Enemy reinforcements can arrive mid-battle; allied employer units may fight on your side (AI-run).

### 2.3 Command
- Space pauses. Click or drag a box to select your units; number keys select lances.
- Right-click ground: move there (in formation). Right-click an enemy: attack it.
- Buttons: Hold, Free (AI), Withdraw (leave by your edge), stance (range, heat), jump jets.
- Orders are recorded by tick, so the battle can be replayed exactly.
- Forced withdrawal: crippled enemy units retreat; the enemy force breaks after heavy losses.
- The battle ends when one side has no units left on the map, the objectives are settled, or time runs out.

### 2.4 After the battle
Casualties, injuries and XP; kills credited. If you hold the field you recover your wrecks and
enemy wrecks go into the salvage pool (split by your salvage rights). If you lose the field,
destroyed units and ejected warriors left behind are lost.

## 3. The company

### 3.1 Personnel
Roles: MechWarrior, vehicle crew (a commander plus crewmen), tech, AsTech pool, doctor, medic pool,
admin (command, logistics, HR). Skills, experience levels (Green, Regular, Veteran, Elite), XP to spend,
injuries with healing times, deaths. Monthly salaries by role and experience. Recruiting from a
personnel market that is largest at hiring halls.

### 3.2 TO&E
Lances of up to 4 units ('Mechs, vehicles or mixed). Each unit has a crew: one MechWarrior for a
'Mech; a vehicle crew for a vehicle (crew size from tonnage).

### 3.3 Hangar and repairs (MekHQ style)
Damage persists between battles: armor and structure per location, destroyed components, motive
damage, spent ammo. The damage becomes repair tasks:
- replace armor in a location (needs armor tonnage), repair structure, replace a destroyed location,
- replace a component (weapon, heat sink, jump jet, actuator, engine, gyro, sensors, cockpit…),
- vehicle motive and turret repairs, reloading ammo bins.
Techs work 480 minutes a day, slowed if short of AsTechs. Each task rolls 2d6 against the tech's
skill plus the task difficulty; a failure wastes the time. Repair mode: standard, extra time
(−1 TN, double time) or rush (+1 TN, half time). Parts come from the warehouse.

### 3.4 Warehouse and procurement
Spare parts, armor tons and ammo tons. Parts come from purchases, salvage and stripping units.
Procurement: queue an item; each day the logistics admin rolls against its availability rating
(A–F, X) and the world (hiring halls and industrial worlds help, the Periphery hurts). A success
means delivery in a few days.

### 3.5 Markets and finances
- Unit market: 'Mechs and vehicles offered by the local owner faction, mercenary dealers and the
  black market, from MegaMek's force generator availability tables for the date.
- Monthly costs: salaries, overhead, maintenance and spare parts, food and housing.
- Simple bank loans. The company folds when its debt passes the bank's limit.

## 4. Data
- `data/game/systems.json`, `merc_factions.json`, `force_tables.json`, `vehicles.json` are built by
  `tools/data_import/build_merc_data.py` from MegaMek Data (CC BY-NC-SA 4.0).
- `data/merc_rules.json`: every merc tuning number (pay, tempo, salaries, repair times and TNs,
  transport costs, rating). Values marked "approx" are estimates, not book numbers.
- `data/combat_tables.json`: vehicle hit location, motive damage and critical hit tables (Total Warfare).

## 5. Later
DropShip and JumpShip ownership, aerospace and infantry, unit quality and maintenance failure,
turnover and loyalty, StratCon-style campaign maps, refits for vehicles, story arcs.
