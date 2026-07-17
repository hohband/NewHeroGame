class_name EffectSystem
extends RefCounted
## 原子效果执行器（策划文档 6.7）：技能 = 效果序列，按顺序执行；新技能 = 策划拼资源文件，程序零介入。
## 已实现：伤害/治疗（phys_dmg、mgc_dmg、heal）、怒气（rage）、位移（pull、push、pull_to_front、
## swap_position、teleport）、控制（stun、sleep、sleep_chance、paralyze、bind）、增减益（buff、def_up、
## armor_break、dodge_up、block_up、debuff_mgc、move_mod）、机制（steal_buff、dispel、summon、aura、
## guard、counter、extra_action*、av_mod）、DoT（poison、burn、bleed）、random_buff、hit_rate。
## （* extra_action 为修正类，由 SkillCommand 统一处理；词表同步见数据表说明第三节）
## 解析失败或未实现的效果必须报错并指出技能 ID 与效果名（数据表说明第四节）。

## DoT 每跳伤害 = 目标最大生命的百分比（占位值，决策日志 D16，待策划确认）
const DOT_PERCENT := 5
## 「高防目标」判定阈值（曹正解牛刀法，占位值，决策日志 D22，待策划确认）
const HIGH_DEF_THRESHOLD := 100
## 召唤物默认耐久（旗帜等，占位值，决策日志 D27）
const SUMMON_HP := 300
## 修正类效果：不改变执行顺序，前置扫描进 mods 供伤害/目标结算消费（决策日志 D21）
const MODIFIER_EFFECTS: Array[String] = [
	"bonus_by_self_lost_hp", "bonus_vs_elite", "bonus_vs_high_def", "bonus_vs_cavalry",
	"sure_hit", "hit_rate", "target_rule", "execute_below", "random_target", "friendly_fire",
	"refresh_on_kill", "extra_action",
]

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

## 逻辑瞬时结算；返回表现事件列表供 FX 层排队回放。
## 修正类效果前置扫描进 ctx.mods（决策日志 D21），不在序列中逐条执行。
static func execute(skill: SkillData, ctx: EffectContext) -> Array:
	var effects := parse_effects(skill.effects)
	ctx.mods = scan_modifiers(effects)
	# hit_rate(p)：整个技能对该目标按概率命中（白胜蒙汗药酒 80%，逐目标判定）
	if ctx.mods.has("hit_rate") and ctx.rolls.roll() >= float(ctx.mods["hit_rate"]) * 100.0:
		return [{"type": "miss", "source": ctx.actor, "target": ctx.target, "skill": skill.skill_id}]
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
		"mgc_dmg":
			return _phys_dmg(skill, float(args[0]), ctx, ctx.actor.get_mgc())
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
			return [_displace(ctx, int(args[0]), 1)]
		"push":
			return [_displace(ctx, int(args[0]), -1)]
		"pull_to_front":
			return [_pull_to_front(ctx)]
		"swap_position":
			return [_swap_position(ctx)]
		"teleport":
			return [_teleport(ctx, int(args[0]))]
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
		"guard":
			return [_apply_status(ctx, skill, &"guard", int(args[0]))]
		"counter":
			return [_apply_status(ctx, skill, &"counter", int(args[0]))]
		"steal_buff":
			return [_steal_buff(ctx, int(args[0]))]
		"av_mod":
			ctx.target.av *= 1.0 + float(args[0])   # 戴宗神行百变：av_mod(-0.5) = 全队 AV 减半
			return [{"type": "av_mod", "target": ctx.target, "value": float(args[0])}]
		"summon":
			return [_summon(ctx, String(args[0]))]
		"aura":
			return [_aura(ctx, skill, args)]
		_:
			push_error("EffectSystem: 未实现的原子效果 '%s'（技能 %s）" % [eff["name"], skill.skill_id])
			return []

# ---------------------------------------------------------------- 伤害

