class_name SkillCommand
extends Command
## 技能指令：校验（怒气/冷却）→ 解析目标（范围模板 × 目标规则）→ 逐目标执行效果序列。
## 与 AttackCommand 共用同一指令管道；普攻与技能的唯一差别是 SkillData 内容。

var skill: SkillData
var aim: Vector2i = Vector2i(-1, -1)   # 指向格（line 技能手动施放时必需）

func _init(p_actor: Unit = null, p_skill: SkillData = null, p_aim: Vector2i = Vector2i(-1, -1)) -> void:
	super(p_actor)
	skill = p_skill
	aim = p_aim

func execute(battle: BattleManager) -> Array:
	if actor == null or skill == null:
		return []
	if not battle.can_use_skill(actor, skill):
		push_error("SkillCommand: %s 无法使用 %s（怒气 %d/%d，冷却 %d）" % [
			actor.data.unit_id, skill.skill_id, actor.rage, skill.rage_cost, actor.skill_cooldown(skill.skill_id)])
		return []
	var targets := Targeting.resolve(skill, actor, aim, battle.grid, battle.units, battle.rolls)
	if targets.is_empty():
		push_error("SkillCommand: 技能 %s 无可命中目标" % skill.skill_id)
		return []
	# 先扣怒气再结算（击杀等收益在释放后自然累积，决策日志 D25）
	actor.gain_rage(-skill.rage_cost)
	var events: Array = []
	var killed_any := false
	# 技能等级效果倍率（养成系统：无档案为 1.0）
	var effect_mult := 1.0
	if actor.hero != null:
		effect_mult = Progression.skill_effect_mult(actor.hero, skill.skill_id, battle.data.progression)
	for t in targets:
		var ctx := EffectContext.new(actor, t, battle.grid, battle.rolls, battle)
		ctx.effect_mult = effect_mult
		events.append_array(EffectSystem.execute(skill, ctx))
		if not t.is_alive():
			killed_any = true
	# 修正类后处理（决策日志 D21/D22）：refresh_on_kill 与 extra_action
	for eff in EffectSystem.parse_effects(skill.effects):
		if eff["name"] == "refresh_on_kill" and killed_any:
			actor.extra_action_pending = true
		if eff["name"] == "extra_action":
			# 令 AV 最高（即将行动）的 n 名友军再动（表15：给「下回合行动价值最高」的队友）
			var n := int(eff["args"][0])
			var allies: Array[Unit] = []
			for t in targets:
				if t != actor and t.is_alive() and t.team == actor.team:
					allies.append(t)
			allies.sort_custom(func(a, b): return a.av < b.av)
			for i in range(mini(n, allies.size())):
				allies[i].av = 0.0
				events.append({"type": "extra_action", "target": allies[i]})
	actor.set_cooldown(skill)
	return events
