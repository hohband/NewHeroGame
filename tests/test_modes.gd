extends GutTest
## 玩法模式（第九章）：日常副本、演武场异步 PVP 与守方策略模板（8.6、决策日志 D34）

var loader: GameDataLoader
var profile: PlayerProfile

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	profile = PlayerProfile.new_default(loader)

# ---------------------------------------------------------------- 日常副本

func test_daily_levels_exist_and_valid() -> void:
	assert_eq(LevelRegistry.list_daily_ids().size(), 6)
	for id in LevelRegistry.list_daily_ids():
		var l := LevelRegistry.get_level(id)
		assert_eq(l.mode, "daily")
		assert_gt(l.enemies.size(), 0, "%s 有敌人" % id)
		assert_true(l.rewards.has("regular"), "%s 有可重复刷的 regular 奖励" % id)

func test_daily_exp_override() -> void:
	var l := LevelRegistry.get_level("daily_exp_1")
	assert_eq(Flow.exp_reward(l), 100, "经验本覆盖通关经验（D34）")
	var s := Flow.apply_battle_result(profile, l, {"won": true, "winner": Unit.Team.PLAYER, "achievements": []}, [], loader)
	assert_eq(int(s["exp_each"]), 100)

func test_daily_farming_rewards_repeatable() -> void:
	var l := LevelRegistry.get_level("daily_mat_1")
	var mats_before: int = int(profile.items.get("breakthrough_mat", 0))
	Flow.apply_battle_result(profile, l, {"won": true, "winner": Unit.Team.PLAYER, "achievements": []}, [], loader)
	Flow.apply_battle_result(profile, l, {"won": true, "winner": Unit.Team.PLAYER, "achievements": []}, [], loader)
	# 首通 3 + 铁匠铺 1，再刷 regular 2 + 铁匠铺 1
	assert_eq(int(profile.items["breakthrough_mat"]), mats_before + 3 + 1 + 2 + 1, "日常材料本可重复刷")

# ---------------------------------------------------------------- 守方配置与模板

func test_arena_default_defense() -> void:
	var d := ArenaSystem.get_defense(profile)
	assert_eq((d["team"] as Array).size(), 3, "默认守方为全部 3 名初始武将（不足 4 取全部）")
	assert_eq(String(d["template"]), "steady")

func test_arena_template_switch() -> void:
	ArenaSystem.set_template(profile, "aggressive")
	assert_eq(String(ArenaSystem.get_defense(profile)["template"]), "aggressive")

func test_arena_level_built_from_profile() -> void:
	var h := profile.get_hero(&"shi_yong")
	h.level = 10
	var l := ArenaSystem.build_arena_level(profile, loader)
	assert_eq(l.mode, "arena")
	assert_eq(l.enemies.size(), 3)
	assert_eq(String(l.pvp_template), "steady")
	assert_true(l.enemies[0].has("hero"), "守方按养成数值生成")

# ---------------------------------------------------------------- 模板对 AI 的修正（8.6）

func _arena_battle(template: String) -> BattleManager:
	ArenaSystem.set_template(profile, template)
	var l := ArenaSystem.build_arena_level(profile, loader)
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, l)
	m.rolls = FixedRollSource.new()
	ArenaSystem.apply_template(m, l.pvp_template)
	return m

func test_template_weights_applied() -> void:
	var m := _arena_battle("steady")
	assert_false(m.pvp_mods.is_empty())
	assert_eq(float(m.pvp_mods["weights"]["danger"]), 1.5, "稳健防守：危险度 ×1.5")
	assert_eq(float(m.pvp_mods["weights"]["damage_expect"]), 0.8)

func test_protect_core_template() -> void:
	var m := _arena_battle("protect_core")
	assert_not_null(m.pvp_core, "保护核心模板指定核心单位")
	assert_eq(float(m.pvp_mods.get("core_danger_mult", 1.0)), 2.0, "核心承伤 ×2")

func test_aggressive_template() -> void:
	var m := _arena_battle("aggressive")
	assert_eq(float(m.pvp_mods["weights"]["kill_bonus"]), 1.5, "激进突进：击杀奖励 ×1.5")
	assert_eq(float(m.pvp_mods["weights"]["danger"]), 0.6)

func test_arena_battle_runs_and_rewards() -> void:
	var m := _arena_battle("steady")
	assert_eq(m.state, BattleManager.State.DEPLOY)
	# 布阵一名后开战，全灭守方即胜
	var w := m.deploy_unit(&"song_wan", Vector2i(4, 6))
	w.data.hp = 99999
	w.hp = 99999
	m.confirm_deploy()
	for u in m.units:
		if u.team == Unit.Team.ENEMY:
			u.take_damage(99999)
	m.advance_turn()
	assert_eq(m.state, BattleManager.State.BATTLE_END)
	var s := Flow.apply_battle_result(profile, m.level, m.compute_result(Unit.Team.PLAYER), [w], loader)
	assert_eq(int(s["rewards"].get("arena_point", 0)), 1, "演武场奖励荣誉点（占位 D34）")
