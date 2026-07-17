class_name Targeting
extends RefCounted
## 技能目标解析：范围模板 × 目标规则（策划文档 6.7）。
## 范围口径（决策日志 D21）：adjacent/diamond = 曼哈顿距离；ring = 切比雪夫距离（周身）；
## line = 同横/纵线贯穿（手动施放需指向格）；all = 全图；self = 自身。
## 多目标时效果序列逐目标执行（决策日志 D23）。

static func resolve(skill: SkillData, caster: Unit, aim: Vector2i, grid: Grid, units: Array[Unit], rolls: RollSource) -> Array[Unit]:
	var out: Array[Unit] = []
	if String(skill.range_shape) == "self":
		out.append(caster)
	else:
		for u in units:
			if not u.is_alive():
				continue
			if not _target_filter(skill, caster, u):
				continue
			if not _in_area(skill, caster, aim, u.coords):
				continue
			out.append(u)
	var mods := EffectSystem.scan_modifiers(EffectSystem.parse_effects(skill.effects))
	# target_rule(lowest_hp)：只保留血量最低者（百步穿杨）
	if mods.get("target_rule", "") == "lowest_hp" and out.size() > 1:
		var lowest: Unit = out[0]
		for u in out:
			if u.hp < lowest.hp:
				lowest = u
		out = [lowest]
	# random_target(n)：范围内随机 n 个目标（飞石连打）
	if mods.has("random_target") and out.size() > int(mods["random_target"]):
		var pool := out.duplicate()
		out = []
		while out.size() < int(mods["random_target"]) and not pool.is_empty():
			var i := int(clampf(rolls.roll() / 100.0, 0.0, 0.9999) * pool.size())
			out.append(pool.pop_at(i))
	# friendly_fire(p)：范围内友军按概率误伤（黑旋风，占位口径，决策日志 D23）
	if mods.has("friendly_fire"):
		var chance := float(mods["friendly_fire"]) * 100.0
		for u in units:
			if not u.is_alive() or u.team != caster.team or u == caster or out.has(u):
				continue
			if _in_area(skill, caster, aim, u.coords) and rolls.roll() < chance:
				out.append(u)
	return out

static func _target_filter(skill: SkillData, caster: Unit, u: Unit) -> bool:
	match String(skill.target):
		"enemy":
			return (u.team == Unit.Team.ENEMY) != (caster.team == Unit.Team.ENEMY)
		"ally":
			return u.team == caster.team
		"self":
			return u == caster
	return false

static func _in_area(skill: SkillData, caster: Unit, aim: Vector2i, cell: Vector2i) -> bool:
	var d := cell - caster.coords
	var man := absi(d.x) + absi(d.y)
	var che := maxi(absi(d.x), absi(d.y))
	match String(skill.range_shape):
		"adjacent", "diamond":
			return man >= skill.range_min and man <= skill.range_max
		"ring":
			return che >= skill.range_min and che <= skill.range_max
		"all":
			return true
		"self":
			return cell == caster.coords
		"line":
			if aim == Vector2i(-1, -1):
				# 无指向：任一直线方向在程内即符合（AI 枚举/预览用）
				return (d.x == 0 or d.y == 0) and man >= skill.range_min and man <= skill.range_max
			var dir := DamageCalculator.dominant_dir(aim - caster.coords)
			if dir == Vector2i.ZERO:
				return false
			if dir.x != 0:
				if d.y != 0 or d.x == 0 or signi(d.x) != dir.x:
					return false
				return absi(d.x) >= skill.range_min and absi(d.x) <= skill.range_max
			else:
				if d.x != 0 or d.y == 0 or signi(d.y) != dir.y:
					return false
				return absi(d.y) >= skill.range_min and absi(d.y) <= skill.range_max
	return false

## 施放是否需要玩家指向（line 且手动施放时需要 aim；其余按模板自动覆盖）
static func needs_aim(skill: SkillData) -> bool:
	return String(skill.range_shape) == "line" and String(skill.target) == "enemy"

## 某单位当前可作为技能目标的格子集合（预览/AI 用）
static func cells_in_range(skill: SkillData, caster: Unit, grid: Grid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if _in_area(skill, caster, Vector2i(-1, -1), c):
				out.append(c)
	return out
