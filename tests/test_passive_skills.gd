extends GutTest
## 被动技能体系（策划 4.3：每人 1 主动 + 2 被动 + 1 绝技）。
## 触发点：on_attack（攻击命中结算后，作用于被攻击者）/ on_hit（被攻击命中后，作用于攻击者）/
## turn_start（激活开始时，作用于自身）；概率经 RollSource（chance 修饰词），结算复用 EffectSystem。

var loader: GameDataLoader
var grid: Grid

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(8, 8)))

func _manager(units: Array[Unit], values: Array[float] = [99.0]) -> BattleManager:
	var m: BattleManager = autofree(BattleManager.new())
	m.setup(loader, grid, units)
	m.rolls = FixedRollSource.new(values)
	return m

func _unit(id: StringName, atk: int, spd: int, team: Unit.Team, coords: Vector2i) -> Unit:
	var u = autofree(UnitFactory.make_unit(atk, 50, spd, team, coords, id))
	grid.place_unit(u, coords)
	return u

## 注入合成被动（与 CSV 内容隔离，测管线本身）
func _inject(owner: String, trigger: StringName, target: StringName, effects: String, id: StringName = &"pas_test") -> SkillData:
	var s := SkillData.new()
	s.skill_id = id
	s.name = "测试被动"
	s.owner = owner
	s.type = &"passive"
	s.trigger = trigger
	s.range_shape = &"self"
	s.target = target
	s.effects = effects
	loader.skills[id] = s
	return s

# ---------------------------------------------------------------- 触发点

func test_on_attack_hits_attacked_target() -> void:
	_inject("attacker", &"on_attack", &"enemy", "phys_dmg(0.5)")
	var attacker = _unit(&"attacker", 100, 80, Unit.Team.PLAYER, Vector2i(4, 4))
	var defender = _unit(&"defender", 50, 40, Unit.Team.ENEMY, Vector2i(4, 5))
	defender.facing = Vector2i(0, -1)   # 面向攻击者（正面，无方位加成）
	var m := _manager([attacker, defender])
	var hp_before: int = defender.hp
	var events := m.submit_command(AttackCommand.new(attacker, defender, m.basic_attack_skill(attacker)))
	var triggers := events.filter(func(e): return e["type"] == "passive_trigger")
	assert_eq(triggers.size(), 1, "普攻命中后触发一次 on_attack 被动")
	assert_eq(triggers[0]["skill"], &"pas_test")
	var dmgs := events.filter(func(e): return e["type"] == "damage" and e["target"] == defender)
	assert_eq(dmgs.size(), 2, "普攻 + 被动各一段伤害，均命中被攻击者")
	assert_eq(dmgs[1]["skill"], &"pas_test")
	assert_eq(dmgs[1]["source"], attacker)
	assert_eq(dmgs[1]["amount"], 33, "100 攻 × 0.5 × 100/150 = 33")
	assert_eq(hp_before - defender.hp, dmgs[0]["amount"] + dmgs[1]["amount"])

func test_on_attack_also_fires_on_skill_damage() -> void:
	_inject("attacker", &"on_attack", &"enemy", "phys_dmg(0.5)")
	var act := SkillData.new()
	act.skill_id = &"act_test"
	act.name = "测试主动"
	act.owner = "attacker"
	act.type = &"active"
	act.trigger = &"manual"
	act.range_shape = &"adjacent"
	act.range_min = 1
	act.range_max = 1
	act.target = &"enemy"
	act.effects = "phys_dmg(1.0)"
	loader.skills[&"act_test"] = act
	var attacker = _unit(&"attacker", 100, 80, Unit.Team.PLAYER, Vector2i(4, 4))
	var defender = _unit(&"defender", 50, 40, Unit.Team.ENEMY, Vector2i(4, 5))
	defender.facing = Vector2i(0, -1)
	var m := _manager([attacker, defender])
	var events := m.submit_command(SkillCommand.new(attacker, act, Vector2i(4, 5)))
	var triggers := events.filter(func(e): return e["type"] == "passive_trigger")
	assert_eq(triggers.size(), 1, "技能攻击同样触发 on_attack 被动")

func test_on_hit_counters_attacker() -> void:
	_inject("defender", &"on_hit", &"enemy", "phys_dmg(0.5)")
	var attacker = _unit(&"attacker", 100, 80, Unit.Team.PLAYER, Vector2i(4, 4))
	var defender = _unit(&"defender", 50, 40, Unit.Team.ENEMY, Vector2i(4, 5))
	defender.facing = Vector2i(0, -1)
	var m := _manager([attacker, defender])
	var hp_before: int = attacker.hp
	var events := m.submit_command(AttackCommand.new(attacker, defender, m.basic_attack_skill(attacker)))
	var counters := events.filter(func(e): return e["type"] == "damage" and e["target"] == attacker)
	assert_eq(counters.size(), 1, "被攻击命中后，on_hit 被动反作用于攻击者")
	assert_eq(counters[0]["source"], defender)
	assert_eq(counters[0]["skill"], &"pas_test")
	assert_eq(counters[0]["amount"], 17, "被动持有者 50 攻 × 0.5 × 100/150 ≈ 17")
	assert_eq(hp_before - attacker.hp, 17)

func test_turn_start_self_buff() -> void:
	_inject("hero", &"turn_start", &"self", "def_up(0.3,1)")
	var hero = _unit(&"hero", 50, 80, Unit.Team.PLAYER, Vector2i(0, 0))
	var enemy = _unit(&"enemy", 50, 40, Unit.Team.ENEMY, Vector2i(7, 7))
	var m := _manager([hero, enemy])
	m.start_battle()
	assert_eq(m.active_unit, hero, "速度 80 先激活")
	assert_eq(hero.get_stat_mod(&"def"), 30, "turn_start 被动给自身防御 +30%")
	assert_eq(hero.get_def(grid), 65, "50 防 × 1.3 = 65")

