extends SceneTree
## godot --headless --path . -s tests/test_stable_jobs.gd
## A stable hiring its fighters out: weekly job offers, who may go, the advance, the weeks away (no bouts,
## no bay work), the battle on return with damage, wounds and pay, and a save/load round trip mid-job.

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _init() -> void:
	var outcomes := {}
	var jobs_seen := 0
	for seed_v in [11, 23, 37, 58]:
		var c := Campaign.new_game("Job Stable", "Silesia", seed_v)
		var p := c.player()
		var guard := 0
		while c.merc_jobs.is_empty() and guard < 30:
			c.advance_week()
			guard += 1
		check(not c.merc_jobs.is_empty(), "a job turns up within a few weeks (seed %d)" % seed_v)
		if c.merc_jobs.is_empty():
			continue
		jobs_seen += c.merc_jobs.size()
		var job: Dictionary = c.merc_jobs[0]
		check(int(job["weeks"]) >= 2 and int(job["slots"]) >= 2 and int(job["rate"]) > 0, "job has weeks, slots and a rate")
		check(str(job["world"]) != "" and str(job["biome"]).begins_with("bf_"), "job has a world and a battlefield")
		var ok := c.job_candidates(job)
		check(not ok.is_empty(), "fighters can go")
		check(c.hire_out(int(job["id"]), []) != "", "nobody picked is refused")
		check(c.hire_out(int(job["id"]), [999999]) != "", "a stranger is refused")
		var wids: Array = ok.slice(0, int(job["slots"]))
		var pay := c.job_pay(job, wids)
		check(int(pay["fee"]) > 0 and int(pay["advance"]) > 0 and int(pay["advance"]) < int(pay["fee"]), "fee and advance")
		var cash0 := p.cash
		var uids: Array = []
		for wid in wids:
			uids.append(int(c.warriors[wid].mech_uid))
		var weeks := int(job["weeks"])
		check(c.hire_out(int(job["id"]), wids) == "", "the job is signed")
		check(p.cash == cash0 + int(pay["advance"]), "the advance is paid")
		check(c.merc_job(int(job["id"])).is_empty() and not c.deployment.is_empty(), "the job leaves the board")
		for wid in wids:
			var w: Warrior = c.warriors[wid]
			check(not w.available() and w.away_weeks == weeks, "the fighter is away")
			check(w.status_str().begins_with("Off-world"), "status says off-world")
			check(c.release(wid) != "", "can't release a fighter who is away")
		for uid in uids:
			check(c.mechs[uid].status == "away" and c.sell_mech(uid) != "", "the 'Mech is away and can't be sold")
		check(c.hire_out(int(job["id"]), wids) != "", "no second job while one runs")
		# save and load mid-job
		var c2 := Campaign.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
		check(not c2.deployment.is_empty() and typeof(c2.deployment["entries"][0]["warrior"]) == TYPE_INT, "deployment survives a save with int ids")
		check(c2.warriors[int(wids[0])].away_weeks == weeks, "away weeks survive a save")
		for k in weeks - 1:
			c2.advance_week()
			check(c2.merc_jobs.is_empty(), "no new offers while fighters are away")
			for b in c2.bookings + c2.ai_card + c2.offers:
				for wid in wids:
					check(not (int(wid) in Campaign.bout_warriors(b)), "an away fighter is not on any card")
		check(not c2.deployment.is_empty(), "still away before the last week")
		var cash1: int = c2.player().cash
		c2.advance_week()
		check(c2.deployment.is_empty(), "they are back after %d weeks" % weeks)
		var ld: Dictionary = c2.last_deployment
		check(str(ld.get("outcome", "")) in ["VICTORY", "DEFEAT", "DRAW"], "an outcome is recorded")
		outcomes[ld.get("outcome", "?")] = int(outcomes.get(ld.get("outcome", "?"), 0)) + 1
		check((ld.get("lines", []) as Array).size() == wids.size(), "one line per fighter")
		check(int(ld.get("pay", 0)) >= int(pay["advance"]), "pay is recorded")
		var found := false
		for n in c2.news:
			if str(n["kind"]) == "contract" and str(n["title"]).begins_with("Back from"):
				found = true
		check(found, "the return makes the news")
		for i in wids.size():
			var w2: Warrior = c2.warriors[int(wids[i])]
			check(w2.away_weeks == 0, "nobody is still marked away")
			check(w2.dead or not w2.history.is_empty() and str(w2.history[-1].get("kind", "")) == "contract" or w2.history.size() > 0, "the job is in the fighter's history")
			var om: OwnedMech = c2.mechs.get(int(uids[i]))
			if om == null:
				check(w2.mech_uid == -1 and not (int(uids[i]) in c2.player().mechs), "a lost 'Mech is gone everywhere")
			else:
				check(om.status in ["ready", "wrecked"], "a returned 'Mech is ready or a wreck, not away (%s)" % om.status)
		print("seed %d: %s on %s, %d 'Mechs, %s; cash change in the last week %d" % [seed_v, ld.get("label", ""), ld.get("world", ""), wids.size(), ld.get("outcome", ""), c2.player().cash - cash1])
		for l in ld.get("lines", []):
			print("   ", l)
		# determinism of the battle
		var a := c.make_job_battle(c.deployment)
		var b2 := c.make_job_battle(c.deployment)
		a.run_to_end(a.time_limit() + 60.0)
		b2.run_to_end(b2.time_limit() + 60.0)
		check(str(a.result["how"]) == str(b2.result["how"]) and is_equal_approx(float(a.result["duration"]), float(b2.result["duration"])), "the battle is deterministic")
	print("outcomes: ", outcomes, "  jobs seen: ", jobs_seen)
	print("JOBS TEST DONE, fails: %d" % fails)
	quit()
