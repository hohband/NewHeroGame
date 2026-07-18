extends GutTest
## battle_constants.csv：战斗常数加载与查询；怒气规则（受击/击杀/待机/施放技能，策划文档 6.5）改经数据表后数值不变。

var loader: GameDataLoader
var grid: Grid

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(8, 8)))

func _manager(units: Array[Unit]) -> BattleManager:
	var m: BattleManager = autofree(BattleManager.new())
	m.setup(loader, grid, units)
	m.rolls = FixedRollSource.new()
	return m

func _csv_unit(id: StringName, team: Unit.Team, coords: Vector2i) -> Unit:
	var u := Unit.new()
	u.setup(loader.get_unit(id), team, coords)
	grid.place_unit(u, coords)
	return autofree(u)

# ---------------------------------------------------------------- 加载与查询

func test_constants_loaded_from_csv() -> void:
	assert_eq(loader.constants.size(), 54, "battle_constants.csv 54 个常数")
	assert_eq(loader.get_constant("rage_on_hit_taken", 0.0), 10.0)
	assert_eq(loader.get_constant("rage_on_kill", 0.0), 30.0)
	assert_eq(loader.get_constant("rage_on_wait", 0.0), 15.0)
	assert_eq(loader.get_constant("rage_on_skill", 0.0), 10.0)
	assert_eq(loader.get_constant("ai_kill_base", 0.0), 50.0)
	assert_eq(loader.get_constant("ai_danger_base", 0.0), -30.0)
	assert_eq(loader.get_constant("ai_target_value_healer", 0.0), 30.0)
	assert_eq(loader.get_constant("ai_target_value_strategist", 0.0), 25.0)
	assert_eq(loader.get_constant("ai_target_value_dps", 0.0), 20.0)
	assert_eq(loader.get_constant("ai_target_value_vanguard", 0.0), 10.0)
	assert_eq(loader.get_constant("ai_heal_expect_factor", 0.0), 1.2)
	assert_eq(loader.get_constant("ai_heal_urgent_bonus", 0.0), 60.0)
	assert_eq(loader.get_constant("ai_heal_overheal_factor", 0.0), 0.3)
	assert_eq(loader.get_constant("ai_vanguard_cover_line", 0.0), 25.0)
	assert_eq(loader.get_constant("ai_strategist_control_high_value", 0.0), 40.0)
	assert_eq(loader.get_constant("ai_support_buff_core", 0.0), 25.0)
	assert_eq(loader.get_constant("ai_target_value_bond_core", 0.0), 15.0)

func test_constant_required_keys_present() -> void:
	for key in GameDataLoader.CONSTANT_KEYS:
		assert_true(loader.constants.has(key), "必备战斗常数 %s" % key)
	assert_eq(loader.validate().size(), 0, "全表校验通过（含 battle_constants.csv）")

func test_get_constant_fallback_on_missing_key() -> void:
	assert_eq(loader.get_constant("no_such_key", 7.5), 7.5, "缺 key 退回 default")

# ---------------------------------------------------------------- 怒气规则（数值经 constants 后不变）

func test_wait_rage_matches_constant() -> void:
	var hero = autofree(UnitFactory.make_unit(100, 0, 80, Unit.Team.PLAYER, Vector2i(0, 0)))
	grid.place_unit(hero, Vector2i(0, 0))
	var m := _manager([hero])
	m.submit_command(WaitCommand.new(hero))
	assert_eq(hero.rage, int(loader.get_constant("rage_on_wait", 0.0)), "待机回怒 = rage_on_wait")

func test_hit_taken_rage_matches_constant() -> void:
	var hero = autofree(UnitFactory.make_unit(100, 0, 80, Unit.Team.PLAYER, Vector2i(0, 0)))
	var enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(1, 0)))
	enemy.facing = Vector2i(-1, 0)   # 正面，无方位加成
	grid.place_unit(hero, Vector2i(0, 0))
	grid.place_unit(enemy, Vector2i(1, 0))
	var m := _manager([hero, enemy])
	m.submit_command(AttackCommand.new(hero, enemy, m.basic_attack_skill(hero)))
	assert_eq(enemy.rage, int(loader.get_constant("rage_on_hit_taken", 0.0)), "受击回怒 = rage_on_hit_taken")
	assert_eq(hero.rage, 20, "普攻 +20 来自效果串 rage()，不经 constants、也不含技能回怒")

func test_kill_rage_matches_constant() -> void:
	var hero = autofree(UnitFactory.make_unit(100, 0, 80, Unit.Team.PLAYER, Vector2i(0, 0)))
	var enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(1, 0)))
	enemy.facing = Vector2i(-1, 0)
	enemy.hp = 1
	grid.place_unit(hero, Vector2i(0, 0))
	grid.place_unit(enemy, Vector2i(1, 0))
	var m := _manager([hero, enemy])
	m.submit_command(AttackCommand.new(hero, enemy, m.basic_attack_skill(hero)))
	assert_eq(hero.rage, 20 + int(loader.get_constant("rage_on_kill", 0.0)), "普攻 +20 + 击杀 rage_on_kill")

func test_skill_cast_grants_rage() -> void:
	# 林冲「风雪山神庙」：怒气 100 − 100（绝技消耗）+ rage_on_skill（策划文档 6.5 施放技能回怒）
	var lc := _csv_unit(&"lin_chong", Unit.Team.PLAYER, Vector2i(4, 4))
	lc.rage = 100
	var enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 2)))
	enemy.facing = Vector2i(0, 1)   # 正面，确保打不死（不混入击杀回怒）
	grid.place_unit(enemy, Vector2i(4, 2))
	var m := _manager([lc, enemy])
	m.submit_command(SkillCommand.new(lc, loader.get_skill(&"ult_fengxue"), Vector2i(4, 2)))
	assert_true(enemy.is_alive(), "目标存活，排除击杀回怒干扰")
	assert_eq(lc.rage, int(loader.get_constant("rage_on_skill", 0.0)), "施放技能回怒 = rage_on_skill")