# ---------------------------------------------------------------- 概率判定（RollSource 可控）

func test_chance_controlled_by_rolls() -> void:
	_inject("attacker", &"on_attack", &"enemy", "chance(0.5);phys_dmg(0.5)")
	# rolls 全 10：chance 判定 10 < 50 → 触发
	var a1 = _unit(&"attacker", 100, 80, Unit.Team.PLAYER, Vector2i(4, 4))
	var d1 = _unit(&"defender", 50, 40, Unit.Team.ENEMY, Vector2i(4, 5))
	var m1 := _manager([a1, d1], [10.0])
	var events := m1.submit_command(AttackCommand.new(a1, d1, m1.basic_attack_skill(a1)))
	assert_eq(events.filter(func(e): return e["type"] == "passive_trigger").size(), 1, "低roll触发被动")
	# rolls 全 90：chance 判定 90 ≥ 50 → 不触发，无任何被动事件
	var a2 = _unit(&"attacker", 100, 80, Unit.Team.PLAYER, Vector2i(2, 2))
	var d2 = _unit(&"defender", 50, 40, Unit.Team.ENEMY, Vector2i(2, 3))
	var m2 := _manager([a2, d2], [90.0])
	events = m2.submit_command(AttackCommand.new(a2, d2, m2.basic_attack_skill(a2)))
	assert_eq(events.filter(func(e): return e["type"] == "passive_trigger").size(), 0, "高roll不触发")
	assert_eq(events.filter(func(e): return e["type"] == "damage").size(), 1, "只剩普攻一段伤害")

func test_passive_damage_grants_no_rage() -> void:
	# 决策日志 D41：被动附带伤害不产受击/击杀怒气（不给对面攒绝技）
	_inject("attacker", &"on_attack", &"enemy", "phys_dmg(0.5)")
	var attacker = _unit(&"attacker", 100, 80, Unit.Team.PLAYER, Vector2i(4, 4))
	var defender = _unit(&"defender", 50, 40, Unit.Team.ENEMY, Vector2i(4, 5))
	defender.facing = Vector2i(0, -1)
	var m := _manager([attacker, defender])
	m.submit_command(AttackCommand.new(attacker, defender, m.basic_attack_skill(attacker)))
	var rage_per_hit := int(loader.get_constant("rage_on_hit_taken", 0.0))
	assert_eq(defender.rage, rage_per_hit, "两段伤害只送一段受击怒气（普攻段），被动段不送")

# ---------------------------------------------------------------- 数据校验

func test_validate_real_data_clean() -> void:
	assert_eq(loader.validate().size(), 0, "真实 CSV 校验全绿（含每人 2 被动）")

func test_validate_missing_passive() -> void:
	loader.skills.erase(&"pas_shemao")   # 林冲只剩 1 个被动
	var errors := loader.validate()
	var hits := errors.filter(func(e): return e.contains("lin_chong") and e.contains("被动数量"))
	assert_eq(hits.size(), 1, "武将缺被动必须报错：%s" % [errors])

func test_validate_manual_trigger_rejected() -> void:
	var s := loader.get_skill(&"pas_shemao")
	s.trigger = &"manual"
	var errors := loader.validate()
	var hits := errors.filter(func(e): return e.contains("pas_shemao") and e.contains("manual"))
	assert_eq(hits.size(), 1, "被动 trigger=manual 必须报错：%s" % [errors])

func test_validate_illegal_trigger_rejected() -> void:
	var s := loader.get_skill(&"pas_shemao")
	s.trigger = &"on_kill"
	var errors := loader.validate()
	var hits := errors.filter(func(e): return e.contains("pas_shemao") and e.contains("非法 trigger"))
	assert_eq(hits.size(), 1, "非法 trigger 必须报错：%s" % [errors])

# ---------------------------------------------------------------- CSV 内容：60 行被动全部可解析、可执行（词表全覆盖）

func test_all_csv_passives_parse_and_execute() -> void:
	var passives: Array[SkillData] = []
	for id in loader.skills:
		var s: SkillData = loader.skills[id]
		if s.type == &"passive":
			passives.append(s)
	assert_eq(passives.size(), 60, "30 武将 × 2 被动")
	assert_eq(loader.hero_ids.size(), 30, "units.csv 武将 30 名")
	for uid in loader.hero_ids:
		var owned := loader.get_passives_for_unit(uid, &"on_attack") \
			+ loader.get_passives_for_unit(uid, &"on_hit") \
			+ loader.get_passives_for_unit(uid, &"turn_start")
		assert_eq(owned.size(), 2, "%s 恰好 2 个被动" % uid)
	# 逐个执行：rolls 全 0 → chance/sleep_chance 必触发；未进词表的效果会 push_error 且无事件
	for s in passives:
		assert_ne(s.trigger, &"manual", "%s 被动 trigger 非 manual" % s.skill_id)
		var parsed := EffectSystem.parse_effects(s.effects)
		assert_gt(parsed.size(), 0, "%s 效果串可解析" % s.skill_id)
		var owner = _unit(StringName(s.owner), 100, 80, Unit.Team.PLAYER, Vector2i(3, 3))
		var other = _unit(&"pas_target", 50, 40, Unit.Team.ENEMY, Vector2i(3, 4))
		var target = owner if s.target == &"self" else other
		var ctx := EffectContext.new(owner, target, grid, FixedRollSource.new([0.0]), null)
		ctx.depth = 1
		var events := EffectSystem.execute(s, ctx)
		assert_gt(events.size(), 0, "%s（%s）触发后必须产生事件" % [s.skill_id, s.effects])
