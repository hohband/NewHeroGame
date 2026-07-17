class_name EffectSystem
extends RefCounted
## 原子效果执行器（策划文档 6.7）：技能 = 效果序列，按顺序执行；新技能 = 策划拼资源文件，程序零介入。
## 已实现：phys_dmg / rage / heal / buff 系（def_up、armor_break、dodge_up、block_up、debuff_mgc、move_mod、buff）
## 　　　　DoT（poison、burn、bleed）/ dispel / random_buff；其余效果随技能系统逐个注册。
## 解析失败或未实现的效果必须报错并指出技能 ID 与效果名（数据表说明第四节）。

## DoT 每跳伤害 = 目标最大生命的百分比（占位值，决策日志 D16，待策划确认）
const DOT_PERCENT := 5
## 「高防目标」判定阈值（曹正解牛刀法，占位值，决策日志 D22，待策划确认）
const HIGH_DEF_THRESHOLD := 100
## 修正类效果：不改变执行顺序，前置扫描进 mods 供伤害/目标结算消费（决策日志 D21）
const MODIFIER_EFFECTS: Array[String] = [
	"bonus_by_self_lost_hp", "bonus_vs_elite", "bonus_vs_high_def", "bonus_vs_cavalry",
	"sure_hit", "hit_rate", "target_rule", "execute_below", "random_target", "friendly_fire",
	"refresh_on_kill",
]

## 前置扫描修正类效果（决策日志 D21）：与 effects 字段中的书写顺序无关。
static func scan_modifiers(effects: Array) -> Dictionary:
	var mods: Dictionary = {}
	for eff in effects:
		var args: Array = eff["args"]
		match String(eff["name"]):
			"sure_hit":
				mods["sure_hit"] = true
			"hit_rate":
				mods["hit_rate"] = float(args[0])
			"bonus_by_self_lost_hp":
				mods["bonus_by_self_lost_hp"] = float(args[0])
			"bonus_vs_elite":
				mods["bonus_vs_elite"] = float(args[0])
			"bonus_vs_high_def":
				mods["bonus_vs_high_def"] = float(args[0])
			"bonus_vs_cavalry":
				mods["bonus_vs_cavalry"] = float(args[0])
			"execute_below":
				mods["execute_below"] = float(args[0])
			"target_rule":
				mods["target_rule"] = String(args[0])
			"random_target":
				mods["random_target"] = int(args[0])
			"friendly_fire":
				mods["friendly_fire"] = float(args[0])
	return mods

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
## 修正类效果前置扫描进 ctx.mods（决策日志 D21），不在序列中逐条执行。
static func execute(skill: SkillData, ctx: EffectContext) -> Array:
	var effects := parse_effects(skill.effects)
	ctx.mods = scan_modifiers(effects)
	var events: Array = []
	for eff in effects:
		if MODIFIER_EFFECTS.has(String(eff["name"])):
			continue
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
		"pull":
			return [_pull(ctx, int(args[0]))]
		"stun":
			return [_apply_status(ctx, skill, &"stun", int(args[0]))]
		"sleep":
			return [_apply_status(ctx, skill, &"sleep", int(args[0]))]
		"sleep_chance":
			if ctx.rolls.roll() < float(args[0]) * 100.0:
				return [_apply_status(ctx, skill, &"sleep", int(args[1]))]
			return [{"type": "status_resist", "target": ctx.target, "status": &"sleep"}]
		"paralyze":
			return [_apply_status(ctx, skill, &"paralyze", int(args[0]))]
		"bind":
			return [_apply_status(ctx, skill, &"bind", int(args[0]))]
		_:
			push_error("EffectSystem: 未实现的原子效果 '%s'（技能 %s）" % [eff["name"], skill.skill_id])
			return []

static func _phys_dmg(skill: SkillData, multiplier: float, ctx: EffectContext) -> Array:
	var mods := ctx.mods
	# hit_rate(p)：整个技能按概率命中（白胜蒙汗药酒 80%）
	if mods.has("hit_rate") and ctx.rolls.roll() >= float(mods["hit_rate"]) * 100.0:
		return [{"type": "miss", "source": ctx.actor, "target": ctx.target, "skill": skill.skill_id}]
	# execute_below(v)：目标血量比例 ≤ v 直接斩杀（丧门剑，决策日志 D22）
	if mods.has("execute_below") and float(ctx.target.hp) / float(ctx.target.data.hp) <= float(mods["execute_below"]):
		var executed: int = ctx.target.take_damage(ctx.target.hp)
		return [{"type": "damage", "source": ctx.actor, "target": ctx.target, "skill": skill.skill_id,
			"amount": executed, "crit": false, "blocked": false, "dir_mod": 0.0, "height_mod": 0.0,
			"died": true, "executed": true}]
	# 修正类效果折算进技能倍率（决策日志 D21）
	var mult := multiplier
	if mods.has("bonus_by_self_lost_hp"):
		var lost := 1.0 - float(ctx.actor.hp) / float(ctx.actor.data.hp)
		mult *= 1.0 + float(mods["bonus_by_self_lost_hp"]) * lost
	if mods.has("bonus_vs_elite") and ctx.target.is_elite:
		mult *= 1.0 + float(mods["bonus_vs_elite"])
	if mods.has("bonus_vs_high_def") and ctx.target.get_def(ctx.grid) >= HIGH_DEF_THRESHOLD:
		mult *= 1.0 + float(mods["bonus_vs_high_def"])
	if mods.has("bonus_vs_cavalry") and ctx.target.data.unit_class == &"cavalry":
		mult *= 1.0 + float(mods["bonus_vs_cavalry"])
	var sure_hit := bool(mods.get("sure_hit", false))
	var r := DamageCalculator.compute(ctx.actor, ctx.target, mult, ctx.grid, ctx.rolls, 0.0, sure_hit)
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

## 将目标向 actor 拉近 cells 格（遇阻挡/贴脸停，决策日志 D23）
static func _pull(ctx: EffectContext, cells: int) -> Dictionary:
	var moved := 0
	for i in range(cells):
		var dir := DamageCalculator.dominant_dir(ctx.actor.coords - ctx.target.coords)
		if dir == Vector2i.ZERO:
			break
		var next: Vector2i = ctx.target.coords + dir
		if not ctx.grid.can_stop(next, ctx.target):
			break
		ctx.grid.move_unit(ctx.target, next)
		moved += 1
	return {"type": "pull", "target": ctx.target, "cells": moved, "to": ctx.target.coords}

## 控制状态（决策日志 D22）：stun/paralyze/sleep = 跳过行动；sleep 受击解除；bind = 不可移动、可行动
static func _apply_status(ctx: EffectContext, skill: SkillData, status: StringName, duration: int) -> Dictionary:
	var b := Buff.new()
	b.buff_id = status
	b.name = skill.name
	b.status = status
	b.duration = duration
	b.is_debuff = true
	b.source = ctx.actor
	ctx.target.add_buff(b)
	return {"type": "status", "target": ctx.target, "status": status, "duration": duration}

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
