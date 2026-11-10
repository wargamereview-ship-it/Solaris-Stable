extends SceneTree
## godot --headless --path . -s tests/test_campaign.gd
## Plays 60 weeks with a simple auto-manager, checks bookkeeping, the championship and save/load.

func _init() -> void:
	var fails := 0
	var t0 := Time.get_ticks_msec()
	var lib := GameData.db().get_library()
	print("library: %d designs (%d ms)" % [lib.size(), Time.get_ticks_msec() - t0])
	t0 = Time.get_ticks_msec()
	var c := Campaign.new_game("Test Stable", "Silesia", 4242)
	print("new game: %d ms, %d stables, %d warriors, %d mechs, pool %d designs in %d" % [Time.get_ticks_msec() - t0, c.stables.size(), c.warriors.size(), c.mechs.size(), c.market_pool().size(), c.year])
	var p := c.player()
	for wid in p.warriors:
		var w: Warrior = c.warriors[wid]
		print("  %s %s age %d %s mech %s" % [w.full_name(), w.skill_str(), w.age(c.year), w.traits, c.mechs[w.mech_uid].design.display_name() if w.mech_uid >= 0 else "-"])
	print("  market: %d mechs, %d agents, %d part types" % [c.market["mechs"].size(), c.market["agents"].size(), c.market["parts"].size()])
	var total_ms := 0
	var player_fights := 0
	var weeks := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 60
	for wk in weeks:
		var t1 := Time.get_ticks_msec()
		# auto-manager: repair damaged mechs, book one bout per ready warrior
		for uid in p.mechs:
			var om: OwnedMech = c.mechs[uid]
			if om.is_damaged() and om.status in ["ready", "wrecked"]:
				c.start_repair(uid)
		if p.warriors.size() < 3 and not c.market["agents"].is_empty():
			var ag: int = c.market["agents"][0]
			c.hire(ag, int(c.warriors[ag].salary * 1.1), 52)
		for wid in p.warriors:
			var w: Warrior = c.warriors[wid]
			if not w.available() or w.mech_uid < 0 or not c.mechs.has(w.mech_uid) or not c.mechs[w.mech_uid].ready():
				continue
			for o in c.offers.duplicate():
				var err := c.book(o["id"], wid, w.mech_uid, {"range": "optimal"}, 0)
				if err == "":
					player_fights += 1
					break
		c.advance_week()
		var dt := Time.get_ticks_msec() - t1
		total_ms += dt
		if wk % 26 == 0 or c.week == 1:
			var ready := {"light": 0, "medium": 0, "heavy": 0, "assault": 0}
			for st in c.stables:
				if st.is_player:
					continue
				for wid in st.warriors:
					var aw: Warrior = c.warriors[wid]
					if aw.available() and aw.mech_uid >= 0 and c.mechs.has(aw.mech_uid) and c.mechs[aw.mech_uid].ready():
						ready[c.mech_class(aw.mech_uid)] += 1
			print("    AI ready by class: ", ready, "  free agents: ", c.warriors.values().filter(func(x): return x.stable_id == -1 and not x.dead and not x.retired).size())
			print("%s  cash %s  fame %.1f  record %d-%d-%d  week took %d ms  AI card %d" % [c.date_str(), Campaign.money(p.cash), p.fame, p.wins, p.losses, p.draws, dt, c.ai_card.size()])
	print("avg week: %d ms, player fights %d" % [total_ms / weeks, player_fights])
	for uid in p.mechs:
		var om: OwnedMech = c.mechs[uid]
		print("  mech %s status %s hours %.0f damaged %s" % [om.design.display_name(), om.status, om.work_hours, om.is_damaged()])
	for wid in p.warriors:
		var w: Warrior = c.warriors[wid]
		print("  warrior %s %s fatigue %.0f inj %d mech %d" % [w.short_name(), w.status_str(), w.fatigue, w.injury_weeks, w.mech_uid])
	for l in p.ledger.slice(-3):
		print("  ledger ", l)
	print("champions: ", c.champions)
	for cls in ["light", "medium", "heavy", "assault"]:
		var r := c.rankings(cls)
		if r.size() > 0:
			var w: Warrior = c.warriors[r[0]]
			print("  #1 %s: %s %s elo %.0f %s" % [cls, w.full_name(), w.record_str(), w.elo, c.mechs[w.mech_uid].design.display_name()])
	var news_n := 0
	for n in c.news:
		if n["kind"] in ["event", "championship", "title"]:
			news_n += 1
	print("news items: %d (events/titles/championship %d)" % [c.news.size(), news_n])
	for n in c.news.slice(-12):
		print("  [%d w%d] %s: %s" % [n["y"], n["w"], n["title"], n["text"]])
	# save / load roundtrip
	var path := "user://test_save.json"
	if not c.save_to(path):
		print("save failed"); fails += 1
	var c2 := Campaign.load_from(path)
	if c2 == null:
		print("load failed"); fails += 1
	else:
		var same: bool = c2.year == c.year and c2.week == c.week and c2.player().cash == c.player().cash and c2.warriors.size() == c.warriors.size() and c2.mechs.size() == c.mechs.size()
		print("save/load roundtrip: ", same)
		if not same:
			fails += 1
		c2.advance_week()
		print("advanced loaded game to ", c2.date_str())
	print("FAILURES: ", fails)
	quit(fails)
