class_name GameAudioManager
extends Node
## AutoLoad（注册名 AudioManager）：占位音频层（决策日志 D39）。
## SFX 为程序合成芯片音（tools/synth_sfx.py 生成，assets/audio/sfx/），
## 正式音频外包到货后按同名文件整体替换即可，本层接口与事件映射不变。
## BGM 预留 play_bgm()（素材依赖 AI 音乐服务，见 docs/handoff/音频-AI音乐prompt.md）。

const SFX_DIR := "res://assets/audio/sfx/"
const POOL_SIZE := 8

var _streams: Dictionary = {}     # 基名 -> Array[AudioStreamWAV]（_01.._0N 变体）
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()
var enabled := true

func _ready() -> void:
	_rng.randomize()
	_load_streams()
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)

func _load_streams() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		push_warning("AudioManager: 无音效目录 " + SFX_DIR)
		return
	for f in dir.get_files():
		if not f.ends_with(".wav"):
			continue
		var stream := AudioStreamWAV.load_from_file(SFX_DIR + f)
		if stream == null:
			continue
		var base := f.trim_suffix(".wav")
		var key := base
		# 变体归组：sfx_atk_melee_01 -> sfx_atk_melee
		var m := base.rfind("_0")
		if m > 0 and base.substr(m + 1).is_valid_int():
			key = base.substr(0, m)
		if not _streams.has(key):
			_streams[key] = []
		_streams[key].append(stream)

## 播放音效（有变体随机轮换）；name 为基名（如 "sfx_atk_melee"）
func play(name: String) -> void:
	if not enabled or not _streams.has(name):
		return
	var variants: Array = _streams[name]
	var stream: AudioStreamWAV = variants[_rng.randi_range(0, variants.size() - 1)]
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.play()

func has_sfx(name: String) -> bool:
	return _streams.has(name)

## BGM 预留（素材未到位，阻塞项；到位后放 assets/audio/bgm/ 即可）
func play_bgm(_name: String) -> void:
	pass

# ---------------------------------------------------------------- 事件映射（战斗/系统）

## 战斗事件（command_executed 的事件数组）逐条映射
func play_event(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"move", "teleport":
			play("sfx_move")
		"damage":
			if bool(e.get("died", false)):
				play("sfx_die")
			elif bool(e.get("crit", false)):
				play("sfx_crit")
			elif bool(e.get("blocked", false)):
				play("sfx_block")
			else:
				play("sfx_hit")
		"dodge":
			play("sfx_dodge")
		"heal":
			play("sfx_heal")
		"buff":
			play("sfx_buff")
		"status", "dot", "hot":
			play("sfx_debuff")
		"dispel":
			play("sfx_heal")
		"collect":
			play("sfx_collect")
		"rage":
			pass
		"wait":
			pass

## 技能音效：签名绝技专属音，其余按主动/绝技归类
func play_skill(skill: SkillData) -> void:
	var specific := "sfx_" + String(skill.skill_id).replace("ult_", "ult_")
	if skill.type == &"ult" and has_sfx(specific):
		play(specific)
	elif skill.type == &"ult":
		play("sfx_ult_generic")
	elif String(skill.range_shape) in ["diamond", "line"] and String(skill.target) == "enemy":
		play("sfx_atk_ranged")
	else:
		play("sfx_atk_melee")
