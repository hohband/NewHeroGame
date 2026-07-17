extends GutTest
## EffectSystem：原子效果解析（数据表说明词表）与已注册效果的执行（phys_dmg / rage）。

func test_parse_basic() -> void:
	var effs := EffectSystem.parse_effects("phys_dmg(1.0);rage(+20)")
	assert_eq(effs.size(), 2)
	assert_eq(effs[0]["name"], "phys_dmg")
	assert_eq(effs[0]["args"], ["1.0"])
	assert_eq(effs[0]["times"], 1)
	assert_eq(effs[1]["name"], "rage")
	assert_eq(effs[1]["args"], ["+20"])

func test_parse_multi_hit() -> void:
	var effs := EffectSystem.parse_effects("phys_dmg(0.9)x4")
	assert_eq(effs.size(), 1)
	assert_eq(effs[0]["times"], 4)
	assert_eq(effs[0]["args"], ["0.9"])

func test_parse_comma_args() -> void:
	var effs := EffectSystem.parse_effects("debuff_mgc(0.3,2)")
	assert_eq(effs[0]["args"], ["0.3", "2"])

func test_parse_paramless() -> void:
	var effs := EffectSystem.parse_effects("swap_position;pull_to_front")
	assert_eq(effs.size(), 2)
	assert_eq(effs[0]["name"], "swap_position")
	assert_eq(effs[0]["args"].size(), 0)

func test_parse_all_csv_skills() -> void:
	var loader = autofree(GameDataLoader.new())
	loader.load_all()
	for id in loader.skills:
		var effs := EffectSystem.parse_effects(loader.skills[id].effects)
		assert_gt(effs.size(), 0, "技能 %s 应解析出至少一个效果" % id)

func test_execute_generic_melee() -> void:
	# 普攻闭环：伤害事件 + 怒气事件；行动 +20 / 受击 +10（策划文档 6.5、决策日志 D7）
	var loader = autofree(GameDataLoader.new())
	loader.load_all()
	var grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4)))
	var a = autofree(UnitFactory.make_unit(100, 0, 50, Unit.Team.PLAYER, Vector2i(0, 0)))
	var t = autofree(UnitFactory.make_unit(0, 50, 50, Unit.Team.ENEMY, Vector2i(1, 0)))
	t.facing = Vector2i(-1, 0)   # 面向攻击者（正面，无方位加成）
	grid.place_unit(a, Vector2i(0, 0))
	grid.place_unit(t, Vector2i(1, 0))
	var ctx := EffectContext.new(a, t, grid, FixedRollSource.new())
	var events := EffectSystem.execute(loader.get_skill(&"generic_melee"), ctx)
	assert_eq(events.size(), 2, "伤害事件 + 怒气事件")
	assert_eq(events[0]["type"], "damage")
	assert_eq(events[0]["amount"], 67)
	assert_eq(t.hp, 433)
	assert_eq(a.rage, 20, "普攻 +20 怒气")
	assert_eq(t.rage, 10, "受击 +10 怒气")

func test_execute_kill_grants_bonus_rage() -> void:
	var loader = autofree(GameDataLoader.new())
	loader.load_all()
	var grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4)))
	var a = autofree(UnitFactory.make_unit(100, 0, 50, Unit.Team.PLAYER, Vector2i(0, 0)))
	var t = autofree(UnitFactory.make_unit(0, 50, 50, Unit.Team.ENEMY, Vector2i(1, 0)))
	t.facing = Vector2i(-1, 0)
	t.hp = 10
	grid.place_unit(a, Vector2i(0, 0))
	grid.place_unit(t, Vector2i(1, 0))
	var ctx := EffectContext.new(a, t, grid, FixedRollSource.new())
	var events := EffectSystem.execute(loader.get_skill(&"generic_melee"), ctx)
	assert_true(events[0]["died"])
	assert_eq(events[0]["amount"], 10, "伤害不超过剩余生命")
	assert_eq(a.rage, 50, "普攻 +20，击杀 +30（策划文档 6.5）")

func test_unimplemented_effect_does_not_crash() -> void:
	var skill := SkillData.new()
	skill.skill_id = &"test_unknown"
	skill.effects = "stun(1)"
	var events := EffectSystem.execute(skill, EffectContext.new())
	assert_eq(events.size(), 0, "未实现效果：报错跳过，不崩溃、不产生事件")
	assert_push_error("未实现的原子效果")
