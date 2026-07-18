extends GutTest
## 拒马可破坏（策划文档 6.3）：普攻削耐久、归零变平原恢复通行、AI 挡路时打障碍、
## 不可破坏地形不受影响。

var loader: GameDataLoader
var grid: Grid

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()

func _manager(g: Grid, units: Array[Unit]) -> BattleManager:
	var m: BattleManager = autofree(BattleManager.new())
	m.setup(loader, g, units)
	m.rolls = FixedRollSource.new()
	return m

func _attacker(atk: int, team: Unit.Team, coords: Vector2i) -> Unit:
	var u = autofree(UnitFactory.make_unit(atk, 0, 80, team, coords))
	return u

# ---------------------------------------------------------------- 普攻削减与破坏

func test_attack_reduces_obstacle_hp() -> void:
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(1, 0): &"barricade"}))
	var u := _attacker(100, Unit.Team.PLAYER, Vector2i(0, 0))
	grid.place_unit(u, u.coords)
	var m := _manager(grid, [u])
	var cell := grid.get_cell(Vector2i(1, 0))
	assert_eq(cell.obstacle_hp, 300, "拒马初始耐久取 terrains.csv hp=300")
	var events := m.submit_command(AttackCommand.new(u, null, m.basic_attack_skill(u), Vector2i(1, 0)))
	assert_eq(cell.obstacle_hp, 200, "障碍无防御/闪避/格挡：伤害 = 攻击力 100")
	assert_eq(cell.terrain.terrain_id, &"barricade", "未归零前地形不变")
	var dmg := events.filter(func(e): return e.get("type") == "obstacle_damage")
	assert_eq(dmg.size(), 1, "应有一条 obstacle_damage 表现事件")
	assert_eq(int(dmg[0]["amount"]), 100)
	assert_eq(int(dmg[0]["remaining"]), 200)

func test_obstacle_destroyed_terrain_becomes_plain_and_passable() -> void:
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(1, 0): &"barricade"}))
	var u := _attacker(100, Unit.Team.PLAYER, Vector2i(0, 0))
	grid.place_unit(u, u.coords)
	var m := _manager(grid, [u])
	var cell := grid.get_cell(Vector2i(1, 0))
	cell.obstacle_hp = 80   # 一击可破
	assert_true(cell.is_blocked(), "破坏前拒马阻挡通行")
	var events := m.submit_command(AttackCommand.new(u, null, m.basic_attack_skill(u), Vector2i(1, 0)))
	assert_eq(cell.obstacle_hp, 0)
	assert_eq(cell.terrain.terrain_id, &"plain", "归零后地形变平原")
	assert_false(cell.is_blocked(), "破坏后恢复通行")
	assert_true(grid.can_pass(Vector2i(1, 0), u), "AStar 通行性同步刷新")
	var tc := events.filter(func(e): return e.get("type") == "terrain_change")
	assert_eq(tc.size(), 1, "应有一条 terrain_change 表现事件")
	assert_eq(tc[0]["from"], &"barricade")
	assert_eq(tc[0]["to"], &"plain")

func test_obstacle_attack_respects_range() -> void:
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(6, 6), {Vector2i(3, 0): &"barricade"}))
	var u := _attacker(100, Unit.Team.PLAYER, Vector2i(0, 0))
	grid.place_unit(u, u.coords)
	var m := _manager(grid, [u])
	assert_eq(m.obstacles_in_range(u).size(), 0, "射程外的障碍不可选")
	assert_false(m.in_obstacle_range(u, Vector2i(3, 0)))
	u.coords = Vector2i(2, 0)
	assert_true(m.in_obstacle_range(u, Vector2i(3, 0)))
	assert_eq(m.obstacles_in_range(u), [Vector2i(3, 0)])

# ---------------------------------------------------------------- 不可破坏地形

func test_non_destructible_terrain_unaffected() -> void:
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(1, 0): &"forest"}))
	var u := _attacker(100, Unit.Team.PLAYER, Vector2i(0, 0))
	grid.place_unit(u, u.coords)
	var m := _manager(grid, [u])
	assert_eq(m.obstacles_in_range(u).size(), 0, "forest destructible=0 不进可选列表")
	var events := m.submit_command(AttackCommand.new(u, null, m.basic_attack_skill(u), Vector2i(1, 0)))
	assert_eq(events.size(), 0, "打不可破坏地形应无结算")
	assert_eq(grid.get_cell(Vector2i(1, 0)).terrain.terrain_id, &"forest", "地形不变")

# ---------------------------------------------------------------- AI：挡路时打障碍

func test_ai_attacks_obstacle_when_no_enemy_reachable() -> void:
	# 拒马墙 x=2 封死，敌人无路可达我方单位
	var terrain := {}
	for y in 4:
		terrain[Vector2i(2, y)] = &"barricade"
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(5, 4), terrain))
	var e = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.ENEMY, Vector2i(1, 1)))
	var p = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(4, 1)))
	grid.place_unit(e, e.coords)
	grid.place_unit(p, p.coords)
	var m := _manager(grid, [e, p])
	var plan := BattleAI.decide(e, m)
	var atk := plan.filter(func(c): return c is AttackCommand and c.target_cell != Vector2i(-1, -1))
	assert_eq(atk.size(), 1, "无路可达敌人时应退而普攻挡路拒马")
	assert_eq(atk[0].target_cell.x, 2, "目标应为拒马墙格子")

func test_ai_prefers_enemy_over_obstacle() -> void:
	# 既有可打敌人又有相邻拒马时，打障碍候选不应出现
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(0, 1): &"barricade"}))
	var e = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.ENEMY, Vector2i(1, 1)))
	var p = autofree(UnitFactory.make_unit(50, 50, 40, Unit.Team.PLAYER, Vector2i(2, 1)))
	grid.place_unit(e, e.coords)
	grid.place_unit(p, p.coords)
	var m := _manager(grid, [e, p])
	var plan := BattleAI.decide(e, m)
	var obstacle_atk := plan.filter(func(c): return c is AttackCommand and c.target_cell != Vector2i(-1, -1))
	assert_eq(obstacle_atk.size(), 0, "有普攻候选时不应打障碍")
	assert_true(plan.any(func(c): return c is AttackCommand and c.target == p), "应正常攻击敌人")
