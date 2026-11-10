class_name MercUnit
extends RefCounted
## A 'Mech or vehicle in the company's hangar: its design, persistent damage, crew and repair state.
## condition ({} = undamaged):
##   'Mech:    {"armor", "internal", "hit_slots": [[loc, i]], "ammo": {mount index: shots}}
##   vehicle:  {"armor", "internal", "dead_mounts": [mount index], "ammo", "vstate"}
## status: ready, damaged, wreck (salvage only), sold

var id := 0
var design: MechDesign
var nickname := ""
var condition: Dictionary = {}
var crew: Array = []          # person ids (one MechWarrior, or a vehicle crew commander)
var lance := -1
var status := "ready"
var kills := 0
var battles := 0
var acquired := ""
var progress: Dictionary = {}  # repair task key -> minutes worked
var origin := ""               # how it joined: start, bought, salvage
## A refit on order ({} = none): {"design": the new design, "need": {part key: quantity},
## "have": {part key: quantity set aside for it}, "freed": {part key: quantity that comes off},
## "minutes": tech minutes of work, "done": minutes worked, "ordered": day}
var refit: Dictionary = {}


func is_vehicle() -> bool:
	return design.is_vehicle()


func label() -> String:
	if nickname != "":
		return "%s (%s)" % [nickname, design.display_name()]
	return design.display_name()


func kind_label() -> String:
	if is_vehicle():
		return (design as VehicleDesign).motion_label()
	return "'Mech"


func tons() -> int:
	return design.tons


func weight_class() -> String:
	return GameData.db().weight_class(design.tons)


func damaged() -> bool:
	return not condition.is_empty()


func wreck() -> bool:
	return status == "wreck"


func analysis() -> Dictionary:
	return Construction.analyze(design)


func base_cost() -> int:
	return int(analysis().get("cost", 0))


func bv() -> int:
	return int(analysis().get("bv", 0))


## 0 = pristine, 1 = gone: share of armor and structure missing.
func damage_fraction() -> float:
	if condition.is_empty():
		return 0.0
	var rep := analysis()
	var ipts: Dictionary = rep.get("internal", {}) if is_vehicle() else Construction.internal_points(design.tons)
	var lost := 0.0
	var tot := 0.0
	var ci: Dictionary = condition.get("internal", {})
	for loc in ipts:
		var mx := float(ipts[loc])
		tot += mx
		lost += mx - float(ci.get(loc, mx))
	var ca: Dictionary = condition.get("armor", {})
	var at := 0.0
	var al := 0.0
	for k in design.armor:
		var mx2 := float(design.armor[k])
		at += mx2
		al += mx2 - float(ca.get(k, mx2))
	return clampf((lost / maxf(1.0, tot)) * 0.7 + (al / maxf(1.0, at)) * 0.3, 0.0, 1.0)


func value() -> int:
	var c := base_cost()
	if wreck():
		return int(c * 0.12)
	return int(c * (1.0 - 0.6 * damage_fraction()))


## The techs have started on the refit: the 'Mech is in pieces and can't fight.
func refitting() -> bool:
	return not refit.is_empty() and float(refit.get("done", 0.0)) > 0.0


func sim_condition() -> Dictionary:
	return condition.duplicate(true)


func to_dict() -> Dictionary:
	return {"id": id, "design": design.to_dict(), "nickname": nickname, "condition": condition, "crew": crew.duplicate(),
		"lance": lance, "status": status, "kills": kills, "battles": battles, "acquired": acquired,
		"progress": progress, "origin": origin, "refit": refit}


static func from_dict(d: Dictionary) -> MercUnit:
	var u := MercUnit.new()
	u.id = int(d.get("id", 0))
	u.design = VehicleDesign.any_from_dict(d["design"])
	u.nickname = str(d.get("nickname", ""))
	u.condition = d.get("condition", {})
	u.crew = []
	for c in d.get("crew", []):
		u.crew.append(int(c))
	u.lance = int(d.get("lance", -1))
	u.status = str(d.get("status", "ready"))
	u.kills = int(d.get("kills", 0))
	u.battles = int(d.get("battles", 0))
	u.acquired = str(d.get("acquired", ""))
	u.progress = d.get("progress", {})
	u.origin = str(d.get("origin", ""))
	u.refit = d.get("refit", {})
	return u
