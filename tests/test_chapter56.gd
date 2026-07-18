extends GutTest
## 第五/六章（江州劫法场、三打祝家庄）：关卡有效性与解锁链路（决策日志 D32）

var loader: GameDataLoader
var profile: PlayerProfile

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	profile = PlayerProfile.new_default(loader)

func test_ch05_ch06_levels_valid() -> void:
	for id in ["ch05_01", "ch05_02", "ch06_01", "ch06_02", "ch06_03"]:
		var l := LevelRegistry.get_level(id)
		assert_not_null(l, id)
		assert_gt(l.enemies.size(), 0, "%s 有敌人" % id)
		for spec in l.enemies + l.npc_allies:
			var c: Vector2i = spec["coords"]
			assert_true(c.x >= 0 and c.y >= 0 and c.x < l.grid_size.x and c.y < l.grid_size.y,
				"%s 的 %s 坐标在棋盘内" % [id, spec["unit"]])
			assert_not_null(loader.get_unit(spec["unit"]), "%s 的 %s 在数据表" % [id, spec["unit"]])

func test_ch05_01_features_likui() -> void:
	var l := LevelRegistry.get_level("ch05_01")
	assert_true(l.required_units.has(&"li_kui"), "劫法场李逵必出（剧情）")
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, l)
	assert_true(m.deployed.any(func(u): return u.data.unit_id == &"li_kui"))

func test_ch05_02_zhangshun_npc_in_water() -> void:
	var l := LevelRegistry.get_level("ch05_02")
	assert_true(l.npc_allies.any(func(s): return s["unit"] == &"zhang_shun"), "张顺 NPC 水中接应")
	assert_eq(l.terrain_map[Vector2i(4, 7)], &"water", "南侧水面")
	assert_true(loader.get_unit(&"zhang_shun").traits.has(&"water_walker"), "张顺水战特性")

func test_hu_sanniang_granted_on_ch06_clear() -> void:
	# 扈三娘 = 第6章「三打祝家庄」通关解锁（CSV 原值，走 D32 通关解锁规则）
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, LevelRegistry.get_level("ch06_03"))
	assert_not_null(m.boss_unit)
	var s := Flow.apply_battle_result(profile, LevelRegistry.get_level("ch06_03"),
		m.compute_result(Unit.Team.PLAYER), [], loader)
	assert_true(profile.has_hero(&"hu_sanniang"), "通关第六章解锁扈三娘")
	assert_true((s["unlocked"] as Array).has(&"hu_sanniang"))
	assert_eq(int(profile.progress["chapter"]), 7, "第六章通关后进入第七章（大聚义，M4）")

func test_chapter4_also_grants_likui() -> void:
	# 李逵 = 第4章剧情加入：通关第三章终关抵达第四章时发放（D32 抵达规则）
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, LevelRegistry.get_level("ch03_01"))
	Flow.apply_battle_result(profile, LevelRegistry.get_level("ch03_01"),
		m.compute_result(Unit.Team.PLAYER), [], loader)
	assert_true(profile.has_hero(&"li_kui"), "李逵第4章剧情加入")
	assert_true(profile.has_hero(&"xu_ning"), "徐宁同批")
