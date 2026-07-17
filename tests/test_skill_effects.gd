extends GutTest
## 补全原子效果的集成测试（全部 26 个 CSV 技能可执行的验收）：
## mgc_dmg、swap_position、guard、counter、teleport、steal_buff、av_mod/extra_action、summon/aura。

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

func _skill(id: StringName, effects: String) -> SkillData:
	var s := SkillData.new()
	s.skill_id = id
	s.name = String(id)
	s.effects = effects
	return s

# ---------------------------------------------------------------- mgc_dmg（公孙胜五雷天罡正法）

func test_mgc_dmg_uses_mgc_not_atk() -> void:
	var gs := _csv_unit(&"gongsun_sheng", Unit.Team.PLAYER, Vector2i(4, 4))   # atk 52 / mgc 118
	gs.rage = 100
	var t = autofree(UnitFactory.make_unit(0, 50, 40, Unit.Team.ENEMY, Vector2i(4, 6)))
	t.facing = Vector2i(0, -1)   # 面向北边的攻击者（正面，无方位加成）
	grid.place_unit(t, Vector2i(4, 6))
	var m := _manager([gs, t])
	var events := m.submit_command(SkillCommand.new(gs, loader.get_skill(&"ult_wulei")))
	var dmg := events.filter(func(e): return e["type"] == "damage")
	assert_gt(dmg.size(), 0)
	# 118 × 1.5 × 100/150 = 118 → 若错用 atk 则只有 52
	assert_eq(dmg[0]["amount"], 118, "法伤应按谋略结算（决策日志 D27）")

# ---------------------------------------------------------------- swap_position（焦挺相扑绝技）

func test_swap_position_exchanges_cells() -> void:
	var jt := _csv_unit(&"jiao_ting", Unit.Team.PLAYER, Vector2i(4, 4))
	var t = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 5)))
	grid.place_unit(t, Vector2i(4, 5))
	var m := _manager([jt, t])
	m.submit_command(SkillCommand.new(jt, loader.get_skill(&"act_xiangpu")))
	assert_eq(jt.coords, Vector2i(4, 5))
	assert_eq(t.coords, Vector2i(4, 4), "摔投换位（决策日志 D23）")
	assert_true(t.has_status(&"stun"))

# ---------------------------------------------------------------- guard（宋万铁壁）

func test_guard_intercepts_ranged_attack() -> void:
	var archer = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.ENEMY, Vector2i(0, 0), &"archer"))
	archer.data.range_min = 2
	archer.data.range_max = 5
	var guarded = autofree(UnitFactory.make_unit(10, 50, 40, Unit.Team.PLAYER, Vector2i(4, 4), &"guarded"))
	var protector = autofree(UnitFactory.make_unit(200, 50, 40, Unit.Team.PLAYER, Vector2i(4, 5), &"protector"))
	grid.place_unit(archer, Vector2i(0, 0))
	grid.place_unit(guarded, Vector2i(4, 4))
	grid.place_unit(protector, Vector2i(4, 5))
	var b := Buff.new()
	b.buff_id = &"guard"
	b.status = &"guard"
	b.duration = 2
	protector.add_buff(b)
	var m := _manager([archer, guarded, protector])
	var hp_before: int = guarded.hp
	var events := m.submit_command(AttackCommand.new(archer, guarded, loader.get_skill(&"generic_ranged")))
	var dmg := events.filter(func(e): return e["type"] == "damage")
	assert_eq(dmg[0]["target"], protector, "远程攻击被相邻的 guard 拦截（决策日志 D27）")
	assert_eq(guarded.hp, hp_before, "被保护者不掉血")

