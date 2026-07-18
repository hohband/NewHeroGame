extends GutTest
## 武器范围模板（weapons.csv，策划 6.5；决策日志 D9 的细化落地）：
## 普攻射程按武器形状判定——枪矛类 line（四方向直线）、远程 diamond（曼哈顿区间）、近战 adjacent（周身）。

var loader: GameDataLoader
var grid: Grid

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(9, 9)))

func _manager(units: Array[Unit]) -> BattleManager:
	var m: BattleManager = autofree(BattleManager.new())
	m.setup(loader, grid, units)
	return m

func _csv_unit(id: StringName, team: Unit.Team, coords: Vector2i) -> Unit:
	var u := Unit.new()
	u.setup(loader.get_unit(id), team, coords)
	grid.place_unit(u, coords)
	return autofree(u)

# ---------------------------------------------------------------- line（枪矛直线，林冲丈八蛇矛 射程 1-2）

func test_line_weapon_hits_straight_cells() -> void:
	var spear := _csv_unit(&"lin_chong", Unit.Team.PLAYER, Vector2i(4, 4))
	var t = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 2)))
	grid.place_unit(t, Vector2i(4, 2))
	var m := _manager([spear, t])
	assert_true(m.in_attack_range(spear, t), "正北直线 2 格可打（射程 1-2）")
	grid.move_unit(t, Vector2i(4, 5))
	assert_true(m.in_attack_range(spear, t), "直线相邻格可打")

func test_line_weapon_misses_diagonal() -> void:
	var spear := _csv_unit(&"lin_chong", Unit.Team.PLAYER, Vector2i(4, 4))
	var t = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(5, 5)))
	grid.place_unit(t, Vector2i(5, 5))
	var m := _manager([spear, t])
	assert_false(m.in_attack_range(spear, t), "斜角 (5,5) 曼哈顿 2 但不在直线上，枪打不到")
	grid.move_unit(t, Vector2i(3, 5))
	assert_false(m.in_attack_range(spear, t), "斜角 (3,5) 同样打不到")
	grid.move_unit(t, Vector2i(6, 4))
	assert_true(m.in_attack_range(spear, t), "正东直线 2 格仍可打")
	# 同源函数一致：可普攻目标列表 / 障碍判定走同一形状
	var targets := m.enemies_in_range(spear)
	assert_eq(targets.size(), 1, "enemies_in_range 与 in_attack_range 同口径")
	assert_eq(targets[0], t)
	grid.get_cell(Vector2i(5, 5)).obstacle_hp = 300
	assert_false(m.in_obstacle_range(spear, Vector2i(5, 5)), "斜角拒马同样打不到")
	grid.get_cell(Vector2i(6, 4)).obstacle_hp = 300
	assert_true(m.in_obstacle_range(spear, Vector2i(6, 4)), "直线拒马可打")

func test_line_weapon_hill_range_mod_extends_straight_line() -> void:
	var spear := _csv_unit(&"lin_chong", Unit.Team.PLAYER, Vector2i(4, 4))
	var t = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(4, 1)))
	grid.place_unit(t, Vector2i(4, 1))
	var m := _manager([spear, t])
	assert_false(m.in_attack_range(spear, t), "直线 3 格超出射程 2")
	grid.set_terrain(Vector2i(4, 4), &"hill")
	assert_true(m.in_attack_range(spear, t), "山地 range_mod +1，直线射程延伸为 3")
	grid.move_unit(t, Vector2i(5, 2))
	assert_false(m.in_attack_range(spear, t), "山地加成不改变形状：斜角曼哈顿 3 仍打不到")

# ---------------------------------------------------------------- diamond（远程区间，花荣天地日月弓 射程 3-5；行为不变）

func test_diamond_weapon_behavior_unchanged() -> void:
	var archer := _csv_unit(&"hua_rong", Unit.Team.PLAYER, Vector2i(4, 4))
	var t = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(5, 6)))
	grid.place_unit(t, Vector2i(5, 6))
	var m := _manager([archer, t])
	assert_true(m.in_attack_range(archer, t), "斜角曼哈顿 3 在射程 3-5 内（diamond 不限直线）")
	grid.move_unit(t, Vector2i(4, 5))
	assert_false(m.in_attack_range(archer, t), "距离 1 低于射程下限 3")
	grid.move_unit(t, Vector2i(0, 4))
	assert_true(m.in_attack_range(archer, t), "距离 4 在区间内")
	grid.move_unit(t, Vector2i(0, 0))
	assert_false(m.in_attack_range(archer, t), "距离 8 超出上限 5")

# ---------------------------------------------------------------- 未登记武器：退回 diamond 并告警

func test_unknown_weapon_falls_back_to_diamond() -> void:
	# UnitFactory 单位 weapon 为空串，未在 weapons.csv 登记
	var u = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(4, 4)))
	u.data.range_min = 1
	u.data.range_max = 2
	var t = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(5, 5)))
	grid.place_unit(u, Vector2i(4, 4))
	grid.place_unit(t, Vector2i(5, 5))
	var m := _manager([u, t])
	assert_eq(loader.get_weapon_shape(u.data.weapon), &"diamond", "未登记武器查询退回 diamond")
	assert_true(m.in_attack_range(u, t), "退回 diamond 后斜角曼哈顿 2 在射程 1-2 内（旧行为）")

func test_registered_weapon_shape_query() -> void:
	assert_eq(loader.get_weapon_shape("丈八蛇矛"), &"line")
	assert_eq(loader.get_weapon_shape("天地日月弓"), &"diamond")
	assert_eq(loader.get_weapon_shape("鬼王板斧"), &"adjacent")

# ---------------------------------------------------------------- validate：武器映射缺失/非法形状报错

func test_validate_reports_missing_weapon_mapping() -> void:
	assert_eq(loader.validate().size(), 0, "交付数据表基线应通过校验")
	loader.weapons.erase("丈八蛇矛")
	var errors := loader.validate()
	assert_gt(errors.size(), 0, "删除武器映射后 validate 应报错")
	assert_true(errors.any(func(e): return e.contains("丈八蛇矛")), "报错应指名缺失的武器")

func test_validate_reports_illegal_weapon_shape() -> void:
	loader.weapons["丈八蛇矛"] = &"circle"
	var errors := loader.validate()
	assert_true(errors.any(func(e): return e.contains("丈八蛇矛") and e.contains("range_shape")),
		"非法 range_shape 应被 validate 检出")
