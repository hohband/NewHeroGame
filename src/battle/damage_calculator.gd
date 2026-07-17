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
static func compute(attacker: Unit, target: Unit, multiplier: float, grid: Grid, rolls: RollSource, aura_mod: float = 0.0, sure_hit: bool = false) -> Dictionary:
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
	var base := float(attacker.get_atk(grid)) * multiplier * 100.0 / float(100 + target.get_def(grid))
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
	var diff := target.coords - attacker.coords
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
	var ha := 0
	var ht := 0
	var ca := grid.get_cell(attacker.coords)
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

static func dominant_dir(diff: Vector2i) -> Vector2i:
	if absi(diff.x) >= absi(diff.y):
		return Vector2i(signi(diff.x), 0)
	return Vector2i(0, signi(diff.y))
