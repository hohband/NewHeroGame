class_name EffectContext
extends RefCounted
## 原子效果执行上下文：谁（actor）对谁（target）在哪张棋盘（grid），用哪个随机源（rolls）。

var actor: Unit
var target: Unit
var grid: Grid
var rolls: RollSource

func _init(p_actor: Unit = null, p_target: Unit = null, p_grid: Grid = null, p_rolls: RollSource = null) -> void:
	actor = p_actor
	target = p_target
	grid = p_grid
	rolls = p_rolls
