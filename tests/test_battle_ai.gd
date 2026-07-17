extends GutTest
## BattleAI：评分制决策（策划文档第八章）、分职业权重、半自动绝技门、集火目标、全自动整局。

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

# ---------------------------------------------------------------- 权重表

func test_ai_weights_loaded() -> void:
	assert_eq(loader.ai_weights.size(), 7, "7 个职业权重行")
	assert_eq(loader.ai_weights[&"vanguard"]["damage_expect"], 0.6)
	assert_eq(loader.ai_weights[&"healer"]["danger"], 2.0)
	assert_eq(loader.validate().size(), 0, "权重表与武将表职业一致")

# ---------------------------------------------------------------- 基础决策

func test_ai_attacks_when_enemy_in_range() -> void:
	var u = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.ENEMY, Vector2i(4, 4)))
	var e = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(4, 5)))
	grid.place_unit(u, Vector2i(4, 4))
	grid.place_unit(e, Vector2i(4, 5))
	var m := _manager([u, e])
	var plan := BattleAI.decide(u, m)
	var has_attack := plan.any(func(c): return c is AttackCommand)
	assert_true(has_attack, "敌人在范围内应攻击而非待机")

func test_ai_prefers_killable_target() -> void:
	var u = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.ENEMY, Vector2i(4, 3)))
	var full = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(4, 4)))
	var weak = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(4, 2)))
	weak.hp = 1
	grid.place_unit(u, Vector2i(4, 3))
	grid.place_unit(full, Vector2i(4, 4))
	grid.place_unit(weak, Vector2i(4, 2))
	var m := _manager([u, full, weak])
	var plan := BattleAI.decide(u, m)
	var atk := plan.filter(func(c): return c is AttackCommand)
	assert_eq(atk.size(), 1)
	assert_eq(atk[0].target, weak, "击杀奖励 +50 应锁定残血目标（表13）")

func test_ai_moves_toward_enemy_when_out_of_range() -> void:
	var u = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.ENEMY, Vector2i(0, 0)))
	u.data.move = 3
	var e = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(7, 7)))
	grid.place_unit(u, Vector2i(0, 0))
	grid.place_unit(e, Vector2i(7, 7))
	var m := _manager([u, e])
	var plan := BattleAI.decide(u, m)
	assert_gt(plan.size(), 0)
	assert_true(plan[0] is MoveCommand, "够不着敌人应先接近")
	var mv: MoveCommand = plan[0]
	var before: int = absi(0 - 7) + absi(0 - 7)
	var after: int = absi(mv.path.back().x - 7) + absi(mv.path.back().y - 7)
	assert_lt(after, before, "移动后距离更近")

func test_archer_keeps_safe_distance() -> void:
	var archer = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.ENEMY, Vector2i(4, 4), &"archer"))
	archer.data.unit_class = &"archer"
	archer.data.range_min = 3
	archer.data.range_max = 5
	archer.data.move = 4
	var e = autofree(UnitFactory.make_unit(100, 50, 40, Unit.Team.PLAYER, Vector2i(4, 5)))
	grid.place_unit(archer, Vector2i(4, 4))
	grid.place_unit(e, Vector2i(4, 5))
	var m := _manager([archer, e])
	var plan := BattleAI.decide(archer, m)
	var mv := plan.filter(func(c): return c is MoveCommand)
	assert_gt(mv.size(), 0, "神射应拉开距离（安全距离 −40，表15）")
	var dest: Vector2i = mv[0].path.back()
	assert_gt(absi(dest.x - e.coords.x) + absi(dest.y - e.coords.y), 3, "落点应在 3 格安全距离外")
	var atk := plan.filter(func(c): return c is AttackCommand)
	assert_eq(atk.size(), 1, "拉开后仍在射程内应攻击")

# ---------------------------------------------------------------- 职业技能与半自动

func test_healer_heals_wounded_ally() -> void:
	var an := _csv_unit(&"an_daoquan", Unit.Team.PLAYER, Vector2i(4, 4))
	var ally = autofree(UnitFactory.make_unit(100, 50, 60, Unit.Team.PLAYER, Vector2i(4, 5)))
	ally.hp = 100   # 20%，濒危
	var enemy = autofree(UnitFactory.make_unit(100, 50, 40, Unit.Team.ENEMY, Vector2i(0, 0)))
	grid.place_unit(ally, Vector2i(4, 5))
	grid.place_unit(enemy, Vector2i(0, 0))
	var m := _manager([an, ally, enemy])
	var plan := BattleAI.decide(an, m)
	var skills := plan.filter(func(c): return c is SkillCommand)
	assert_eq(skills.size(), 1, "医者应对濒危队友施放治疗（表15：濒危 +60）")
	assert_eq(skills[0].skill.skill_id, &"act_miaoshou")

