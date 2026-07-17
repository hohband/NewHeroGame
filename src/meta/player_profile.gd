class_name PlayerProfile
extends Resource
## 玩家档案：已拥有武将、资源、关卡进度。JSON 序列化存档（SaveSystem）。

@export var heroes: Dictionary = {}      # unit_id -> Hero
@export var gold: int = 0
@export var items: Dictionary = {}       # 道具：shard（通用碎片）/ skill_book / breakthrough_mat ...
@export var progress: Dictionary = {}    # {"chapter": 1, "cleared": [level_id...]}
@export var achievements: Dictionary = {} # 成就 id -> true（如「不战而屈人之兵」）

## 新档：初始武将（CSV unlock=初始武将：石勇/宋万/杜迁）+ 启动资源（决策日志 D30）
static func new_default(loader: GameDataLoader) -> PlayerProfile:
	var p := PlayerProfile.new()
	for id in loader.units:
		var ud: UnitData = loader.units[id]
		if ud.unlock == "初始武将":
			p.add_hero(Hero.new(id, ud.quality))
	p.gold = 2000
	p.items = {"shard": 20, "skill_book": 5, "breakthrough_mat": 3}
	p.progress = {"chapter": 1, "cleared": []}
	return p

func add_hero(hero: Hero) -> void:
	heroes[hero.unit_id] = hero

func get_hero(unit_id: StringName) -> Hero:
	return heroes.get(unit_id) as Hero

func has_hero(unit_id: StringName) -> bool:
	return heroes.has(unit_id)

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	return true

func spend_item(item_id: StringName, count: int) -> bool:
	if int(items.get(item_id, 0)) < count:
		return false
	items[item_id] = int(items[item_id]) - count
	return true

func gain_item(item_id: StringName, count: int) -> void:
	items[item_id] = int(items.get(item_id, 0)) + count

func to_dict() -> Dictionary:
	var hs: Dictionary = {}
	for id in heroes:
		hs[String(id)] = (heroes[id] as Hero).to_dict()
	return {
		"version": 1,
		"heroes": hs,
		"gold": gold,
		"items": items.duplicate(),
		"progress": progress.duplicate(),
		"achievements": achievements.duplicate(),
	}

static func from_dict(d: Dictionary) -> PlayerProfile:
	var p := PlayerProfile.new()
	for id in d.get("heroes", {}):
		p.heroes[StringName(id)] = Hero.from_dict(d["heroes"][id])
	p.gold = int(d.get("gold", 0))
	p.items = d.get("items", {}).duplicate()
	p.progress = d.get("progress", {"chapter": 1, "cleared": []}).duplicate()
	p.achievements = d.get("achievements", {}).duplicate()
	return p
