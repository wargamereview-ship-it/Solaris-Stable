class_name Stable
extends RefCounted
## A stable: the player's or one of the AI rivals.

var id := 0
var name := ""
var sector := "International Zone"
var house := ""
var color := Color(0.6, 0.6, 0.6)
var camo := ""
var is_player := false
var cash := 0
var fame := 5.0
var bays := 4
var techs := 3
var medic := 0
var sim_pods := 0
var warriors: Array = []
var mechs: Array = []
var inventory: Dictionary = {}
var ledger: Array = []
var philosophy := "balanced"
var wins := 0
var losses := 0
var draws := 0
var week_lines: Dictionary = {}


func add_ledger(label: String, amount: int) -> void:
	cash += amount
	week_lines[label] = int(week_lines.get(label, 0)) + amount


func close_week(year: int, week: int) -> void:
	ledger.append({"year": year, "week": week, "lines": week_lines.duplicate(), "cash": cash})
	while ledger.size() > 104:
		ledger.pop_front()
	week_lines = {}


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "sector": sector, "house": house, "color": [color.r, color.g, color.b],
		"camo": camo, "is_player": is_player, "cash": cash, "fame": fame, "bays": bays, "techs": techs,
		"medic": medic, "sim_pods": sim_pods, "warriors": warriors, "mechs": mechs, "inventory": inventory,
		"ledger": ledger, "philosophy": philosophy, "wins": wins, "losses": losses, "draws": draws,
		"week_lines": week_lines}


static func from_dict(d: Dictionary) -> Stable:
	var s := Stable.new()
	s.id = int(d["id"])
	s.name = str(d["name"])
	s.sector = str(d.get("sector", ""))
	s.house = str(d.get("house", ""))
	var c: Array = d.get("color", [0.6, 0.6, 0.6])
	s.color = Color(float(c[0]), float(c[1]), float(c[2]))
	s.camo = str(d.get("camo", ""))
	s.is_player = bool(d.get("is_player", false))
	s.cash = int(d.get("cash", 0))
	s.fame = float(d.get("fame", 0))
	s.bays = int(d.get("bays", 4))
	s.techs = int(d.get("techs", 3))
	s.medic = int(d.get("medic", 0))
	s.sim_pods = int(d.get("sim_pods", 0))
	s.warriors = []
	for w in d.get("warriors", []):
		s.warriors.append(int(w))
	s.mechs = []
	for m in d.get("mechs", []):
		s.mechs.append(int(m))
	s.inventory = {}
	var inv: Dictionary = d.get("inventory", {})
	for k in inv:
		s.inventory[k] = int(inv[k])
	s.ledger = d.get("ledger", [])
	s.philosophy = str(d.get("philosophy", "balanced"))
	s.wins = int(d.get("wins", 0))
	s.losses = int(d.get("losses", 0))
	s.draws = int(d.get("draws", 0))
	s.week_lines = d.get("week_lines", {})
	return s