func test_semi_auto_blocks_ult_until_condition_met() -> void:
	var lc := _csv_unit(&"lin_chong", Unit.Team.PLAYER, Vector2i(4, 4))
	lc.rage = 100
	var enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 2)))
	grid.place_unit(enemy, Vector2i(4, 2))
	var m := _manager([lc, enemy])
	m.auto_mode = BattleManager.AutoMode.SEMI
	# 条件不满足（无击杀、命中 <2）：半自动不放绝技
	var plan := BattleAI.decide(lc, m)
	assert_true(plan.any(func(c): return c is AttackCommand), "半自动：条件不满足时用普攻")
	assert_false(plan.any(func(c): return c is SkillCommand), "半自动：绝技被条件门拦下（表16）")
	# 敌人残血可击杀 → 条件满足 → 放绝技
	enemy.hp = 1
	plan = BattleAI.decide(lc, m)
	var skills := plan.filter(func(c): return c is SkillCommand)
	assert_eq(skills.size(), 1, "可完成击杀时半自动放绝技")
	assert_eq(skills[0].skill.skill_id, &"ult_fengxue")

func test_full_auto_uses_ult_freely() -> void:
	var lz := _csv_unit(&"lu_zhishen", Unit.Team.ENEMY, Vector2i(4, 4))
	lz.rage = 100
	var e1 = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(4, 3)))
	var e2 = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(3, 4)))
	grid.place_unit(e1, Vector2i(4, 3))
	grid.place_unit(e2, Vector2i(3, 4))
	var m := _manager([lz, e1, e2])
	m.auto_mode = BattleManager.AutoMode.FULL
	var plan := BattleAI.decide(lz, m)
	var skills := plan.filter(func(c): return c is SkillCommand)
	assert_eq(skills.size(), 1, "全自动：AOE 绝技覆盖 2 人应优先")
	assert_eq(skills[0].skill.skill_id, &"ult_chuiyangliu")

func test_focus_target_shifts_attack() -> void:
	var u = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.ENEMY, Vector2i(4, 3)))
	var a = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(4, 4), &"a"))
	var b = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(3, 3), &"b"))
	grid.place_unit(u, Vector2i(4, 3))
	grid.place_unit(a, Vector2i(4, 4))
	grid.place_unit(b, Vector2i(3, 3))
	var m := _manager([u, a, b])
	m.set_focus_target(b)
	var plan := BattleAI.decide(u, m)
	var atk := plan.filter(func(c): return c is AttackCommand)
	assert_eq(atk[0].target, b, "集火目标评分 +100（8.5）")

# ---------------------------------------------------------------- 整局托管

func test_full_auto_battle_completes() -> void:
	var p1 := _csv_unit(&"lin_chong", Unit.Team.PLAYER, Vector2i(2, 6))
	var p2 := _csv_unit(&"lu_zhishen", Unit.Team.PLAYER, Vector2i(3, 6))
	var p3 := _csv_unit(&"an_daoquan", Unit.Team.PLAYER, Vector2i(1, 6))
	var e1 := _csv_unit(&"shi_yong", Unit.Team.ENEMY, Vector2i(4, 1))
	var e2 := _csv_unit(&"song_wan", Unit.Team.ENEMY, Vector2i(3, 1))
	var e3 := _csv_unit(&"du_qian", Unit.Team.ENEMY, Vector2i(5, 1))
	var m := _manager([p1, p2, p3, e1, e2, e3])
	m.auto_mode = BattleManager.AutoMode.FULL
	m.start_battle()
	var guard := 0
	while m.state != BattleManager.State.BATTLE_END and guard < 500:
		guard += 1
		m.run_ai()
	assert_eq(m.state, BattleManager.State.BATTLE_END, "全自动整局应在 500 回合内分出胜负")
	assert_gt(guard, 3, "战斗应持续数个回合")