func test_guard_does_not_intercept_melee() -> void:
	var melee = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.ENEMY, Vector2i(4, 3)))
	var guarded = autofree(UnitFactory.make_unit(10, 50, 40, Unit.Team.PLAYER, Vector2i(4, 4), &"guarded"))
	var protector = autofree(UnitFactory.make_unit(200, 50, 40, Unit.Team.PLAYER, Vector2i(4, 5), &"protector"))
	grid.place_unit(melee, Vector2i(4, 3))
	grid.place_unit(guarded, Vector2i(4, 4))
	grid.place_unit(protector, Vector2i(4, 5))
	var b := Buff.new()
	b.buff_id = &"guard"
	b.status = &"guard"
	b.duration = 2
	protector.add_buff(b)
	var m := _manager([melee, guarded, protector])
	var events := m.submit_command(AttackCommand.new(melee, guarded, loader.get_skill(&"generic_melee")))
	var dmg := events.filter(func(e): return e["type"] == "damage")
	assert_eq(dmg[0]["target"], guarded, "近战不触发挡刀")

# ---------------------------------------------------------------- counter（杜迁摸着天）

func test_counter_strikes_back_in_range() -> void:
	var atk_unit = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.ENEMY, Vector2i(4, 3)))
	var defender = autofree(UnitFactory.make_unit(60, 50, 40, Unit.Team.PLAYER, Vector2i(4, 4)))
	grid.place_unit(atk_unit, Vector2i(4, 3))
	grid.place_unit(defender, Vector2i(4, 4))
	var b := Buff.new()
	b.buff_id = &"counter"
	b.status = &"counter"
	b.duration = 2
	defender.add_buff(b)
	var m := _manager([atk_unit, defender])
	var hp_before: int = atk_unit.hp
	var events := m.submit_command(AttackCommand.new(atk_unit, defender, loader.get_skill(&"generic_melee")))
	var dmg := events.filter(func(e): return e["type"] == "damage")
	assert_eq(dmg.size(), 2, "攻击 + 反击各一次（决策日志 D27）")
	assert_lt(atk_unit.hp, hp_before, "攻击方被反击掉血")

# ---------------------------------------------------------------- teleport / steal_buff（时迁飞檐走壁）

func test_teleport_moves_toward_enemy_ignoring_terrain() -> void:
	var sq := _csv_unit(&"shi_qian", Unit.Team.PLAYER, Vector2i(0, 0))
	var t = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(6, 0)))
	grid.place_unit(t, Vector2i(6, 0))
	# 沿途铺满拒马：普通移动不可过，瞬移无视
	for x in range(1, 6):
		grid.get_cell(Vector2i(x, 0)).obstacle_hp = 300
	var m := _manager([sq, t])
	m.submit_command(SkillCommand.new(sq, loader.get_skill(&"act_feiyan")))
	assert_eq(sq.coords, Vector2i(5, 1), "瞬移 6 格到 (5,1)：(5,0) 被拒马挡、敌人相邻格超程（决策日志 D27）")

func test_steal_buff_takes_dispellable_buff() -> void:
	var sq := _csv_unit(&"shi_qian", Unit.Team.PLAYER, Vector2i(4, 4))
	var t = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(5, 4)))
	grid.place_unit(t, Vector2i(5, 4))
	var b := Buff.new()
	b.buff_id = &"enemy_atk_up"
	b.stat_mods = {&"atk": 30}
	b.duration = 2
	t.add_buff(b)
	var m := _manager([sq, t])
	m.submit_command(SkillCommand.new(sq, loader.get_skill(&"act_feiyan")))   # teleport(6);steal_buff(1)
	assert_eq(t.buffs.size(), 0, "增益被偷走")
	assert_eq(sq.get_stat_mod(&"atk"), 30, "时迁获得偷来的增益")

# ---------------------------------------------------------------- 戴宗「神行百变」：av_mod / move_mod / extra_action