static func _phys_dmg(skill: SkillData, multiplier: float, ctx: EffectContext, attack_value: int = -1) -> Array:
	var target := ctx.target
	# guard：相邻友军替其挡下远程攻击（宋万铁壁，决策日志 D27）
	if ctx.depth == 0 and target != ctx.actor and _manhattan(ctx.actor.coords, target.coords) > 1:
		for d in Grid.DIRS:
			var c := ctx.grid.get_cell(target.coords + d)
			if c != null and c.occupant != null and c.occupant.is_alive() \
					and c.occupant.team == target.team and c.occupant.has_status(&"guard"):
				target = c.occupant
				break
	var events: Array = []
	var mods := ctx.mods
	# execute_below(v)：目标血量比例 ≤ v 直接斩杀（丧门剑，决策日志 D22）
	if mods.has("execute_below") and float(target.hp) / float(target.data.hp) <= float(mods["execute_below"]):
		var executed: int = target.take_damage(target.hp)
		return [{"type": "damage", "source": ctx.actor, "target": target, "skill": skill.skill_id,
			"amount": executed, "crit": false, "blocked": false, "dir_mod": 0.0, "height_mod": 0.0,
			"died": true, "executed": true}]
	# 修正类效果折算进技能倍率（决策日志 D21）；技能等级倍率（养成）一并乘入
	var mult := multiplier * ctx.effect_mult
	if mods.has("bonus_by_self_lost_hp"):
		var lost := 1.0 - float(ctx.actor.hp) / float(ctx.actor.data.hp)
		mult *= 1.0 + float(mods["bonus_by_self_lost_hp"]) * lost
	if mods.has("bonus_vs_elite") and target.is_elite:
		mult *= 1.0 + float(mods["bonus_vs_elite"])
	if mods.has("bonus_vs_high_def") and target.get_def(ctx.grid) >= HIGH_DEF_THRESHOLD:
		mult *= 1.0 + float(mods["bonus_vs_high_def"])
	if mods.has("bonus_vs_cavalry") and target.data.unit_class == &"cavalry":
		mult *= 1.0 + float(mods["bonus_vs_cavalry"])
	var sure_hit := bool(mods.get("sure_hit", false))
	var r := DamageCalculator.compute(ctx.actor, target, mult, ctx.grid, ctx.rolls, 0.0, sure_hit, attack_value)
	if r["dodged"]:
		return [{"type": "dodge", "source": ctx.actor, "target": target, "skill": skill.skill_id}]
	var applied: int = target.take_damage(int(r["amount"]))
	var killed := not target.is_alive()
	# 怒气：受击 +10（文档未量化，占位值，决策日志 D7）；击杀奖励 +30（策划文档 6.5）
	target.gain_rage(10)
	if killed:
		ctx.actor.gain_rage(30)
	events.append({
		"type": "damage", "source": ctx.actor, "target": target, "skill": skill.skill_id,
		"amount": applied, "crit": r["crit"], "blocked": r["blocked"],
		"dir_mod": r["dir_mod"], "height_mod": r["height_mod"], "died": killed,
	})
	# counter：受击方在武器范围内反击一次（杜迁摸着天/石勇赌命，决策日志 D27；深度防互反）
	if not killed and ctx.depth == 0 and target.has_status(&"counter"):
		var dist := _manhattan(ctx.actor.coords, target.coords)
		if dist >= target.data.range_min and dist <= target.data.range_max:
			var cctx := EffectContext.new(target, ctx.actor, ctx.grid, ctx.rolls, ctx.battle)
			cctx.depth = 1
			events.append_array(_phys_dmg(skill, 1.0, cctx))
	return events

## 治疗量 = 施法者谋略 × 倍率 × 技能等级倍率（D19 占位；养成倍率见 progression.csv）
static func _heal(skill: SkillData, multiplier: float, ctx: EffectContext) -> Array:
	var amount := maxi(0, roundi(float(ctx.actor.get_mgc()) * multiplier * ctx.effect_mult))
	var applied := ctx.target.heal(amount)
	return [{"type": "heal", "source": ctx.actor, "target": ctx.target, "skill": skill.skill_id, "amount": applied}]

# ---------------------------------------------------------------- 位移

## 拉（dir_sign=1，向施法者）/ 推（-1，远离施法者），逐格移动，遇阻挡或贴脸停（决策日志 D23）
static func _displace(ctx: EffectContext, cells: int, dir_sign: int) -> Dictionary:
	var moved := 0
	for i in range(cells):
		var dir := DamageCalculator.dominant_dir(ctx.actor.coords - ctx.target.coords) * dir_sign
		if dir == Vector2i.ZERO:
			break
		var next: Vector2i = ctx.target.coords + dir
		if not ctx.grid.can_stop(next, ctx.target):
			break
		ctx.grid.move_unit(ctx.target, next)
		moved += 1
	return {"type": "pull" if dir_sign > 0 else "push", "target": ctx.target, "cells": moved, "to": ctx.target.coords}

## 拉至施法者身前（红棉套索）：向施法者拉近至相邻为止
static func _pull_to_front(ctx: EffectContext) -> Dictionary:
	var moved := 0
	while _manhattan(ctx.actor.coords, ctx.target.coords) > 1:
		var dir := DamageCalculator.dominant_dir(ctx.actor.coords - ctx.target.coords)
		var next: Vector2i = ctx.target.coords + dir
		if not ctx.grid.can_stop(next, ctx.target):
			break
		ctx.grid.move_unit(ctx.target, next)
		moved += 1
	return {"type": "pull", "target": ctx.target, "cells": moved, "to": ctx.target.coords}

## 交换施法者与目标位置（相扑摔投/调虎离山）
static func _swap_position(ctx: EffectContext) -> Dictionary:
	var a := ctx.actor.coords
	var b := ctx.target.coords
	ctx.grid.move_unit(ctx.actor, b)
	ctx.grid.move_unit(ctx.target, a)
	return {"type": "swap", "source": ctx.actor, "target": ctx.target}

