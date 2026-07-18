extends GutTest
## 占位音频层（决策日志 D39）：合成 SFX 文件有效、AudioManager 加载分组、事件映射不崩

const NEED := [
	"sfx_ui_click", "sfx_ui_hover", "sfx_move_01", "sfx_atk_melee_01", "sfx_atk_melee_02",
	"sfx_atk_melee_03", "sfx_atk_ranged_01", "sfx_hit_01", "sfx_dodge", "sfx_block",
	"sfx_crit", "sfx_die", "sfx_heal", "sfx_buff", "sfx_debuff", "sfx_turn",
	"sfx_win", "sfx_lose", "sfx_levelup", "sfx_unlock", "sfx_collect",
	"sfx_ult_generic", "sfx_ult_fengxue", "sfx_ult_chuiyangliu", "sfx_ult_jiangmenshen", "sfx_ult_wulei",
]

var manager: GameAudioManager

func before_each() -> void:
	manager = GameAudioManager.new()
	add_child(manager)   # 触发 _ready 加载
	autofree(manager)

func test_wav_files_exist_and_valid() -> void:
	for name in NEED:
		var path := "res://assets/audio/sfx/%s.wav" % name
		assert_true(FileAccess.file_exists(path), "%s 存在" % name)
		var stream := AudioStreamWAV.load_from_file(path)
		assert_not_null(stream, "%s 可加载" % name)
		assert_gt(stream.get_length(), 0.02, "%s 有实际内容" % name)

func test_variants_grouped() -> void:
	assert_true(manager.has_sfx("sfx_atk_melee"))
	assert_eq(manager._streams["sfx_atk_melee"].size(), 3, "近战普攻 3 变体归组")
	assert_eq(manager._streams["sfx_move"].size(), 3)

func test_play_skill_routing() -> void:
	manager.enabled = false   # 无头环境不实际播放，只验证路由不崩
	var loader := GameDataLoader.new()
	loader.load_all()
	loader.free()
	var ult := SkillData.new()
	ult.skill_id = &"ult_fengxue"
	ult.type = &"ult"
	ult.target = &"enemy"
	ult.range_shape = &"line"
	assert_true(manager.has_sfx("sfx_" + String(ult.skill_id)))
	manager.play_skill(ult)
	var melee := SkillData.new()
	melee.skill_id = &"generic_melee"
	melee.type = &"active"
	melee.target = &"enemy"
	melee.range_shape = &"adjacent"
	manager.play_skill(melee)

func test_event_mapping_no_crash() -> void:
	manager.enabled = false
	for e in [
		{"type": "move"}, {"type": "damage", "crit": true}, {"type": "damage", "blocked": true},
		{"type": "damage", "died": true}, {"type": "dodge"}, {"type": "heal"},
		{"type": "buff"}, {"type": "status"}, {"type": "collect"}, {"type": "dispel"},
	]:
		manager.play_event(e)
	assert_true(manager.has_sfx("sfx_hit"), "全部事件类型映射执行无异常")

# ---------------------------------------------------------------- 总线与音量设置

func test_bus_layout_exists() -> void:
	assert_gt(AudioServer.get_bus_index(&"Music"), -1, "Music 总线存在（default_bus_layout.tres）")
	assert_gt(AudioServer.get_bus_index(&"SFX"), -1, "SFX 总线存在")

func test_apply_settings_and_restore() -> void:
	var s := {"volume_master": 1.0, "volume_sfx": 1.0, "volume_music": 1.0, "mute": true}
	manager.apply_settings(s)
	assert_true(AudioServer.is_bus_mute(0), "静音应用")
	manager.apply_settings({"mute": false})
	assert_false(AudioServer.is_bus_mute(0), "恢复")

func test_settings_persist_in_profile() -> void:
	var p := PlayerProfile.new()
	p.get_settings()["volume_sfx"] = 0.5
	p.get_settings()["mute"] = true
	var p2 := PlayerProfile.from_dict(p.to_dict())
	assert_eq(float(p2.settings["volume_sfx"]), 0.5, "音量设置入档（D39 注）")
	assert_true(p2.settings["mute"])
	assert_eq(float(p2.get_settings()["volume_master"]), 1.0, "缺省键补默认值")

# ---------------------------------------------------------------- BGM（正式 OGG 优先 + chiptune 兜底，D39 注）

func test_bgm_files_valid() -> void:
	for name in ["bgm_main", "bgm_battle", "bgm_camp"]:
		var ogg := "res://assets/audio/bgm/%s.ogg" % name
		assert_true(FileAccess.file_exists(ogg), "正式 OGG 存在：%s" % name)
		var stream := AudioStreamOggVorbis.load_from_file(ogg)
		assert_not_null(stream, "%s OGG 可加载" % name)
		assert_gt(stream.get_length(), 60.0, "%s 为完整曲目（生成记录：60s+）" % name)

func test_play_bgm_prefers_ogg_with_wav_fallback() -> void:
	manager.play_bgm("bgm_main")
	assert_eq(manager._bgm_name, "bgm_main")
	assert_true(manager._bgm_player.stream is AudioStreamOggVorbis, "优先用正式 OGG")
	assert_true(manager._bgm_player.stream.loop, "OGG 循环播放")
	manager.play_bgm("bgm_battle")
	assert_eq(manager._bgm_name, "bgm_battle", "切曲正常")
	manager.stop_bgm()
	assert_eq(manager._bgm_name, "")
