extends GutTest
## 技能框架集成测试（M1 第 3 阶段验收核心）：
## 3 个示范技能全部通过 CSV 配置驱动，程序零介入——林冲突进、鲁智深拉拽、安道全治疗。

var loader: GameDataLoader
var grid: Grid
var manager: BattleManager

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

# ---------------------------------------------------------------- 目标解析（Targeting）

func test_targeting_line_pierces() -> void:
	var caster = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(4, 4)))
	var e1 = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 2)))
	var e2 = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 5)))
	var off = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(1, 1)))
	grid.place_unit(caster, Vector2i(4, 4))
	grid.place_unit(e1, Vector2i(4, 2))
	grid.place_unit(e2, Vector2i(4, 5))
	grid.place_unit(off, Vector2i(1, 1))
	var skill := loader.get_skill(&"ult_fengxue")   # line 1-2
	var rolls := FixedRollSource.new()
	var hits := Targeting.resolve(skill, caster, Vector2i(4, 2), grid, [caster, e1, e2, off], rolls)
	assert_eq(hits.size(), 1, "向上 line 1-2 只命中 (4,2)；贯穿数受 range_max 限制")
	assert_eq(hits[0], e1)
	hits = Targeting.resolve(skill, caster, Vector2i(4, 5), grid, [caster, e1, e2, off], rolls)
	assert_eq(hits.size(), 1, "向下命中 (4,5)，距离 1")
	assert_false(hits.has(off), "斜线敌人不在 line 上")

func test_targeting_ring_chebyshev() -> void:
	var caster = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(4, 4)))
	var near_diag = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(6, 6)))   # 切比雪夫 2
	var far = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 1)))          # 切比雪夫 3
	grid.place_unit(caster, Vector2i(4, 4))
	grid.place_unit(near_diag, Vector2i(6, 6))
	grid.place_unit(far, Vector2i(4, 1))
	var skill := loader.get_skill(&"ult_chuiyangliu")   # ring 0-2
	var hits := Targeting.resolve(skill, caster, Vector2i(-1, -1), grid, [caster, near_diag, far], FixedRollSource.new())
	assert_true(hits.has(near_diag), "斜角 2 格在周身 2 范围内")
	assert_false(hits.has(far), "距离 3 超出")

func test_targeting_diamond_manhattan() -> void:
	var caster = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(4, 4)))
	var ally_diag = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(5, 5)))   # 曼哈顿 2
	var enemy_near = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 5)))
	grid.place_unit(caster, Vector2i(4, 4))
	grid.place_unit(ally_diag, Vector2i(5, 5))
	grid.place_unit(enemy_near, Vector2i(4, 5))
	var skill := loader.get_skill(&"act_miaoshou")   # diamond 0-2, target ally
	var hits := Targeting.resolve(skill, caster, Vector2i(-1, -1), grid, [caster, ally_diag, enemy_near], FixedRollSource.new())
	assert_true(hits.has(ally_diag), "斜角曼哈顿 2 在菱形 0-2 内")
	assert_false(hits.has(enemy_near), "ally 过滤掉敌人")

# ---------------------------------------------------------------- 示范技能 1：林冲「风雪山神庙」
## phys_dmg(2.2);bonus_by_self_lost_hp(1.0);refresh_on_kill(1)

func test_fengxue_low_hp_hits_harder() -> void:
	var lc := _csv_unit(&"lin_chong", Unit.Team.PLAYER, Vector2i(4, 4))
	lc.rage = 100
	var skill := loader.get_skill(&"ult_fengxue")
	# 满血一击
	var e1 = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 2)))
	e1.facing = Vector2i(0, 1)   # 面向下 = 面向林冲（正面，无方位加成）
	grid.place_unit(e1, Vector2i(4, 2))
	var m1 := _manager([lc, e1])
	var events := m1.submit_command(SkillCommand.new(lc, skill, Vector2i(4, 2)))
	var dmg_full: int = events[0]["amount"]
	assert_eq(dmg_full, 158, "108 × 2.2 × 100/150 = 158.4 → 满血无加成")
	# 残血（40%）一击：加成 = 1 + 1.0 × 0.6 = 1.6 倍
	var lc2 := _csv_unit(&"lin_chong", Unit.Team.PLAYER, Vector2i(4, 4))
	lc2.rage = 100
	lc2.hp = int(lc2.data.hp * 0.4)
	var e2 = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 2)))
	e2.facing = Vector2i(0, 1)
	grid.place_unit(e2, Vector2i(4, 2))
	var m2 := _manager([lc2, e2])
	events = m2.submit_command(SkillCommand.new(lc2, skill, Vector2i(4, 2)))
	assert_gt(events[0]["amount"], dmg_full, "血量越低伤害越高（决策日志 D21 修正前置）")

