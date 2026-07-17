class_name Hero
extends Resource
## 已拥有武将实例（养成载体）：CSV 基础值之上的玩家养成进度（策划文档第四章）。
## 战斗内生效数值 = 基础 × 等级成长 × 星级倍率 × 突破档 + 武器（Progression.compute_unit_data）。

@export var unit_id: StringName
@export var level: int = 1
@export var exp: int = 0
@export var star: int = 1
## 当前品质（聚义升星可突破提升：绿→蓝→紫，橙为上限，策划文档 4.4）
@export var quality: StringName = &"green"
@export var weapon_enhance: int = 0   # 武器强化等级
@export var weapon_refine: int = 0    # 武器精炼阶数
@export var skill_levels: Dictionary = {}   # skill_id -> 等级（1 起）

func _init(p_id: StringName = &"", p_quality: StringName = &"green") -> void:
	unit_id = p_id
	quality = p_quality

func skill_level(skill_id: StringName) -> int:
	return int(skill_levels.get(skill_id, 1))

func to_dict() -> Dictionary:
	return {
		"unit_id": String(unit_id), "level": level, "exp": exp, "star": star,
		"quality": String(quality), "weapon_enhance": weapon_enhance,
		"weapon_refine": weapon_refine,
		"skill_levels": skill_levels.duplicate(),
	}

static func from_dict(d: Dictionary) -> Hero:
	var h := Hero.new(StringName(d.get("unit_id", "")), StringName(d.get("quality", "green")))
	h.level = int(d.get("level", 1))
	h.exp = int(d.get("exp", 0))
	h.star = int(d.get("star", 1))
	h.weapon_enhance = int(d.get("weapon_enhance", 0))
	h.weapon_refine = int(d.get("weapon_refine", 0))
	for k in d.get("skill_levels", {}):
		h.skill_levels[StringName(k)] = int(d["skill_levels"][k])
	return h
