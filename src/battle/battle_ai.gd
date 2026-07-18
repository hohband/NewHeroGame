class_name BattleAI
extends RefCounted
## 评分制战斗 AI（策划文档第八章）：枚举「移动落点 × 行动选项」，逐项打分，执行最高分。
##   行动得分 S = Σ（评分因子 × 职业权重）     —— 权重表即策划配置表（data/ai_weights.csv）
## 评分常数全部走 data/battle_constants.csv（代码内 fallback 与表内原值一致，仅防缺 key 漂移）。
## 评估全程只读，不改变战斗状态。口径见决策日志 D26（核心标记/光环覆盖已按羁绊与光环系统实判）。

## 控制类效果（表15：眩晕/睡眠/束缚等 status 类）
const CONTROL_EFFECTS: Array[String] = ["stun", "sleep", "sleep_chance", "paralyze", "bind"]

## 读战斗常数（battle_constants.csv）
static func _c(battle: BattleManager, key: String, fallback: float) -> float:
	return battle.data.get_constant(key, fallback)

## 返回本回合的行动计划（0—2 个 Command：移动 + 行动）。
static func decide(unit: Unit, battle: BattleManager) -> Array:
	var weights: Dictionary = battle.data.get_ai_weights(unit.data.unit_class)
	# PVP 守方策略模板：权重修正系数（8.6，仅敌方 AI）
	if unit.team == Unit.Team.ENEMY and not battle.pvp_mods.is_empty():
		weights = weights.duplicate()
		for k in battle.pvp_mods.get("weights", {}):
			if weights.has(k):
				weights[k] = float(weights[k]) * float(battle.pvp_mods["weights"][k])
	var candidates: Array = []
	var reachable := battle.grid.get_reachable(unit, unit.get_move(battle.grid))
	var dests: Array[Vector2i] = [unit.coords]
	for c in reachable:
		dests.append(c)
	var enemies := _hostiles_of(unit, battle)
	var has_attack_candidate := false
	var yaojiu_reserved := _yaojiu_reserved_for_stall(unit, battle)
	for dest in dests:
		# 普攻候选：对每个可及敌人（射程按武器范围模板，与 BattleManager 同源）
		for enemy in enemies:
			if battle.in_attack_range_from(unit, dest, enemy.coords):
				var s := _score_attack(unit, enemy, dest, battle, weights, 1.0, 1)
				candidates.append({"score": s, "dest": dest, "kind": "attack", "target": enemy})
				has_attack_candidate = true
		# 技能候选：主动技 + 绝技（半自动模式下我方绝技受释放条件限制，表16）
		for skill in _usable_skills(unit, battle):
			if yaojiu_reserved and skill.skill_id == &"act_yaojiu":
				continue   # 蒙汗药酒留给酒摊剧情（D38 目标行为优先）
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
	# 关卡目标行为（决策日志 D38）：夺取（COLLECT）与护送（ESCORT）
	_add_objective_candidates(unit, battle, dests, candidates)
	# 打障碍候选：攻击枚举为空（无路可达任何敌人）时，退而求其次普攻射程内的可破坏拒马（6.3）
	if not has_attack_candidate:
		_add_obstacle_candidates(unit, battle, dests, candidates)
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
		"obstacle":
			plan.append(AttackCommand.new(unit, null, battle.basic_attack_skill(unit), best["cell"]))
		"skill":
			var skill: SkillData = best["skill"]
			var aim := Vector2i(-1, -1)
			if Targeting.needs_aim(skill):
				aim = _best_aim(unit, skill, dest, battle)
			plan.append(SkillCommand.new(unit, skill, aim))
		"interact":
			plan.append(InteractCommand.new(unit, best["object"]))
		_:
			plan.append(WaitCommand.new(unit))
	return plan

# ---------------------------------------------------------------- 关卡目标行为（决策日志 D38）

