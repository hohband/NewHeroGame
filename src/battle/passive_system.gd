class_name PassiveSystem
extends RefCounted
## 被动技能体系（策划文档 4.3：每名武将 1 主动 + 2 被动 + 1 怒气绝技）。
## 触发点：on_attack（单位攻击命中结算后）/ on_hit（单位被攻击命中后）/ turn_start（单位激活开始时）。
## 目标语义（数据表说明「被动触发语义」一节）：被动无手动目标——target=self 作用于持有者自身；
## target=enemy 作用于「涉事对方」（on_attack→被攻击者，on_hit→攻击者）。
## 结算复用 EffectSystem 同一路径（ctx.depth=1，被动伤害不再触发反击/连锁被动）；
## 概率经 RollSource（chance 修饰词）；事件复用现有类型，前置 passive_trigger 标记事件。
## AI 不评估被动：自动生效，与 AI 决策路径无涉。

## 指令结算后触发 on_attack / on_hit（BattleManager.submit_command 调用，事件并入同一回放队列）。
## 只认指令行动者本人造成的伤害（source == 行动者）：反击/被动造成的伤害不回流触发。
static func after_command(battle: BattleManager, cmd: Command, events: Array) -> Array:
	var out: Array = []
	if cmd == null or cmd.actor == null or not cmd.actor.is_alive():
		return out
	if not (cmd is AttackCommand or cmd is SkillCommand):
		return out
	var hit_targets: Array[Unit] = []
	for e in events:
		if String(e.get("type", "")) != "damage" or e.get("source") != cmd.actor:
			continue
		var t := e.get("target") as Unit
		if t != null and t != cmd.actor and not hit_targets.has(t):
			hit_targets.append(t)
	if hit_targets.is_empty():
		return out
	# on_attack：行动者的被动，涉事对方 = 首个被命中目标（优先存活者）
	var primary: Unit = null
	for t in hit_targets:
		if t.is_alive():
			primary = t
			break
	if primary == null:
		primary = hit_targets[0]
	out.append_array(_fire(battle, cmd.actor, &"on_attack", primary))
	# on_hit：每个被命中且存活目标的被动，涉事对方 = 攻击者
	for t in hit_targets:
		if t.is_alive():
			out.append_array(_fire(battle, t, &"on_hit", cmd.actor))
	return out

## 单位激活开始时触发 turn_start（BattleManager.advance_turn 调用）。
## 无涉事对方：target=enemy 的 turn_start 被动不会触发（validate 拦截）。
static func at_turn_start(battle: BattleManager, unit: Unit) -> Array:
	return _fire(battle, unit, &"turn_start", null)

static func _fire(battle: BattleManager, unit: Unit, trigger: StringName, counterpart: Unit) -> Array:
	var out: Array = []
	if unit == null or not unit.is_alive() or unit.data == null or battle.data == null:
		return out
	for skill: SkillData in battle.data.get_passives_for_unit(unit.data.unit_id, trigger):
		# target=self → 持有者自身；target=enemy → 涉事对方（已死则跳过，避免对尸体结算）
		var target := unit if skill.target == &"self" else counterpart
		if target == null or (skill.target == &"enemy" and not target.is_alive()):
			continue
		var ctx := EffectContext.new(unit, target, battle.grid, battle.rolls, battle)
		ctx.depth = 1   # 深度防连锁（同反击口径，决策日志 D27）
		ctx.mods["passive"] = true   # 被动附带伤害不给目标送受击怒气（决策日志 D41）
		if unit.hero != null:
			ctx.effect_mult = Progression.skill_effect_mult(unit.hero, skill.skill_id, battle.data.progression)
		var evs := EffectSystem.execute(skill, ctx)
		if evs.is_empty():
			continue   # chance 未触发等：无事件即无表现
		out.append({"type": "passive_trigger", "unit": unit, "skill": skill.skill_id,
			"name": skill.name, "trigger": trigger})
		out.append_array(evs)
	return out
