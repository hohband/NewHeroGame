extends GutTest
## AI 关卡目标行为（决策日志 D38）：夺取/护送/酒摊路线 + 物件不可攻击 + 触发器 who 按单位判定

var loader: GameDataLoader

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()

func _cargo_manager() -> BattleManager:
	var l := LevelConfig.new()
	l.grid_size = Vector2i(6, 6)
	l.win_condition = {"type": "COLLECT", "target": "cargo", "count": 1}
	l.deploy_zone = Rect2i(0, 4, 6, 2)
	l.required_units = []
	l.objects = [{"id": "cargo", "coords": Vector2i(3, 3), "hp": 300}]
	l.enemies = [{"unit": &"xiangjun_spear", "coords": Vector2i(0, 0)}]
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, l)
	m.rolls = FixedRollSource.new()
	return m

func test_cargo_not_targetable() -> void:
	var m := _cargo_manager()
	var u := m.deploy_unit(&"shi_yong", Vector2i(3, 4))
	assert_eq(m.enemies_in_range(u).size(), 0, "可夺取物件不出现在可攻击列表（D38）")
	# 技能目标解析同样排除
	var cargo: Unit = m.units.filter(func(x): return x.is_object)[0]
	var skill := loader.get_skill(&"ult_chuiyangliu")
	var hits := Targeting.resolve(skill, u, Vector2i(-1, -1), m.grid, m.units, FixedRollSource.new())
	assert_false(hits.has(cargo), "AOE 不会波及镖担（杨志不砸自己的镖）")

func test_ai_collects_adjacent_cargo() -> void:
	var m := _cargo_manager()
	var u := m.deploy_unit(&"shi_yong", Vector2i(3, 4))
	var plan := BattleAI.decide(u, m)
	assert_true(plan.any(func(c): return c is InteractCommand), "相邻物件时 AI 应夺取")

func test_ai_approaches_cargo() -> void:
	var m := _cargo_manager()
	var u := m.deploy_unit(&"shi_yong", Vector2i(0, 5))
	var plan := BattleAI.decide(u, m)
	var mv := plan.filter(func(c): return c is MoveCommand)
	assert_gt(mv.size(), 0, "远离物件时向物件机动")
	var dest: Vector2i = mv[0].path.back()
	var before: int = absi(0 - 3) + absi(5 - 3)
	assert_lt(absi(dest.x - 3) + absi(dest.y - 3), before)

func test_escort_unit_heads_to_zone() -> void:
	var l := LevelConfig.new()
	l.grid_size = Vector2i(6, 8)
	l.win_condition = {"type": "ESCORT", "unit": "chao_gai_npc", "zone": Rect2i(0, 0, 6, 1)}
	l.deploy_zone = Rect2i(0, 6, 6, 2)
	l.npc_allies = [{"unit": &"chao_gai_npc", "coords": Vector2i(3, 6)}]
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, l)
	m.rolls = FixedRollSource.new()
	var npc := m._find_unit(&"chao_gai_npc")
	var plan := BattleAI.decide(npc, m)
	var mv := plan.filter(func(c): return c is MoveCommand)
	assert_gt(mv.size(), 0, "护送目标本人应向目标区机动")
	assert_lt(mv[0].path.back().y, 6, "向北推进")

func test_yaojiu_owner_heads_to_wine_stall() -> void:
	var l := LevelConfig.new()
	l.grid_size = Vector2i(10, 8)
	l.terrain_map = {Vector2i(6, 4): &"wine_stall"}
	l.win_condition = {"type": "COLLECT", "target": "cargo", "count": 3}
	l.deploy_zone = Rect2i(0, 6, 10, 2)
	l.required_units = [&"bai_sheng"]
	l.objects = [{"id": "cargo", "coords": Vector2i(4, 3), "hp": 300}]
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, l)
	m.rolls = FixedRollSource.new()
	var bs := m._find_unit(&"bai_sheng")
	var plan := BattleAI.decide(bs, m)
	var mv := plan.filter(func(c): return c is MoveCommand)
	assert_gt(mv.size(), 0)
	var dest: Vector2i = mv[0].path.back()
	var before: int = absi(bs.coords.x - 6) + absi(bs.coords.y - 4)
	assert_lt(absi(dest.x - 6) + absi(dest.y - 4), before, "白胜向酒摊机动（7.4 T2 路线）")

func test_trigger_who_matches_unit_id() -> void:
	var l := LevelConfig.new()
	l.grid_size = Vector2i(4, 4)
	l.deploy_zone = Rect2i(0, 2, 4, 2)
	l.required_units = []
	l.triggers = [{"id": "t", "once": true, "on": {"type": "ENTER_ZONE", "zone": Rect2i(0, 0, 4, 1), "who": "bai_sheng"},
		"actions": [{"type": "dialogue", "text": "只有白胜能触发"}]}]
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, l)
	m.rolls = FixedRollSource.new()
	var other := m.deploy_unit(&"shi_yong", Vector2i(1, 3))
	var bs := m.deploy_unit(&"bai_sheng", Vector2i(2, 3))
	m.submit_command(MoveCommand.new(other, [Vector2i(1, 2), Vector2i(1, 1), Vector2i(1, 0)]))
	assert_false(bool(m._triggers[0].get("fired", false)), "非白胜进格不触发（D38 who 按单位判定）")
	m.submit_command(MoveCommand.new(bs, [Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)]))
	assert_true(bool(m._triggers[0].get("fired", false)), "白胜进格触发")
