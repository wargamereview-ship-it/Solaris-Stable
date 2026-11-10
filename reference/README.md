# Reference Sources

The user's own rulebook PDFs, kept for personal use only. Originals are in `~/Downloads/`. `text/` holds plain-text extractions (`pdftotext -layout`), so sessions can grep them instead of reading the PDFs page by page.

Page numbers below are **PDF page numbers**, which match the Read tool's `pages:` and the form-feed page index in `text/*.txt`. The printed page = PDF page − offset.

| File | Book | Offset | Main use |
|---|---|---|---|
| `battlemechmanual.pdf` → `text/battlemech_manual.txt` | BattleMech Manual | 2 | **Primary combat rules + weapon/equipment stats** |
| `totalwarfare.pdf` → `text/total_warfare.txt` | Total Warfare | ~2 | Secondary combat reference (BMM consolidates the 'Mech rules) |
| `battletech_recognitionguide_vol1_classics.pdf` → `text/rg_vol1_classics.txt` | Recognition Guide Vol. 1: Classics | 2 | Chassis lore, manufacturers, notable pilots; modern-variant stat blocks |
| `battletech_recognitionguide_vol2_ilclan.pdf` → `text/rg_vol2_ilclan.txt` | Recognition Guide: ilClan Vol. 2 | 1 | Same, many more chassis (incl. short "Upgrades" entries for classics) |
| `battletechuniverse.pdf` → `text/battletech_universe.txt` | BattleTech: Universe | 1 | Lore: timeline, Houses, Succession Wars, the Games, currency |

## Where things are

### BattleMech Manual (PDF pages)
- Sequence of play, movement, terrain: 12–21
- Combat (LOS, arcs, to-hit, attack modifiers): 24–35; **hit location table 35**
- Physical attacks: 36–42
- Damage, transfer, critical hits & effects: 43–51
- **Heat** (build-up, dissipation, heat scale effects): 52–54
- Piloting skill rolls, falling, damaging a MechWarrior: 55–60
- Terrain types & planetary conditions: 61–64 (useful for arena maps)
- **Design Quirks** (positive/negative, per-'Mech quirk listing): 84–97. Good material for giving each chassis its own character in the autobattler.
- Weapon rules by type: 98–112
- **Weapon & equipment tables** (heat, damage, min/short/med/long, tons, crits, shots per ton):
  - IS weapons 123–125, Clan weapons 126–127
  - IS equipment 128, Clan equipment 129 (armor/structure/engine **crit slots** only; tons are "—")

### BattleTech: Universe (PDF pages)
- The BattleMech, MechWarrior, cockpit: 21–34
- Succession Wars overview, ComStar, military organization: 47–56
- Mercenaries: 67–68
- **The Games (Solaris VII, stables, managers, other game worlds): 69–70**
- Third Succession War, **Lostech**, "Keeping the Wheels Turning": 73–82
- **Inner Sphere map, 3025: 81**
- House Lords, **Fourth Succession War (3028–30)**: 83–88; War of 3039: 89
- Currency (C-bills, local scrip incl. Solaris): 174
- Great Houses (Davion 181, Kurita 187, Liao 193, Marik 199, Steiner 205)
- Mercenary units (Dragoons, Kell Hounds, Gray Death…): 267–282

### Recognition Guides
- Each chassis has 2–4 pages: history, capabilities, battle history, variants, notable MechWarriors (several of them Solaris fighters), plus TRO-style stat blocks with **component masses** (structure, engine, gyro, cockpit, heat sinks, armor), per-location IS/armor values, crits and BV.
- Solaris mentions: Vol. 1 PDF pages 36, 48, 60–76, 84–85, 108, 116, 128; Vol. 2 PDF pages 35, 69, 81, 86, 182–199.
- Vol. 1 ToC: PDF 4. Vol. 2 ToC: PDF 3.

## Gaps in these books (filled 2026-11-08, see `data/README.md`)

The five books lack construction weight tables, 3015-era stock designs, and tech dates and costs. These now come from:
- **MegaMek** (open-source rules engine plus its `mm-data` unit files, CC BY-NC-SA): engine and structure tables, cost formula, equipment dates, costs and availability, and 4,263 stock loadouts.
- **Master Unit List** (masterunitlist.battletech.com): intro years, BV, roles, and faction availability per era.
- **Sarna** (sarna.net): rule confirmations and a spot check of tech dates. Sarna does not host the full TechManual tables.

The Recognition Guide stat blocks are the **validator test set**. They list the mass of every component, and the tables were verified against them: 58 of 58 engines and 49 of 49 structure rows match.

Online sources:
- MUL: https://masterunitlist.battletech.com/. Its data files are behind a Cloudflare check, so export them through the browser, not curl.
- MegaMek: https://github.com/MegaMek/megamek (rules code) and https://github.com/MegaMek/mm-data (unit `.mtf` files)
- Sarna: append `?action=raw` to a wiki URL for wikitext
