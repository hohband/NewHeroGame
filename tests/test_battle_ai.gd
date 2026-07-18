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

# ---------------------------------------------------------------- D26 占位收口（表15：连线掩护/控制高价值/增益核心；光环实判；医者退化）

func test_vanguard_cover_line_bonus() -> void:
	# 敌人 (4,2) → 队友 (4,6) 的连线格为 (4,3)(4,4)(4,5)
	var vg = autofree(UnitFactory.make_unit(80, 50, 60, Unit.Team.ENEMY, Vector2i(1, 1)))
	vg.data.unit_class = &"vanguard"
	var ally = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.ENEMY, Vector2i(4, 6), &"ally"))
	var foe = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.PLAYER, Vector2i(4, 2)))
	grid.place_unit(vg, Vector2i(1, 1))
	grid.place_unit(ally, Vector2i(4, 6))
	grid.place_unit(foe, Vector2i(4, 2))
	var m := _manager([vg, ally, foe])
	assert_eq(BattleAI._class_special(vg, null, Vector2i(4, 4), m, 0.0, 1), 25.0, "落点在敌我连线格 +25（表15）")
	assert_eq(BattleAI._class_special(vg, null, Vector2i(4, 5), m, 0.0, 1), 35.0, "连线格 + 相邻队友 = 25+10")
	assert_eq(BattleAI._class_special(vg, null, Vector2i(5, 4), m, 0.0, 1), 0.0, "落点不在连线格无加分")

func test_strategist_control_high_value_bonus() -> void:
	# 高价值目标（医者，表13 最高档 30）被控制技能命中 +40
	var st = autofree(UnitFactory.make_unit(50, 50, 60, Unit.Team.ENEMY, Vector2i(4, 4)))
	st.data.unit_class = &"strategist"
	var inf = autofree(UnitFactory.make_unit(50, 50, 60, Unit.Team.ENEMY, Vector2i(1, 1), &"inf"))
	var healer_t = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(4, 5), &"healer_t"))
	healer_t.data.unit_class = &"healer"
	var vg_t = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(4, 3), &"vg_t"))
	vg_t.data.unit_class = &"vanguard"
	grid.place_unit(st, Vector2i(4, 4))
	grid.place_unit(inf, Vector2i(1, 1))
	grid.place_unit(healer_t, Vector2i(4, 5))
	grid.place_unit(vg_t, Vector2i(4, 3))
	var m := _manager([st, inf, healer_t, vg_t])
	var control: SkillData = loader.get_skill(&"act_yaojiu")    # sleep(1);hit_rate(0.8)，纯控制
	var nuke: SkillData = loader.get_skill(&"ult_fengxue")      # 纯伤害，非控制
	assert_eq(BattleAI._control_high_value_bonus(st, control, healer_t, m), 40.0, "谋士控制命中高价值 +40（表15）")
	assert_eq(BattleAI._control_high_value_bonus(st, control, vg_t, m), 0.0, "低价值目标不加分")
	assert_eq(BattleAI._control_high_value_bonus(st, nuke, healer_t, m), 0.0, "非控制技能不加分")
	assert_eq(BattleAI._control_high_value_bonus(inf, control, healer_t, m), 0.0, "非谋士职业不加分")
	# 技能评分整合：命中目标换成低价值职业后，分差 = 目标价值差 × 权重 + 40
	var w := loader.get_ai_weights(&"strategist")
	var s1 := BattleAI._score_skill(st, control, st.coords, m, w)
	healer_t.data.unit_class = &"vanguard"
	var s2 := BattleAI._score_skill(st, control, st.coords, m, w)
	assert_almost_eq(s1 - s2, 20.0 * float(w["target_value"]) + 40.0, 0.01, "分差 = 目标价值差 + 控制高价值 +40")

func test_support_buff_core_bonus() -> void:
	# 羁绊在场激活 = 阵容核心（D26 改判）；辅助增益命中核心 +25（表15）
	var dz := _csv_unit(&"dai_zong", Unit.Team.ENEMY, Vector2i(2, 2))
	var core = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.ENEMY, Vector2i(3, 3), &"core_u"))
	var partner = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.ENEMY, Vector2i(5, 5), &"partner_u"))
	var bond: Array[Dictionary] = [{"target": &"partner_u", "name": "测试羁绊"}]
	core.data.bonds = bond
	grid.place_unit(core, Vector2i(3, 3))
	grid.place_unit(partner, Vector2i(5, 5))
	var m := _manager([dz, core, partner])
	var buff_skill: SkillData = loader.get_skill(&"act_shenxing")   # ally 全队增益
	var w := loader.get_ai_weights(&"support")
	var before := BattleAI._score_skill(dz, buff_skill, dz.coords, m, w)
	BondSystem.apply_bonds(m.units, loader.progression)
	var after := BattleAI._score_skill(dz, buff_skill, dz.coords, m, w)
	assert_true(BattleAI._is_core(core), "羁绊激活后为阵容核心")
	assert_false(BattleAI._is_core(partner), "单向羁绊只有持有者一方挂加成")
	assert_almost_eq(after - before, 25.0, 0.01, "增益命中羁绊核心 +25（表15）")
	assert_almost_eq(BattleAI._target_value(core, m) - BattleAI._target_value(partner, m), 15.0, 0.01, "羁绊核心目标价值 +15（D26 改判）")

