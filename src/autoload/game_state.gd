class_name GameStateClass
extends Node
## AutoLoad（注册名 GameState）：场景间传递状态（当前关卡、战斗结果摘要）。

var current_level_id: String = "debug_01"
var last_result: Dictionary = {}   # Flow.apply_battle_result 的摘要（结果界面展示用）
