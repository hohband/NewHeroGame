extends GutTest
## 特殊关卡机制（策划 6.8）：迷雾（布阵阶段敌情不明）与限定职业上阵（马军限定挑战关）

var loader: GameDataLoader

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()

func _manager(level: LevelConfig) -> BattleManager:
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, level)
	m.rolls = FixedRollSource.new()
	return m

func _base_level() -> LevelConfig:
	var l := LevelConfig.new()
	l.id = "test_special"
	l.grid_size = Vector2i(6, 6)
	l.deploy_zone = Rect2i(0, 4, 6, 2)
	l.max_deploy = 4
	l.required_units = []
	l.roster = [&"lin_chong", &"wu_yong"]
	l.enemies = [{"unit": &"shi_yong", "coords": Vector2i(3, 1)}]
	l.win_condition = {"type": "WIPE_OUT"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	return l

# ---------------------------------------------------------------- LevelConfig 字段

func test_special_fields_default_off() -> void:
	var l := LevelConfig.new()
	assert_false(l.fog, "默认无迷雾")
	assert_eq(l.allowed_classes.size(), 0, "默认不限职业")

func test_registry_levels_carry_special_fields() -> void:
	var majun := LevelRegistry.get_level("challenge_majun")
	assert_not_null(majun)
	assert_eq(majun.allowed_classes, ["cavalry"], "马军限定关限定 cavalry")
	assert_eq(majun.mode, "challenge")
	var fog_level := LevelRegistry.get_level("daily_mat_1")
	assert_true(fog_level.fog, "奇袭·辎重营为迷雾示范关")
	var normal := LevelRegistry.get_level("daily_exp_1")
	assert_false(normal.fog, "普通日常关无迷雾")
	assert_eq(normal.allowed_classes.size(), 0)

# ---------------------------------------------------------------- 迷雾：布阵阶段不暴露敌方

func test_fog_hides_enemy_deploy_intel() -> void:
	var l := _base_level()
	l.fog = true
	var m := _manager(l)
	assert_eq(m.deploy_intel_enemies().size(), 0, "迷雾关布阵敌情查询不暴露敌方")
	assert_not_null(m.grid.get_cell(Vector2i(3, 1)).occupant, "敌方单位仍正常落位（仅信息隐藏）")

func test_no_fog_exposes_enemy_deploy_intel() -> void:
	var m := _manager(_base_level())
	var intel := m.deploy_intel_enemies()
	assert_eq(intel.size(), 1, "非迷雾关布阵敌情可见")
	assert_eq(intel[0].data.unit_id, &"shi_yong")

# ---------------------------------------------------------------- 限定职业：布阵硬校验

func test_class_restriction_rejects_disallowed() -> void:
	var l := _base_level()
	l.allowed_classes = ["cavalry"]
	var m := _manager(l)
	var bad := m.deploy_unit(&"wu_yong", Vector2i(1, 4))   # 步军，非限定职业
	assert_null(bad, "非限定职业不可上阵（逻辑层硬校验）")
	assert_push_error("限定职业")
	assert_eq(m.deployed.size(), 0)

func test_class_restriction_allows_listed_class() -> void:
	var l := _base_level()
	l.allowed_classes = ["cavalry"]
	var m := _manager(l)
	var ok := m.deploy_unit(&"lin_chong", Vector2i(1, 4))   # 马军
	assert_not_null(ok, "限定职业可正常上阵")
	assert_true(m.confirm_deploy(), "限定职业上阵后可开战")

func test_class_restriction_helper() -> void:
	var l := _base_level()
	l.allowed_classes = ["cavalry"]
	var m := _manager(l)
	assert_true(m.is_class_allowed(&"lin_chong"), "林冲 = 马军")
	assert_false(m.is_class_allowed(&"wu_yong"), "吴用 = 谋士")
	l.allowed_classes = []
	assert_true(m.is_class_allowed(&"wu_yong"), "空表 = 不限")

# ---------------------------------------------------------------- 马军限定挑战关内容

func test_majun_level_valid() -> void:
	var l := LevelRegistry.get_level("challenge_majun")
	assert_not_null(l)
	assert_gt(l.enemies.size(), 0)
	for spec in l.enemies:
		assert_not_null(loader.get_unit(spec["unit"]), "敌方 %s 在表内" % spec["unit"])
	var cavalry_count := 0
	for id in l.roster:
		if String(loader.get_unit(id).unit_class) == "cavalry":
			cavalry_count += 1
	assert_eq(cavalry_count, 3, "候选池含全部三员马军（林冲/秦明/扈三娘）")
	assert_true(l.max_deploy <= cavalry_count, "上阵上限不超过可用马军数")

func test_majun_deploy_flow() -> void:
	var m := _manager(LevelRegistry.get_level("challenge_majun"))
	var non_cavalry := m.deploy_unit(&"wu_song", Vector2i(1, 6))
	assert_null(non_cavalry, "武松（步军）被马军限定拒绝")
	assert_push_error("限定职业")
	var cells := m._free_deploy_cells()
	var ok := m.deploy_unit(&"lin_chong", cells[0])
	assert_not_null(ok)
	assert_true(m.confirm_deploy(), "马军上阵后可开战")
