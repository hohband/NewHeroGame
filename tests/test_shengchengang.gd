extends GutTest
## 智取生辰纲示范关（策划文档第七章验收）：
## 地图/双方配置、夺取机制、警觉特性、T1—T6 触发器、双互斥成就、回合上限。

var loader: GameDataLoader
var manager: BattleManager

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	manager = autofree(BattleManager.new())
	manager.setup_level(loader, LevelRegistry.get_level("ch03_01"))
	manager.rolls = FixedRollSource.new()

func _u(id: StringName) -> Unit:
	return manager._find_unit(id)

func _drive_rounds(max_turns: int) -> void:
	for i in range(max_turns):
		if manager.state == BattleManager.State.BATTLE_END:
			break
		manager.finish_turn()

# ---------------------------------------------------------------- 装载（7.2/7.3）

func test_level_setup_matches_design() -> void:
	assert_eq(manager.grid.size, Vector2i(10, 8), "10×8 黄泥冈")
	assert_eq(manager.grid.get_cell(Vector2i(6, 4)).terrain.terrain_id, &"wine_stall", "酒摊互动格")
	assert_eq(manager.grid.get_cell(Vector2i(9, 0)).height, 1, "东北角高台")
	assert_eq(manager.deployed.size(), 2, "吴用、白胜必出")
	assert_true(manager.deployed.any(func(u): return u.data.unit_id == &"wu_yong"))
	assert_true(manager.deployed.any(func(u): return u.data.unit_id == &"bai_sheng"))
	assert_not_null(_u(&"chao_gai_npc"))
	assert_not_null(_u(&"liu_tang_npc"))
	assert_not_null(manager.boss_unit)
	assert_eq(manager.boss_unit.data.unit_id, &"yang_zhi_boss")
	var cargo := manager.units.filter(func(u): return u.is_object)
	assert_eq(cargo.size(), 3, "3 副生辰纲担")

func test_enemy_units_from_csv() -> void:
	assert_not_null(loader.get_unit(&"yang_zhi_boss"))
	assert_eq(loader.get_unit(&"yang_zhi_boss").hp, 1400, "杨志 HP1400（7.3）")
	assert_true(loader.get_unit(&"yang_zhi_boss").traits.has(&"alert"), "警觉特性")
	assert_eq(loader.get_unit(&"xiangjun_shield").block, 25, "刀牌格挡 25%（7.3）")
	assert_eq(loader.validate().size(), 0, "敌方数据并入后校验仍通过")

# ---------------------------------------------------------------- T1 / 彩蛋

func test_t1_intro_dialogue() -> void:
	watch_signals(manager)
	manager.start_battle()
	assert_signal_emitted(manager, "dialogue")

func test_gongsun_egg_only_when_deployed() -> void:
	manager.start_battle()
	assert_false(manager.achievement_paths.has("gongsun"), "未上阵无彩蛋（此处借路径标记判有无）")

# ---------------------------------------------------------------- T2 蒙汗药酒（7.4）

func test_t2_drugged_wine_event() -> void:
	manager.start_battle()
	var bs := _u(&"bai_sheng")
	manager.grid.move_unit(bs, Vector2i(6, 5))
	manager.submit_command(MoveCommand.new(bs, [Vector2i(6, 4)]))
	# 敌方全体睡眠 2 回合，杨志仅 1 回合（警觉）
	for u in manager.units:
		if u.team != Unit.Team.ENEMY or u.is_object:
			continue
		var dur := 0
		for b in u.buffs:
			if b.status == &"sleep":
				dur = b.duration
		if u.data.unit_id == &"yang_zhi_boss":
			assert_eq(dur, 1, "杨志因警觉仅 1 回合（7.4 T2）")
		else:
			assert_eq(dur, 2, "其余敌方睡眠 2 回合")
	assert_eq(bs.get_stat_mod(&"atk"), 25, "白胜：功臣标记 +20% 叠加生辰纲羁绊 +5%")
	assert_true(manager.achievement_paths.has("drugged_wine"), "解锁成就路线 A")

# ---------------------------------------------------------------- T3 狂暴（7.3/7.4）

func test_t3_yangzhi_rage() -> void:
	manager.start_battle()
	var boss := manager.boss_unit
	boss.hp = 650   # 46% < 50%
	var attacker := _u(&"wu_yong")
	manager.grid.move_unit(attacker, Vector2i(5, 3))
	# 把杨志旁边的物件挪开，让攻击者贴脸
	manager.grid.move_unit(boss, Vector2i(5, 2))
	manager.submit_command(AttackCommand.new(attacker, boss, manager.basic_attack_skill(attacker)))
	assert_eq(boss.get_stat_mod(&"atk"), 30, "狂暴攻+30%（羞刀难入鞘）")
	var has_regen := boss.buffs.any(func(b): return b.tick_effect.get("kind") == "hot")
	assert_true(has_regen, "每回合回血 5%")
	boss.hp = 300
	var events := boss.tick_effects()
	assert_eq(boss.hp, 370, "回血 5% × 1400 = 70")

