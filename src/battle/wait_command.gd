class_name WaitCommand
extends Command
## 待机：本回合防御 +20%、怒气 +rage_on_wait（battle_constants.csv；策划文档 6.5 行动表，鼓励战术性蹲坑）。
## 防御增益持续到下次自己行动（持有者回合开始 tick 归零，决策日志 D15）。

func execute(battle: BattleManager) -> Array:
	if actor == null:
		return []
	var rage := 15
	if battle != null and battle.data != null:
		rage = int(battle.data.get_constant("rage_on_wait", 15.0))
	actor.gain_rage(rage)
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
		{"type": "rage", "unit": actor, "value": rage},
	]
