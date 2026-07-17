class_name DamageCalculator
extends RefCounted
## 伤害与命中结算（策划文档 6.6 及修正表）：
##   基础伤害 = 攻击 × 技能倍率 × 100 ÷ (100 + 目标防御)
##   最终伤害 = 基础伤害 × 暴击(1.5) × (1 + 方位 + 高低差 + 光环)
## 同类百分比加成相加而非叠乘（决策日志 D6）；闪避 = 完全免伤；格挡 = 减伤 30%。

const CRIT_MULT := 1.5
const BLOCK_REDUCE := 0.3
const BACKSTAB_MOD := 0.25
const SIDE_MOD := 0.10
const HIGH_GROUND_MOD := 0.15
const LOW_GROUND_MOD := -0.10

## 结算一次攻击。返回 {hit, dodged, blocked, crit, amount, dir_mod, height_mod}。
## rolls 可注入固定序列的随机源以便测试；sure_hit = true 时跳过闪避判定（百步穿杨）。
static func compute(attacker: Unit, target: Unit, multiplier: float, grid: Grid, rolls: RollSource, aura_mod: float = 0.0, sure_hit: bool = false, attack_value: int = -1) -> Dictionary:
	var result := {
		"hit": true, "dodged": false, "blocked": false, "crit": false,
		"amount": 0, "dir_mod": 0.0, "height_mod": 0.0,
	}
	# 闪避判定（命中对抗，完全免伤）
	if not sure_hit and rolls.roll() < float(target.get_dodge(grid)):
		result["hit"] = false
		result["dodged"] = true
		return result
	var dir_mod := direction_mod(attacker, target)
	var height_mod := _height_mod(attacker, target, grid)
	result["dir_mod"] = dir_mod
	result["height_mod"] = height_mod
	var atk_value := attacker.get_atk(grid) if attack_value < 0 else attack_value   # mgc_dmg 传入谋略（决策日志 D27）
	var base := float(atk_value) * multiplier * 100.0 / float(100 + target.get_def(grid))
	var amount := base * (1.0 + dir_mod + height_mod + aura_mod)
	if rolls.roll() < float(attacker.get_crit()):
		result["crit"] = true
		amount *= CRIT_MULT
	if rolls.roll() < float(target.get_block()):
		result["blocked"] = true
		amount *= 1.0 - BLOCK_REDUCE
	result["amount"] = maxi(1, roundi(amount))
	return result

## 方位加成：攻击方向与目标朝向一致 = 背刺 +25%；垂直 = 侧击 +10%；正面 +0（决策日志 D5）。
static func direction_mod(attacker: Unit, target: Unit) -> float:
	return direction_mod_from(attacker, target, attacker.coords)

## 从指定位置攻击的方位加成（AI 评估候选落点用）。
static func direction_mod_from(attacker: Unit, target: Unit, from: Vector2i) -> float:
	var diff := target.coords - from
	if diff == Vector2i.ZERO:
		return 0.0
	var dir := dominant_dir(diff)
	if dir == target.facing:
		return BACKSTAB_MOD
	if dir == -target.facing:
		return 0.0
	return SIDE_MOD

## 高低差：高打低 +15% / 低打高 -10%。
static func _height_mod(attacker: Unit, target: Unit, grid: Grid) -> float:
	return _height_mod_from(attacker, target, grid, attacker.coords)

static func _height_mod_from(attacker: Unit, target: Unit, grid: Grid, from: Vector2i) -> float:
	var ha := 0
	var ht := 0
	var ca := grid.get_cell(from)
	var ct := grid.get_cell(target.coords)
	if ca != null:
		ha = ca.height
	if ct != null:
		ht = ct.height
	if ha > ht:
		return HIGH_GROUND_MOD
	if ha < ht:
		return LOW_GROUND_MOD
	return 0.0

## 不掷骰的伤害期望值（AI 评分用）：闪避折算命中率、暴击折算期望加成。
## 攻击者地形修正按当前格读取（CSV 中 atk_mod 全 0，决策日志 D26 注）。
static func estimate_at(attacker: Unit, target: Unit, multiplier: float, grid: Grid, from: Vector2i) -> float:
	var dir := direction_mod_from(attacker, target, from)
	var height := _height_mod_from(attacker, target, grid, from)
	var base := float(attacker.get_atk(grid)) * multiplier * 100.0 / float(100 + target.get_def(grid))
	var expect := base * (1.0 + dir + height)
	expect *= 1.0 + float(attacker.get_crit()) / 100.0 * (CRIT_MULT - 1.0)
	expect *= clampf(1.0 - float(target.get_dodge(grid)) / 100.0, 0.05, 1.0)
	return expect

static func dominant_dir(diff: Vector2i) -> Vector2i:
	if absi(diff.x) >= absi(diff.y):
		return Vector2i(signi(diff.x), 0)
	return Vector2i(0, signi(diff.y))
