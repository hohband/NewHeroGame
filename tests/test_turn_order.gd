extends GutTest
## TurnOrder：CTB 速度排队（策划文档 6.4）与平局规则（决策日志 D3）。

func test_fastest_acts_first_and_laps() -> void:
	var fast = autofree(UnitFactory.make_unit(100, 50, 100, Unit.Team.ENEMY, Vector2i.ZERO, &"fast"))
	var slow = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.ENEMY, Vector2i.ZERO, &"slow"))
	var order := TurnOrder.new()
	var units: Array[Unit] = [fast, slow]
	assert_eq(order.next_actor(units), fast, "AV 最小者先行动")
	fast.reset_av()
	assert_eq(order.next_actor(units), fast, "速度翻倍 → 同刻归零时速度高者先（套圈）")
	fast.reset_av()
	assert_eq(order.next_actor(units), slow)

func test_tie_break_player_first() -> void:
	var enemy = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.ENEMY, Vector2i.ZERO, &"aaa"))
	var player = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.PLAYER, Vector2i.ZERO, &"bbb"))
	var order := TurnOrder.new()
	var units: Array[Unit] = [enemy, player]
	assert_eq(order.next_actor(units), player, "同速同刻：我方优先")

func test_tie_break_id_order() -> void:
	var a = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.ENEMY, Vector2i.ZERO, &"aaa"))
	var b = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.ENEMY, Vector2i.ZERO, &"bbb"))
	var order := TurnOrder.new()
	var units: Array[Unit] = [b, a]
	assert_eq(order.next_actor(units), a, "同速同队：unit_id 字典序")

func test_dead_units_never_act() -> void:
	var a = autofree(UnitFactory.make_unit(100, 50, 100, Unit.Team.ENEMY, Vector2i.ZERO, &"a"))
	var b = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.ENEMY, Vector2i.ZERO, &"b"))
	var order := TurnOrder.new()
	var units: Array[Unit] = [a, b]
	a.take_damage(99999)
	assert_eq(order.next_actor(units), b)
	b.reset_av()
	assert_eq(order.next_actor(units), b, "死者不再进入行动序列")

func test_all_dead_returns_null() -> void:
	var a = autofree(UnitFactory.make_unit(100, 50, 100, Unit.Team.ENEMY, Vector2i.ZERO, &"a"))
	var order := TurnOrder.new()
	var units: Array[Unit] = [a]
	a.take_damage(99999)
	assert_null(order.next_actor(units))

func test_preview_matches_actual_sequence() -> void:
	var a = autofree(UnitFactory.make_unit(100, 50, 100, Unit.Team.PLAYER, Vector2i.ZERO, &"a"))
	var b = autofree(UnitFactory.make_unit(100, 50, 60, Unit.Team.ENEMY, Vector2i.ZERO, &"b"))
	var c = autofree(UnitFactory.make_unit(100, 50, 45, Unit.Team.ENEMY, Vector2i.ZERO, &"c"))
	var order := TurnOrder.new()
	var units: Array[Unit] = [a, b, c]
	var av_before: Array = units.map(func(u): return u.av)
	var expected := order.preview(units, 6)
	assert_eq(order.preview(units, 6), expected, "重复预览结果一致（非破坏性，决策日志 D17）")
	for i in units.size():
		assert_eq(units[i].av, av_before[i], "预览不改变真实 AV")
	var actual: Array[Unit] = []
	for i in range(6):
		var u := order.next_actor(units)
		actual.append(u)
		u.reset_av()
	assert_eq(actual, expected, "预览序列应与实际行动序列一致")
