class_name ExpeditionSystem
extends RefCounted
## 梁山远征：Roguelike 爬塔（策划文档第九章，长线终局玩法，决策日志 D35）。
## 规则：固定 4 人队连续挑战 10 层，生命跨层继承，阵亡不进下赛季；
## 每层胜利后三选一奖励（休整/磨刀/扎营），全灭或通关 10 层结算。

const MAX_FLOOR := 10
const FLOOR_STAT_MULT := 0.12   # 每层敌人属性 +12%（占位，D35）

const FLOOR_REWARDS: Array[Dictionary] = [
	{"id": "heal", "name": "休整：全队回复 30% 生命"},
	{"id": "atk_up", "name": "磨刀：全队攻 +10%（本次远征）"},
	{"id": "def_up", "name": "扎营：全队防 +10%（本次远征）"},
]

# ---------------------------------------------------------------- 队伍与关卡

## 新远征：队伍 = 等级前 4（后续版本开放自选）
static func new_run(profile: PlayerProfile) -> Dictionary:
	var sorted := profile.heroes.values()
	sorted.sort_custom(func(a, b): return a.level > b.level)
	var team: Array = []
	for i in range(mini(4, sorted.size())):
		team.append({"unit_id": sorted[i].unit_id, "hp_ratio": 1.0, "alive": true})
	return {"floor": 1, "team": team, "buffs": [], "finished": false}

