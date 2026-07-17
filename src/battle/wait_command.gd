class_name WaitCommand
extends Command
## 待机：本回合防御 +20%、怒气 +15（策划文档 6.5 行动表，鼓励战术性蹲坑）。
## 防御增益持续到下次自己行动（持有者回合开始 tick 归零，决策日志 D15）。

func execute(_battle: BattleManager) -> Array:
	if actor == null:
		return []
	actor.gain_rage(15)
	var b := Buff.new()
	b.buff_id = &"wait_def"
	b.name = "待机守备"
	b.stat_mods = {&"def": 20}
	b.duration = 1
	b.dispellable = false
	b.source = actor
	actor.add_buff(b)
	return [
		{"type": "wait", "unit": actor},
		{"type": "rage", "unit": actor, "value": 15},
	]