## 夺取：相邻物件 → 夺取候选（ai_collect_interact 分，高于常规攻击）；靠近物件的落点加分。
## 护送：护送目标本人以趋向目标区为第一优先级。分值常数见 battle_constants.csv。
static func _add_objective_candidates(unit: Unit, battle: BattleManager, dests: Array, candidates: Array) -> void:
	if battle.level == null:
		return
	var win_type := String(battle.level.win_condition.get("type", ""))
	if win_type == "COLLECT" and unit.team == Unit.Team.PLAYER:
		for obj in battle.units:
			if not (obj.is_object and obj.collectable and obj.is_alive()):
				continue
			var dist := _manhattan(unit.coords, obj.coords)
			if dist == 1:
				candidates.append({"score": _c(battle, "ai_collect_interact", 120.0), "dest": unit.coords, "kind": "interact", "object": obj})
			elif dist > 1:
				for dest in dests:
					var d := _manhattan(dest, obj.coords)
					if d < dist and d >= 1:
						var s := _c(battle, "ai_collect_approach_base", 100.0) - float(d) * _c(battle, "ai_collect_approach_cell_cost", 2.0) \
							+ _danger(unit, dest, battle) * _c(battle, "ai_obj_danger_factor", 0.5)
						candidates.append({"score": s, "dest": dest, "kind": "wait"})
	elif win_type == "ESCORT" and _is_escort_unit(unit, battle):
		var zone: Rect2i = battle.level.win_condition.get("zone", Rect2i())
		for dest in dests:
			var d := _dist_to_zone(dest, zone)
			var s := _c(battle, "ai_escort_base", 250.0) - float(d) * _c(battle, "ai_escort_cell_cost", 3.0) \
				+ _danger(unit, dest, battle) * _c(battle, "ai_obj_danger_factor", 0.5)
			candidates.append({"score": s, "dest": dest, "kind": "wait"})
	# 蒙汗药酒路线：持有 act_yaojiu 的单位优先走向酒摊触发剧情（7.4 T2，决策日志 D38 注）
	if unit.team == Unit.Team.PLAYER:
		var act := battle.data.get_skill_for_unit(unit.data.unit_id, &"active")
		if act != null and act.skill_id == &"act_yaojiu":
			for coords: Vector2i in battle.grid.cells:
				var cell: GridCell = battle.grid.cells[coords]
				if cell.terrain.terrain_id != &"wine_stall" or cell.occupant != null:
					continue
				for dest in dests:
					if dest == coords:
						candidates.append({"score": _c(battle, "ai_wine_stall_arrive", 150.0) \
							+ _danger(unit, dest, battle) * _c(battle, "ai_obj_danger_factor", 0.5), "dest": dest, "kind": "wait"})
					elif _manhattan(dest, coords) < _manhattan(unit.coords, coords):
						var s := _c(battle, "ai_wine_stall_approach_base", 140.0) \
							- float(_manhattan(dest, coords)) * _c(battle, "ai_wine_stall_cell_cost", 2.0) \
							+ _danger(unit, dest, battle) * _c(battle, "ai_obj_danger_factor", 0.5)
						candidates.append({"score": s, "dest": dest, "kind": "wait"})

## 打障碍候选（拒马可破坏，6.3）：仅在没有普攻候选时启用，固定低优先级分（battle_constants.csv）。
static func _add_obstacle_candidates(unit: Unit, battle: BattleManager, dests: Array, candidates: Array) -> void:
	var base := _c(battle, "ai_obstacle_attack_base", 3.0)
	for dest in dests:
		for coords: Vector2i in battle.grid.cells:
			var cell: GridCell = battle.grid.cells[coords]
			if not cell.has_obstacle():
				continue
			if battle.in_attack_range_from(unit, dest, coords):
				candidates.append({"score": base, "dest": dest, "kind": "obstacle", "cell": coords})

static func _is_escort_unit(unit: Unit, battle: BattleManager) -> bool:
	return battle.level != null \
		and String(battle.level.win_condition.get("type", "")) == "ESCORT" \
		and unit.data.unit_id == StringName(battle.level.win_condition.get("unit", ""))

## 蒙汗药酒路线（决策日志 D38）：场上有空酒摊时，持有者的 act_yaojiu 留给酒摊剧情，
## AI 不把它当普通技能施放（否则技能评分会盖过「优先走向酒摊」的目标行为）。
static func _yaojiu_reserved_for_stall(unit: Unit, battle: BattleManager) -> bool:
	if battle.level == null:
		return false
	var act := battle.data.get_skill_for_unit(unit.data.unit_id, &"active")
	if act == null or act.skill_id != &"act_yaojiu":
		return false
	for coords: Vector2i in battle.grid.cells:
		var cell: GridCell = battle.grid.cells[coords]
		if cell.terrain.terrain_id == &"wine_stall" and cell.occupant == null:
			return true
	return false

