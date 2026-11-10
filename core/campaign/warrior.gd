class_name Warrior
extends RefCounted
## A MechWarrior: skills on the tabletop scale (lower is better), traits, condition, contract, record.

var id := 0
var first := ""
var last := ""
var callsign := ""
var gender := "m"
var portrait := ""
var culture := "Mercenary"
var birth_year := 2990
var gunnery := 4
var piloting := 5
var traits: Array = []
var morale := 60.0
var fatigue := 0.0
var injury_weeks := 0
var wounds := 0
var fame := 0.0
var xp := 0
var salary := 2000
var contract_weeks := 0
var purse_share := 0.1
var stable_id := -1
var mech_uid := -1
var elo := 1200.0
var wins := 0
var losses := 0
var draws := 0
var kills := 0
var titles: Array = []
var retired := false
var dead := false
var drafted_weeks := 0
var away_weeks := 0
var orders: Dictionary = {}
var history: Array = []
var streak := 0


func full_name() -> String:
	if callsign != "":
		return "%s \"%s\" %s" % [first, callsign, last]
	return "%s %s" % [first, last]


func short_name() -> String:
	return callsign if callsign != "" else last


func age(year: int) -> int:
	return year - birth_year


func record_str() -> String:
	return "%d-%d-%d" % [wins, losses, draws]


func skill_str() -> String:
	return "%d/%d" % [gunnery, piloting]


func available() -> bool:
	return not retired and not dead and injury_weeks <= 0 and drafted_weeks <= 0 and away_weeks <= 0 and fatigue < 70.0


func status_str() -> String:
	if dead:
		return "Dead"
	if retired:
		return "Retired"
	if away_weeks > 0:
		return "Off-world on contract (%d wk)" % away_weeks
	if drafted_weeks > 0:
		return "Recalled to the front (%d wk)" % drafted_weeks
	if injury_weeks > 0:
		return "Injured (%d wk)" % injury_weeks
	if fatigue >= 70.0:
		return "Exhausted"
	return "Ready"


## Market value of skills: fair weekly salary.
func fair_salary(rules: Dictionary) -> int:
	var s: Dictionary = rules["salary"]
	var skill := maxi(0, 5 - gunnery) + maxi(0, 6 - piloting)
	return int(float(s["base"]) + skill * float(s["per_skill_point"]) + fame * float(s["per_fame"]))


func to_dict() -> Dictionary:
	return {
		"id": id, "first": first, "last": last, "callsign": callsign, "gender": gender, "portrait": portrait,
		"culture": culture, "birth_year": birth_year, "gunnery": gunnery, "piloting": piloting, "traits": traits,
		"morale": morale, "fatigue": fatigue, "injury_weeks": injury_weeks, "wounds": wounds, "fame": fame, "xp": xp,
		"salary": salary, "contract_weeks": contract_weeks, "purse_share": purse_share, "stable_id": stable_id,
		"mech_uid": mech_uid, "elo": elo, "wins": wins, "losses": losses, "draws": draws, "kills": kills,
		"titles": titles, "retired": retired, "dead": dead, "drafted_weeks": drafted_weeks, "away_weeks": away_weeks, "orders": orders,
		"history": history, "streak": streak,
	}


static func from_dict(d: Dictionary) -> Warrior:
	var w := Warrior.new()
	for k in d:
		if k in w:
			var v = d[k]
			if typeof(w.get(k)) == TYPE_INT:
				v = int(v)
			w.set(k, v)
	return w


## Combat-sim view of the warrior.
func sim_dict() -> Dictionary:
	return {"name": full_name(), "callsign": short_name(), "gunnery": gunnery, "piloting": piloting, "traits": traits}
