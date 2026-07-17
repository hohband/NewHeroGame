class_name BattleAI
extends RefCounted
## 评分制战斗 AI（策划文档第八章）：枚举「移动落点 × 行动选项」，逐项打分，执行最高分。
##   行动得分 S = Σ（评分因子 × 职业权重）     —— 权重表即策划配置表（data/ai_weights.csv）
## 评估全程只读，不改变战斗状态。占位口径见决策日志 D26。

const KILL_BONUS := 50.0        # 击杀奖励（表13）
const FOCUS_BONUS := 100.0      # 集火目标加分（8.5）
const DANGER_BASE := 30.0       # 危险度基准分（表13：承伤 ÷ 自身HP × 100 → −30 基准）
const CLOSE_BONUS := 2.0        # 向敌接近每格加分（占位，D26）

## 返回本回合的行动计划（0—2 个 Command：移动 + 行动）。
static func decide(unit: Unit, battle: BattleManager) -> Array:
	var weights: Dictionary = battle.data.get_ai_weights(unit.data.unit_class)
	var candidates: Array = []
	var reachable := battle.grid.get_reachable(unit, unit.get_move(battle.grid))
	var dests: Array[Vector2i] = [unit.coords]
	for c in reachable:
		dests.append(c)
	var enemies := _hostiles_of(unit, battle)
	for dest in dests:
		# 普攻候选：对每个可及敌人
		for enemy in enemies:
			var dist := _manhattan(dest, enemy.coords)
			if dist >= unit.data.range_min and dist <= unit.data.range_max:
				var s := _score_attack(unit, enemy, dest, battle, weights, 1.0, 1)
				candidates.append({"score": s, "dest": dest, "kind": "attack", "target": enemy})
		# 技能候选：主动技 + 绝技（半自动模式下我方绝技受释放条件限制，表16）
		for skill in _usable_skills(unit, battle):
			if skill.type == &"ult" and unit.team == Unit.Team.PLAYER \
					and battle.auto_mode == BattleManager.AutoMode.SEMI \
					and not ult_allowed(unit, skill, battle):
				continue
			var s := _score_skill(unit, skill, dest, battle, weights)
			if s > -99999.0:
				candidates.append({"score": s, "dest": dest, "kind": "skill", "skill": skill})
		# 待机候选：原地或移动后蹲坑（含向敌接近分）
		var ws := _score_wait(unit, dest, battle, weights, enemies)
		candidates.append({"score": ws, "dest": dest, "kind": "wait"})
	if candidates.is_empty():
		return [WaitCommand.new(unit)]
	candidates.sort_custom(func(a, b): return a["score"] > b["score"])
	var best: Dictionary = candidates[0]
	return _build_plan(unit, best, battle)

static func _build_plan(unit: Unit, best: Dictionary, battle: BattleManager) -> Array:
	var plan: Array = []
	var dest: Vector2i = best["dest"]
	if dest != unit.coords:
		var path := battle.grid.find_path(unit, dest)
		if not path.is_empty():
			path.remove_at(0)
			plan.append(MoveCommand.new(unit, path))
	match String(best["kind"]):
		"attack":
			plan.append(AttackCommand.new(unit, best["target"], battle.basic_attack_skill(unit)))
		"skill":
			var skill: SkillData = best["skill"]
			var aim := Vector2i(-1, -1)
			if Targeting.needs_aim(skill):
				aim = _best_aim(unit, skill, dest, battle)
			plan.append(SkillCommand.new(unit, skill, aim))
		_:
			plan.append(WaitCommand.new(unit))
	return plan

# ---------------------------------------------------------------- 评分因子（表13）

