extends GutTest
## 道具系统（策划 6.5「道具：每局限用次数」）：
## 加载校验、使用扣次数、次数耗尽拒绝、效果结算（治疗/驱散）、占用行动点、submit_command 管道。

var loader: GameDataLoader
var grid: Grid
var manager: BattleManager
var hero: Unit
var ally: Unit
var enemy: Unit

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(6, 6)))
	hero = autofree(UnitFactory.make_unit(100, 0, 80, Unit.Team.PLAYER, Vector2i(0, 0), &"hero"))
	ally = autofree(UnitFactory.make_unit(50, 0, 70, Unit.Team.PLAYER, Vector2i(1, 0), &"ally"))
	enemy = autofree(UnitFactory.make_unit(50, 0, 40, Unit.Team.ENEMY, Vector2i(3, 0), &"enemy"))
	grid.place_unit(hero, Vector2i(0, 0))
	grid.place_unit(ally, Vector2i(1, 0))
	grid.place_unit(enemy, Vector2i(3, 0))
	manager = autofree(BattleManager.new())
	manager.setup(loader, grid, [hero, ally, enemy])
	manager.rolls = FixedRollSource.new([0.0])   # 判定全过：无闪避/暴击/格挡干扰
	manager.active_unit = hero

func _make_debuff(id: StringName) -> Buff:
	var b := Buff.new()
	b.buff_id = id
	b.is_debuff = true
	b.dispellable = true
	b.duration = 2
	return b

# ---------------------------------------------------------------- 加载与校验

func test_items_loaded() -> void:
	assert_eq(loader.items.size(), 5, "items.csv 内置 5 件道具")
	var it := loader.get_item(&"jinchuangyao")
	assert_not_null(it)
	assert_eq(it.range_shape, &"adjacent")
	assert_eq(it.target, &"ally")
	assert_eq(it.uses_per_battle, 3)
	assert_eq(it.effects, "heal(1.2)")

func test_validate_passes_with_items() -> void:
	var errors := loader.validate()
	assert_eq(errors.size(), 0, "全表校验应通过（含道具表）：%s" % str(errors))

# ---------------------------------------------------------------- 道具栏与次数

func test_default_stock_initialized_on_setup() -> void:
	assert_eq(manager.item_stock, loader.default_item_stock(), "开局标准道具栏 = items.csv 全员次数")
	assert_eq(manager.item_uses_left(&"jinchuangyao"), 3)
	assert_eq(manager.item_uses_left(&"xingjunjiu"), 2)

func test_use_item_consumes_count() -> void:
	ally.hp = 100
	manager.submit_command(ItemCommand.new(hero, loader.get_item(&"jinchuangyao"), ally))
	assert_eq(manager.item_uses_left(&"jinchuangyao"), 2, "使用后剩余 2 次")

func test_item_rejected_when_exhausted() -> void:
	manager.set_item_stock({&"jinchuangyao": 0})
	ally.hp = 100
	var events := manager.submit_command(ItemCommand.new(hero, loader.get_item(&"jinchuangyao"), ally))
	assert_eq(events.size(), 0, "次数耗尽指令应失败")
	assert_eq(ally.hp, 100, "未生效")
	assert_push_error("无法使用")

func test_set_item_stock_interface() -> void:
	manager.set_item_stock({&"jinchuangyao": 1, &"feihuangshi": 5, &"unknown_item": 3})
	assert_eq(manager.item_uses_left(&"jinchuangyao"), 1)
	assert_eq(manager.item_uses_left(&"feihuangshi"), 5)
	assert_eq(manager.item_stock.size(), 2, "表外道具被忽略")

# ---------------------------------------------------------------- 效果结算

func test_heal_item_settles() -> void:
	hero.data.mgc = 50
	ally.hp = 100
	var events := manager.submit_command(ItemCommand.new(hero, loader.get_item(&"jinchuangyao"), ally))
	assert_eq(ally.hp, 160, "治疗量 = 使用者谋略 50 × 1.2")
	assert_eq(events[0]["type"], "item_use")
	assert_eq(int(events[0]["left"]), 2)
	var heals := events.filter(func(e): return e["type"] == "heal")
	assert_eq(heals.size(), 1)
	assert_eq(int(heals[0]["amount"]), 60)

func test_dispel_item_only_on_picked_target() -> void:
	ally.add_buff(_make_debuff(&"poison"))
	ally.add_buff(_make_debuff(&"armor_break"))
	hero.add_buff(_make_debuff(&"bleed"))
	var events := manager.submit_command(ItemCommand.new(hero, loader.get_item(&"jiedusan"), ally))
	assert_eq(ally.buffs.size(), 0, "目标 2 个减益被驱散")
	assert_eq(hero.buffs.size(), 1, "道具为单目标指定：范围内其他友军不受影响")
	var dispels := events.filter(func(e): return e["type"] == "dispel")
	assert_eq(dispels.size(), 1)
	assert_eq((dispels[0]["removed"] as Array).size(), 2)

func test_rage_item_via_pipeline() -> void:
	var events := manager.submit_command(ItemCommand.new(hero, loader.get_item(&"xingjunjiu"), hero))
	assert_gt(events.size(), 0, "经 submit_command 管道结算")
	assert_eq(events[0]["type"], "item_use")
	assert_eq(hero.rage, 30, "行军酒 +30 怒气")
	assert_eq(manager.item_uses_left(&"xingjunjiu"), 1)
	assert_eq(manager.state, BattleManager.State.IDLE, "指令后回到 IDLE")

func test_damage_item_settles() -> void:
	var events := manager.submit_command(ItemCommand.new(hero, loader.get_item(&"feihuangshi"), enemy))
	var dmgs := events.filter(func(e): return e["type"] == "damage")
	assert_eq(dmgs.size(), 1)
	assert_lt(enemy.hp, enemy.data.hp, "飞蝗石造成伤害")
	assert_eq(manager.item_uses_left(&"feihuangshi"), 2)

# ---------------------------------------------------------------- 行动口径

func test_item_marks_action_used_and_blocks_second() -> void:
	manager.submit_command(ItemCommand.new(hero, loader.get_item(&"xingjunjiu"), hero))
	assert_true(manager.action_used, "使用道具占本激活行动")
	assert_false(manager.can_use_item(hero, loader.get_item(&"jinchuangyao")), "行动已用后道具不可用")
	ally.hp = 100
	var events := manager.submit_command(ItemCommand.new(hero, loader.get_item(&"jinchuangyao"), ally))
	assert_eq(events.size(), 0, "同一激活第二次道具被拒绝")
	assert_eq(manager.item_uses_left(&"jinchuangyao"), 3, "不扣次数")
	assert_eq(ally.hp, 100)
	assert_push_error("无法使用")