## 生成当层关卡（敌人按层数缩放属性）
static func build_floor(run: Dictionary, loader: GameDataLoader) -> LevelConfig:
	var floor: int = run["floor"]
	var l := LevelConfig.new()
	l.id = "expedition_%d" % floor
	l.name = "梁山远征·第 %d 层" % floor
	l.mode = "expedition"
	l.grid_size = Vector2i(8, 8)
	# 地形按层轮换增加变化
	match floor % 3:
		0:
			l.terrain_map = {Vector2i(3, 3): &"hill", Vector2i(4, 3): &"hill"}
			l.height_map = {Vector2i(3, 3): 1, Vector2i(4, 3): 1}
		1:
			l.terrain_map = {Vector2i(2, 2): &"forest", Vector2i(5, 2): &"forest", Vector2i(3, 4): &"camp"}
		2:
			l.terrain_map = {Vector2i(4, 2): &"barricade", Vector2i(3, 5): &"camp", Vector2i(2, 3): &"forest"}
	l.win_condition = {"type": "WIPE_OUT"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	l.required_units = []
	l.roster = []
	l.max_deploy = 4
	l.deploy_zone = Rect2i(0, 6, 8, 2)
	l.enemies.assign(_floor_enemies(floor))
	var mult := 1.0 + FLOOR_STAT_MULT * float(floor - 1)
	for spec in l.enemies:
		spec["stat_mult"] = mult
	return l

static func _floor_enemies(floor: int) -> Array:
	var spear := func(c: Vector2i) -> Dictionary: return {"unit": &"xiangjun_spear", "coords": c}
	var shield := func(c: Vector2i) -> Dictionary: return {"unit": &"xiangjun_shield", "coords": c}
	var duguan := func(c: Vector2i, elite := false) -> Dictionary:
		return {"unit": &"lao_duguan", "coords": c, "elite": elite}
	match floor:
		1:
			return [spear.call(Vector2i(3, 1)), spear.call(Vector2i(4, 1)), spear.call(Vector2i(5, 1))]
		2:
			return [spear.call(Vector2i(3, 1)), spear.call(Vector2i(5, 1)), spear.call(Vector2i(4, 2)), shield.call(Vector2i(4, 1))]
		3:
			return [spear.call(Vector2i(2, 1)), spear.call(Vector2i(3, 1)), spear.call(Vector2i(5, 1)), spear.call(Vector2i(6, 1)), shield.call(Vector2i(4, 1))]
		4:
			return [spear.call(Vector2i(3, 1)), spear.call(Vector2i(5, 1)), spear.call(Vector2i(4, 2)), shield.call(Vector2i(3, 2)), shield.call(Vector2i(5, 2)), duguan.call(Vector2i(4, 0))]
		5:
			return [duguan.call(Vector2i(4, 1), true), spear.call(Vector2i(3, 1)), spear.call(Vector2i(5, 1)), spear.call(Vector2i(4, 2)), shield.call(Vector2i(4, 3))]
		6:
			return [spear.call(Vector2i(2, 1)), spear.call(Vector2i(3, 1)), spear.call(Vector2i(5, 1)), spear.call(Vector2i(6, 1)), shield.call(Vector2i(3, 2)), shield.call(Vector2i(5, 2))]
		7:
			return [spear.call(Vector2i(2, 1)), spear.call(Vector2i(3, 1)), spear.call(Vector2i(5, 1)), spear.call(Vector2i(6, 1)), shield.call(Vector2i(4, 1)), shield.call(Vector2i(4, 2)), duguan.call(Vector2i(4, 0))]
		8:
			return [spear.call(Vector2i(2, 1)), spear.call(Vector2i(3, 1)), spear.call(Vector2i(4, 2)), spear.call(Vector2i(5, 1)), spear.call(Vector2i(6, 1)), shield.call(Vector2i(3, 2)), shield.call(Vector2i(5, 2))]
		9:
			return [duguan.call(Vector2i(4, 0), true), spear.call(Vector2i(2, 1)), spear.call(Vector2i(3, 1)), spear.call(Vector2i(5, 1)), spear.call(Vector2i(6, 1)), shield.call(Vector2i(4, 1)), shield.call(Vector2i(4, 2))]
		10:
			return [{"unit": &"yang_zhi_boss", "coords": Vector2i(4, 1), "elite": true, "boss": true},
				spear.call(Vector2i(3, 1)), spear.call(Vector2i(5, 1)), shield.call(Vector2i(3, 2)), shield.call(Vector2i(5, 2))]
	push_error("ExpeditionSystem: 非法层数 %d" % floor)
	return []

# ---------------------------------------------------------------- 跨层状态

## 布阵后调用：生命按比率继承，远征增益上身
static func apply_carryover(manager: BattleManager, run: Dictionary) -> void:
	for u in manager.deployed:
		for t in run["team"]:
			if t["unit_id"] == u.data.unit_id:
				u.hp = maxi(1, roundi(float(u.data.hp) * float(t["hp_ratio"])))
		for b in run["buffs"]:
			var buff := Buff.new()
			buff.buff_id = StringName("expedition_%s" % String(b["field"]))
			buff.name = "远征增益"
			buff.stat_mods = {b["field"]: int(b["value"])}
			buff.duration = 99
			buff.dispellable = false
			u.add_buff(buff)

## 战斗结束后记录队伍状态（生命比率、存活）
static func record_floor_result(manager: BattleManager, run: Dictionary) -> void:
	for t in run["team"]:
		for u in manager.deployed:
			if u.data.unit_id == t["unit_id"]:
				t["hp_ratio"] = clampf(float(u.hp) / float(u.data.hp), 0.0, 1.0)
				t["alive"] = u.is_alive()

# ---------------------------------------------------------------- 层间奖励与结算

static func apply_reward_choice(run: Dictionary, reward_id: String) -> void:
	match reward_id:
		"heal":
			for t in run["team"]:
				if t["alive"]:
					t["hp_ratio"] = minf(1.0, float(t["hp_ratio"]) + 0.3)
		"atk_up":
			run["buffs"].append({"field": &"atk", "value": 10})
		"def_up":
			run["buffs"].append({"field": &"def", "value": 10})

## 远征结算：每层 200 金币，每 3 层 1 突破材料（占位 D35）；记录最佳层数
static func finish_run(profile: PlayerProfile, run: Dictionary) -> Dictionary:
	var cleared: int = run["floor"] - 1
	var gold := cleared * 200
	var mats := cleared / 3
	profile.gold += gold
	profile.gain_item(&"breakthrough_mat", mats)
	var best := int(profile.progress.get("expedition_best", 0))
	profile.progress["expedition_best"] = maxi(best, cleared)
	run["finished"] = true
	return {"floors_cleared": cleared, "gold": gold, "breakthrough_mat": mats,
		"completed": cleared >= MAX_FLOOR}