static func _score_attack(unit: Unit, target: Unit, dest: Vector2i, battle: BattleManager, w: Dictionary, mult: float, times: int) -> float:
	var est := DamageCalculator.estimate_at(unit, target, mult, battle.grid, dest) * times
	var s := est * float(w["damage_expect"])
	if est >= float(target.hp):
		s += KILL_BONUS * float(w["kill_bonus"])
	s += _target_value(target) * float(w["target_value"])
	s += _danger(unit, dest, battle) * float(w["danger"])
	s += _aura_coverage(unit, dest, battle) * 10.0 * float(w["aura_coverage"])
	s += _position_bonus(unit, target, dest, battle) * float(w["position"])
	s += _class_special(unit, target, dest, battle, est, 1)
	if battle.focus_target == target:
		s += FOCUS_BONUS
	return s

## 技能评分：伤害型按普攻模型折算；治疗型按恢复模型；增益/控制按目标价值（占位 D26）
static func _score_skill(unit: Unit, skill: SkillData, dest: Vector2i, battle: BattleManager, w: Dictionary) -> float:
	var effects := EffectSystem.parse_effects(skill.effects)
	var dmg := _first_effect(effects, "phys_dmg")
	var heal := _first_effect(effects, "heal")
	if not dmg.is_empty() and String(skill.target) == "enemy":
		var mult := float(dmg["args"][0])
		var times := int(dmg["times"])
		var best := -99999.0
		for enemy in _targets_from(unit, skill, dest, battle):
			var s := _score_attack(unit, enemy, dest, battle, w, mult, times)
			var extra := _targets_from(unit, skill, dest, battle).size()
			s += _aoe_bonus(unit, extra)
			best = maxf(best, s)
		return best
	if not heal.is_empty():
		var mult := float(heal["args"][0])
		var amount := float(unit.get_mgc()) * mult
		var s := 0.0
		var any_hurt := false
		for ally in _targets_from(unit, skill, dest, battle):
			var missing := float(ally.data.hp - ally.hp)
			if missing <= 0.0:
				continue
			any_hurt = true
			s += minf(amount, missing) * 1.2       # 有效恢复 ×1.2（表15）
			if float(ally.hp) / float(ally.data.hp) < 0.35:
				s += 60.0                          # 濒危 +60（表15）
			s -= maxf(0.0, amount - missing) * 0.3   # 治疗溢出扣分（表13）
		if not any_hurt:
			return -99999.0                        # 无治疗需求
		s += _danger(unit, dest, battle) * float(w["danger"])
		s += _aura_coverage(unit, dest, battle) * 10.0 * float(w["aura_coverage"])
		return s
	# 增益/控制/功能型：覆盖人数 × 20，敌方目标加目标价值（占位口径 D26）
	var targets := _targets_from(unit, skill, dest, battle)
	if targets.is_empty():
		return -99999.0
	var s := 0.0
	for t in targets:
		s += 20.0
		if String(skill.target) == "enemy":
			s += _target_value(t) * float(w["target_value"])
	s += _danger(unit, dest, battle) * float(w["danger"])
	s += _aura_coverage(unit, dest, battle) * 10.0 * float(w["aura_coverage"])
	return s

static func _score_wait(unit: Unit, dest: Vector2i, battle: BattleManager, w: Dictionary, enemies: Array[Unit]) -> float:
	var s := 5.0
	s += _danger(unit, dest, battle) * float(w["danger"])
	s += _aura_coverage(unit, dest, battle) * 10.0 * float(w["aura_coverage"])
	s += _position_bonus(unit, null, dest, battle) * float(w["position"])
	if not enemies.is_empty():
		var nearest := 9999
		for e in enemies:
			nearest = mini(nearest, _manhattan(dest, e.coords))
		s -= float(nearest) * CLOSE_BONUS   # 向敌接近（占位 D26）
	return s

