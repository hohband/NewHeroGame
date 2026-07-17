extends GutTest
## DataLoader：CSV 解析、BOM 处理、字段映射、数据校验。

var loader: GameDataLoader

func before_each() -> void:
	loader = autofree(GameDataLoader.new()) as GameDataLoader
	loader.load_all()

func test_loads_all_tables() -> void:
	assert_eq(loader.units.size(), 30, "24 名武将 + 6 名敌方/剧情单位（enemies.csv）")
	assert_eq(loader.skills.size(), 28, "26 个武将技能 + 2 个敌方技能")
	assert_eq(loader.terrains.size(), 9, "8 种地形 + 酒摊互动格")

func test_bom_stripped() -> void:
	assert_true(loader.units.has(&"lin_chong"), "首行 unit_id 不含 BOM")

func test_unit_fields() -> void:
	var u := loader.get_unit(&"lin_chong")
	assert_eq(u.name, "林冲")
	assert_eq(u.unit_class, &"cavalry")
	assert_eq(u.hp, 700)
	assert_eq(u.range_min, 1)
	assert_eq(u.range_max, 2)
	assert_eq(u.bonds.size(), 2)
	assert_eq(u.bonds[0]["target"], &"lu_zhishen")
	assert_eq(u.bonds[0]["name"], "结义")

func test_skill_with_quoted_commas() -> void:
	# effects 内含逗号的字段带引号，须按 CSV 标准解析
	var s := loader.get_skill(&"ult_diaohulishan")
	assert_eq(s.effects, "swap_position;debuff_mgc(0.3,2)")

func test_terrain_fields() -> void:
	var t := loader.get_terrain(&"barricade")
	assert_eq(t.move_cost, 99)
	assert_false(t.passable)
	assert_true(t.destructible)
	assert_eq(t.hp, 300)

func test_empty_bonds() -> void:
	var u := loader.get_unit(&"yu_baosi")
	assert_eq(u.bonds.size(), 0)

func test_validate_passes() -> void:
	assert_eq(loader.validate().size(), 0, "交付数据表应通过全部校验")

func test_reserved_registered() -> void:
	assert_true(loader.reserved.has(&"xu_ning"))
	assert_true(loader.reserved.has(&"zhang_qing2"))
