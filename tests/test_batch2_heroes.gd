extends GutTest
## 第二批 6 将（5.6 补羁绊/神射缺口）+ 水战特性（6.3 水面留坑，决策日志 D36）

var loader: GameDataLoader

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()

func test_batch2_loaded() -> void:
	for id in [&"xu_ning", &"zhang_shun", &"wang_ying", &"gong_wang", &"ding_desun", &"yan_qing"]:
		assert_not_null(loader.get_unit(id), "%s 已实装" % id)
	assert_eq(loader.units.size(), 36, "24+6 将 + 6 敌方")
	assert_eq(loader.skills.size(), 34, "技能表 +6")

func test_bond_gaps_filled() -> void:
	# 原先的预留羁绊缺口全部闭环（5.6：优先补首批标注「预留」的羁绊缺口）
	assert_eq(loader.validate().size(), 0)
	assert_eq(loader.get_unit(&"shi_qian").bonds[0]["target"], &"xu_ning")
	assert_eq(loader.get_unit(&"an_daoquan").bonds[0]["target"], &"zhang_shun")
	assert_eq(loader.get_unit(&"hu_sanniang").bonds[0]["target"], &"wang_ying")
	assert_eq(loader.get_unit(&"zhang_qing").bonds.size(), 2, "张清两员副将到位")

func test_archer_gap_filled() -> void:
	# 首发神射仅 2 名是刻意缺口（5.6），第二批补 3 名
	var archers := 0
	for id in [&"hua_rong", &"zhang_qing", &"gong_wang", &"ding_desun", &"yan_qing"]:
		if loader.get_unit(id).unit_class == &"archer":
			archers += 1
	assert_eq(archers, 5)

func test_reserved_list_updated() -> void:
	assert_false(loader.reserved.has(&"xu_ning"), "已实装移出预留名单")
	assert_true(loader.reserved.has(&"lu_junyi"), "卢俊义新登记（燕青主仆羁绊）")

func test_water_walker_ignores_water() -> void:
	# 河道挡路：张顺（水军）水面消耗 1 且不吃减速，其他人消耗 3 且移动 -1
	var grid: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(4, 4),
		{Vector2i(1, 0): &"water", Vector2i(1, 1): &"water", Vector2i(1, 2): &"water", Vector2i(1, 3): &"water"}))
	var zs: Unit = autofree(Unit.new())
	zs.setup(loader.get_unit(&"zhang_shun"), Unit.Team.PLAYER, Vector2i(0, 1))
	grid.place_unit(zs, Vector2i(0, 1))
	var r := grid.get_reachable(zs, 4)
	assert_true(r.has(Vector2i(3, 1)), "张顺横渡河道（水面 1 消耗）")
	var zs2 = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(1, 1)))
	grid.place_unit(zs2, Vector2i(1, 1))
	assert_eq(zs.get_move(grid), 6, "张顺站水面不减速")
	# 普通人：站水面移动 -1，过水每格 3 消耗
	var normal = autofree(UnitFactory.make_unit(100, 50, 80, Unit.Team.PLAYER, Vector2i(0, 1)))
	normal.data.move = 3
	var r2 := grid.get_reachable(normal, 3)
	assert_false(r2.has(Vector2i(3, 1)), "普通人 3 移动力过不去 3 格水路")

func test_new_skills_parse_and_work() -> void:
	# 徐宁金枪破阵：直线伤害 + 破甲
	var grid: Grid = autofree(UnitFactory.make_grid(loader, Vector2i(6, 6)))
	var xn: Unit = autofree(Unit.new())
	xn.setup(loader.get_unit(&"xu_ning"), Unit.Team.PLAYER, Vector2i(0, 0))
	grid.place_unit(xn, Vector2i(0, 0))
	var e = autofree(UnitFactory.make_unit(50, 60, 40, Unit.Team.ENEMY, Vector2i(2, 0)))
	grid.place_unit(e, Vector2i(2, 0))
	var m: BattleManager = autofree(BattleManager.new())
	m.setup(loader, grid, [xn, e])
	m.rolls = FixedRollSource.new()
	m.submit_command(SkillCommand.new(xn, loader.get_skill(&"act_jinqiang"), Vector2i(2, 0)))
	assert_eq(e.get_stat_mod(&"def"), -30, "金枪破阵破甲 30%")
	assert_gt(e.hp, 0)
	assert_lt(e.hp, 500, "伤害生效")