## 目标价值：职业基础 + 残血加成 + 核心标记（表13；羁绊核心暂以满怒代理，D26）
static func _target_value(target: Unit) -> float:
	var base := 15.0   # support/未列明职业占位（D26）
	match String(target.data.unit_class):
		"healer":
			base = 30.0
		"strategist":
			base = 25.0
		"archer", "infantry", "cavalry":
			base = 20.0
		"vanguard":
			base = 10.0
	base += (1.0 - float(target.hp) / float(target.data.hp)) * 20.0   # 残血加成 0—20
	if target.rage >= Unit.MAX_RAGE:
		base += 15.0                                                   # 核心标记（满怒）
	return base

## 危险度：落点在下回合敌方预估承伤 ÷ 自身最大HP ×（−30 基准）（表13）
static func _danger(unit: Unit, dest: Vector2i, battle: BattleManager) -> float:
	var total := 0.0
	for e in battle.units:
		if not e.is_alive() or not _is_hostile(unit, e):
			continue
		if _manhattan(e.coords, dest) <= e.data.move + e.data.range_max:
			total += DamageCalculator.estimate_at(e, unit, 1.0, battle.grid, e.coords)
	return -(total / float(maxi(1, unit.data.hp))) * DANGER_BASE

## 光环/羁绊覆盖：落点 2 格内队友数（ aura 系统未落地前的代理，D26）
static func _aura_coverage(unit: Unit, dest: Vector2i, battle: BattleManager) -> float:
	var n := 0
	for a in battle.units:
		if a != unit and a.is_alive() and a.team == unit.team and _manhattan(a.coords, dest) <= 2:
			n += 1
	return float(n)

## 站位奖励：背刺 +20 / 侧击 +10 / 高地 +15（表13）
static func _position_bonus(unit: Unit, target: Unit, dest: Vector2i, battle: BattleManager) -> float:
	var s := 0.0
	if target != null:
		var dir := DamageCalculator.direction_mod_from(unit, target, dest)
		if dir >= DamageCalculator.BACKSTAB_MOD:
			s += 20.0
		elif dir >= DamageCalculator.SIDE_MOD:
			s += 10.0
	var cell := battle.grid.get_cell(dest)
	if cell != null and cell.height > 0:
		s += 15.0
	return s

## 职业特殊评分项（表15；可实现项先行，占位口径见 D26）
static func _class_special(unit: Unit, target: Unit, dest: Vector2i, battle: BattleManager, est: float, targets: int) -> float:
	match String(unit.data.unit_class):
		"vanguard":
			var cover := 0
			for a in battle.units:
				if a != unit and a.is_alive() and a.team == unit.team and _manhattan(a.coords, dest) <= 1:
					cover += 1
			return float(cover) * 10.0   # 掩护：降低队友受击风险 +10/人
		"infantry":
			if target != null and DamageCalculator.direction_mod_from(unit, target, dest) >= DamageCalculator.BACKSTAB_MOD:
				return 20.0              # 背刺位 +20
		"cavalry":
			var s := float(_manhattan(unit.coords, dest)) * 3.0   # 冲锋每格 +3
			if est >= float(target.hp) and _has_refresh_on_kill(unit, battle):
				s += 30.0                # 预计可触发击杀刷新 +30
			return s
		"archer":
			var s := 0.0
			for e in battle.units:
				if e.is_alive() and _is_hostile(unit, e) and _manhattan(e.coords, dest) <= 3:
					s -= 40.0            # 安全距离：3 格内有敌人 −40
					break
			var cell := battle.grid.get_cell(dest)
			if cell != null and cell.height > 0:
				s += 20.0                # 高地 +20
			return s
		"strategist":
			return float(maxi(0, targets - 1)) * 15.0   # AOE 每多覆盖 1 敌 +15
	return 0.0

static func _aoe_bonus(unit: Unit, targets: int) -> float:
	if String(unit.data.unit_class) == "strategist":
		return float(maxi(0, targets - 1)) * 15.0
	return 0.0

# ---------------------------------------------------------------- 半自动绝技条件（表16）