# ---------------------------------------------------------------- T4 援军（7.4）

func test_t4_reinforce_at_round_6() -> void:
	# 防止我方在空转回合中被击杀导致提前终局
	for u in manager.units:
		u.hp = 99999
		u.data.hp = 99999
	manager.start_battle()
	var before := manager.units.size()
	_drive_rounds(120)   # 14 个行动单位，1 回合 ≈ 14 次行动，推进到第 6 回合
	assert_gt(manager.units.size(), before, "第 6 回合刷出援军（未集齐 3 担）")

func test_t4_skipped_when_collected() -> void:
	manager.collect_counts["cargo"] = 3
	assert_false(manager._trigger_if_met({"type": "collect_below", "target": "cargo", "count": 3}), "已集齐 3 担则不满足刷援军条件（7.4 T4）")
	manager.collect_counts["cargo"] = 1
	assert_true(manager._trigger_if_met({"type": "collect_below", "target": "cargo", "count": 3}))

# ---------------------------------------------------------------- 夺取机制（7.3）

func test_channel_collect_and_interrupt() -> void:
	manager.start_battle()
	var bs := _u(&"bai_sheng")
	var cargo: Unit = manager.units.filter(func(u): return u.is_object)[0]
	# 打断：先引导，受击后引导失效
	manager.grid.move_unit(bs, cargo.coords + Vector2i(0, 1))
	var events := manager.submit_command(InteractCommand.new(bs, cargo))
	assert_eq(events[0]["type"], "channel_start")
	assert_not_null(bs.channeling)
	bs.take_damage(10)
	assert_null(bs.channeling, "引导期间被攻击则打断（7.3）")
	# 重新引导并推进到白胜下回合：完成收讫
	manager.submit_command(InteractCommand.new(bs, cargo))
	manager._complete_collect(bs)
	assert_eq(int(manager.collect_counts["cargo"]), 1)
	assert_eq(manager.units.filter(func(u): return u.is_object).size(), 2, "收讫后担被移除")

func test_collect_three_wins() -> void:
	manager.start_battle()
	watch_signals(manager)
	for i in range(3):
		manager.collect("cargo")
	manager.advance_turn()
	assert_signal_emitted(manager, "battle_ended")
	assert_eq(manager.state, BattleManager.State.BATTLE_END)

func test_turn_limit_loses() -> void:
	manager.start_battle()
	_drive_rounds(200)
	assert_eq(manager.state, BattleManager.State.BATTLE_END, "10 回合未集齐判负（7.6 lose_condition）")

# ---------------------------------------------------------------- T6 与成就（7.4/7.5）

func test_t6_baisheng_down() -> void:
	manager.start_battle()
	watch_signals(manager)
	_u(&"bai_sheng").take_damage(99999)
	assert_signal_emitted(manager, "dialogue")
	var boss := manager.boss_unit
	assert_eq(boss.get_stat_mod(&"atk"), 10, "敌方士气攻+10%")

func test_achievement_buzhan() -> void:
	manager.start_battle()
	manager.achievement_paths["drugged_wine"] = true
	# 不走战斗直接结算：集 3 担获胜
	for i in range(3):
		manager.collect("cargo")
	var result := manager.compute_result(Unit.Team.PLAYER)
	assert_true(result["achievements"].has("buzhan"), "药酒路线且未杀厢军 → 不战而屈人之兵")
	assert_false(result["achievements"].has("biaoshi"), "互斥（7.5）")

func test_achievement_buzhan_blocked_by_xiangjun_kill() -> void:
	manager.start_battle()
	manager.achievement_paths["drugged_wine"] = true
	manager._kill_teams[&"xiangjun_spear"] = Unit.Team.PLAYER
	for i in range(3):
		manager.collect("cargo")
	var result := manager.compute_result(Unit.Team.PLAYER)
	assert_false(result["achievements"].has("buzhan"), "我方击杀过厢军则路线 A 失败")

func test_achievement_biaoshi() -> void:
	manager.start_battle()
	manager.boss_unit.take_damage(99999)
	var result := manager.compute_result(Unit.Team.PLAYER)
	assert_true(result["achievements"].has("biaoshi"), "击杀杨志 → 黄泥冈镖师")

func test_achievement_mutual_exclusion() -> void:
	manager.start_battle()
	manager.achievement_paths["drugged_wine"] = true
	manager.boss_unit.take_damage(99999)   # 药酒 + 杀杨志同时满足
	var result := manager.compute_result(Unit.Team.PLAYER)
	assert_eq(result["achievements"].size(), 1, "两成就互斥只取其一（决策日志 D31）")
	assert_eq(result["achievements"][0], "buzhan", "路线成就优先")

func test_rewards_present() -> void:
	var result := manager.compute_result(Unit.Team.PLAYER)
	var first: Dictionary = result["rewards"].get("first_clear", {})
	assert_eq(int(first.get("gold", 0)), 2000, "首通金币 ×2000（7.5）")
	assert_eq(int(first.get("skill_book", 0)), 3)
	assert_eq(int(first.get("shard_bai_sheng", 0)), 10)
