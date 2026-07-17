extends GutTest
## Flow：战斗结算应用（奖励/经验/成就/章节进度/武将解锁/招募，决策日志 D32）

var loader: GameDataLoader
var profile: PlayerProfile

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	profile = PlayerProfile.new_default(loader)

func _result(won := true, achievements: Array = []) -> Dictionary:
	return {"won": won, "winner": Unit.Team.PLAYER if won else Unit.Team.ENEMY, "achievements": achievements}

# ---------------------------------------------------------------- 奖励与进度

func test_first_clear_and_regular_rewards() -> void:
	var level := LevelRegistry.get_level("ch01_01")
	var gold_before: int = profile.gold
	var s := Flow.apply_battle_result(profile, level, _result(), [], loader)
	assert_true(s["first_clear"])
	assert_eq(profile.gold, gold_before + 400, "首通金币 400")
	assert_true(profile.progress["cleared"].has("ch01_01"))
	# 重复通关：regular 奖励
	var s2 := Flow.apply_battle_result(profile, level, _result(), [], loader)
	assert_false(s2["first_clear"])
	assert_eq(int(s2["rewards"].get("gold", 0)), 120)

func test_defeat_applies_nothing() -> void:
	var gold_before: int = profile.gold
	var s := Flow.apply_battle_result(profile, LevelRegistry.get_level("ch01_01"), _result(false), [], loader)
	assert_false(s["won"])
	assert_eq(profile.gold, gold_before)
	assert_eq((profile.progress["cleared"] as Array).size(), 0)

func test_achievements_persisted() -> void:
	var s := Flow.apply_battle_result(profile, LevelRegistry.get_level("ch01_01"), _result(true, ["buzhan"]), [], loader)
	assert_eq(s["achievements"], ["buzhan"])
	assert_true(profile.achievements.has("buzhan"))

# ---------------------------------------------------------------- 章节推进与解锁

func test_chapter_final_detection() -> void:
	assert_true(Flow.is_chapter_final(LevelRegistry.get_level("ch01_05"), loader), "ch01_05 是第一章终关")
	assert_false(Flow.is_chapter_final(LevelRegistry.get_level("ch01_01"), loader))
	assert_true(Flow.is_chapter_final(LevelRegistry.get_level("ch02_02"), loader))
	assert_true(Flow.is_chapter_final(LevelRegistry.get_level("ch03_01"), loader), "生辰纲是第三章（唯一关）")

func test_chapter_advance_and_hero_grants() -> void:
	# 通关第一章终关：进入第二章（无解锁）
	Flow.apply_battle_result(profile, LevelRegistry.get_level("ch01_05"), _result(), [], loader)
	assert_eq(int(profile.progress["chapter"]), 2)
	# 通关第二章终关：鲁智深（第2章通关解锁）+ 吴用/白胜（第3章剧情加入）
	var s := Flow.apply_battle_result(profile, LevelRegistry.get_level("ch02_02"), _result(), [], loader)
	assert_eq(int(profile.progress["chapter"]), 3)
	assert_true(profile.has_hero(&"lu_zhishen"), "鲁智深第2章通关解锁")
	assert_true(profile.has_hero(&"wu_yong"), "吴用第3章剧情加入（抵达第三章即发放）")
	assert_true(profile.has_hero(&"bai_sheng"))
	assert_eq((s["unlocked"] as Array).size(), 3)

func test_no_duplicate_grants() -> void:
	Flow.apply_battle_result(profile, LevelRegistry.get_level("ch02_02"), _result(), [], loader)
	var s := Flow.apply_battle_result(profile, LevelRegistry.get_level("ch02_02"), _result(), [], loader)
	assert_eq((s["unlocked"] as Array).size(), 0, "已拥有不重复发放")

# ---------------------------------------------------------------- 经验

func test_exp_to_deployed_heroes() -> void:
	var level := LevelRegistry.get_level("ch01_01")
	var h := profile.get_hero(&"shi_yong")
	assert_not_null(h)
	# 构造一个带档案的上阵单位
	var u := Unit.new()
	u.setup(loader.get_unit(&"shi_yong"), Unit.Team.PLAYER, Vector2i.ZERO)
	u.hero = h
	var s := Flow.apply_battle_result(profile, level, _result(), [u], loader)
	assert_eq(int(s["exp_each"]), 50, "第一章经验 30+20×1 = 50")
	assert_eq(h.exp, 50)

# ---------------------------------------------------------------- 招募

func test_recruit() -> void:
	profile.items["shard"] = 40
	assert_true(Flow.can_recruit(profile, &"an_daoquan", loader))
	assert_true(Flow.recruit(profile, &"an_daoquan", loader))
	assert_true(profile.has_hero(&"an_daoquan"))
	assert_eq(int(profile.items["shard"]), 20)
	assert_false(Flow.recruit(profile, &"an_daoquan", loader), "不可重复招募")
	assert_false(Flow.can_recruit(profile, &"lin_chong", loader), "非聚义厅招募渠道不可招募")

# ---------------------------------------------------------------- 关卡包完整性

func test_all_registry_levels_valid() -> void:
	for id in LevelRegistry.list_ids():
		var l := LevelRegistry.get_level(id)
		assert_not_null(l, "关卡 %s 可加载" % id)
		if l == null:
			continue
		assert_gt(l.grid_size.x, 0)
		assert_true(l.win_condition.has("type"), "%s 有胜利条件" % id)
		for spec in l.enemies:
			assert_not_null(loader.get_unit(spec["unit"]), "%s 的敌方 %s 在数据表中" % [id, spec["unit"]])
		for spec in l.npc_allies:
			assert_not_null(loader.get_unit(spec["unit"]), "%s 的NPC %s 在数据表中" % [id, spec["unit"]])
		for spec in l.enemies + l.npc_allies:
			var c: Vector2i = spec["coords"]
			assert_true(l.grid_size.x > c.x and l.grid_size.y > c.y and c.x >= 0 and c.y >= 0,
				"%s 的 %s 坐标在棋盘内" % [id, spec["unit"]])
