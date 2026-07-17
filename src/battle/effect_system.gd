class_name EffectSystem
extends RefCounted
## 原子效果执行器（策划文档 6.7）：技能 = 效果序列，按顺序执行；新技能 = 策划拼资源文件，程序零介入。
## 已实现：phys_dmg / rage / heal / buff 系（def_up、armor_break、dodge_up、block_up、debuff_mgc、move_mod、buff）
## 　　　　DoT（poison、burn、bleed）/ dispel / random_buff；其余效果随技能系统逐个注册。
## 解析失败或未实现的效果必须报错并指出技能 ID 与效果名（数据表说明第四节）。

## DoT 每跳伤害 = 目标最大生命的百分比（占位值，决策日志 D16，待策划确认）
const DOT_PERCENT := 5

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
		"heal":
			return _heal(skill, float(args[0]), ctx)
		"buff":
			return [_apply_stat_buff(ctx, skill, StringName(args[0]), _percent_value(args[1]), int(args[2]), false)]
		"def_up":
			return [_apply_stat_buff(ctx, skill, &"def", _percent_value(args[0]), int(args[1]), false)]
		"armor_break":
			return [_apply_stat_buff(ctx, skill, &"def", -_percent_value(args[0]), int(args[1]), true)]
		"dodge_up":
			return [_apply_stat_buff(ctx, skill, &"dodge", _percent_value(args[0]), int(args[1]), false)]
		"block_up":
			return [_apply_stat_buff(ctx, skill, &"block", _percent_value(args[0]), int(args[1]), false)]
		"debuff_mgc":
			return [_apply_stat_buff(ctx, skill, &"mgc", -_percent_value(args[0]), int(args[1]), true)]
		"move_mod":
			return [_apply_stat_buff(ctx, skill, &"move", int(args[0]), int(args[1]), String(args[0]).begins_with("-"))]
		"poison":
			return [_apply_dot(ctx, skill, &"poison", int(args[0]))]
		"burn":
			return [_apply_dot(ctx, skill, &"burn", int(args[0]))]
		"bleed":
			return [_apply_dot(ctx, skill, &"bleed", int(args[0]))]
		"dispel":
			var ids: Array = ctx.target.dispel_debuffs(int(args[0]))
			return [{"type": "dispel", "target": ctx.target, "removed": ids}]
		"random_buff":
			return _random_buff(skill, args, ctx)
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

## 治疗量 = 施法者谋略 × 倍率（文档未定义，决策日志 D19，待策划确认）
static func _heal(skill: SkillData, multiplier: float, ctx: EffectContext) -> Array:
	var amount := maxi(0, roundi(float(ctx.actor.get_mgc()) * multiplier))
	var applied := ctx.target.heal(amount)
	return [{"type": "heal", "source": ctx.actor, "target": ctx.target, "skill": skill.skill_id, "amount": applied}]

## CSV 数值惯例：0.3 = 30%（决策日志 D15）
static func _percent_value(arg: String) -> int:
	return roundi(float(arg) * 100.0)

static func _apply_stat_buff(ctx: EffectContext, skill: SkillData, field: StringName, value: int, duration: int, is_debuff: bool) -> Dictionary:
	var b := Buff.new()
	b.buff_id = StringName("%s_%s" % [skill.skill_id, field])
	b.name = skill.name
	b.stat_mods = {field: value}
	b.duration = duration
	b.is_debuff = is_debuff
	b.source = ctx.actor
	ctx.target.add_buff(b)
	return {"type": "buff", "target": ctx.target, "buff": b.buff_id, "field": field, "value": value, "duration": duration}

static func _apply_dot(ctx: EffectContext, skill: SkillData, dot_id: StringName, duration: int) -> Dictionary:
	var b := Buff.new()
	b.buff_id = dot_id
	b.name = skill.name
	b.duration = duration
	b.is_debuff = true
	b.tick_effect = {"kind": "dot", "percent": DOT_PERCENT}
	b.source = ctx.actor
	ctx.target.add_buff(b)
	return {"type": "buff", "target": ctx.target, "buff": dot_id, "duration": duration}

## random_buff(A参数|B参数)，如 random_buff(def_up,0.4,2|counter,1)：随机执行一个选项
static func _random_buff(skill: SkillData, args: Array, ctx: EffectContext) -> Array:
	var options := ",".join(args).split("|", false)
	if options.is_empty():
		push_error("EffectSystem: random_buff 无选项（技能 %s）" % skill.skill_id)
		return []
	var idx := 0 if ctx.rolls.roll() < 50.0 else options.size() - 1
	var parts := options[mini(idx, options.size() - 1)].split(",", false)
	if parts.is_empty():
		push_error("EffectSystem: random_buff 选项为空（技能 %s）" % skill.skill_id)
		return []
	var eff := {"name": parts[0].strip_edges(), "args": parts.slice(1), "times": 1}
	return _execute_one(skill, eff, ctx)
