extends SceneTree
## 数值平衡模拟器（开发计划 M3 数值调优工具，决策日志 D38）：
## 无头自动对战 N 局，输出胜率/回合数/阵亡统计，代替人工试玩做第一轮 sanity 检查。
##
## 用法：
##   godot --headless --path . -s src/tools/balance_sim.gd -- --level ch01_01 --runs 20
##   godot --headless --path . -s src/tools/balance_sim.gd -- --all-story --runs 10
##
## 队伍口径：必出 + 候选池前 (max_deploy - 必出数) 名，按关卡推荐等级生成养成数值
## （对齐 7.1「推荐等级」的应有队伍强度，决策日志 D38）。

var _args := {}

func _initialize() -> void:
	_parse_args()
	var loader := GameDataLoader.new()
	loader.load_all()
	if _args.get("all_story", false):
		for id in LevelRegistry.list_ids():
			if id == "debug_01":
				continue
			_simulate_level(loader, LevelRegistry.get_level(id), int(_args.get("runs", 10)))
	else:
		var id := String(_args.get("level", "ch01_01"))
		var level := LevelRegistry.get_level(id)
		if level == null:
			printerr("未知关卡：", id)
			quit(1)
			return
		_simulate_level(loader, level, int(_args.get("runs", 20)))
	quit(0)

func _parse_args() -> void:
	var argv := OS.get_cmdline_user_args()
	var i := 0
	while i < argv.size():
		match argv[i]:
			"--level":
				i += 1
				_args["level"] = argv[i]
			"--runs":
				i += 1
				_args["runs"] = argv[i]
			"--all-story":
				_args["all_story"] = true
			"--verbose":
				_args["verbose"] = true
		i += 1

func _simulate_level(loader: GameDataLoader, level: LevelConfig, runs: int) -> void:
	var wins := 0
	var total_rounds := 0
	var total_deaths := 0
	var total_hp_ratio := 0.0
	var timeouts := 0
	for i in range(runs):
		var r := _run_once(loader, level, 1000 + i * 7)
		if r["timeout"]:
			timeouts += 1
		if r["won"]:
			wins += 1
		total_rounds += int(r["rounds"])
		total_deaths += int(r["deaths"])
		total_hp_ratio += float(r["hp_ratio"])
	var n := float(maxi(1, runs))
	print("%-28s 胜率 %5.1f%%  平均回合 %4.1f  平均阵亡 %.1f  剩余生命 %4.1f%%  超时 %d" % [
		"%s(%s)" % [level.name, level.id],
		wins / n * 100.0,
		total_rounds / n,
		total_deaths / n,
		total_hp_ratio / n * 100.0,
		timeouts,
	])

func _run_once(loader: GameDataLoader, level: LevelConfig, seed_value: int) -> Dictionary:
	var m := BattleManager.new()
	m.setup_level(loader, level)
	m.set_seed(seed_value)
	m.auto_mode = BattleManager.AutoMode.FULL
	# 合成推荐等级队伍（无养成的关卡其推荐等级多为 1，不影响）
	var profile := PlayerProfile.new()
	for id in level.required_units + level.roster:
		var ud := loader.get_unit(id)
		if ud == null:
			continue
		var h := Hero.new(id, ud.quality)
		h.level = maxi(1, level.recommended_level)
		profile.add_hero(h)
	m.apply_profile_to_deployed(profile)
	if _args.get("verbose", false):
		m.dialogue.connect(func(t): print("  [剧情] ", t))
		m.turn_started.connect(func(u): print("  [行动] ", u.data.unit_id, " hp:", u.hp))
		m.tick_events.connect(func(u, evs):
			for e in evs:
				if e.get("type") in ["collect", "status", "turn_skipped"]:
					print("  [事件] ", e.get("type"), " ", e.get("unit", e.get("target", "?")).data.unit_id if (e.get("unit", e.get("target")) != null) else ""))
		m.unit_died.connect(func(u): print("  [阵亡] ", u.data.unit_id))
	# 必出之外用候选池前若干名补满
	var cells := m._free_deploy_cells()
	var slots: int = level.max_deploy - m.deployed.size()
	for id in level.roster:
		if slots <= 0 or cells.is_empty():
			break
		m.deploy_unit(id, cells.pop_front(), profile.get_hero(id))
		slots -= 1
	m.confirm_deploy()
	var guard := 0
	while m.state != BattleManager.State.BATTLE_END and guard < 500:
		guard += 1
		m.run_ai()
	var hp_left := 0.0
	var hp_max := 0.0
	for u in m.units:
		if u.team == Unit.Team.PLAYER and not u.is_object:
			hp_left += float(maxi(0, u.hp))
			hp_max += float(u.data.hp)
	var result := {
		"won": m.check_winner() == Unit.Team.PLAYER,
		"rounds": m.round_count,
		"deaths": m._player_deaths,
		"hp_ratio": hp_left / maxf(1.0, hp_max),
		"timeout": guard >= 500,
	}
	m.queue_free()
	return result