static func ult_allowed(unit: Unit, skill: SkillData, battle: BattleManager) -> bool:
	match String(unit.data.unit_class):
		"vanguard":
			if float(unit.hp) / float(unit.data.hp) < 0.4:
				return true
			var near := 0
			for e in _hostiles_of(unit, battle):
				if _manhattan(e.coords, unit.coords) <= 2:
					near += 1
			return near >= 3
		"infantry", "cavalry":
			for e in _hostiles_of(unit, battle):
				if DamageCalculator.estimate_at(unit, e, 1.0, battle.grid, unit.coords) >= float(e.hp):
					return true                                # 可完成击杀
			return _targets_from(unit, skill, unit.coords, battle).size() >= 2   # 一次可命中 ≥2
		"archer":
			for e in _targets_from(unit, skill, unit.coords, battle):
				if DamageCalculator.estimate_at(unit, e, 1.0, battle.grid, unit.coords) >= float(e.hp):
					return true
				if e.rage >= Unit.MAX_RAGE:
					return true                                # 满怒/高威胁目标
			return false
		"strategist":
			return _targets_from(unit, skill, unit.coords, battle).size() >= 3   # 一次可命中 ≥3
		"healer":
			var total := 0.0
			var n := 0
			for a in battle.units:
				if a.is_alive() and a.team == unit.team:
					total += float(a.hp) / float(a.data.hp)
					n += 1
					if float(a.hp) / float(a.data.hp) < 0.35:
						return true                            # 存在濒危队友
			return n > 0 and total / float(n) < 0.6            # 队友平均 HP < 60%
		"support":
			return _targets_from(unit, skill, unit.coords, battle).size() >= 4   # 一次可覆盖 ≥4
	return false

# ---------------------------------------------------------------- 工具

static func _usable_skills(unit: Unit, battle: BattleManager) -> Array:
	var out: Array = []
	for t in [&"active", &"ult"]:
		var s := battle.data.get_skill_for_unit(unit.data.unit_id, t)
		if s != null and battle.can_use_skill(unit, s):
			out.append(s)
	return out

## 从指定落点解析技能目标（评估用，瞄准点自动选最优）
static func _targets_from(unit: Unit, skill: SkillData, dest: Vector2i, battle: BattleManager) -> Array[Unit]:
	if Targeting.needs_aim(skill):
		var aim := _best_aim(unit, skill, dest, battle)
		if aim == Vector2i(-1, -1):
			return []
		return Targeting.resolve_from(skill, unit, aim, battle.grid, battle.units, battle.rolls, dest)
	return Targeting.resolve_from(skill, unit, Vector2i(-1, -1), battle.grid, battle.units, battle.rolls, dest)

static func _best_aim(unit: Unit, skill: SkillData, dest: Vector2i, battle: BattleManager) -> Vector2i:
	var best_aim := Vector2i(-1, -1)
	var best_n := 0
	for e in _hostiles_of(unit, battle):
		var hits := Targeting.resolve_from(skill, unit, e.coords, battle.grid, battle.units, battle.rolls, dest)
		if hits.size() > best_n:
			best_n = hits.size()
			best_aim = e.coords
	return best_aim

static func _first_effect(effects: Array, eff_name: String) -> Dictionary:
	for eff in effects:
		if eff["name"] == eff_name:
			return eff
	return {}

static func _has_refresh_on_kill(unit: Unit, battle: BattleManager) -> bool:
	for t in [&"active", &"ult"]:
		var s := battle.data.get_skill_for_unit(unit.data.unit_id, t)
		if s != null and s.effects.contains("refresh_on_kill"):
			return true
	return false

static func _hostiles_of(unit: Unit, battle: BattleManager) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in battle.units:
		if u.is_alive() and _is_hostile(unit, u):
			out.append(u)
	return out

static func _is_hostile(unit: Unit, other: Unit) -> bool:
	return (other.team == Unit.Team.ENEMY) != (unit.team == Unit.Team.ENEMY)

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
