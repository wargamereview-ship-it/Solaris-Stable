class_name MercPerson
extends RefCounted
## One member of the company. Skills are target numbers (lower is better), as in MekHQ:
## gunnery and piloting for MechWarriors and vehicle crews (piloting = driving), tech, medical, admin.
## A vehicle crew is its commander plus `crew` anonymous crewmen.

const ROLES := {"mechwarrior": "MechWarrior", "vehicle_crew": "Vehicle crew", "tech": "Tech", "doctor": "Doctor",
	"admin": "Admin", "astech": "AsTech", "medic": "Medic"}

var id := 0
var first := ""
var last := ""
var callsign := ""
var gender := "male"
var portrait := ""
var role := "mechwarrior"
var gunnery := 4
var piloting := 5
var tech := 7
var medical := 7
var admin := 7
var negotiation := 8
var crew := 0                # vehicle crew: extra crewmen besides the commander
var xp := 0
var injury_days := 0
var injury := ""
var status := "active"       # active, injured, dead, mia, left
var unit_id := -1
var kills := 0
var battles := 0
var joined := ""
var age := 28
var traits: Array = []
var notes := ""


func full_name() -> String:
	if callsign != "" and role in ["mechwarrior", "vehicle_crew"]:
		return "%s \"%s\" %s" % [first, callsign, last]
	return "%s %s" % [first, last]


func short_name() -> String:
	if callsign != "":
		return callsign
	return last


func role_label() -> String:
	return ROLES.get(role, role)


func combat() -> bool:
	return role in ["mechwarrior", "vehicle_crew"]


func available() -> bool:
	return status == "active"


func alive() -> bool:
	return status in ["active", "injured"]


## Green, regular, veteran or elite, from the role's main skills.
func experience(rules: Dictionary) -> String:
	var sk: Dictionary = rules["skills"]
	if combat():
		var s := gunnery + piloting
		for row in sk["combat_levels"]:
			if s >= int(row[0]):
				return str(row[1])
		return "elite"
	var tn := 7
	match role:
		"tech":
			tn = tech
		"doctor":
			tn = medical
		"admin":
			tn = admin
		_:
			return "regular"
	for row in sk["support_levels"]:
		if tn >= int(row[0]):
			return str(row[1])
	return "elite"


func salary(rules: Dictionary) -> int:
	var s: Dictionary = rules["salaries"]
	var base := float(s.get(role, 500))
	var mult := float(s["experience_mult"].get(experience(rules), 1.0))
	var total := base * mult
	if role == "vehicle_crew":
		total += float(s["crewman"]) * crew
	return int(round(total))


func skill_str() -> String:
	match role:
		"mechwarrior", "vehicle_crew":
			return "G%d / %s%d" % [gunnery, "P" if role == "mechwarrior" else "D", piloting]
		"tech":
			return "Tech %d" % tech
		"doctor":
			return "Medicine %d" % medical
		"admin":
			return "Admin %d, Negotiation %d" % [admin, negotiation]
	return ""


func headcount() -> int:
	return 1 + (crew if role == "vehicle_crew" else 0)


func to_dict() -> Dictionary:
	return {"id": id, "first": first, "last": last, "callsign": callsign, "gender": gender, "portrait": portrait,
		"role": role, "gunnery": gunnery, "piloting": piloting, "tech": tech, "medical": medical, "admin": admin,
		"negotiation": negotiation, "crew": crew, "xp": xp, "injury_days": injury_days, "injury": injury,
		"status": status, "unit_id": unit_id, "kills": kills, "battles": battles, "joined": joined, "age": age,
		"traits": traits.duplicate(), "notes": notes}


static func from_dict(d: Dictionary) -> MercPerson:
	var p := MercPerson.new()
	p.id = int(d.get("id", 0))
	p.first = str(d.get("first", ""))
	p.last = str(d.get("last", ""))
	p.callsign = str(d.get("callsign", ""))
	p.gender = str(d.get("gender", "male"))
	p.portrait = str(d.get("portrait", ""))
	p.role = str(d.get("role", "mechwarrior"))
	p.gunnery = int(d.get("gunnery", 4))
	p.piloting = int(d.get("piloting", 5))
	p.tech = int(d.get("tech", 7))
	p.medical = int(d.get("medical", 7))
	p.admin = int(d.get("admin", 7))
	p.negotiation = int(d.get("negotiation", 8))
	p.crew = int(d.get("crew", 0))
	p.xp = int(d.get("xp", 0))
	p.injury_days = int(d.get("injury_days", 0))
	p.injury = str(d.get("injury", ""))
	p.status = str(d.get("status", "active"))
	p.unit_id = int(d.get("unit_id", -1))
	p.kills = int(d.get("kills", 0))
	p.battles = int(d.get("battles", 0))
	p.joined = str(d.get("joined", ""))
	p.age = int(d.get("age", 28))
	p.traits = (d.get("traits", []) as Array).duplicate()
	p.notes = str(d.get("notes", ""))
	return p


## What the fight engine needs to know about whoever is at the controls.
func sim_dict() -> Dictionary:
	return {"callsign": short_name(), "name": full_name(), "gunnery": gunnery, "piloting": piloting, "traits": traits.duplicate()}
