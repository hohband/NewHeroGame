extends GutTest
## DamageCalculator：伤害公式（策划文档 6.6）、方位/高低差/暴击/格挡/闪避、同类加成相加（决策日志 D6）。

var loader: GameDataLoader
var grid: Grid
var attacker: Unit
var target: Unit

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4)))
	attacker = autofree(UnitFactory.make_unit(100, 0, 50, Unit.Team.PLAYER, Vector2i(1, 1)))
	target = autofree(UnitFactory.make_unit(0, 50, 50, Unit.Team.ENEMY, Vector2i(1, 2)))
	target.facing = Vector2i(0, -1)   # 面向攻击者 = 正面
	grid.place_unit(attacker, Vector2i(1, 1))
	grid.place_unit(target, Vector2i(1, 2))

func test_base_formula() -> void:
	# 100 × 1.0 × 100 ÷ (100 + 50) = 66.67 → 67
	var r := DamageCalculator.compute(attacker, target, 1.0, grid, FixedRollSource.new())
	assert_eq(r["amount"], 67)
	assert_true(r["hit"])
	assert_false(r["crit"])
	assert_false(r["blocked"])

func test_skill_multiplier() -> void:
	# 100 × 2.2 × 100 ÷ 150 = 146.67 → 147
	var r := DamageCalculator.compute(attacker, target, 2.2, grid, FixedRollSource.new())
	assert_eq(r["amount"], 147)

func test_backstab() -> void:
	target.facing = Vector2i(0, 1)   # 背对攻击者
	var r := DamageCalculator.compute(attacker, target, 1.0, grid, FixedRollSource.new())
	assert_eq(r["amount"], 83, "66.67 × 1.25 = 83.3")
	assert_eq(r["dir_mod"], DamageCalculator.BACKSTAB_MOD)

func test_side_attack() -> void:
	target.facing = Vector2i(1, 0)   # 侧向
	var r := DamageCalculator.compute(attacker, target, 1.0, grid, FixedRollSource.new())
	assert_eq(r["amount"], 73, "66.67 × 1.1 = 73.3")

func test_mods_add_not_multiply() -> void:
	# 背刺 +25% 与高地 +15% 相加为 +40%（决策日志 D6，而非 1.25 × 1.15）
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {}, {Vector2i(1, 1): 1}))
	var a = autofree(UnitFactory.make_unit(100, 0, 50, Unit.Team.PLAYER, Vector2i(1, 1)))
	var t = autofree(UnitFactory.make_unit(0, 50, 50, Unit.Team.ENEMY, Vector2i(1, 2)))
	t.facing = Vector2i(0, 1)
	g.place_unit(a, Vector2i(1, 1))
	g.place_unit(t, Vector2i(1, 2))
	var r := DamageCalculator.compute(a, t, 1.0, g, FixedRollSource.new())
	assert_eq(r["amount"], 93, "66.67 × (1 + 0.25 + 0.15) = 93.3")

func test_high_ground_bonus() -> void:
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {}, {Vector2i(1, 1): 1}))
	var a = autofree(UnitFactory.make_unit(100, 0, 50, Unit.Team.PLAYER, Vector2i(1, 1)))
	var t = autofree(UnitFactory.make_unit(0, 50, 50, Unit.Team.ENEMY, Vector2i(1, 2)))
	t.facing = Vector2i(0, -1)
	g.place_unit(a, Vector2i(1, 1))
	g.place_unit(t, Vector2i(1, 2))
	var r := DamageCalculator.compute(a, t, 1.0, g, FixedRollSource.new())
	assert_eq(r["amount"], 77, "66.67 × 1.15 = 76.67")

func test_low_ground_penalty() -> void:
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {}, {Vector2i(1, 2): 1}))
	var a = autofree(UnitFactory.make_unit(100, 0, 50, Unit.Team.PLAYER, Vector2i(1, 1)))
	var t = autofree(UnitFactory.make_unit(0, 50, 50, Unit.Team.ENEMY, Vector2i(1, 2)))
	t.facing = Vector2i(0, -1)
	g.place_unit(a, Vector2i(1, 1))
	g.place_unit(t, Vector2i(1, 2))
	var r := DamageCalculator.compute(a, t, 1.0, g, FixedRollSource.new())
	assert_eq(r["amount"], 60, "66.67 × 0.9 = 60")

func test_crit_multiplier() -> void:
	attacker.data.crit = 10
	var r := DamageCalculator.compute(attacker, target, 1.0, grid, FixedRollSource.new([99.0, 0.0, 99.0]))
	assert_true(r["crit"])
	assert_eq(r["amount"], 100, "66.67 × 1.5 = 100")

func test_block_reduces_damage() -> void:
	target.data.block = 20
	var r := DamageCalculator.compute(attacker, target, 1.0, grid, FixedRollSource.new([99.0, 99.0, 0.0]))
	assert_true(r["blocked"])
	assert_eq(r["amount"], 47, "66.67 × 0.7 = 46.67")

func test_dodge_avoids_all_damage() -> void:
	target.data.dodge = 100
	var r := DamageCalculator.compute(attacker, target, 1.0, grid, FixedRollSource.new([50.0]))
	assert_false(r["hit"])
	assert_true(r["dodged"])
	assert_eq(r["amount"], 0)

func test_minimum_damage_is_one() -> void:
	var a = autofree(UnitFactory.make_unit(1, 0, 50, Unit.Team.PLAYER, Vector2i(1, 1)))
	var t = autofree(UnitFactory.make_unit(0, 999, 50, Unit.Team.ENEMY, Vector2i(1, 2)))
	t.facing = Vector2i(0, -1)
	grid.place_unit(a, Vector2i(1, 1))
	grid.place_unit(t, Vector2i(1, 2))
	var r := DamageCalculator.compute(a, t, 1.0, grid, FixedRollSource.new())
	assert_eq(r["amount"], 1, "伤害保底 1 点")

func test_terrain_def_mod() -> void:
	# 目标站森林：防御 +10%（50 → 55）→ 100 × 100 ÷ 155 = 64.5 → 65
	var g: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4), {Vector2i(1, 2): &"forest"}))
	var a = autofree(UnitFactory.make_unit(100, 0, 50, Unit.Team.PLAYER, Vector2i(1, 1)))
	var t = autofree(UnitFactory.make_unit(0, 50, 50, Unit.Team.ENEMY, Vector2i(1, 2)))
	t.facing = Vector2i(0, -1)
	g.place_unit(a, Vector2i(1, 1))
	g.place_unit(t, Vector2i(1, 2))
	var r := DamageCalculator.compute(a, t, 1.0, g, FixedRollSource.new())
	assert_eq(t.get_def(g), 55)
	assert_eq(r["amount"], 65)
