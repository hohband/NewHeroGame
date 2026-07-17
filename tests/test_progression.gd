extends GutTest
## 养成系统：升级/升星/突破/武器/技能/羁绊（策划文档第四章、决策日志 D29）

var loader: GameDataLoader

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()

func _hero(id: StringName = &"lin_chong") -> Hero:
	return Hero.new(id, loader.get_unit(id).quality)

# ---------------------------------------------------------------- 参数表

func test_progression_table_loaded() -> void:
	assert_gt(loader.progression.size(), 10, "养成参数表已加载")
	assert_eq(loader.progression["star_max"], 5.0)
	assert_eq(loader.validate().size(), 0, "参数表通过校验")

# ---------------------------------------------------------------- 升级

func test_exp_and_levels() -> void:
	var h := _hero()
	assert_eq(Progression.exp_to_next(1, loader.progression), 100)
	var gained := Progression.add_exp(h, 250, loader.progression)
	assert_eq(gained, 1, "250 经验升 1 级（1→2 需 100，2→3 需 200 不够）")
	assert_eq(h.level, 2)
	assert_eq(h.exp, 150)

func test_stat_mult_growth() -> void:
	var h := _hero()
	h.level = 11   # 1 + 0.02×10 = 1.2
	var base := loader.get_unit(&"lin_chong")
	var m := Progression.stat_mult(h, base, loader.progression)
	assert_almost_eq(m, 1.2, 0.001)

func test_compute_unit_data() -> void:
	var h := _hero()
	h.level = 11
	h.star = 3        # ×1.2（星级）→ 总 1.2×1.2 = 1.44
	h.weapon_enhance = 10   # 攻 +30%
	var base := loader.get_unit(&"lin_chong")
	var d := Progression.compute_unit_data(h, base, loader.progression)
	assert_eq(d.hp, roundi(700.0 * 1.44))
	assert_eq(d.atk, roundi(108.0 * 1.44 * 1.3), "攻击另乘武器倍率")
	assert_eq(d.quality, h.quality)

# ---------------------------------------------------------------- 升星与突破

func test_star_up_cost_and_cap() -> void:
	var h := _hero()
	assert_eq(Progression.star_up_cost(h, loader.progression), 20, "1→2 星 = 10×2 碎片")
	assert_true(Progression.can_star_up(h, 20, loader.progression))
	assert_false(Progression.can_star_up(h, 19, loader.progression))
	h.star = 5
	assert_false(Progression.can_star_up(h, 999, loader.progression), "满星不可再升")

func test_breakthrough_ladder() -> void:
	var h := Hero.new(&"shi_yong", &"green")
	assert_false(Progression.can_breakthrough(h, loader.progression), "未满星不可突破")
	h.star = 5
	assert_true(Progression.breakthrough(h, loader.progression))
	assert_eq(h.quality, &"blue", "绿→蓝（4.4 聚义升星）")
	assert_true(Progression.breakthrough(h, loader.progression))
	assert_eq(h.quality, &"purple")
	h.quality = &"orange"
	assert_false(Progression.breakthrough(h, loader.progression), "橙为上限")

func test_breakthrough_stat_step() -> void:
	# 绿将基础值已按绿基调（-8%），突破到蓝：+8% 一档
	var h := Hero.new(&"shi_yong", &"blue")
	var base := loader.get_unit(&"shi_yong")
	var m := Progression.stat_mult(h, base, loader.progression)
	assert_almost_eq(m, 1.08, 0.001)

# ---------------------------------------------------------------- 武器与技能

func test_weapon_caps() -> void:
	var h := _hero()
	for i in range(12):
		Progression.weapon_enhance(h, loader.progression)
	assert_eq(h.weapon_enhance, 10, "强化上限 10")
	assert_eq(Progression.weapon_enhance_cost(h, loader.progression), 1100, "第 11 级消耗 1100 金币")
	for i in range(7):
		Progression.weapon_refine(h, loader.progression)
	assert_eq(h.weapon_refine, 5, "精炼上限 5")
	var mult := Progression.weapon_atk_mult(h, loader.progression)
	assert_almost_eq(mult, 1.55, 0.001, "1 + 0.03×10 + 0.05×5 = 1.55")

func test_skill_upgrade_and_effect_mult() -> void:
	var h := _hero()
	assert_eq(Progression.skill_upgrade_cost(h, &"ult_fengxue", loader.progression), 2)
	assert_true(Progression.skill_upgrade(h, &"ult_fengxue", loader.progression))
	assert_eq(h.skill_level(&"ult_fengxue"), 2)
	var mult := Progression.skill_effect_mult(h, &"ult_fengxue", loader.progression)
	assert_almost_eq(mult, 1.05, 0.001)
	for i in range(5):
		Progression.skill_upgrade(h, &"ult_fengxue", loader.progression)
	assert_eq(h.skill_level(&"ult_fengxue"), 5, "技能上限 5")

