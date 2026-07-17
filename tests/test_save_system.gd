extends GutTest
## 存档系统：新档默认、资源规则、JSON 往返（决策日志 D30）

var loader: GameDataLoader
var save: GameSaveSystem

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	save = autofree(GameSaveSystem.new())
	_cleanup()

func after_each() -> void:
	_cleanup()

func _cleanup() -> void:
	if FileAccess.file_exists(GameSaveSystem.SAVE_PATH):
		DirAccess.remove_absolute(GameSaveSystem.SAVE_PATH)

func test_new_game_defaults() -> void:
	save.new_game(loader)
	assert_eq(save.profile.heroes.size(), 3, "初始武将三名（石勇/宋万/杜迁）")
	assert_true(save.profile.has_hero(&"shi_yong"))
	assert_true(save.profile.has_hero(&"song_wan"))
	assert_true(save.profile.has_hero(&"du_qian"))
	assert_eq(save.profile.gold, 2000)
	assert_eq(int(save.profile.items["shard"]), 20)

func test_spend_rules() -> void:
	save.new_game(loader)
	assert_true(save.profile.spend_gold(1000))
	assert_eq(save.profile.gold, 1000)
	assert_false(save.profile.spend_gold(9999), "余额不足不可扣")
	assert_true(save.profile.spend_item(&"shard", 10))
	assert_eq(int(save.profile.items["shard"]), 10)
	assert_false(save.profile.spend_item(&"shard", 99))

func test_save_load_roundtrip() -> void:
	save.new_game(loader)
	var h := save.profile.get_hero(&"shi_yong")
	h.level = 12
	h.star = 3
	h.weapon_enhance = 4
	h.skill_levels[&"act_duming"] = 2
	save.profile.gold = 12345
	save.profile.progress = {"chapter": 3, "cleared": ["ch01_01", "ch01_02"]}
	assert_eq(save.save_game(), OK)
	assert_true(save.has_save())
	# 用新实例读回
	var save2: GameSaveSystem = autofree(GameSaveSystem.new())
	assert_true(save2.load_game())
	var p: PlayerProfile = save2.profile
	assert_eq(p.gold, 12345)
	assert_eq(p.heroes.size(), 3)
	var h2: Hero = p.get_hero(&"shi_yong")
	assert_eq(h2.level, 12)
	assert_eq(h2.star, 3)
	assert_eq(h2.weapon_enhance, 4)
	assert_eq(h2.skill_level(&"act_duming"), 2)
	assert_eq(int(p.progress["chapter"]), 3)
	assert_eq((p.progress["cleared"] as Array).size(), 2)

func test_load_missing_or_corrupt() -> void:
	assert_false(save.has_save(), "无存档时 has_save 为假")
	assert_false(save.load_game())
	# 写入坏文件
	var f := FileAccess.open(GameSaveSystem.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{不是合法JSON")
	f.close()
	assert_false(save.load_game(), "损坏存档读取失败不崩溃")
	assert_engine_error("Parse JSON failed")
	assert_push_error("存档损坏")
