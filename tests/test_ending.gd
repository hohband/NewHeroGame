extends GutTest
## 终章双路线结局（剧情框架：招安/不招安，提升重复游玩价值）

var loader: GameDataLoader
var profile: PlayerProfile

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	profile = PlayerProfile.new_default(loader)
	profile.progress["chapter"] = 7

func _win(level_id: String) -> Dictionary:
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, LevelRegistry.get_level(level_id))
	return Flow.apply_battle_result(profile, LevelRegistry.get_level(level_id),
		m.compute_result(Unit.Team.PLAYER), [], loader)

func test_ending_levels_valid() -> void:
	for id in ["ch07_01a", "ch07_01b"]:
		var l := LevelRegistry.get_level(id)
		assert_not_null(l)
		assert_eq(l.chapter, 7)
		assert_gt(l.enemies.size(), 0)
		assert_eq(l.mode, "story")

func test_zhaoan_route_records_ending() -> void:
	var s := _win("ch07_01a")
	assert_eq(String(profile.progress.get("ending", "")), "zhaoan", "招安线写入结局")
	assert_eq(String(s.get("ending", "")), "zhaoan")
	assert_gt((s.get("epilogue", []) as Array).size(), 0, "带后日谈")

func test_kangzhao_route_records_ending() -> void:
	var s := _win("ch07_01b")
	assert_eq(String(profile.progress.get("ending", "")), "kangzhao", "不招安线写入结局")
	assert_eq(String(s.get("ending", "")), "kangzhao")

func test_ending_does_not_advance_chapter() -> void:
	_win("ch07_01a")
	assert_eq(int(profile.progress["chapter"]), 7, "结局关不再推进章节（大聚义即终章）")

func test_both_routes_replayable() -> void:
	_win("ch07_01a")
	assert_eq(String(profile.progress["ending"]), "zhaoan")
	_win("ch07_01b")   # 重打另一路线（重复游玩价值，剧情框架）
	assert_eq(String(profile.progress["ending"]), "kangzhao", "另一路线可覆盖结局")