func test_skill_level_scales_battle_heal() -> void:
	# 战斗内生效：安道全技能 3 级（+10%）治疗 = mgc × 1.5 × 1.1
	var grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4)))
	var an: Unit = autofree(Unit.new())
	an.setup(loader.get_unit(&"an_daoquan"), Unit.Team.PLAYER, Vector2i(0, 0))
	grid.place_unit(an, Vector2i(0, 0))
	var h := Hero.new(&"an_daoquan", &"blue")
	h.skill_levels[&"act_miaoshou"] = 3
	an.hero = h
	var ally = autofree(UnitFactory.make_unit(100, 50, 60, Unit.Team.PLAYER, Vector2i(1, 0)))
	ally.hp = 100
	grid.place_unit(ally, Vector2i(1, 0))
	var m: BattleManager = autofree(BattleManager.new())
	m.setup(loader, grid, [an, ally])
	m.rolls = FixedRollSource.new()
	var events := m.submit_command(SkillCommand.new(an, loader.get_skill(&"act_miaoshou")))
	var heals := events.filter(func(e): return e["type"] == "heal" and e["target"] == ally)
	assert_eq(heals[0]["amount"], 178, "108 × 1.5 × 1.1 = 178.2 → 178（养成进战斗，D29）")

# ---------------------------------------------------------------- 羁绊

func test_bonds_activate_for_partners() -> void:
	var grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4)))
	var lc: Unit = autofree(Unit.new())
	lc.setup(loader.get_unit(&"lin_chong"), Unit.Team.PLAYER, Vector2i(0, 0))
	var lz: Unit = autofree(Unit.new())
	lz.setup(loader.get_unit(&"lu_zhishen"), Unit.Team.PLAYER, Vector2i(1, 0))
	var ws: Unit = autofree(Unit.new())
	ws.setup(loader.get_unit(&"wu_song"), Unit.Team.PLAYER, Vector2i(2, 0))
	var an: Unit = autofree(Unit.new())
	an.setup(loader.get_unit(&"an_daoquan"), Unit.Team.PLAYER, Vector2i(3, 0))
	grid.place_unit(lc, Vector2i(0, 0))
	grid.place_unit(lz, Vector2i(1, 0))
	grid.place_unit(ws, Vector2i(2, 0))
	grid.place_unit(an, Vector2i(3, 0))
	var m: BattleManager = autofree(BattleManager.new())
	m.setup(loader, grid, [lc, lz, ws, an])
	var events := BondSystem.apply_bonds(m.units, loader.progression)
	assert_gt(lc.get_stat_mod(&"atk"), 0, "林冲激活结义羁绊（鲁智深在场）")
	assert_gt(lz.get_stat_mod(&"atk"), 0, "鲁智深互激活")
	assert_gt(ws.get_stat_mod(&"atk"), 0, "武松激活二龙山羁绊（鲁智深在场）")
	assert_eq(an.get_stat_mod(&"atk"), 0, "安道全搭档张顺为预留未实装，不生效（D29）")
	assert_gt(events.size(), 0)

func test_bonds_require_same_team() -> void:
	var grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4)))
	var lc: Unit = autofree(Unit.new())
	lc.setup(loader.get_unit(&"lin_chong"), Unit.Team.PLAYER, Vector2i(0, 0))
	var lz_enemy: Unit = autofree(Unit.new())
	lz_enemy.setup(loader.get_unit(&"lu_zhishen"), Unit.Team.ENEMY, Vector2i(1, 0))
	grid.place_unit(lc, Vector2i(0, 0))
	grid.place_unit(lz_enemy, Vector2i(1, 0))
	BondSystem.apply_bonds([lc, lz_enemy], loader.progression)
	assert_eq(lc.get_stat_mod(&"atk"), 0, "敌方鲁智深不激活我方羁绊（D29）")

func test_bonds_applied_at_battle_start() -> void:
	var l := LevelConfig.new()
	l.grid_size = Vector2i(6, 6)
	l.deploy_zone = Rect2i(0, 4, 6, 2)
	l.required_units = [&"lin_chong"]
	l.roster = [&"lu_zhishen"]
	l.enemies = [{"unit": &"shi_yong", "coords": Vector2i(3, 1)}]
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, l)
	m.deploy_unit(&"lu_zhishen", Vector2i(1, 4))
	m.start_battle()
	assert_eq(m.deployed[0].get_stat_mod(&"atk"), 5, "开战自动激活羁绊（progression.csv）")
