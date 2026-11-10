extends Node
## Autoload "Game": holds the running campaign, switches screens, caches sprites and portraits.

const SAVE_DIR := "user://saves"
const UNITS := "res://assets/megamek/units/"
const PORTRAITS := "res://assets/megamek/portraits/"
const CAMO := "res://assets/megamek/camo/"

var campaign: Campaign
var merc: MercCampaign          # the Mercenary Company mode (null while running a Solaris stable)
var root_ui: Control
var ui_theme: Theme
var tint_shader: Shader
var _tex := {}
var last_tab := "dashboard"
var merc_tab := "command"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	ui_theme = UI.build_theme()
	tint_shader = load("res://ui/mech_tint.gdshader")


func _load_png(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var img := Image.load_from_file(path)
	var tex: Texture2D = null
	if img != null and not img.is_empty():
		tex = ImageTexture.create_from_image(img)
	_tex[path] = tex
	return tex


func mech_texture(sprite: String) -> Texture2D:
	var t := _load_png(UNITS + sprite)
	if t == null:
		t = _load_png(UNITS + "defaults/default_medium.png")
	return t


func wreck_texture(sprite: String) -> Texture2D:
	var t := _load_png(UNITS + sprite)
	if t == null:
		t = _load_png(UNITS + "wrecks/default_mech_wreck.png")
	return t


func portrait(file: String) -> Texture2D:
	if file == "":
		return null
	return _load_png(PORTRAITS + file)


func camo_texture(file: String) -> Texture2D:
	if file == "":
		return null
	return _load_png(CAMO + file)


func tint_material(color: Color, camo := "") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = tint_shader
	m.set_shader_parameter("tint", color)
	var ct := camo_texture(camo)
	if ct != null:
		m.set_shader_parameter("camo", ct)
		m.set_shader_parameter("use_camo", 1.0)
		m.set_shader_parameter("camo_scale", 0.6)
	return m


func stable_material(stable_id: int) -> ShaderMaterial:
	if campaign == null or stable_id < 0 or stable_id >= campaign.stables.size():
		return tint_material(Color(0.6, 0.6, 0.6))
	var s: Stable = campaign.stables[stable_id]
	return tint_material(s.color, s.camo)


# ------------------------------------------------------------------ screens

var _next_screen: Control


## Screen swaps wait until the current input event is fully handled: the button that asked for the
## swap must not be freed while it's still processing its own click.
func show_screen(node: Control) -> void:
	if root_ui == null:
		return
	if _next_screen != null and _next_screen != node and not _next_screen.is_inside_tree():
		_next_screen.queue_free()
	_next_screen = node
	_swap_screen.call_deferred()


func _swap_screen() -> void:
	var node := _next_screen
	_next_screen = null
	if node == null or root_ui == null:
		return
	UI.clear(root_ui)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.add_child(node)
	UI.fade_in(node, 0.22)


func show_menu() -> void:
	show_screen(load("res://ui/screens/menu.gd").new())


func show_hub(tab := "") -> void:
	if tab != "":
		last_tab = tab
	show_screen(load("res://ui/screens/hub.gd").new())


func new_game(stable_name: String, sector: String, color: Color, seed_v: int) -> void:
	merc = null
	campaign = Campaign.new_game(stable_name, sector, seed_v, color)
	save_game("autosave")
	show_hub("dashboard")


func new_merc_game(company: String, color: Color, year: int, hall: String, package: String, seed_v: int, difficulty := "Regular") -> void:
	campaign = null
	merc = MercCampaign.new_game(company, color, year, hall, package, seed_v, difficulty)
	save_game("merc_autosave")
	show_merc_hub("command")


## New games from the setup screen: `setup` is what you start with, `play` the campaign settings.
func new_game_custom(stable_name: String, sector: String, color: Color, seed_v: int, setup: Dictionary, play: Dictionary) -> void:
	merc = null
	campaign = Campaign.new_game(stable_name, sector, seed_v, color, setup, play)
	save_game("autosave")
	show_hub("dashboard")


func new_merc_custom(company: String, color: Color, setup: Dictionary, seed_v: int, play: Dictionary) -> void:
	campaign = null
	merc = MercCampaign.new_custom(company, color, setup, seed_v, play)
	save_game("merc_autosave")
	show_merc_hub("command")


func show_setup(mode: String) -> void:
	var s: Control = load("res://ui/screens/setup.gd").new()
	s.mode = mode
	show_screen(s)


func show_merc_hub(tab := "") -> void:
	if tab != "":
		merc_tab = tab
	show_screen(load("res://ui/merc/merc_hub.gd").new())


func save_game(slot := "autosave") -> bool:
	if merc != null:
		if not slot.begins_with("merc_"):
			slot = "merc_" + slot
		return merc.save_to("%s/%s.json" % [SAVE_DIR, slot])
	if campaign == null:
		return false
	return campaign.save_to("%s/%s.json" % [SAVE_DIR, slot])


func list_saves() -> Array:
	var out: Array = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			var path := "%s/%s" % [SAVE_DIR, f]
			out.append({"slot": f.trim_suffix(".json"), "path": path, "time": FileAccess.get_modified_time(path)})
	out.sort_custom(func(a, b): return a["time"] > b["time"])
	return out


func load_game(path: String) -> bool:
	if path.get_file().begins_with("merc_"):
		var mc := MercCampaign.load_from(path)
		if mc == null:
			return false
		campaign = null
		merc = mc
		show_merc_hub("command")
		return true
	var c := Campaign.load_from(path)
	if c == null:
		return false
	merc = null
	campaign = c
	show_hub("dashboard")
	return true


## Opens a merc battle live in the command view.
func watch_merc_battle(sid: int, uids: Array) -> void:
	if merc == null:
		return
	var b := merc.make_battle(sid, uids, true)
	if b.is_empty():
		return
	var cv = load("res://ui/fight/command_view.gd").new()
	cv.setup_merc(b["sim"], b["battle"])
	show_screen(cv)


## Company paint for a merc battle unit: the company's color for your side, faction colors for others.
func merc_material(team: int, faction := "") -> ShaderMaterial:
	if team == 0 and merc != null:
		return tint_material(merc.color, merc.camo)
	if faction != "":
		return tint_material(StarMap.get_map().faction_color(faction).lerp(Color(0.5, 0.5, 0.5), 0.25))
	return tint_material(Color(0.6, 0.6, 0.6))


## Simulates a booked bout with full recording and opens the fight viewer.
func watch_bout(bout_id: int) -> void:
	for b in campaign.bookings:
		if int(b["id"]) == bout_id and not b["resolved"]:
			# the fight runs live in the viewer so you can make corner calls
			var sim := campaign.make_sim(b, true)
			var fv = load("res://ui/fight/fight_view.gd").new()
			fv.setup(sim, b)
			show_screen(fv)
			return


## A merc company's duel on Solaris VII, live in the fight viewer.
func watch_merc_bout(offer_id: int, uid: int, orders: Dictionary) -> void:
	var b := merc.make_arena_bout(offer_id, uid, orders, true)
	if b.is_empty():
		return
	var fv = load("res://ui/fight/fight_view.gd").new()
	fv.setup(b["sim"], b["bout"])
	show_screen(fv)


func simulate_bout(bout_id: int) -> Dictionary:
	for b in campaign.bookings:
		if int(b["id"]) == bout_id and not b["resolved"]:
			var sim := campaign.make_sim(b, false)
			sim.run_to_end()
			return campaign.apply_result(b, sim.result)
	return {}


func finish_watched(bout: Dictionary, sim: CombatSim) -> Dictionary:
	if bout.get("resolved", false):
		return {}
	return campaign.apply_result(bout, sim.result)
