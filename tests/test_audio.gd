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
