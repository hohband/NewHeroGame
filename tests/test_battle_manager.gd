extends GutTest
## BattleManager：CTB 回合流转、状态机、胜负判定、信号广播。

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
	enemy = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.ENEMY, Vector2i(3, 3)))
	grid.place_unit(hero, Vector2i(0, 0))
	grid.place_unit(enemy, Vector2i(3, 3))
	manager = autofree(BattleManager.new())
	manager.setup(loader, grid, [hero, enemy])
	manager.set_seed(42)

func test_first_actor_is_fastest() -> void:
	manager.start_battle()
	assert_eq(manager.active_unit, hero, "速度 80 先于速度 40")
	assert_eq(manager.state, BattleManager.State.IDLE, "我方回合等待输入")

func test_turn_rotation_reaches_enemy() -> void:
	manager.start_battle()
	var got_enemy := false
	for i in range(10):
		manager.finish_turn()
		if manager.active_unit == enemy:
			got_enemy = true
			break
	assert_true(got_enemy, "10 次轮换内敌方应获得行动机会（CTB 套圈规则）")

func test_enemy_turn_sets_ai_state() -> void:
	manager.start_battle()
	for i in range(10):
		manager.finish_turn()
		if manager.active_unit == enemy:
			break
	assert_eq(manager.state, BattleManager.State.AI_TURN)

func test_in_attack_range_manhattan() -> void:
	grid.move_unit(enemy, Vector2i(1, 0))
	assert_true(manager.in_attack_range(hero, enemy))
	grid.move_unit(enemy, Vector2i(2, 0))
	assert_false(manager.in_attack_range(hero, enemy), "近战范围 1，距离 2 不可攻击")

func test_battle_ends_when_side_wiped() -> void:
	watch_signals(manager)
	enemy.take_damage(99999)
	manager.advance_turn()
	assert_signal_emitted(manager, "battle_ended")
	assert_eq(manager.state, BattleManager.State.BATTLE_END)

func test_winner_check_both_alive() -> void:
	assert_eq(manager.check_winner(), -1)

func test_dead_unit_frees_cell() -> void:
	enemy.take_damage(99999)
	assert_null(grid.get_cell(Vector2i(3, 3)).occupant, "死亡后让出格子")

func test_turn_started_signal_broadcasts() -> void:
	watch_signals(manager)
	manager.start_battle()
	assert_signal_emitted(manager, "turn_started")