func test_fengxue_kill_grants_extra_action() -> void:
	var lc := _csv_unit(&"lin_chong", Unit.Team.PLAYER, Vector2i(4, 4))
	lc.rage = 100
	var enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 3)))
	enemy.facing = Vector2i(0, 1)
	enemy.hp = 1
	grid.place_unit(enemy, Vector2i(4, 3))
	var m := _manager([lc, enemy])
	m.submit_command(SkillCommand.new(lc, loader.get_skill(&"ult_fengxue"), Vector2i(4, 3)))
	assert_true(lc.extra_action_pending, "击杀刷新行动（refresh_on_kill，决策日志 D22）")
	assert_eq(lc.rage, 40, "绝技扣 100 怒气，施放 +10（策划 6.5），击杀 +30")

func test_fengxue_requires_rage() -> void:
	var lc := _csv_unit(&"lin_chong", Unit.Team.PLAYER, Vector2i(4, 4))
	lc.rage = 50   # 不足 100
	var enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 3)))
	grid.place_unit(enemy, Vector2i(4, 3))
	var m := _manager([lc, enemy])
	var events := m.submit_command(SkillCommand.new(lc, loader.get_skill(&"ult_fengxue"), Vector2i(4, 3)))
	assert_eq(events.size(), 0, "怒气不足无法释放")
	assert_push_error("无法使用")

# ---------------------------------------------------------------- 示范技能 2：鲁智深「倒拔垂杨柳」
## phys_dmg(1.2);pull(1);stun(1)，ring 0-2

func test_chuiyangliu_aoe_pull_and_stun() -> void:
	var lz := _csv_unit(&"lu_zhishen", Unit.Team.PLAYER, Vector2i(4, 4))
	lz.rage = 100
	var e1 = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 2)))
	var e2 = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(2, 4)))
	grid.place_unit(e1, Vector2i(4, 2))
	grid.place_unit(e2, Vector2i(2, 4))
	var m := _manager([lz, e1, e2])
	var events := m.submit_command(SkillCommand.new(lz, loader.get_skill(&"ult_chuiyangliu")))
	var dmg_events := events.filter(func(e): return e["type"] == "damage")
	assert_eq(dmg_events.size(), 2, "周身 2 格 AOE 命中两个敌人")
	var pulls := events.filter(func(e): return e["type"] == "pull" and e["cells"] > 0)
	assert_eq(pulls.size(), 2, "两个敌人都被拉近 1 格")
	assert_true(e1.coords in [Vector2i(4, 3)], "e1 被拉向鲁智深")
	assert_true(e2.coords in [Vector2i(3, 4)], "e2 被拉向鲁智深")
	var stuns := events.filter(func(e): return e["type"] == "status" and e["status"] == &"stun")
	assert_eq(stuns.size(), 2, "两个敌人都被眩晕")
	assert_false(e1.can_act(), "眩晕不可行动")

func test_stun_skips_turn_in_battle() -> void:
	var lz := _csv_unit(&"lu_zhishen", Unit.Team.PLAYER, Vector2i(4, 4))
	lz.rage = 100
	var stunned_enemy = autofree(UnitFactory.make_unit(50, 50, 50, Unit.Team.ENEMY, Vector2i(4, 2), &"fast_enemy"))
	# 慢敌放在 AOE 范围外（切比雪夫 4），不被眩晕
	var slow_enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(0, 0), &"slow_enemy"))
	grid.place_unit(stunned_enemy, Vector2i(4, 2))
	grid.place_unit(slow_enemy, Vector2i(0, 0))
	var m := _manager([lz, stunned_enemy, slow_enemy])
	m.submit_command(SkillCommand.new(lz, loader.get_skill(&"ult_chuiyangliu")))
	lz.av = 999.0   # 模拟鲁智深刚行动完
	# 快敌（速 50）本应先行动，但眩晕 1 回合 → 跳过；轮到慢敌（速 40）
	m.start_battle()
	assert_eq(m.active_unit, slow_enemy, "眩晕单位跳过行动（决策日志 D22）")

# ---------------------------------------------------------------- 示范技能 3：安道全「妙手回春」
## heal(1.5);dispel(2)，diamond 0-2，ally

