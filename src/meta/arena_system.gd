class_name ArenaSystem
extends RefCounted
## 演武场异步 PVP（策划文档 8.6/第九章）：攻方手动 vs 守方预设阵容 AI。
## 守方策略模板 = 一套权重修正系数。无服务器环境下的本地闭环：
## 挑战「自己的守方阵容」镜像（联网对战需服务器，属阻塞清单，决策日志 D34）。

## 守方策略模板（8.6 原值）：权重修正 + 特殊规则
const TEMPLATES := {
	"steady": {"name": "稳健防守",
		"weights": {"danger": 1.5, "damage_expect": 0.8},
		"away_from_deploy": -10.0},
	"aggressive": {"name": "激进突进",
		"weights": {"damage_expect": 1.3, "kill_bonus": 1.5, "danger": 0.6}},
	"protect_core": {"name": "保护核心",
		"weights": {}, "core_bonus": 20.0, "core_danger_mult": 2.0},
}
const TEMPLATE_ORDER: Array[String] = ["steady", "aggressive", "protect_core"]
const MAX_DEFENSE := 4

## 守方配置存于 profile.progress["arena"] = {"team": [unit_id...], "template": "steady"}
static func get_defense(profile: PlayerProfile) -> Dictionary:
	if not profile.progress.has("arena"):
		profile.progress["arena"] = {"team": _default_team(profile), "template": "steady"}
	return profile.progress["arena"]

## 默认守方：等级最高的 4 名武将
static func _default_team(profile: PlayerProfile) -> Array:
	var sorted := profile.heroes.values()
	sorted.sort_custom(func(a, b): return a.level > b.level)
	var out: Array = []
	for i in range(mini(MAX_DEFENSE, sorted.size())):
		out.append(sorted[i].unit_id)
	return out

static func set_template(profile: PlayerProfile, template: String) -> void:
	get_defense(profile)["template"] = template

static func set_team(profile: PlayerProfile, ids: Array) -> void:
	get_defense(profile)["team"] = ids.slice(0, MAX_DEFENSE)

## 生成演武场关卡：守方阵容按玩家养成数值生成为敌方（含策略模板）
static func build_arena_level(profile: PlayerProfile, loader: GameDataLoader) -> LevelConfig:
	var defense := get_defense(profile)
	var l := LevelConfig.new()
	l.id = "arena_pvp"
	l.name = "演武场·切磋"
	l.mode = "arena"
	l.grid_size = Vector2i(10, 8)
	l.terrain_map = {Vector2i(4, 3): &"hill", Vector2i(5, 3): &"hill"}
	l.height_map = {Vector2i(4, 3): 1, Vector2i(5, 3): 1}
	l.win_condition = {"type": "WIPE_OUT"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	l.required_units = []
	l.max_deploy = MAX_DEFENSE
	l.deploy_zone = Rect2i(0, 6, 10, 2)
	for id in profile.heroes:
		l.roster.append(id)
	var coords_list: Array[Vector2i] = [Vector2i(3, 1), Vector2i(6, 1), Vector2i(4, 1), Vector2i(5, 1)]
	var team: Array = defense.get("team", [])
	for i in range(mini(team.size(), MAX_DEFENSE)):
		var uid: StringName = StringName(team[i])
		if not profile.has_hero(uid) or loader.get_unit(uid) == null:
			continue
		l.enemies.append({"unit": uid, "coords": coords_list[i], "team": "enemy", "hero": profile.get_hero(uid)})
	l.pvp_template = String(defense.get("template", "steady"))
	l.rewards = {"first_clear": {"gold": 300, "arena_point": 1}, "regular": {"gold": 300, "arena_point": 1}}
	return l

## 把模板应用到战斗（场景在 setup_level 后调用）；核心模板以守方首单位为核心（8.6）
static func apply_template(manager: BattleManager, template: String) -> void:
	var t: Dictionary = TEMPLATES.get(template, {})
	manager.pvp_mods = t.duplicate(true)
	if t.has("core_bonus"):
		for u in manager.units:
			if u.team == Unit.Team.ENEMY and not u.is_object:
				manager.pvp_core = u
				break
