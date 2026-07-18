class_name ItemCommand
extends Command
## 道具指令（策划 6.5「道具：每局限用次数」）：消耗道具栏一次使用次数，借道 Targeting/EffectSystem 结算效果。
## 与攻击/技能同走 BattleManager.submit_command 管道；使用即占本激活「行动」（action_used，同攻击口径），
## 分段移动规则不受影响。道具不触发攻击类被动（非攻击/技能，PassiveSystem 只认 Attack/SkillCommand）。
## AI 不使用道具（决策日志口径）；meta/背包对接见 BattleManager.set_item_stock。

var item: ItemData
## 指定目标（玩家点选）：须在道具范围内，且只对该目标生效（道具为单目标指定）；
## 为空时退回技能同口径——范围内全体合法目标生效（脚本化/测试用）。
var target_unit: Unit = null
var aim := Vector2i(-1, -1)   # line 类道具的指向格（当前道具表无 line 行，保留与技能同口径）

func _init(p_actor: Unit = null, p_item: ItemData = null, p_target: Unit = null, p_aim: Vector2i = Vector2i(-1, -1)) -> void:
	super(p_actor)
	item = p_item
	target_unit = p_target
	aim = p_aim

func execute(battle: BattleManager) -> Array:
	if actor == null or item == null:
		return []
	if not battle.can_use_item(actor, item):
		push_error("ItemCommand: %s 无法使用 %s（剩余 %d 次，行动%s用）" % [
			actor.data.unit_id, item.item_id, battle.item_uses_left(item.item_id),
			"已" if battle.action_used else "未"])
		return []
	var skill := item.to_skill_data()
	var targets := Targeting.resolve(skill, actor, aim, battle.grid, battle.units, battle.rolls)
	if target_unit != null:
		if not targets.has(target_unit):
			push_error("ItemCommand: 目标不在道具 %s 的合法范围内" % item.item_id)
			return []
		targets = [target_unit]
	if targets.is_empty():
		push_error("ItemCommand: 道具 %s 无可命中目标" % item.item_id)
		return []
	# 先扣次数再结算（同技能先扣怒气口径，决策日志 D25）
	battle.consume_item(item.item_id)
	var events: Array = [{"type": "item_use", "unit": actor, "item": item.item_id,
		"name": item.name, "left": battle.item_uses_left(item.item_id)}]
	for t in targets:
		var ctx := EffectContext.new(actor, t, battle.grid, battle.rolls, battle)
		events.append_array(EffectSystem.execute(skill, ctx))
	# 使用道具 = 本激活的「行动」（策划 6.5 行动表，与攻击/技能同级）
	battle.action_used = true
	return events