func test_aura_coverage_uses_real_radius() -> void:
	# 真实光环（Buff.aura_radius，D27）：落点在半径内 +1/源；无光环时落点旁有队友也不计（不再按 2 格代理）
	var u = autofree(UnitFactory.make_unit(50, 50, 60, Unit.Team.ENEMY, Vector2i(4, 4)))
	var holder = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.ENEMY, Vector2i(0, 0), &"holder"))
	var mate = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.ENEMY, Vector2i(4, 5), &"mate"))
	grid.place_unit(u, Vector2i(4, 4))
	grid.place_unit(holder, Vector2i(0, 0))
	grid.place_unit(mate, Vector2i(4, 5))
	var m := _manager([u, holder, mate])
	assert_eq(BattleAI._aura_coverage(u, Vector2i(4, 4), m), 0.0, "无光环：落点旁有队友也不计（D26 改判）")
	var aura := Buff.new()
	aura.buff_id = &"aura_test"
	aura.aura_radius = 3
	aura.aura_mods = {&"atk": 15}
	holder.add_buff(aura)
	assert_eq(BattleAI._aura_coverage(u, Vector2i(0, 3), m), 1.0, "落点在光环半径内 +1")
	assert_eq(BattleAI._aura_coverage(u, Vector2i(0, 4), m), 0.0, "落点超出光环半径不计")

func test_aura_coverage_self_source() -> void:
	# 自身为光环源：落点光环能罩住的队友数
	var u = autofree(UnitFactory.make_unit(50, 50, 60, Unit.Team.ENEMY, Vector2i(4, 4)))
	var mate = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.ENEMY, Vector2i(4, 5), &"mate"))
	var far = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.ENEMY, Vector2i(0, 0), &"far"))
	grid.place_unit(u, Vector2i(4, 4))
	grid.place_unit(mate, Vector2i(4, 5))
	grid.place_unit(far, Vector2i(0, 0))
	var m := _manager([u, mate, far])
	var aura := Buff.new()
	aura.buff_id = &"aura_test"
	aura.aura_radius = 3
	aura.aura_mods = {&"atk": 15}
	u.add_buff(aura)
	assert_eq(BattleAI._aura_coverage(u, Vector2i(4, 4), m), 1.0, "自身光环从落点罩住 1 名队友")
	assert_eq(BattleAI._aura_coverage(u, Vector2i(2, 2), m), 0.0, "落点远了罩不到队友")

func test_healer_falls_back_to_support_scoring() -> void:
	# 无治疗需求：治疗技能本身不施放（维持原行为）；医者的增益技能按辅助口径评分（命中核心 +25，表15）
	var an := _csv_unit(&"an_daoquan", Unit.Team.PLAYER, Vector2i(4, 4))
	var core = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.PLAYER, Vector2i(4, 5), &"core_u"))
	var partner = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.PLAYER, Vector2i(6, 6), &"partner_u"))
	var bond: Array[Dictionary] = [{"target": &"partner_u", "name": "测试羁绊"}]
	core.data.bonds = bond
	grid.place_unit(core, Vector2i(4, 5))
	grid.place_unit(partner, Vector2i(6, 6))
	var m := _manager([an, core, partner])
	var w := loader.get_ai_weights(&"healer")
	var heal_skill: SkillData = loader.get_skill(&"act_miaoshou")
	assert_eq(BattleAI._score_skill(an, heal_skill, an.coords, m, w), -99999.0, "全员满血：治疗技能不施放（维持原行为）")
	# 医者持有增益技能（合成）：按辅助评分，命中羁绊核心 +25
	var buff_skill := SkillData.new()
	buff_skill.skill_id = &"act_test_buff"
	buff_skill.type = &"active"
	buff_skill.range_shape = &"diamond"
	buff_skill.range_min = 0
	buff_skill.range_max = 2
	buff_skill.target = &"ally"
	buff_skill.effects = "buff(atk+0.2,2)"
	var before := BattleAI._score_skill(an, buff_skill, an.coords, m, w)
	BondSystem.apply_bonds(m.units, loader.progression)
	var after := BattleAI._score_skill(an, buff_skill, an.coords, m, w)
	assert_almost_eq(after - before, 25.0, 0.01, "医者退化为辅助评分：增益命中核心 +25（表15）")
