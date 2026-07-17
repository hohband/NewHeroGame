class_name GameStateClass
extends Node
## AutoLoad（注册名 GameState）：场景间传递状态（当前关卡、战斗结果摘要）。

var current_level_id: String = "debug_01"
var custom_level: LevelConfig = null   # 动态生成的关卡（演武场/远征），优先于 current_level_id
var last_result: Dictionary = {}   # Flow.apply_battle_result 的摘要（结果界面展示用）

func _ready() -> void:
	_register_joypad_actions()

## 手柄动作映射（Steam Deck 适配基础，开发计划 M2）：方向键=光标，A=确认，B=取消，
## X=主动技，Y=绝技，LB=夺取/撤下，RB=集火/换候选，START=待机/开战。
func _register_joypad_actions() -> void:
	_map("battle_up", [JOY_BUTTON_DPAD_UP], [KEY_UP])
	_map("battle_down", [JOY_BUTTON_DPAD_DOWN], [KEY_DOWN])
	_map("battle_left", [JOY_BUTTON_DPAD_LEFT], [KEY_LEFT])
	_map("battle_right", [JOY_BUTTON_DPAD_RIGHT], [KEY_RIGHT])
	_map("battle_confirm", [JOY_BUTTON_A])
	_map("battle_cancel", [JOY_BUTTON_B])
	_map("battle_skill", [JOY_BUTTON_X])
	_map("battle_ult", [JOY_BUTTON_Y])
	_map("battle_lb", [JOY_BUTTON_LEFT_SHOULDER])
	_map("battle_rb", [JOY_BUTTON_RIGHT_SHOULDER])
	_map("battle_wait", [JOY_BUTTON_START])

func _map(action: StringName, buttons: Array, keys: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