static func _dist_to_zone(cell: Vector2i, zone: Rect2i) -> int:
	var best := 9999
	for y in range(zone.position.y, zone.end.y):
		for x in range(zone.position.x, zone.end.x):
			best = mini(best, _manhattan(cell, Vector2i(x, y)))
	return best

# ---------------------------------------------------------------- 评分因子（表13）

static func _score_attack(unit: Unit, target: Unit, dest: Vector2i, battle: BattleManager, w: Dictionary, mult: float, times: int) -> float:
	var est := DamageCalculator.estimate_at(unit, target, mult, battle.grid, dest) * times
	var s := est * float(w["damage_expect"])
	if est >= float(target.hp):
		s += _c(battle, "ai_kill_base", 50.0) * float(w["kill_bonus"])
	s += _target_value(target, battle) * float(w["target_value"])
	s += _danger(unit, dest, battle) * float(w["danger"])
	s += _aura_coverage(unit, dest, battle) * _c(battle, "ai_aura_coverage_factor", 10.0) * float(w["aura_coverage"])
	s += _position_bonus(unit, target, dest, battle) * float(w["position"])
	s += _class_special(unit, target, dest, battle, est, 1)
	s += _pvp_template_bonus(unit, dest, battle)
	if battle.focus_target == target:
		s += _c(battle, "ai_focus_bonus", 100.0)
	return s

## PVP 策略模板附加分（8.6）：「保护核心」队友距核心 ≤2 格 +20；「稳健防守」远离布阵区每格 −10
static func _pvp_template_bonus(unit: Unit, dest: Vector2i, battle: BattleManager) -> float:
	if unit.team != Unit.Team.ENEMY or battle.pvp_mods.is_empty():
		return 0.0
	var s := 0.0
	if battle.pvp_core != null and unit != battle.pvp_core and unit.team == battle.pvp_core.team:
		if _manhattan(dest, battle.pvp_core.coords) <= 2:
			s += float(battle.pvp_mods.get("core_bonus", 20.0))
	if battle.pvp_mods.has("away_from_deploy") and battle.level != null:
		var zone := battle.level.deploy_zone
		var dist := 9999
		for y in range(zone.position.y, zone.end.y):
			for x in range(zone.position.x, zone.end.x):
				dist = mini(dist, _manhattan(dest, Vector2i(x, y)))
		if dist < 9999:
			s += float(battle.pvp_mods["away_from_deploy"]) * float(dist)
	return s

## 技能评分：伤害型按普攻模型折算；治疗型按恢复模型；增益/控制按目标价值（表15）
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
			s += _aoe_bonus(unit, extra, battle)
			s += _control_high_value_bonus(unit, skill, enemy, battle)   # 谋士控制命中高价值（表15）
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
			s += minf(amount, missing) * _c(battle, "ai_heal_expect_factor", 1.2)   # 有效恢复 ×系数（表15）
			if float(ally.hp) / float(ally.data.hp) < _c(battle, "ai_heal_urgent_threshold", 0.35):
				s += _c(battle, "ai_heal_urgent_bonus", 60.0)                        # 濒危加分（表15）
			s -= maxf(0.0, amount - missing) * _c(battle, "ai_heal_overheal_factor", 0.3)   # 治疗溢出扣分（表13）
		if not any_hurt:
			return -99999.0                        # 无治疗需求：治疗技能本身不施放；医者的增益技能走下方辅助评分（退化为辅助，表15/D26）
		s += _danger(unit, dest, battle) * float(w["danger"])
		s += _aura_coverage(unit, dest, battle) * _c(battle, "ai_aura_coverage_factor", 10.0) * float(w["aura_coverage"])
		return s
	# 增益/控制/功能型：覆盖人数 × ai_buff_target_base；敌方目标加目标价值；
	# 谋士控制命中高价值 +40（表15）；辅助增益核心输出 +25（表15；医者无治疗需求时同按辅助评分，D26）
	var targets := _targets_from(unit, skill, dest, battle)
	if targets.is_empty():
		return -99999.0
	var s := 0.0
	for t in targets:
		s += _c(battle, "ai_buff_target_base", 20.0)
		if String(skill.target) == "enemy":
			s += _target_value(t, battle) * float(w["target_value"])
			s += _control_high_value_bonus(unit, skill, t, battle)
		elif _is_core(t) and ["support", "healer"].has(String(unit.data.unit_class)):
			s += _c(battle, "ai_support_buff_core", 25.0)                # 增益对象为队内核心输出（表15）
	s += _danger(unit, dest, battle) * float(w["danger"])
	s += _aura_coverage(unit, dest, battle) * _c(battle, "ai_aura_coverage_factor", 10.0) * float(w["aura_coverage"])
	return s

