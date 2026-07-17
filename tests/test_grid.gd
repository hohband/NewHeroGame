extends GutTest
## Grid：移动范围（Dijkstra/地形消耗）、寻路（AStarGrid2D）、占位规则（决策日志 D4）。

var loader: GameDataLoader
var grid: Grid
var mover: Unit

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4)))
	mover = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.PLAYER, Vector2i(0, 0)))
	grid.place_unit(mover, Vector2i(0, 0))

func test_reachable_manhattan_ball() -> void:
	var r := grid.get_reachable(mover, 3)
	assert_eq(r.size(), 9)
	assert_true(r.has(Vector2i(3, 0)))
	assert_true(r.has(Vector2i(0, 3)))
	assert_true(r.has(Vector2i(2, 1)))
	assert_false(r.has(Vector2i(2, 2)), "消耗 4 超出预算")
	assert_false(r.has(Vector2i(0, 0)), "不含起点")

func test_terrain_cost_limits_range() -> void:
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(1, 0): &"forest"}))
	var u = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.PLAYER, Vector2i(0, 0)))
	g.place_unit(u, Vector2i(0, 0))
	var r := g.get_reachable(u, 2)
	assert_true(r.has(Vector2i(1, 0)), "森林消耗 2，预算 2 可达")
	assert_false(r.has(Vector2i(2, 0)), "经森林消耗 3，超出预算")

func test_obstacle_blocks_and_detour() -> void:
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(1, 0): &"barricade"}))
	var u = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.PLAYER, Vector2i(0, 0)))
	g.place_unit(u, Vector2i(0, 0))
	assert_false(g.get_reachable(u, 3).has(Vector2i(2, 0)), "拒马挡路，预算 3 不可达")
	assert_true(g.get_reachable(u, 4).has(Vector2i(2, 0)), "预算 4 可绕行")

func test_enemy_blocks_passage() -> void:
	var enemy = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.ENEMY, Vector2i(1, 0)))
	grid.place_unit(enemy, Vector2i(1, 0))
	var r := grid.get_reachable(mover, 2)
	assert_false(r.has(Vector2i(1, 0)))
	assert_false(r.has(Vector2i(2, 0)), "不可穿过敌军")

func test_ally_pass_through_not_stop() -> void:
	var ally = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.PLAYER, Vector2i(1, 0)))
	grid.place_unit(ally, Vector2i(1, 0))
	var r := grid.get_reachable(mover, 2)
	assert_false(r.has(Vector2i(1, 0)), "友军格不可停留")
	assert_true(r.has(Vector2i(2, 0)), "可穿过友军")

func test_find_path_around_obstacle() -> void:
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(1, 0): &"barricade"}))
	var u = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.PLAYER, Vector2i(0, 0)))
	g.place_unit(u, Vector2i(0, 0))
	var path := g.find_path(u, Vector2i(2, 0))
	assert_false(path.is_empty())
	assert_eq(path[0], Vector2i(0, 0), "路径含起点")
	assert_eq(path.back(), Vector2i(2, 0))
	assert_false(path.has(Vector2i(1, 0)), "不经过拒马")
	assert_eq(path.size(), 5, "绕行 4 步")

func test_find_path_unreachable() -> void:
	var blocked := {Vector2i(1, 0): &"barricade", Vector2i(1, 1): &"barricade", Vector2i(0, 1): &"barricade"}
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(2, 2), blocked))
	var u = autofree(UnitFactory.make_unit(100, 50, 50, Unit.Team.PLAYER, Vector2i(0, 0)))
	g.place_unit(u, Vector2i(0, 0))
	assert_eq(g.find_path(u, Vector2i(1, 1)).size(), 0)

func test_move_unit_updates_occupancy() -> void:
	grid.move_unit(mover, Vector2i(2, 2))
	assert_null(grid.get_cell(Vector2i(0, 0)).occupant)
	assert_eq(grid.get_cell(Vector2i(2, 2)).occupant, mover)
	assert_eq(mover.coords, Vector2i(2, 2))
