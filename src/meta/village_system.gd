class_name VillageSystem
extends RefCounted
## 山寨经营雏形（策划文档第三章、开发计划 M2）：
## 聚义厅产金币、铁匠铺产突破材料、演武场产经验；不上场武将可派驻增产（决策日志 D33）。
## 产出节奏：每通关一次关卡收获一轮（与核心循环同节拍）。

const MAX_LEVEL := 3
const BUILDING_NAMES := {
	&"juyiting": "聚义厅",
	&"tiejiangpu": "铁匠铺",
	&"yanwuchang": "演武场",
}

static func default_village() -> Dictionary:
	return {
		&"juyiting": {"level": 1, "assigned": ""},
		&"tiejiangpu": {"level": 1, "assigned": ""},
		&"yanwuchang": {"level": 1, "assigned": ""},
	}

static func get_village(profile: PlayerProfile) -> Dictionary:
	if not profile.progress.has("village"):
		profile.progress["village"] = default_village()
	return profile.progress["village"]

# ---------------------------------------------------------------- 升级

static func upgrade_cost(current_level: int) -> int:
	return 500 * current_level

static func can_upgrade(profile: PlayerProfile, building: StringName) -> bool:
	var b: Dictionary = get_village(profile)[building]
	return int(b["level"]) < MAX_LEVEL and profile.gold >= upgrade_cost(int(b["level"]))

static func upgrade(profile: PlayerProfile, building: StringName) -> bool:
	if not can_upgrade(profile, building):
		return false
	var b: Dictionary = get_village(profile)[building]
	profile.spend_gold(upgrade_cost(int(b["level"])))
	b["level"] = int(b["level"]) + 1
	return true

# ---------------------------------------------------------------- 派驻

## 派驻/调换岗位：一名武将只能占一个岗位（自动从旧岗位卸下）；岗位只能容一人。
static func assign(profile: PlayerProfile, building: StringName, unit_id: StringName) -> void:
	var village := get_village(profile)
	for id in village:
		if String(village[id].get("assigned", "")) == String(unit_id):
			village[id]["assigned"] = ""
	village[building]["assigned"] = String(unit_id)

static func unassign(profile: PlayerProfile, building: StringName) -> void:
	get_village(profile)[building]["assigned"] = ""

# ---------------------------------------------------------------- 产出

## 每次通关的产出预览；派驻 +25%，汤隆驻铁匠铺再 +25%（4.2 汤隆铁匠铺产出提升，D33）
static func production(profile: PlayerProfile, building: StringName) -> Dictionary:
	var b: Dictionary = get_village(profile)[building]
	var level := int(b["level"])
	var mult := 1.0
	var assigned := String(b.get("assigned", ""))
	if assigned != "":
		mult += 0.25
		if assigned == "tang_long" and building == &"tiejiangpu":
			mult += 0.25
	match building:
		&"juyiting":
			return {"gold": roundi(100.0 * level * mult)}
		&"tiejiangpu":
			return {"breakthrough_mat": maxi(1, roundi(1.0 * level * mult))}
		&"yanwuchang":
			return {"exp": roundi(30.0 * level * mult)}
	return {}

## 通关后收获一轮（Flow 在胜利结算时调用）：金币/材料入档，经验全员发放。
## 返回摘要：{"gold", "materials", "exp_each", "level_ups"}
static func collect(profile: PlayerProfile, loader: GameDataLoader) -> Dictionary:
	var summary := {"gold": 0, "materials": 0, "exp_each": 0, "level_ups": {}}
	var gold: int = production(profile, &"juyiting").get("gold", 0)
	profile.gold += gold
	summary["gold"] = gold
	var mats: int = production(profile, &"tiejiangpu").get("breakthrough_mat", 0)
	profile.gain_item(&"breakthrough_mat", mats)
	summary["materials"] = mats
	var exp: int = production(profile, &"yanwuchang").get("exp", 0)
	summary["exp_each"] = exp
	if exp > 0:
		for id in profile.heroes:
			var ups := Progression.add_exp(profile.heroes[id], exp, loader.progression)
			if ups > 0:
				summary["level_ups"][id] = ups
	return summary