## 无视地形瞬移：向最近敌人接近（时迁飞檐走壁，占位口径 D27）
static func _teleport(ctx: EffectContext, cells: int) -> Dictionary:
	var origin := ctx.actor.coords
	var hostile := _nearest_hostile(ctx)
	var best := origin
	if hostile != null:
		var best_dist := _manhattan(origin, hostile.coords)
		for dy in range(-cells, cells + 1):
			for dx in range(-cells, cells + 1):
				if absi(dx) + absi(dy) > cells:
					continue
				var c := origin + Vector2i(dx, dy)
				if not ctx.grid.is_inside(c):
					continue
				var cell := ctx.grid.get_cell(c)
				if cell.is_blocked() or (cell.occupant != null and cell.occupant != ctx.actor):
					continue
				var d := _manhattan(c, hostile.coords)
				if d < best_dist:
					best_dist = d
					best = c
	if best != origin:
		ctx.grid.move_unit(ctx.actor, best)
	return {"type": "teleport", "unit": ctx.actor, "from": origin, "to": best}

# ---------------------------------------------------------------- 增益/机制

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

## 控制状态（决策日志 D22/D27）：stun/paralyze/sleep = 跳过行动；sleep 受击解除；bind = 不可移动；
## guard = 替相邻友军挡远程攻击；counter = 受击反击
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

## 偷取目标 count 个可驱散增益（时迁盗甲；target=self 时从最近敌人偷，占位口径 D27）
static func _steal_buff(ctx: EffectContext, count: int) -> Dictionary:
	var from := ctx.target
	if from == ctx.actor:
		from = _nearest_hostile(ctx)
	if from == null:
		return {"type": "steal", "count": 0, "stolen": []}
	var stolen: Array = []
	for b in from.buffs.duplicate():
		if stolen.size() >= count:
			break
		if not b.is_debuff and b.dispellable:
			from.buffs.erase(b)
			from.buffs_changed.emit(from)
			ctx.actor.add_buff(b)
			stolen.append(b.buff_id)
	return {"type": "steal", "from": from, "count": stolen.size(), "stolen": stolen}

## 召唤物件（旗帜等）：静态友军单位，不行动、可被攻击、不计入胜负（占位口径 D27）
static func _summon(ctx: EffectContext, object_id: String) -> Dictionary:
	# 找施法者相邻空格
	var spot := Vector2i(-1, -1)
	for d in Grid.DIRS:
		var c: Vector2i = ctx.actor.coords + d
		if ctx.grid.is_inside(c) and ctx.grid.can_stop(c, ctx.actor):
			spot = c
			break
	if spot == Vector2i(-1, -1):
		push_error("EffectSystem: summon(%s) 无空位可放置" % object_id)
		return {"type": "summon", "object": object_id, "ok": false}
	var data := UnitData.new()
	data.unit_id = StringName("summon_" + object_id)
	data.name = object_id
	data.hp = SUMMON_HP
	data.spd = 1
	var obj := Unit.new()
	obj.is_object = true
	obj.setup(data, ctx.actor.team, spot)
	ctx.grid.place_unit(obj, spot)
	if ctx.battle != null:
		ctx.battle.add_unit(obj)
	ctx.summoned = obj
	return {"type": "summon", "object": object_id, "unit": obj, "cell": spot, "ok": true}

## aura(atk+0.15,def+0.15,r3)：给光环携带者（召唤物优先，否则自身）挂光环（决策日志 D27）
static func _aura(ctx: EffectContext, skill: SkillData, args: Array) -> Dictionary:
	var mods: Dictionary = {}
	var radius := 0
	for a in args:
		var s := String(a)
		if s.begins_with("r"):
			radius = int(s.substr(1))
		else:
			var parts := s.split("+")
			if parts.size() == 2:
				mods[StringName(parts[0])] = roundi(float(parts[1]) * 100.0)
	var holder := ctx.summoned if ctx.summoned != null else ctx.actor
	var b := Buff.new()
	b.buff_id = StringName("aura_%s" % skill.skill_id)
	b.name = skill.name
	b.duration = 99   # 光环跟随携带者生命（占位口径）
	b.dispellable = false
	b.aura_mods = mods
	b.aura_radius = radius
	b.source = ctx.actor
	holder.add_buff(b)
	return {"type": "aura", "holder": holder, "radius": radius, "mods": mods}

# ---------------------------------------------------------------- 工具

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

static func _nearest_hostile(ctx: EffectContext) -> Unit:
	var best: Unit = null
	var best_dist := 9999
	for c in ctx.grid.cells.values():
		var u: Unit = (c as GridCell).occupant
		if u == null or not u.is_alive():
			continue
		if (u.team == Unit.Team.ENEMY) == (ctx.actor.team == Unit.Team.ENEMY):
			continue
		var d := _manhattan(ctx.actor.coords, u.coords)
		if d < best_dist:
			best_dist = d
			best = u
	return best