static func _score_wait(unit: Unit, dest: Vector2i, battle: BattleManager, w: Dictionary, enemies: Array[Unit]) -> float:
	var s := _c(battle, "ai_wait_base", 5.0)
	s += _danger(unit, dest, battle) * float(w["danger"])
	s += _aura_coverage(unit, dest, battle) * _c(battle, "ai_aura_coverage_factor", 10.0) * float(w["aura_coverage"])
	s += _position_bonus(unit, null, dest, battle) * float(w["position"])
	if not enemies.is_empty():
		var nearest := 9999
		for e in enemies:
			nearest = mini(nearest, _manhattan(dest, e.coords))
		s -= float(nearest) * _c(battle, "ai_close_bonus", 2.0)   # 向敌接近（占位 D26）
	return s

## 目标价值：职业基础 + 残血加成 + 核心标记（表13；数值见 battle_constants.csv）
## 核心标记（D26 改判）：羁绊系统在场激活（携带 bond_ 加成）的单位视为阵容核心；满怒保留为高威胁次要加分
static func _target_value(target: Unit, battle: BattleManager) -> float:
	var base := _c(battle, "ai_target_value_default", 15.0)   # support/未列明职业占位（D26）
	match String(target.data.unit_class):
		"healer":
			base = _c(battle, "ai_target_value_healer", 30.0)
		"strategist":
			base = _c(battle, "ai_target_value_strategist", 25.0)
		"archer", "infantry", "cavalry":
			base = _c(battle, "ai_target_value_dps", 20.0)
		"vanguard":
			base = _c(battle, "ai_target_value_vanguard", 10.0)
	base += (1.0 - float(target.hp) / float(target.data.hp)) * _c(battle, "ai_target_value_low_hp", 20.0)   # 残血加成
	if _is_core(target):
		base += _c(battle, "ai_target_value_bond_core", 15.0)   # 羁绊核心标记（D26 改判）
	if target.rage >= Unit.MAX_RAGE:
		base += _c(battle, "ai_target_value_full_rage", 15.0)   # 满怒高威胁（次要加分）
	return base

## 阵容核心（D26 改判）：羁绊加成在场激活的单位（BondSystem 施加的 bond_ 前缀 Buff，决策日志 D29）
static func _is_core(u: Unit) -> bool:
	for b in u.buffs:
		if String(b.buff_id).begins_with("bond_"):
			return true
	return false

## 危险度：落点在下回合敌方预估承伤 ÷ 自身最大HP × ai_danger_base 基准（表13）
## 「保护核心」模板：核心单位承伤风险 ×2（8.6）
static func _danger(unit: Unit, dest: Vector2i, battle: BattleManager) -> float:
	var total := 0.0
	for e in battle.units:
		if not e.is_alive() or not _is_hostile(unit, e):
			continue
		if _manhattan(e.coords, dest) <= e.data.move + e.data.range_max:
			total += DamageCalculator.estimate_at(e, unit, 1.0, battle.grid, e.coords)
	var v := (total / float(maxi(1, unit.data.hp))) * _c(battle, "ai_danger_base", -30.0)
	if battle.pvp_core == unit:
		v *= float(battle.pvp_mods.get("core_danger_mult", 1.0))
	return v

## 光环覆盖（D26 改判）：按真实光环系统计分（Buff.aura_radius/aura_mods，决策日志 D27）。
## 落点被我方光环携带者的光环半径罩住 +1/源；自身为光环源时，落点光环能罩住的队友 +1/人。
static func _aura_coverage(unit: Unit, dest: Vector2i, battle: BattleManager) -> float:
	var n := 0
	for a in battle.units:
		if not a.is_alive() or a.team != unit.team:
			continue
		for b in a.buffs:
			if b.aura_radius <= 0:
				continue
			if a == unit:
				for ally in battle.units:
					if ally != unit and ally.is_alive() and ally.team == unit.team \
							and _manhattan(ally.coords, dest) <= b.aura_radius:
						n += 1
			elif _manhattan(a.coords, dest) <= b.aura_radius:
				n += 1
	return float(n)

