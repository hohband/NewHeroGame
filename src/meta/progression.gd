class_name Progression
extends RefCounted
## 养成系统（策划文档第四章）：升级/升星/突破/武器/技能的全部规则与数值。
## 数值参数全部来自 data/progression.csv（DataLoader.progression），禁止硬编码。
## 公式为原型期占位（决策日志 D29，待策划平衡）。

const QUALITY_ORDER: Array[StringName] = [&"green", &"blue", &"purple", &"orange"]

# ---------------------------------------------------------------- 查询

static func exp_to_next(level: int, prog: Dictionary) -> int:
	return int(prog["level_exp_base"]) * level

## 属性倍率 = 等级成长 × 星级倍率 × 突破档（对齐数值基调）
static func stat_mult(hero: Hero, base: UnitData, prog: Dictionary) -> float:
	var m := 1.0 + float(prog["level_stat_growth"]) * float(hero.level - 1)
	m *= 1.0 + float(prog["star_stat_mult"]) * float(hero.star - 1)
	m *= 1.0 + float(prog["breakthrough_stat_step"]) * float(_tiers_above_base(hero, base))
	return m

static func _tiers_above_base(hero: Hero, base: UnitData) -> int:
	return QUALITY_ORDER.find(hero.quality) - QUALITY_ORDER.find(base.quality)

static func weapon_atk_mult(hero: Hero, prog: Dictionary) -> float:
	return 1.0 + float(prog["weapon_enhance_atk"]) * float(hero.weapon_enhance) \
		+ float(prog["weapon_refine_atk"]) * float(hero.weapon_refine)

static func skill_effect_mult(hero: Hero, skill_id: StringName, prog: Dictionary) -> float:
	return 1.0 + float(prog["skill_level_mult"]) * float(hero.skill_level(skill_id) - 1)

## 生成战斗用 UnitData：基础 × 养成倍率；攻击另乘武器倍率；品质取当前（可突破）
static func compute_unit_data(hero: Hero, base: UnitData, prog: Dictionary) -> UnitData:
	var d := base.duplicate()
	var m := stat_mult(hero, base, prog)
	d.hp = roundi(float(base.hp) * m)
	d.atk = roundi(float(base.atk) * m * weapon_atk_mult(hero, prog))
	d.def = roundi(float(base.def) * m)
	d.mgc = roundi(float(base.mgc) * m)
	d.spd = roundi(float(base.spd) * m)
	d.quality = hero.quality
	return d

# ---------------------------------------------------------------- 操作（返回是否成功；消耗品由调用方持有并扣减）

static func add_exp(hero: Hero, amount: int, prog: Dictionary) -> int:
	## 返回升了几级
	var gained := 0
	hero.exp += amount
	while hero.exp >= exp_to_next(hero.level, prog):
		hero.exp -= exp_to_next(hero.level, prog)
		hero.level += 1
		gained += 1
	return gained

static func star_up_cost(hero: Hero, prog: Dictionary) -> int:
	return int(prog["star_shard_cost"]) * (hero.star + 1)

static func can_star_up(hero: Hero, shards: int, prog: Dictionary) -> bool:
	return hero.star < int(prog["star_max"]) and shards >= star_up_cost(hero, prog)

static func star_up(hero: Hero, prog: Dictionary) -> bool:
	if hero.star >= int(prog["star_max"]):
		return false
	hero.star += 1
	return true

static func can_breakthrough(hero: Hero, prog: Dictionary) -> bool:
	return hero.star >= int(prog["star_max"]) and hero.quality != &"orange"

static func breakthrough(hero: Hero, prog: Dictionary) -> bool:
	if not can_breakthrough(hero, prog):
		return false
	var idx := QUALITY_ORDER.find(hero.quality)
	hero.quality = QUALITY_ORDER[idx + 1]
	return true

static func skill_upgrade_cost(hero: Hero, skill_id: StringName, prog: Dictionary) -> int:
	return int(prog["skill_book_cost"]) * (hero.skill_level(skill_id) + 1)

static func skill_upgrade(hero: Hero, skill_id: StringName, prog: Dictionary) -> bool:
	if hero.skill_level(skill_id) >= int(prog["skill_level_max"]):
		return false
	hero.skill_levels[skill_id] = hero.skill_level(skill_id) + 1
	return true

static func weapon_enhance_cost(hero: Hero, prog: Dictionary) -> int:
	return int(prog["weapon_enhance_gold"]) * (hero.weapon_enhance + 1)

static func weapon_enhance(hero: Hero, prog: Dictionary) -> bool:
	if hero.weapon_enhance >= int(prog["weapon_enhance_max"]):
		return false
	hero.weapon_enhance += 1
	return true

static func weapon_refine(hero: Hero, prog: Dictionary) -> bool:
	if hero.weapon_refine >= int(prog["weapon_refine_max"]):
		return false
	hero.weapon_refine += 1
	return true
