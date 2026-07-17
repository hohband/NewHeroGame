extends GutTest
## Command / MoveCommand / AttackCommand：指令管道与朝向更新（策划文档第十一章）。

var loader: GameDataLoader
var grid: Grid
var manager: BattleManager
var hero: Unit
var enemy: Unit

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4)))
	hero = autofree(UnitFactory.make_unit(100, 0, 80, Unit.Team.PLAYER, Vector2i(0, 0)))
	enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(2, 0)))
	enemy.facing = Vector2i(0, 1)
	grid.place_unit(hero, Vector2i(0, 0))
	grid.place_unit(enemy, Vector2i(2, 0))
	manager = autofree(BattleManager.new())
	manager.setup(loader, grid, [hero, enemy])
	manager.set_seed(42)

func test_move_command_updates_position_and_occupancy() -> void:
	var path := grid.find_path(hero, Vector2i(1, 0))
	path.remove_at(0)
	var events := manager.submit_command(MoveCommand.new(hero, path))
	assert_eq(hero.coords, Vector2i(1, 0))
	assert_eq(grid.get_cell(Vector2i(1, 0)).occupant, hero)
	assert_null(grid.get_cell(Vector2i(0, 0)).occupant)
	assert_eq(events[0]["type"], "move")

func test_move_command_sets_facing() -> void:
	manager.submit_command(MoveCommand.new(hero, [Vector2i(0, 1)]))
	assert_eq(hero.facing, Vector2i(0, 1))

func test_move_command_rejects_occupied_cell() -> void:
	var events := manager.submit_command(MoveCommand.new(hero, [Vector2i(2, 0)]))
	assert_eq(events.size(), 0, "目标格被敌人占位，指令应失败")
	assert_eq(hero.coords, Vector2i(0, 0), "位置不变")
	assert_push_error("不可停留")

func test_attack_command_applies_damage_and_rage() -> void:
	grid.move_unit(hero, Vector2i(1, 0))
	var skill := manager.basic_attack_skill(hero)
	assert_eq(skill.skill_id, &"generic_melee")
	var events := manager.submit_command(AttackCommand.new(hero, enemy, skill))
	var dmg_events := events.filter(func(e): return e["type"] in ["damage", "dodge"])
	assert_eq(dmg_events.size(), 1)
	assert_gt(hero.rage, 0, "普攻积累怒气")

func test_attack_sets_facing_toward_target() -> void:
	grid.move_unit(hero, Vector2i(1, 0))
	manager.submit_command(AttackCommand.new(hero, enemy, manager.basic_attack_skill(hero)))
	assert_eq(hero.facing, Vector2i(1, 0))

func test_ranged_unit_uses_ranged_basic() -> void:
	var archer = autofree(UnitFactory.make_unit(100, 0, 50, Unit.Team.PLAYER, Vector2i(0, 0)))
	archer.data.range_min = 2
	archer.data.range_max = 5
	assert_eq(manager.basic_attack_skill(archer).skill_id, &"generic_ranged")

func test_submit_command_restores_idle_state() -> void:
	manager.active_unit = hero
	manager.submit_command(MoveCommand.new(hero, [Vector2i(0, 1)]))
	assert_eq(manager.state, BattleManager.State.IDLE)