## 站位奖励：背刺 / 侧击 / 高地（表13，数值见 battle_constants.csv）
static func _position_bonus(unit: Unit, target: Unit, dest: Vector2i, battle: BattleManager) -> float:
	var s := 0.0
	if target != null:
		var dir := DamageCalculator.direction_mod_from(unit, target, dest)
		if dir >= DamageCalculator.BACKSTAB_MOD:
			s += _c(battle, "ai_pos_backstab", 20.0)
		elif dir >= DamageCalculator.SIDE_MOD:
			s += _c(battle, "ai_pos_side", 10.0)
	var cell := battle.grid.get_cell(dest)
	if cell != null and cell.height > 0:
		s += _c(battle, "ai_pos_highground", 15.0)
	return s

## 职业特殊评分项（表15；可实现项先行，占位口径见 D26；数值见 battle_constants.csv）
static func _class_special(unit: Unit, target: Unit, dest: Vector2i, battle: BattleManager, est: float, targets: int) -> float:
	match String(unit.data.unit_class):
		"vanguard":
			var cover := 0
			for a in battle.units:
				if a != unit and a.is_alive() and a.team == unit.team and _manhattan(a.coords, dest) <= 1:
					cover += 1
			var s := float(cover) * _c(battle, "ai_vanguard_cover", 10.0)   # 掩护：降低队友受击风险
			if _on_cover_line(unit, dest, battle):
				s += _c(battle, "ai_vanguard_cover_line", 25.0)             # 落点在敌我连线格上（表15）
			return s
		"infantry":
			if target != null and DamageCalculator.direction_mod_from(unit, target, dest) >= DamageCalculator.BACKSTAB_MOD:
				return _c(battle, "ai_infantry_backstab", 20.0)           # 背刺位加分
		"cavalry":
			var s := float(_manhattan(unit.coords, dest)) * _c(battle, "ai_cavalry_charge_per_cell", 3.0)   # 冲锋每格加分
			if est >= float(target.hp) and _has_refresh_on_kill(unit, battle):
				s += _c(battle, "ai_cavalry_refresh_kill", 30.0)          # 预计可触发击杀刷新
			return s
		"archer":
			var s := 0.0
			for e in battle.units:
				if e.is_alive() and _is_hostile(unit, e) and _manhattan(e.coords, dest) <= int(_c(battle, "ai_archer_safe_dist", 3.0)):
					s += _c(battle, "ai_archer_danger_penalty", -40.0)    # 安全距离内有敌人扣分
					break
			var cell := battle.grid.get_cell(dest)
			if cell != null and cell.height > 0:
				s += _c(battle, "ai_archer_highground", 20.0)             # 高地加分
			return s
		"strategist":
			return float(maxi(0, targets - 1)) * _c(battle, "ai_strategist_aoe_per_extra", 15.0)   # AOE 每多覆盖 1 敌加分
	return 0.0

static func _aoe_bonus(unit: Unit, targets: int, battle: BattleManager) -> float:
	if String(unit.data.unit_class) == "strategist":
		return float(maxi(0, targets - 1)) * _c(battle, "ai_strategist_aoe_per_extra", 15.0)
	return 0.0

## 连线掩护（表15）：落点处在「敌人→我方队友」连线格上，即替队友挡住敌人的接近路径。
## 几何口径（从简）：敌人与队友配对，落点共线且严格位于线段内部即算。
static func _on_cover_line(unit: Unit, dest: Vector2i, battle: BattleManager) -> bool:
	for e in battle.units:
		if not e.is_alive() or not _is_hostile(unit, e):
			continue
		for a in battle.units:
			if a == unit or not a.is_alive() or a.team != unit.team:
				continue
			if _between_on_line(e.coords, a.coords, dest):
				return true
	return false

## p 是否严格位于 a—b 连线段经过的格上（共线且在线段内部，不含端点）
static func _between_on_line(a: Vector2i, b: Vector2i, p: Vector2i) -> bool:
	var ab := b - a
	var ap := p - a
	if ab.x * ap.y != ab.y * ap.x:
		return false   # 不共线
	if ap.x * ab.x + ap.y * ab.y <= 0:
		return false   # 不在 a 之后
	return ap.length_squared() < ab.length_squared()   # 不超出 b 端

## 谋士控制技能命中高价值目标（表15）：目标价值达到表13 最高职业档（ai_target_value_healer）即为高价值
static func _control_high_value_bonus(unit: Unit, skill: SkillData, target: Unit, battle: BattleManager) -> float:
	if String(unit.data.unit_class) != "strategist" or not _is_control_skill(skill):
		return 0.0
	if _target_value(target, battle) >= _c(battle, "ai_target_value_healer", 30.0):
		return _c(battle, "ai_strategist_control_high_value", 40.0)
	return 0.0

