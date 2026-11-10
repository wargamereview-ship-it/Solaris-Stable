# MegaMek art

Copied from [MegaMek Data](https://github.com/MegaMek/mm-data) (`data/images/`), licensed CC BY-NC-SA 4.0 by the MegaMek Development Team. Personal, non-commercial use only.

| Folder | Source | Use |
|---|---|---|
| `units/meks/`, `units/mekset.txt` | `data/images/units/meks/` + `mekset.txt` | Top-down 'Mech sprites (grayscale, tinted in-game by `ui/mech_tint.gdshader`) |
| `units/vehicles/` | `data/images/units/vehicles/` | Top-down combat vehicle sprites for the merc mode (copied by `build_merc_data.py`, only the ones the imported vehicles use) |
| `units/infantry/` | `data/images/units/Infantry/`, `battle armor/`, `defaults/default_infantry_platoon.png` | Top-down infantry platoon and battle armour squad sprites for the merc mode (`fallen.png`, the marker left by a wiped-out squad, is the project's own) |
| `units/wrecks/` | `data/images/units/wrecks/` | Destroyed 'Mech sprites |
| `units/defaults/` | `data/images/units/defaults/` | Fallback sprites by weight class; `asf.png` is the fighter that flies an air strike |
| `portraits/` | `data/images/portraits/{Male,Female}/MekWarrior/` | MechWarrior portraits, resized to 128x160 (`m_*` male, `f_*` female) |
| `camo/` | `data/images/camo/Faction Camouflage/Gradients/` | House camo patterns for stable paint |

The `.gdignore` keeps Godot from importing thousands of images; the game loads them at runtime with `Image.load_from_file`.
