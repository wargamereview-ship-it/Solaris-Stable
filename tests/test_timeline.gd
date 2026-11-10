extends SceneTree
## godot --headless --path . -s tests/test_timeline.gd
## The canon timeline in both modes: the data itself, events firing on their date, their effects on
## prices, purses, pay and who hires, wars and front lines taken from MegaMek's data, and saves.

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func has_title(list: Array, title: String) -> bool:
	for n in list:
		if str(n["title"]) == title:
			return true
	return false


func merc_at(y: int, m: int, d: int, hall := "Galatea", seed_v := 7) -> MercCampaign:
	var c := MercCampaign.new_game("Timeline Co", Color(0.4, 0.5, 0.6), y, hall, "lance", seed_v)
	c.day = MercCampaign.jdn(y, m, d)
	c.events_day = c.day
	c.front_day = c.day
	c.sm.year_hint = c.year_f()
	return c


func _init() -> void:
	var db := GameData.db()
	var sm := StarMap.get_map()

	# ---------------------------------------------------------------- the data
	check(db.events.size() >= 90, "a full timeline (%d events)" % db.events.size())
	check(str(db.events[0]["date"]).begins_with("3015") and str(db.events[db.events.size() - 1]["date"]).begins_with("3152"), "from 3015 to 3152")
	var war_names := {}
	for w in sm.relations["wars"]:
		war_names[str(w["name"])] = true
	var stable_keys := ["weeks", "price_mult", "purse_mult", "tension", "jobs", "draft", "free_agent_boost", "clan_salvage"]
	var merc_keys := ["days", "pay", "offers", "price", "supply", "recruits", "employers", "note"]
	var prev := ""
	for e in db.events:
		var t := str(e["title"])
		check(str(e["date"]) >= prev, "%s is in date order" % t)
		prev = str(e["date"])
		check(int(e["year"]) >= 3015 and int(e["month"]) >= 1 and int(e["month"]) <= 12 and int(e["week"]) >= 1 and int(e["week"]) <= 52, "%s has a date" % t)
		check(str(e["text"]).length() > 30, "%s has a text" % t)
		check(str(e.get("only", "")) in ["", "stable", "merc"], "%s: only" % t)
		for k in e.get("stable", {}):
			check(k in stable_keys, "%s: stable effect '%s' is known" % [t, k])
		for k in e.get("merc", {}):
			check(k in merc_keys, "%s: merc effect '%s' is known" % [t, k])
		for f in (e.get("merc", {}) as Dictionary).get("employers", {}):
			check(sm.factions.has(str(f)), "%s: employer %s exists" % [t, f])
		for key in ["war_start", "war_end"]:
			for wn in e.get(key, []):
				check(war_names.has(str(wn)), "%s: war '%s' is in the data" % [t, wn])
		if e.has("merc"):
			check(int(e["merc"].get("days", 0)) > 0, "%s: merc effects have a length" % t)

	# ---------------------------------------------------------------- stable mode
	var c := Campaign.new_game("Timeline Stable", "Silesia", 21)
	check(has_title(c.news, "A new season on the Game World") or c.fired_events.size() == 0, "the opening entry")
	c.advance_week()
	check(has_title(c.news, "A new season on the Game World"), "the first week's news")
	check(not has_title(c.news, "Death to Mercenaries"), "nothing early")
	# jump to the week before the Fourth Succession War
	c.year = 3028
	c.week = 33
	c._fire_events()
	check(not has_title(c.news, "Marik raid on Solaris VII"), "events long past make no late news")
	check(absf(c.price_mult() - 1.0) < 0.001, "and are not replayed (prices %.2f)" % c.price_mult())
	check(absf(c.effect_mult("purse_mult") - 1.0) < 0.001, "no purse effect from a skipped entry")
	c.week = 34
	c._fire_events()
	check(has_title(c.news, "The Fourth Succession War"), "the war makes the news in its week")
	var n4: Dictionary = c.news[c.news.size() - 1]
	for n in c.news:
		if str(n["title"]) == "The Fourth Succession War":
			n4 = n
	check(str(n4["text"]).contains("Solaris City"), "with the view from Solaris")
	check(absf(c.price_mult() - 1.25) < 0.001, "wartime prices (%.2f)" % c.price_mult())
	check(absf(c.effect_mult("tension") - 1.3) < 0.001, "crowds")
	check(absf(c.effect_mult("job_chance") - 1.6) < 0.001 and absf(c.effect_mult("job_pay") - 1.25) < 0.001, "more mercenary work, better paid")
	var inf := c.effects_in_force()
	check(inf.size() == 1 and str(inf[0]["src"]) == "The Fourth Succession War" and str(inf[0]["text"]).contains("prices +25%"), "the office names what is in force: %s" % str(inf))
	check(not has_title(c.news, "Wolf's Dragoons sign with the Dragon"), "mercenary-only entries stay out of the stable game")
	var before := c.fired_events.size()
	c._fire_events()
	check(c.fired_events.size() == before and c.effects_in_force().size() == 1, "nothing fires twice")
	# the war's effects run out
	c.year = 3030
	c.week = 3
	c._fire_events()
	check(has_title(c.news, "The guns fall quiet"), "the peace is news")
	c.week = 10
	c._fire_events()
	check(absf(c.price_mult() - 1.0) < 0.001, "prices settle after the war (%.2f)" % c.price_mult())
	# the Clans: a flag that lasts
	c.year = 3050
	c.week = 10
	c._fire_events()
	check(c.flag_active("clan_salvage"), "Clan salvage reaches the market")
	var path := "user://_timeline_test.json"
	check(c.save_to(path), "stable save")
	var c2 := Campaign.load_from(path)
	check(c2 != null and absf(c2.price_mult() - c.price_mult()) < 0.001 and c2.effects_in_force().size() == c.effects_in_force().size(), "effects survive a save")
	check(c2 != null and c2.fired_events.size() == c.fired_events.size(), "fired entries survive a save")
	# an old save meets the new timeline in 3050: flags only
	var c3 := Campaign.new_game("Old Stable", "Cathay", 5)
	c3.year = 3051
	c3.week = 30
	c3._fire_events()
	check(c3.flag_active("clan_salvage") and absf(c3.price_mult() - 1.0) < 0.001, "a late start still knows about the Clans")
	check(c3.news.size() <= 2, "and gets no flood of old news (%d)" % c3.news.size())

	# the Republic's long peace, then the Dark Age
	var c4 := Campaign.new_game("Late Stable", "Black Hills", 8)
	c4.year = 3085
	c4.week = 40
	c4._fire_events()
	check(has_title(c4.news, "The long peace") and absf(c4.effect_mult("job_chance") - 0.6) < 0.001, "the long peace: less mercenary work")
	c4.year = 3110
	c4._fire_events()
	check(absf(c4.effect_mult("job_chance") - 0.6) < 0.001, "still so a generation later")
	c4.year = 3132
	c4.week = 32
	c4._fire_events()
	c4.week = 34
	check(has_title(c4.news, "Gray Monday") and absf(c4.effect_mult("job_chance") - 1.6) < 0.001, "Gray Monday ends it (%.2f)" % c4.effect_mult("job_chance"))
	c4.year = 3145
	c4.week = 37
	c4._fire_events()
	check(has_title(c4.news, "The Wolves take Solaris"), "3145: the Wolves take Solaris")
	for k in 3:
		c4.advance_week()
	check(c4.year == 3145 and c4.week == 40, "the stable game runs in 3145")

	# ---------------------------------------------------------------- mercenary mode: dated events
	var m := merc_at(3028, 8, 18)
	check(m.timeline_active().is_empty() or absf(m.price_mult() - 1.0) < 0.001, "peace prices before the war")
	var base_price := int(m.part_info("armor:standard")["price"])
	var tn0 := int(m.procurement_tn("armor:standard")["tn"])
	var stop := false
	for k in 3:
		for e in m.advance_day():
			if str(e["kind"]) == "news" and e.get("stop", false) and str(e["text"]).begins_with("The Fourth Succession War"):
				stop = true
	check(stop, "a major event stops the clock")
	check(has_title(m.news, "The Fourth Succession War"), "and is in the news")
	check(absf(m.timeline_mult("pay") - 1.25) < 0.001 and absf(m.timeline_mult("offers") - 1.3) < 0.001, "war pay and more offers")
	check(absf(m.employer_weight("FS") - 2.0) < 0.001 and absf(m.employer_weight("FWL") - 1.0) < 0.001, "the Houses at war hire more")
	check(absf(m.price_mult() - 1.2) < 0.001 and m.supply_mod() == 1, "prices and shortages")
	check(int(m.part_info("armor:standard")["price"]) == int(round(base_price * 1.2)), "a part costs more")
	check(int(m.procurement_tn("armor:standard")["tn"]) == tn0 + 1, "and is harder to find")
	var sumry := m.timeline_summary()
	check(sumry.size() == 1 and str(sumry[0]["text"]).contains("contract pay +25%"), "the summary says so: %s" % str(sumry))
	check("Federated Suns" in m.hiring_outlook()["more"] and (m.hiring_outlook()["less"] as Array).is_empty(), "and who is hiring: %s" % str(m.hiring_outlook()))
	check("Draconis Combine" in merc_at(3032, 6, 1).hiring_outlook()["less"], "3032: the outlook names the Dragon")
	m.refresh_markets()
	var wartime := 0
	for k in 6:
		m.generate_contracts()
		for o in m.contract_offers:
			if o.get("wartime", false):
				wartime += 1
	check(wartime > 0, "wartime contracts are on offer")
	# stateless: a company founded mid-war lives under the same effects
	var m2 := merc_at(3029, 2, 1)
	check(absf(m2.price_mult() - 1.2) < 0.001 and m2.news.is_empty(), "a company founded mid-war pays war prices, with no old news")
	# Death to Mercenaries, and its end
	check(absf(merc_at(3032, 6, 1).employer_weight("DC") - 0.12) < 0.001, "3032: the Dragon does not hire")
	check(absf(merc_at(3045, 6, 1).employer_weight("DC") - 0.5) < 0.001, "3045: the Dragon hires quietly")
	check(absf(merc_at(3055, 6, 1).employer_weight("DC") - 1.5) < 0.001, "3055: the Dragon hires openly")
	check(absf(merc_at(3058, 6, 1).employer_weight("DC") - 1.0) < 0.001, "3058: back to normal")
	# stable-only entries stay out
	var m3 := merc_at(3027, 5, 24)
	for k in 4:
		m3.advance_day()
	check(not has_title(m3.news, "Xiang's season"), "stable-only entries stay out of the mercenary game")

	# ---------------------------------------------------------------- wars from the data
	var m4 := merc_at(3053, 12, 29)
	for k in 5:
		m4.advance_day()
	var found := false
	for n in m4.news:
		if str(n["kind"]) == "war" and str(n["title"]) == "Marian-Lothian War" and str(n["text"]).contains("Marian Hegemony") and str(n["text"]).contains("Lothian League"):
			found = true
	check(found, "a war the timeline has no entry for is announced from the data: %s" % str(m4.news))
	var m5 := merc_at(3025, 12, 20)
	for k in 20:
		m5.advance_day()
	check(has_title(m5.news, "The Third Succession War gutters out"), "the timeline's own entry for the end of a war")
	var doubled := 0
	for n in m5.news:
		if str(n["kind"]) == "war" and (str(n["title"]).contains("Third Succession War") or str(n["title"]).contains("Fourth Succession War")):
			doubled += 1
	check(doubled == 0, "and no second announcement from the data")
	check(m.war_sides({"pairs": [["FS", "CC"], ["FS", "DC"], ["LA", "CC"], ["LA", "DC"]]}, 3028.7)== "the Federated Suns and the Lyran Commonwealth against the Capellan Confederation and the Draconis Combine", "the sides of a war in words: %s" % m.war_sides({"pairs": [["FS", "CC"], ["FS", "DC"], ["LA", "CC"], ["LA", "DC"]]}, 3028.7))

	check(m.war_sides({"pairs": [["CWE", "ROS"], ["CJF", "ROS"], ["CWE", "CJF"]]}, 3151.1).ends_with("each against the others"), "a three-cornered war")
	check(m.war_sides({"pairs": [["CFM", "CFM"]]}, 3050.0) == "Clan Fire Mandrill against itself", "a civil war")

	# ---------------------------------------------------------------- front lines
	var m6 := merc_at(3034, 3, 1, "Galatea")
	var rasal := sm.index_of("Rasalhague")
	check(rasal >= 0 and sm.owner_changes(3034.0, 3034.4).size() > 50, "worlds change hands in spring 3034")
	m6.location = rasal
	var mine := false
	var fronts := 0
	for k in 40:
		for e in m6.advance_day():
			if str(e["kind"]) == "news" and e.get("stop", false) and str(e["text"]).begins_with("Rasalhague now belongs to"):
				mine = true
	for n in m6.news:
		if str(n["kind"]) == "front" and str(n["text"]).contains("Free Rasalhague Republic"):
			fronts += 1
	check(fronts >= 1, "the monthly report names the new republic: %s" % str(m6.news))
	check(mine, "the world under the company's feet changing hands stops the clock")
	check(has_title(m6.news, "The Free Rasalhague Republic"), "and the timeline tells why")
	var m7 := merc_at(3030, 11, 25)
	for k in 45:
		m7.advance_day()
	var hall := false
	for n in m7.news:
		if str(n["kind"]) == "front" and str(n["text"]).contains("A hiring hall is open on Outreach"):
			hall = true
	check(hall, "a hiring hall opening is reported")

	# ---------------------------------------------------------------- the Republic and after
	check(absf(merc_at(3100, 1, 1).timeline_mult("offers") - 0.8) < 0.001 and absf(merc_at(3100, 1, 1).timeline_mult("pay") - 0.9) < 0.001, "3100: the long peace is thin for mercenaries")
	check(absf(merc_at(3133, 1, 1).timeline_mult("offers") - 1.3) < 0.001, "3133: after Gray Monday there is work")
	var m8 := merc_at(3150, 12, 20)
	var terra := false
	for k in 150:
		for e in m8.advance_day():
			if str(e["kind"]) == "news" and e.get("stop", false) and str(e["text"]).begins_with("The Battle of Terra"):
				terra = true
	check(terra and has_title(m8.news, "The ilClan"), "3151: Terra, and the ilClan")
	var late_wars := 0
	for n in m8.news:
		if str(n["kind"]) == "war":
			late_wars += 1
	check(late_wars >= 2, "and the smaller wars of 3151 from the data (%d)" % late_wars)
	m8.refresh_markets()
	check(m8.market_units.size() > 0, "a market in 3151")

	# the map follows: planet owners run to 3152
	var solaris := sm.index_of("Solaris")
	var terra_i := sm.index_of("Terra")
	check(sm.owner(solaris, 3145.0) == "LA" and sm.owner(solaris, 3146.0) == "CWE", "Solaris is Lyran, then the Wolf Empire's")
	check(sm.owner(terra_i, 3140.0) == "ROS" and sm.owner(terra_i, 3152.5) == "SL3", "Terra is the Republic's, then the Star League's")
	check(sm.owner_changes(3090.0, 3153.0).size() > 1500, "worlds change hands after 3090 (%d)" % sm.owner_changes(3090.0, 3153.0).size())
	var m9 := merc_at(3145, 9, 1, "Solaris")
	var taken := false
	for k in 40:
		for e in m9.advance_day():
			if str(e["kind"]) == "news" and e.get("stop", false) and str(e["text"]).begins_with("Solaris now belongs to"):
				taken = true
	check(taken and has_title(m9.news, "The Wolves take Solaris"), "a company on Solaris in September 3145 sees the Wolves arrive")
	var m10 := merc_at(3146, 2, 1)
	m10.refresh_markets()
	var offers46 := 0
	for k in 4:
		m10.generate_contracts()
		offers46 += m10.contract_offers.size()
	check(offers46 > 0 and m10.market_units.size() > 0, "contracts and a market at Galatea in 3146 (%d offers)" % offers46)
	for f in sm.borders(3146.0):
		check(sm.factions.has(str(f)), "every state on the 3146 map is a known faction (%s)" % f)

	# ---------------------------------------------------------------- saves
	var mpath := "user://_timeline_merc_test.json"
	check(m.save_to(mpath), "merc save")
	var ml := MercCampaign.load_from(mpath)
	check(ml != null and ml.news.size() == m.news.size() and ml.events_day == m.events_day and ml.front_day == m.front_day, "news and the timeline's place survive a save")
	var old := m.to_dict()
	old.erase("news")
	old.erase("events_day")
	old.erase("front_day")
	var mo := MercCampaign.from_dict(JSON.parse_string(JSON.stringify(old)))
	check(mo.events_day == mo.day and mo.news.is_empty(), "a save from before the timeline starts reading today")
	var late := 0
	for k in 3:
		for e in mo.advance_day():
			if str(e["kind"]) == "news":
				late += 1
	check(late == 0, "and gets no late news")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mpath))

	# ---------------------------------------------------------------- a long run: nothing breaks, the news keeps coming
	var r := merc_at(3049, 6, 1, "Outreach", 99)
	var majors := 0
	for k in 1200:
		for e in r.advance_day():
			if str(e["kind"]) == "news" and e.get("stop", false):
				majors += 1
	check(majors >= 2, "three and a half years across the Clan invasion: %d major stops" % majors)
	check(has_title(r.news, "Tukayyid") and has_title(r.news, "Radstadt"), "the invasion is told")
	check(r.news.size() <= int(r.rules["timeline"]["news_kept"]), "the news list stays bounded")
	var kinds := {}
	for n in r.news:
		kinds[str(n["kind"])] = int(kinds.get(str(n["kind"]), 0)) + 1
	print("news over 1200 days from mid-3049: ", kinds)
	print("TIMELINE TEST DONE, fails: %d" % fails)
	quit()