## 控制类技能：effects 含眩晕/睡眠/束缚等 status 类效果（表15）
static func _is_control_skill(skill: SkillData) -> bool:
	for eff in EffectSystem.parse_effects(skill.effects):
		if CONTROL_EFFECTS.has(String(eff["name"])):
			return true
	return false

# ---------------------------------------------------------------- 半自动绝技条件（表16；阈值见 battle_constants.csv）

static func ult_allowed(unit: Unit, skill: SkillData, battle: BattleManager) -> bool:
	match String(unit.data.unit_class):
		"vanguard":
			if float(unit.hp) / float(unit.data.hp) < _c(battle, "ai_ult_vanguard_hp", 0.4):
				return true
			var near := 0
			for e in _hostiles_of(unit, battle):
				if _manhattan(e.coords, unit.coords) <= 2:
					near += 1
			return near >= int(_c(battle, "ai_ult_vanguard_near", 3.0))
		"infantry", "cavalry":
			for e in _hostiles_of(unit, battle):
				if DamageCalculator.estimate_at(unit, e, 1.0, battle.grid, unit.coords) >= float(e.hp):
					return true                                # 可完成击杀
			return _targets_from(unit, skill, unit.coords, battle).size() >= int(_c(battle, "ai_ult_dps_min_targets", 2.0))   # 一次可命中 ≥N
		"archer":
			for e in _targets_from(unit, skill, unit.coords, battle):
				if DamageCalculator.estimate_at(unit, e, 1.0, battle.grid, unit.coords) >= float(e.hp):
					return true
				if e.rage >= Unit.MAX_RAGE:
					return true                                # 满怒/高威胁目标
			return false
		"strategist":
			return _targets_from(unit, skill, unit.coords, battle).size() >= int(_c(battle, "ai_ult_strategist_min_targets", 3.0))   # 一次可命中 ≥N
		"healer":
			var total := 0.0
			var n := 0
			for a in battle.units:
				if a.is_alive() and a.team == unit.team:
					total += float(a.hp) / float(a.data.hp)
					n += 1
					if float(a.hp) / float(a.data.hp) < _c(battle, "ai_ult_healer_urgent_hp", 0.35):
						return true                            # 存在濒危队友
			return n > 0 and total / float(n) < _c(battle, "ai_ult_healer_avg_hp", 0.6)   # 队友平均 HP 低于阈值
		"support":
			return _targets_from(unit, skill, unit.coords, battle).size() >= int(_c(battle, "ai_ult_support_min_targets", 4.0))   # 一次可覆盖 ≥N
	return false

# ---------------------------------------------------------------- 工具

static func _usable_skills(unit: Unit, battle: BattleManager) -> Array:
	var out: Array = []
	for t in [&"active", &"ult"]:
		var s := battle.data.get_skill_for_unit(unit.data.unit_id, t)
		if s != null and battle.can_use_skill(unit, s):
			out.append(s)
	return out

## 从指定落点解析技能目标（评估用，瞄准点自动选最优）。
## 误伤（friendly_fire）卷入的友军不算合法目标：否则 AI 会把队友当敌人打分，
## 且结算时重掷误伤判定可能无一命中（「无可命中目标」报错）。
static func _targets_from(unit: Unit, skill: SkillData, dest: Vector2i, battle: BattleManager) -> Array[Unit]:
	var resolved: Array[Unit] = []
	if Targeting.needs_aim(skill):
		var aim := _best_aim(unit, skill, dest, battle)
		if aim == Vector2i(-1, -1):
			return []
		resolved = Targeting.resolve_from(skill, unit, aim, battle.grid, battle.units, battle.rolls, dest)
	else:
		resolved = Targeting.resolve_from(skill, unit, Vector2i(-1, -1), battle.grid, battle.units, battle.rolls, dest)
	if String(skill.target) != "enemy":
		return resolved
	var out: Array[Unit] = []
	for u in resolved:
		if _is_hostile(unit, u):
			out.append(u)
	return out

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
	if other.collectable:
		return false   # AI 不攻击可夺取物件（杨志不砸自己的镖，决策日志 D38）
	return (other.team == Unit.Team.ENEMY) != (unit.team == Unit.Team.ENEMY)

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
