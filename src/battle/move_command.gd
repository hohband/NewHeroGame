class_name MoveCommand
extends Command
## 移动：沿寻路路径走到目标格，更新占位与朝向。

var path: Array[Vector2i] = []

func _init(p_actor: Unit = null, p_path: Array[Vector2i] = []) -> void:
	super(p_actor)
	path = p_path

func execute(battle: BattleManager) -> Array:
	if actor == null or path.is_empty():
		return []
	var from := actor.coords
	var dest: Vector2i = path.back()
	if not battle.grid.can_stop(dest, actor):
		push_error("MoveCommand: 目标格不可停留 %s" % dest)
		return []
	battle.grid.move_unit(actor, dest)
	var last_step: Vector2i = dest - (path[path.size() - 2] if path.size() >= 2 else from)
	if last_step != Vector2i.ZERO:
		actor.facing = DamageCalculator.dominant_dir(last_step)
	return [{"type": "move", "unit": actor, "from": from, "path": path.duplicate()}]
