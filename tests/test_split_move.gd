extends GutTest
## 移动可拆成两段（策划 6.5）：剩余移动力跟踪、分段移动、行动后移动、耗尽/超耗拒绝、CTB 不误判。

var loader: GameDataLoader
var grid: Grid
var manager: BattleManager
var hero: Unit
var enemy: Unit

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(6, 6)))
	hero = autofree(UnitFactory.make_unit(100, 0, 80, Unit.Team.PLAYER, Vector2i(0, 0)))
	enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(5, 5)))
	grid.place_unit(hero, Vector2i(0, 0))
	grid.place_unit(enemy, Vector2i(5, 5))
	manager = autofree(BattleManager.new())
	manager.setup(loader, grid, [hero, enemy])
	manager.set_seed(42)
	manager.start_battle()   # hero 速度 80 先行动（UnitFactory 移动力 = 3）

func test_activation_grants_full_move_points() -> void:
	assert_eq(manager.active_unit, hero)
	assert_eq(manager.move_points_left, hero.get_move(grid), "激活时剩余移动力 = 单位移动力")
	assert_eq(manager.move_points_left, 3)
	assert_true(manager.can_move(hero))
	assert_false(manager.can_move(enemy), "非激活单位不可移动")

func test_first_segment_deducts_path_cost() -> void:
	manager.submit_command(MoveCommand.new(hero, [Vector2i(1, 0), Vector2i(2, 0)]))
	assert_eq(hero.coords, Vector2i(2, 0))
	assert_eq(manager.move_points_left, 1, "平原 2 格消耗 2 点")

func test_terrain_cost_deducted_by_grid_rule() -> void:
	grid.set_terrain(Vector2i(1, 0), &"forest")   # 森林进入消耗 2（地形表）
	manager.submit_command(MoveCommand.new(hero, [Vector2i(1, 0)]))
	assert_eq(manager.move_points_left, 1, "路径消耗与 get_reachable/AStar 同口径（按地形扣减）")

func test_second_segment_limited_to_remaining() -> void:
	manager.submit_command(MoveCommand.new(hero, [Vector2i(1, 0)]))
	var reach: Dictionary = manager.reachable_cells(hero)
	assert_true(reach.has(Vector2i(3, 0)), "剩余 2 点可再走 2 格")
	assert_false(reach.has(Vector2i(4, 0)), "超出剩余移动力的格不可达")
	manager.submit_command(MoveCommand.new(hero, [Vector2i(2, 0), Vector2i(3, 0)]))
	assert_eq(hero.coords, Vector2i(3, 0), "第二段走到剩余范围内落点")
	assert_eq(manager.move_points_left, 0)

func test_move_exhausted_blocks_further_move() -> void:
	manager.submit_command(MoveCommand.new(hero, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]))
	assert_eq(manager.move_points_left, 0)
	assert_false(manager.can_move(hero), "移动力耗尽后不可再移动")
	assert_eq(manager.reachable_cells(hero).size(), 0, "耗尽后可达格为空")
	manager.submit_command(MoveCommand.new(hero, [Vector2i(4, 0)]))
	assert_eq(hero.coords, Vector2i(3, 0), "耗尽后的移动指令被拒绝")
	assert_push_error("超出剩余移动力")

func test_path_cost_exceeding_remaining_rejected() -> void:
	manager.submit_command(MoveCommand.new(hero, [Vector2i(1, 0)]))
	manager.submit_command(MoveCommand.new(hero, [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]))
	assert_eq(hero.coords, Vector2i(1, 0), "路径消耗 3 > 剩余 2，整段拒绝")
	assert_eq(manager.move_points_left, 2, "拒绝不扣减剩余移动力")
	assert_push_error("超出剩余移动力")

func test_action_then_move_with_remaining() -> void:
	grid.move_unit(enemy, Vector2i(0, 1))
	manager.submit_command(AttackCommand.new(hero, enemy, manager.basic_attack_skill(hero)))
	manager.action_used = true   # 行动标记由表现层置位（battle.gd 同口径）
	assert_eq(manager.move_points_left, 3, "行动不扣移动力")
	assert_eq(manager.active_unit, hero, "行动后激活不结束（移动力未用完）")
	manager.submit_command(MoveCommand.new(hero, [Vector2i(1, 0), Vector2i(2, 0)]))
	assert_eq(hero.coords, Vector2i(2, 0), "行动后仍可用剩余移动力移动")
	assert_eq(manager.move_points_left, 1)

func test_two_segments_do_not_end_activation() -> void:
	manager.submit_command(MoveCommand.new(hero, [Vector2i(1, 0)]))
	manager.submit_command(MoveCommand.new(hero, [Vector2i(2, 0)]))
	assert_eq(manager.active_unit, hero, "两段移动不算两次行动，激活不结束")
	assert_eq(manager.state, BattleManager.State.IDLE)

func test_move_points_reset_on_next_activation() -> void:
	manager.submit_command(MoveCommand.new(hero, [Vector2i(1, 0), Vector2i(2, 0)]))
	assert_eq(manager.move_points_left, 1)
	manager.finish_turn()
	for i in range(10):
		if manager.active_unit == hero:
			break
		manager.finish_turn()
	assert_eq(manager.active_unit, hero)
	assert_eq(manager.move_points_left, hero.get_move(grid), "下次激活移动力恢复满")