func test_shenxing_full_package() -> void:
	var dz := _csv_unit(&"dai_zong", Unit.Team.PLAYER, Vector2i(4, 4))
	var a1 = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.PLAYER, Vector2i(4, 5), &"a1"))
	var a2 = autofree(UnitFactory.make_unit(100, 50, 60, Unit.Team.PLAYER, Vector2i(5, 5), &"a2"))
	grid.place_unit(a1, Vector2i(4, 5))
	grid.place_unit(a2, Vector2i(5, 5))
	a1.reset_av()
	a2.reset_av()
	var av1_before: float = a1.av
	var m := _manager([dz, a1, a2])
	var events := m.submit_command(SkillCommand.new(dz, loader.get_skill(&"act_shenxing")))
	assert_eq(a1.get_move(grid), 5, "全队移动力 +2")
	assert_lt(a1.av, av1_before, "全队 AV 减半（av_mod(-0.5)）")
	var extra := events.filter(func(e): return e["type"] == "extra_action")
	assert_eq(extra.size(), 1, "只有 1 名队友获得再动（extra_action(1)，决策日志 D27）")

# ---------------------------------------------------------------- 郁保四「替天行道旗」：summon + aura

func test_flag_summon_and_aura() -> void:
	var yb := _csv_unit(&"yu_baosi", Unit.Team.PLAYER, Vector2i(4, 4))
	var ally = autofree(UnitFactory.make_unit(100, 50, 60, Unit.Team.PLAYER, Vector2i(5, 5), &"ally"))
	ally.data.atk = 100
	var enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(0, 0)))
	grid.place_unit(ally, Vector2i(5, 5))
	grid.place_unit(enemy, Vector2i(0, 0))
	var m := _manager([yb, ally, enemy])
	var atk_before: int = ally.get_atk(grid)
	m.submit_command(SkillCommand.new(yb, loader.get_skill(&"act_qi")))
	var flag: Unit = null
	for u in m.units:
		if u.is_object:
			flag = u
	assert_not_null(flag, "旗帜被召唤入场")
	assert_true(m.units.has(flag))
	assert_eq(ally.get_atk(grid), 115, "半径 3 内友军攻 +15%：100 → 115（决策日志 D27）")
	# 物件不行动、不计入胜负
	flag.take_damage(99999)
	assert_eq(m.check_winner(), -1, "旗帜死亡不影响胜负判定")

# ---------------------------------------------------------------- 全部 CSV 技能可执行（无解析/未实现报错）

func test_all_csv_skills_executable() -> void:
	var ctx_unit = autofree(UnitFactory.make_unit(100, 100, 80, Unit.Team.PLAYER, Vector2i(4, 4)))
	ctx_unit.data.mgc = 100
	grid.place_unit(ctx_unit, Vector2i(4, 4))
	var enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 5)))
	grid.place_unit(enemy, Vector2i(4, 5))
	var enemy_far = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 1), &"far"))
	grid.place_unit(enemy_far, Vector2i(4, 1))
	var ally = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(5, 4)))
	grid.place_unit(ally, Vector2i(5, 4))
	var m := _manager([ctx_unit, enemy, enemy_far, ally])
	var failed: Array = []
	for id in loader.skills:
		var s: SkillData = loader.skills[id]
		if id in [&"generic_melee", &"generic_ranged"]:
			continue
		# 每个技能都在干净状态下尝试：回位、满怒、清冷却、敌方复位
		grid.move_unit(ctx_unit, Vector2i(4, 4))
		ctx_unit.rage = 100
		ctx_unit.cooldowns.clear()
		for e in [enemy, enemy_far]:
			e.hp = 500
			grid.place_unit(e, Vector2i(4, 5) if e == enemy else Vector2i(4, 1))
		var events: Array = []
		for aim in [Vector2i(-1, -1), enemy.coords, enemy_far.coords]:
			events = m.submit_command(SkillCommand.new(ctx_unit, s, aim))
			if not events.is_empty():
				break
		if events.is_empty():
			failed.append(id)
	assert_eq(failed, [], "以下技能未能执行：%s" % [failed])
