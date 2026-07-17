extends GutTest
## Buff 系统：属性修正、持续回合、DoT、驱散、移动力修正、地形 tick、待机（策划文档 6.7、决策日志 D15/D16/D18）

var loader: GameDataLoader
var grid: Grid
var hero: Unit
var enemy: Unit

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4)))
	hero = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(0, 0)))
	enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(3, 3)))
	grid.place_unit(hero, Vector2i(0, 0))
	grid.place_unit(enemy, Vector2i(3, 3))

func _buff(id: StringName, field: StringName, value: int, duration: int, debuff := false) -> Buff:
	var b := Buff.new()
	b.buff_id = id
	b.stat_mods = {field: value}
	b.duration = duration
	b.is_debuff = debuff
	return b

func _poison(duration: int) -> Buff:
	var b := Buff.new()
	b.buff_id = &"poison"
	b.duration = duration
	b.is_debuff = true
	b.tick_effect = {"kind": "dot", "percent": 5}
	return b

func test_atk_buff_applies() -> void:
	hero.add_buff(_buff(&"b1", &"atk", 20, 2))
	assert_eq(hero.get_atk(grid), 120)

func test_buffs_stack_additively() -> void:
	hero.add_buff(_buff(&"b1", &"atk", 20, 2))
	hero.add_buff(_buff(&"b2", &"atk", 10, 2))
	assert_eq(hero.get_atk(grid), 130, "多个 buff 相加")

func test_same_id_refreshes_duration() -> void:
	hero.add_buff(_buff(&"b1", &"atk", 20, 2))
	hero.add_buff(_buff(&"b1", &"atk", 20, 3))
	assert_eq(hero.buffs.size(), 1, "同 id 不叠层（决策日志 D15）")
	assert_eq(hero.buffs[0].duration, 3, "刷新为较长持续")

func test_buff_expires_at_own_turn_start() -> void:
	hero.add_buff(_buff(&"b1", &"atk", 20, 1))
	var events: Array = hero.tick_turn_start()
	assert_eq(hero.buffs.size(), 0, "持续 1 回合的 buff 在下次自己回合开始过期")
	assert_eq(hero.get_atk(grid), 100)
	assert_true(events.any(func(e): return e["type"] == "buff_expired"))

func test_dot_ticks_each_turn() -> void:
	hero.add_buff(_poison(2))
	hero.tick_turn_start()
	assert_eq(hero.hp, 475, "5% × 500 = 25（决策日志 D16）")
	hero.tick_turn_start()
	assert_eq(hero.hp, 450)
	assert_eq(hero.buffs.size(), 0, "两跳后 poison 过期")

func test_dispel_removes_only_debuffs() -> void:
	hero.add_buff(_buff(&"b1", &"atk", 20, 2))
	hero.add_buff(_buff(&"b2", &"def", -30, 2, true))
	hero.add_buff(_buff(&"b3", &"mgc", -30, 2, true))
	var removed: Array = hero.dispel_debuffs(1)
	assert_eq(removed.size(), 1, "dispel(1) 只驱一个")
	assert_eq(hero.buffs.size(), 2)
	hero.dispel_debuffs(2)
	assert_eq(hero.buffs.size(), 1, "减益驱完，增益保留")
	assert_eq(hero.get_stat_mod(&"atk"), 20)

func test_move_buff_and_water_penalty() -> void:
	hero.add_buff(_buff(&"b1", &"move", 2, 1))
	assert_eq(hero.get_move(grid), 5)
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(0, 0): &"water"}))
	var u = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(0, 0)))
	g.place_unit(u, Vector2i(0, 0))
	u.add_buff(_buff(&"b1", &"move", 2, 1))
	assert_eq(u.get_move(g), 4, "水面移动力 -1（决策日志 D18）")

func test_dodge_block_are_points_not_percent() -> void:
	hero.add_buff(_buff(&"b1", &"dodge", 50, 1))
	hero.add_buff(_buff(&"b2", &"block", 30, 1))
	assert_eq(hero.get_dodge(grid), 50)
	assert_eq(hero.get_block(), 30)

func test_camp_heals_at_turn_start() -> void:
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(0, 0): &"camp"}))
	var h: Unit = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(0, 0)))
	var e: Unit = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(3, 3)))
	g.place_unit(h, Vector2i(0, 0))
	g.place_unit(e, Vector2i(3, 3))
	var manager: BattleManager = autofree(BattleManager.new())
	manager.setup(loader, g, [h, e])
	h.hp = 300
	watch_signals(manager)
	manager.start_battle()   # h 速度 80 先行动 → 回合开始 tick
	assert_eq(h.hp, 340, "营帐回血 8% × 500 = 40（决策日志 D18）")
	assert_signal_emitted(manager, "tick_events")

func test_fire_damages_at_turn_start() -> void:
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(0, 0): &"fire"}))
	var h: Unit = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(0, 0)))
	var e: Unit = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(3, 3)))
	g.place_unit(h, Vector2i(0, 0))
	g.place_unit(e, Vector2i(3, 3))
	var manager: BattleManager = autofree(BattleManager.new())
	manager.setup(loader, g, [h, e])
	manager.start_battle()
	assert_eq(h.hp, 475, "火堆灼烧 5% × 500 = 25（决策日志 D18）")

func test_wait_command_grants_def_and_rage() -> void:
	var manager: BattleManager = autofree(BattleManager.new())
	manager.setup(loader, grid, [hero, enemy])
	manager.submit_command(WaitCommand.new(hero))
	assert_eq(hero.rage, 15, "待机怒气 +15（表格9）")
	assert_eq(hero.get_def(grid), 60, "待机防御 +20%")
	var events: Array = hero.tick_turn_start()
	assert_eq(hero.get_def(grid), 50, "下次自己回合开始时失效")
	assert_true(events.any(func(e): return e.get("buff") == &"wait_def"))

func test_dot_death_skips_turn() -> void:
	# 我方需 2 人，否则 DoT 致死即全灭战败，谈不上"轮到下一单位"
	var ally: Unit = autofree(UnitFactory.make_unit(90, 50, 70, Unit.Team.PLAYER, Vector2i(1, 0), &"ally"))
	grid.place_unit(ally, Vector2i(1, 0))
	var manager: BattleManager = autofree(BattleManager.new())
	manager.setup(loader, grid, [hero, ally, enemy])
	hero.add_buff(_poison(3))
	hero.hp = 10   # 一跳即死
	manager.start_battle()   # hero 速度 80 先轮到 → DoT 致死 → 跳过
	assert_false(hero.is_alive())
	assert_eq(manager.active_unit, ally, "DoT 致死直接轮到下一单位（AV 次小者）")
	assert_eq(manager.state, BattleManager.State.IDLE)
