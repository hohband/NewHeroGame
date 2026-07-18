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
	skill.effects = "nonexistent_effect(1)"   # 词表外的非法效果
	var events := EffectSystem.execute(skill, EffectContext.new())
	assert_eq(events.size(), 0, "未实现效果：报错跳过，不崩溃、不产生事件")
	assert_push_error("未实现的原子效果")

# ---------------------------------------------------------------- Buff 系效果

func _skill(id: StringName, effects: String) -> SkillData:
	var s := SkillData.new()
	s.skill_id = id
	s.name = String(id)
	s.effects = effects
	return s

func _buff_ctx() -> Dictionary:
	var loader = autofree(GameDataLoader.new())
	loader.load_all()
	var grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4)))
	var a = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.PLAYER, Vector2i(0, 0)))
	var t = autofree(UnitFactory.make_unit(0, 50, 50, Unit.Team.ENEMY, Vector2i(1, 0)))
	grid.place_unit(a, Vector2i(0, 0))
	grid.place_unit(t, Vector2i(1, 0))
	return {"grid": grid, "actor": a, "target": t}

func test_effect_def_up() -> void:
	var f: Dictionary = _buff_ctx()
	var ctx := EffectContext.new(f["actor"], f["actor"], f["grid"], FixedRollSource.new())
	var events := EffectSystem.execute(_skill(&"t", "def_up(0.3,1)"), ctx)
	assert_eq(f["actor"].get_def(f["grid"]), 65, "50 × 1.3（0.3 = 30%，决策日志 D15）")
	assert_eq(events[0]["type"], "buff")

func test_effect_armor_break_is_debuff() -> void:
	var f: Dictionary = _buff_ctx()
	var ctx := EffectContext.new(f["actor"], f["target"], f["grid"], FixedRollSource.new())
	EffectSystem.execute(_skill(&"t", "armor_break(0.3,2)"), ctx)
	assert_eq(f["target"].get_def(f["grid"]), 35, "50 × 0.7")
	assert_true(f["target"].buffs[0].is_debuff)
	assert_eq(f["target"].buffs[0].duration, 2)

func test_effect_poison_and_dispel() -> void:
	var f: Dictionary = _buff_ctx()
	var ctx := EffectContext.new(f["actor"], f["target"], f["grid"], FixedRollSource.new())
	EffectSystem.execute(_skill(&"t", "poison(2)"), ctx)
	assert_eq(f["target"].buffs.size(), 1)
	assert_true(f["target"].buffs[0].is_debuff, "中毒为减益")
	f["target"].tick_turn_start()
	assert_eq(f["target"].hp, 475, "中毒每跳 5% 最大生命")
	var events := EffectSystem.execute(_skill(&"t", "dispel(1)"), ctx)
	assert_eq(events[0]["removed"], [&"poison"])
	assert_eq(f["target"].buffs.size(), 0)

func test_effect_heal_uses_caster_mgc() -> void:
	var f: Dictionary = _buff_ctx()
	f["actor"].data.mgc = 100
	f["target"].hp = 100
	var ctx := EffectContext.new(f["actor"], f["target"], f["grid"], FixedRollSource.new())
	var events := EffectSystem.execute(_skill(&"t", "heal(1.5)"), ctx)
	assert_eq(events[0]["amount"], 150, "治疗 = 谋略 100 × 1.5（决策日志 D19）")
	assert_eq(f["target"].hp, 250)

func test_effect_move_mod() -> void:
	var f: Dictionary = _buff_ctx()
	var ctx := EffectContext.new(f["actor"], f["actor"], f["grid"], FixedRollSource.new())
	EffectSystem.execute(_skill(&"t", "move_mod(+2,1)"), ctx)
	assert_eq(f["actor"].get_move(f["grid"]), 5)

func test_random_buff_picks_first_option() -> void:
	var f: Dictionary = _buff_ctx()
	var ctx := EffectContext.new(f["actor"], f["actor"], f["grid"], FixedRollSource.new([0.0]))
	EffectSystem.execute(_skill(&"t", "random_buff(def_up,0.4,2|counter,1)"), ctx)
	assert_eq(f["actor"].get_def(f["grid"]), 70, "50 × 1.4，选中第一选项")

func test_random_buff_middle_option_reachable() -> void:
	var f: Dictionary = _buff_ctx()
	var ctx := EffectContext.new(f["actor"], f["actor"], f["grid"], FixedRollSource.new([50.0]))
	EffectSystem.execute(_skill(&"t", "random_buff(def_up,0.4,2|counter,1|dodge_up,0.1,1)"), ctx)
	assert_true(f["actor"].has_status(&"counter"), "三选项时 50% 判定值命中中间选项（均匀选取）")

func test_random_buff_unimplemented_option_safe() -> void:
	var f: Dictionary = _buff_ctx()
	var ctx := EffectContext.new(f["actor"], f["actor"], f["grid"], FixedRollSource.new([99.0]))
	EffectSystem.execute(_skill(&"t", "random_buff(def_up,0.4,2|nonexistent_fx,1)"), ctx)
	assert_eq(f["actor"].get_def(f["grid"]), 50, "选中未实现选项：报错跳过")
	assert_push_error("未实现的原子效果")
