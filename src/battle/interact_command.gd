class_name InteractCommand
extends Command
## 夺取/场景互动：对相邻物件开始 1 回合引导（策划文档 7.3）。
## 消耗本回合行动；下次自己回合开始时完成收讫；引导期间被攻击则打断。

var target: Unit

func _init(p_actor: Unit = null, p_target: Unit = null) -> void:
	super(p_actor)
	target = p_target

func execute(battle: BattleManager) -> Array:
	if not battle.can_channel(actor, target):
		push_error("InteractCommand: 无法对 %s 执行夺取（需相邻、未在引导）" % (target.data.name if target != null else "?"))
		return []
	actor.channeling = target
	return [{"type": "channel_start", "unit": actor, "object": String(target.data.unit_id).trim_prefix("obj_")}]