func test_miaoshou_aoe_heal_and_dispel() -> void:
	var an := _csv_unit(&"an_daoquan", Unit.Team.PLAYER, Vector2i(4, 4))   # mgc 108
	var a1 = autofree(UnitFactory.make_unit(100, 50, 60, Unit.Team.PLAYER, Vector2i(5, 5)))
	var a2 = autofree(UnitFactory.make_unit(100, 50, 70, Unit.Team.PLAYER, Vector2i(4, 6)))
	grid.place_unit(a1, Vector2i(5, 5))
	grid.place_unit(a2, Vector2i(4, 6))
	a1.hp = 100
	a2.hp = 200
	var poison := Buff.new()
	poison.buff_id = &"poison"
	poison.is_debuff = true
	poison.duration = 2
	poison.tick_effect = {"kind": "dot", "percent": 5}
	a1.add_buff(poison)
	var m := _manager([an, a1, a2])
	var events := m.submit_command(SkillCommand.new(an, loader.get_skill(&"act_miaoshou")))
	var heals := events.filter(func(e): return e["type"] == "heal")
	assert_eq(heals.size(), 3, "安道全自己与两名友军都被治疗（diamond 0-2 含自身）")
	assert_eq(a1.hp, 262, "100 + 108 × 1.5 = 262")
	assert_eq(a1.buffs.size(), 0, "中毒被驱散")
	# 冷却 2 回合
	assert_eq(an.skill_cooldown(&"act_miaoshou"), 2)
	an.tick_turn_start()
	assert_eq(an.skill_cooldown(&"act_miaoshou"), 1, "持有者回合开始冷却 -1（决策日志 D24）")
	an.tick_turn_start()
	assert_eq(an.skill_cooldown(&"act_miaoshou"), 0)

func test_skill_cooldown_blocks_recast() -> void:
	var an := _csv_unit(&"an_daoquan", Unit.Team.PLAYER, Vector2i(4, 4))
	var m := _manager([an])
	m.submit_command(SkillCommand.new(an, loader.get_skill(&"act_miaoshou")))
	var events := m.submit_command(SkillCommand.new(an, loader.get_skill(&"act_miaoshou")))
	assert_eq(events.size(), 0, "冷却中无法再次施放")
	assert_push_error("无法使用")

# ---------------------------------------------------------------- 控制状态行为（决策日志 D22）

func test_sleep_breaks_on_damage() -> void:
	var u = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(0, 0)))
	var b := Buff.new()
	b.buff_id = &"sleep"
	b.status = &"sleep"
	b.duration = 2
	u.add_buff(b)
	assert_false(u.can_act(), "睡眠不可行动")
	u.take_damage(10)
	assert_true(u.can_act(), "受击解除睡眠")

func test_bind_blocks_move_not_act() -> void:
	var u = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(0, 0)))
	var b := Buff.new()
	b.buff_id = &"bind"
	b.status = &"bind"
	b.duration = 1
	u.add_buff(b)
	assert_false(u.can_move(), "束缚不可移动")
	assert_true(u.can_act(), "束缚仍可行动")

# ---------------------------------------------------------------- 修正类效果（决策日志 D21）

func test_sure_hit_bypasses_dodge() -> void:
	var caster = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(4, 4)))
	caster.rage = 100   # 绝技怒气门槛
	var t = autofree(UnitFactory.make_unit(0, 50, 40, Unit.Team.ENEMY, Vector2i(4, 2)))
	t.data.dodge = 100
	grid.place_unit(caster, Vector2i(4, 4))
	grid.place_unit(t, Vector2i(4, 2))
	var m := _manager([caster, t])
	var skill := loader.get_skill(&"ult_baibu")   # phys_dmg(2.5);sure_hit;target_rule(lowest_hp)，line 3-6
	var events := m.submit_command(SkillCommand.new(caster, skill, Vector2i(4, 2)))
	assert_eq(events.size(), 0, "目标距离 2 不在 line 3-6 内，无法施放")
	assert_push_error("无可命中目标")
	# 换到距离 4：必中穿过 100% 闪避
	grid.move_unit(t, Vector2i(4, 0))
	grid.move_unit(caster, Vector2i(4, 4))
	events = m.submit_command(SkillCommand.new(caster, skill, Vector2i(4, 0)))
	var dmg := events.filter(func(e): return e["type"] == "damage")
	assert_eq(dmg.size(), 1, "sure_hit 无视闪避（决策日志 D21）")

func test_execute_below_instant_kill() -> void:
	var caster = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(0, 0)))
	var t = autofree(UnitFactory.make_unit(0, 50, 40, Unit.Team.ENEMY, Vector2i(1, 0)))
	t.hp = 100   # 20% ≤ 25%
	grid.place_unit(caster, Vector2i(0, 0))
	grid.place_unit(t, Vector2i(1, 0))
	var m := _manager([caster, t])
	var events := m.submit_command(SkillCommand.new(caster, loader.get_skill(&"act_sangmen"), Vector2i(1, 0)))
	assert_true(events[0].get("executed", false), "残血直接斩杀（丧门剑）")
	assert_false(t.is_alive())
