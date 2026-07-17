class_name Command
extends RefCounted
## 指令对象：玩家点击与 AI 决策生成同一种 Command，进同一执行队列（策划文档第十一章）。

var actor: Unit

func _init(p_actor: Unit = null) -> void:
	actor = p_actor

## 逻辑瞬时结算，返回表现事件数组（供 FX 层排队回放）。
func execute(_battle: BattleManager) -> Array:
	push_error("Command.execute() 需要在子类中实现")
	return []
