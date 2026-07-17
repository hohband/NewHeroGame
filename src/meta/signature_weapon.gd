class_name SignatureWeapon
extends RefCounted
## 专属武器（策划文档 4.2/4.4）：每名武将预留专属武器槽，专武带来技能形态质变。
## 首个落地案例：汤隆专武——act_goulian 单体破甲升级为群体破甲（溅射 2 格，D35）。

const UNLOCK_MAT_COST := 5    # 突破材料 ×5（占位）
const UNLOCK_MIN_STAR := 3    # 3 星解锁（占位）

## 技能形态质变注册表：skill_id -> {"effect": 溅射的原子效果名, "splash_radius": 格}
const MORPHS := {
	&"act_goulian": {"effect": "armor_break", "splash_radius": 2},
}

static func can_unlock(hero: Hero, profile: PlayerProfile) -> bool:
	return not hero.has_signature_weapon \
		and hero.star >= UNLOCK_MIN_STAR \
		and int(profile.items.get("breakthrough_mat", 0)) >= UNLOCK_MAT_COST

static func unlock(hero: Hero, profile: PlayerProfile) -> bool:
	if not can_unlock(hero, profile):
		return false
	profile.spend_item(&"breakthrough_mat", UNLOCK_MAT_COST)
	hero.has_signature_weapon = true
	return true

## 有专武则返回该技能的形态质变（无则空表）
static func morph_for(hero: Hero, skill_id: StringName) -> Dictionary:
	if hero == null or not hero.has_signature_weapon:
		return {}
	return MORPHS.get(skill_id, {})
