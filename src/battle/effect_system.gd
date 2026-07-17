class_name EffectSystem
extends RefCounted
## 原子效果执行器（策划文档 6.7）：技能 = 效果序列，按顺序执行；新技能 = 策划拼资源文件，程序零介入。
## 当前已实现：phys_dmg / rage（W1-2 普攻闭环）；其余效果随 Buff/位移/控制系统逐个注册。
## 解析失败或未实现的效果必须报错并指出技能 ID 与效果名（数据表说明第四节）。

## "phys_dmg(0.9)x4;rage(+20)" -> [{name, args, times}, ...]
static func parse_effects(raw: String) -> Array:
	var out: Array = []
	for part in raw.split(";", false):
		var body := part.strip_edges()
		if body.is_empty():
			continue
		var times := 1
		var x_idx := body.rfind(")x")
		if x_idx != -1:
			var suffix := body.substr(x_idx + 2)
			if suffix.is_valid_int():
				times = maxi(1, int(suffix))
				body = body.substr(0, x_idx + 1)
		var open := body.find("(")
		if open == -1:
			# 无参效果（pull_to_front / sure_hit / swap_position 等）
			out.append({"name": body, "args": [], "times": times})
			continue
		var close := body.rfind(")")
		if open <= 0 or close != body.length() - 1:
			push_error("EffectSystem: 无法解析效果 '%s'" % part)
			continue
		var args: Array = []
		for a in body.substr(open + 1, close - open - 1).split(",", false):
			args.append(a.strip_edges())
		out.append({"name": body.substr(0, open).strip_edges(), "args": args, "times": times})
	return out

## 逻辑瞬时结算；返回表现事件列表供 FX 层排队回放。
static func execute(skill: SkillData, ctx: EffectContext) -> Array:
	var events: Array = []
	for eff in parse_effects(skill.effects):
		for i in range(int(eff["times"])):
			events.append_array(_execute_one(skill, eff, ctx))
	return events

static func _execute_one(skill: SkillData, eff: Dictionary, ctx: EffectContext) -> Array:
	var args: Array = eff["args"]
	match String(eff["name"]):
		"phys_dmg":
			return _phys_dmg(skill, float(args[0]), ctx)
		"rage":
			var v := int(args[0])
			ctx.actor.gain_rage(v)
			return [{"type": "rage", "unit": ctx.actor, "value": v}]
		_:
			push_error("EffectSystem: 未实现的原子效果 '%s'（技能 %s）" % [eff["name"], skill.skill_id])
			return []

static func _phys_dmg(skill: SkillData, multiplier: float, ctx: EffectContext) -> Array:
	var r := DamageCalculator.compute(ctx.actor, ctx.target, multiplier, ctx.grid, ctx.rolls)
	if r["dodged"]:
		return [{"type": "dodge", "source": ctx.actor, "target": ctx.target, "skill": skill.skill_id}]
	var applied: int = ctx.target.take_damage(int(r["amount"]))
	var killed := not ctx.target.is_alive()
	# 怒气：受击 +10（文档未量化，占位值，决策日志 D7）；击杀奖励 +30（策划文档 6.5）
	ctx.target.gain_rage(10)
	if killed:
		ctx.actor.gain_rage(30)
	return [{
		"type": "damage", "source": ctx.actor, "target": ctx.target, "skill": skill.skill_id,
		"amount": applied, "crit": r["crit"], "blocked": r["blocked"],
		"dir_mod": r["dir_mod"], "height_mod": r["height_mod"], "died": killed,
	}]
