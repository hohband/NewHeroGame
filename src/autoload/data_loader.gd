class_name GameDataLoader
extends Node
## AutoLoad（注册名 DataLoader）：启动时解析 data/ 三张 CSV → 缓存 Resource，全项目按 ID 查询。
## CSV 是唯一数据源，禁止在代码里硬编码数值（数据表说明第四节）。
## 测试与命令行工具请自行实例化（GameDataLoader.new() + load_all()），不依赖 autoload。

const UNITS_CSV := "res://data/units.csv"
const SKILLS_CSV := "res://data/skills.csv"
const TERRAINS_CSV := "res://data/terrains.csv"
const AI_WEIGHTS_CSV := "res://data/ai_weights.csv"
const RESERVED_TXT := "res://data/reserved_units.txt"

const QUALITIES: Array[StringName] = [&"orange", &"purple", &"blue", &"green"]
const CLASSES: Array[StringName] = [&"vanguard", &"infantry", &"cavalry", &"archer", &"strategist", &"healer", &"support"]
const SKILL_TYPES: Array[StringName] = [&"active", &"passive", &"ult"]
const RANGE_SHAPES: Array[StringName] = [&"adjacent", &"line", &"ring", &"diamond", &"all", &"self"]
const TARGETS: Array[StringName] = [&"enemy", &"ally", &"self"]

var units: Dictionary = {}      # unit_id -> UnitData
var skills: Dictionary = {}     # skill_id -> SkillData
var terrains: Dictionary = {}   # terrain_id -> TerrainData
var ai_weights: Dictionary = {} # class -> {factor -> float}（策划文档 8.3 权重表）
var reserved: Dictionary = {}   # 预留武将（未实装）：StringName -> true

func _ready() -> void:
	load_all()

func load_all() -> void:
	terrains = _load_terrains(TERRAINS_CSV)
	skills = _load_skills(SKILLS_CSV)
	units = _load_units(UNITS_CSV)
	ai_weights = _load_ai_weights(AI_WEIGHTS_CSV)
	reserved = _load_reserved(RESERVED_TXT)

func get_unit(id: StringName) -> UnitData:
	return units.get(id) as UnitData

func get_skill(id: StringName) -> SkillData:
	return skills.get(id) as SkillData

func get_terrain(id: StringName) -> TerrainData:
	return terrains.get(id) as TerrainData

## 按持有者 + 类型查技能（武将的 act_/ult_ 技能；skill_signature 字段之外的主动技走这里）
func get_skill_for_unit(unit_id: StringName, type: StringName) -> SkillData:
	for id in skills:
		var s: SkillData = skills[id]
		if s.owner == String(unit_id) and s.type == type:
			return s
	return null

## 职业 AI 权重（ai_weights.csv）；缺行时退回全 1.0 并告警
func get_ai_weights(class_id: StringName) -> Dictionary:
	if not ai_weights.has(class_id):
		push_warning("DataLoader: 职业 %s 缺少 AI 权重行，按全 1.0 处理" % class_id)
		return {"damage_expect": 1.0, "kill_bonus": 1.0, "target_value": 1.0, "danger": 1.0, "aura_coverage": 1.0, "position": 1.0}
	return ai_weights[class_id]

# ---------------------------------------------------------------- CSV 解析

## 读取 CSV 为 [{表头: 值}, ...]；自动跳过 UTF-8 BOM 与尾部空行，列数不符的行告警跳过。
static func _read_table(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataLoader: 无法打开 " + path)
		return result
	if f.get_buffer(3) != PackedByteArray([0xEF, 0xBB, 0xBF]):
		f.seek(0)   # 无 BOM 则回到开头
	var headers := f.get_csv_line()
	while f.get_position() < f.get_length():
		var line := f.get_csv_line()
		if line.size() != headers.size():
			if line.size() == 1 and line[0].strip_edges().is_empty():
				continue   # 尾部空行
			push_warning("DataLoader: %s 行列数(%d)≠表头(%d)，已跳过：%s" % [path, line.size(), headers.size(), line])
			continue
		var row: Dictionary = {}
		for i in headers.size():
			row[headers[i]] = line[i]
		result.append(row)
	return result

static func _int(row: Dictionary, key: String) -> int:
	return int(str(row.get(key, "0")).strip_edges())

static func _load_units(path: String) -> Dictionary:
	var out: Dictionary = {}
	for row in _read_table(path):
		var u := UnitData.new()
		u.unit_id = StringName(row.get("unit_id", ""))
		u.name = row.get("name", "")
		u.nickname = row.get("nickname", "")
		u.star = row.get("star", "")
		u.quality = StringName(row.get("quality", ""))
		u.unit_class = StringName(row.get("class", ""))
		u.hp = _int(row, "hp")
		u.atk = _int(row, "atk")
		u.def = _int(row, "def")
		u.mgc = _int(row, "mgc")
		u.spd = _int(row, "spd")
		u.crit = _int(row, "crit")
		u.dodge = _int(row, "dodge")
		u.block = _int(row, "block")
		u.move = _int(row, "move")
		u.range_min = _int(row, "range_min")
		u.range_max = _int(row, "range_max")
		u.weapon = row.get("weapon", "")
		u.skill_signature = StringName(row.get("skill_signature", ""))
		u.bonds = parse_bonds(row.get("bonds", ""))
		u.unlock = row.get("unlock", "")
		if out.has(u.unit_id):
			push_error("DataLoader: 重复 unit_id '%s'" % u.unit_id)
		out[u.unit_id] = u
	return out

static func _load_skills(path: String) -> Dictionary:
	var out: Dictionary = {}
	for row in _read_table(path):
		var s := SkillData.new()
		s.skill_id = StringName(row.get("skill_id", ""))
		s.name = row.get("name", "")
		s.owner = row.get("owner", "")
		s.type = StringName(row.get("type", ""))
		s.trigger = StringName(row.get("trigger", ""))
		s.range_shape = StringName(row.get("range_shape", ""))
		s.range_min = _int(row, "range_min")
		s.range_max = _int(row, "range_max")
		s.target = StringName(row.get("target", ""))
		s.cooldown = _int(row, "cooldown")
		s.rage_cost = _int(row, "rage_cost")
		s.effects = row.get("effects", "")
		s.desc = row.get("desc", "")
		if out.has(s.skill_id):
			push_error("DataLoader: 重复 skill_id '%s'" % s.skill_id)
		out[s.skill_id] = s
	return out

static func _load_terrains(path: String) -> Dictionary:
	var out: Dictionary = {}
	for row in _read_table(path):
		var t := TerrainData.new()
		t.terrain_id = StringName(row.get("terrain_id", ""))
		t.name = row.get("name", "")
		t.move_cost = _int(row, "move_cost")
		t.dodge_mod = _int(row, "dodge_mod")
		t.def_mod = _int(row, "def_mod")
		t.atk_mod = _int(row, "atk_mod")
		t.range_mod = _int(row, "range_mod")
		t.passable = _int(row, "passable") == 1
		t.destructible = _int(row, "destructible") == 1
		t.hp = _int(row, "hp")
		t.special = row.get("special", "")
		if out.has(t.terrain_id):
			push_error("DataLoader: 重复 terrain_id '%s'" % t.terrain_id)
		out[t.terrain_id] = t
	return out

static func _load_ai_weights(path: String) -> Dictionary:
	var out: Dictionary = {}
	for row in _read_table(path):
		out[StringName(row.get("class", ""))] = {
			"damage_expect": float(str(row.get("damage_expect", "1.0"))),
			"kill_bonus": float(str(row.get("kill_bonus", "1.0"))),
			"target_value": float(str(row.get("target_value", "1.0"))),
			"danger": float(str(row.get("danger", "1.0"))),
			"aura_coverage": float(str(row.get("aura_coverage", "1.0"))),
			"position": float(str(row.get("position", "1.0"))),
		}
	return out

static func _load_reserved(path: String) -> Dictionary:
	var out: Dictionary = {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("DataLoader: 预留名单缺失 " + path)
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		out[StringName(line)] = true
	return out

## 羁绊格式：目标unit_id或预留名|羁绊名;…（数据表说明第一节）
static func parse_bonds(raw: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in raw.split(";", false):
		var parts := entry.split("|", false)
		if parts.is_empty():
			continue
		out.append({
			"target": StringName(parts[0].strip_edges()),
			"name": parts[1].strip_edges() if parts.size() > 1 else "",
		})
	return out

# ---------------------------------------------------------------- 数据校验（数据表说明第五节）

func validate() -> Array[String]:
	var errors: Array[String] = []
	for id in units:
		var u: UnitData = units[id]
		if not QUALITIES.has(u.quality):
			errors.append("武将 %s：非法 quality '%s'" % [id, u.quality])
		if not CLASSES.has(u.unit_class):
			errors.append("武将 %s：非法 class '%s'" % [id, u.unit_class])
		if not ai_weights.has(u.unit_class):
			errors.append("武将 %s：职业 %s 缺少 AI 权重行（ai_weights.csv）" % [id, u.unit_class])
		if not skills.has(u.skill_signature):
			errors.append("武将 %s：skill_signature '%s' 不在技能表" % [id, u.skill_signature])
		for b in u.bonds:
			var t: StringName = b["target"]
			if not units.has(t) and not reserved.has(t):
				errors.append("武将 %s：羁绊目标 '%s' 未实装且未登记为预留名" % [id, t])
		for field in ["hp", "atk", "def", "mgc", "spd", "crit", "dodge", "block", "move", "range_min", "range_max"]:
			if int(u.get(field)) < 0:
				errors.append("武将 %s：%s 不得为负" % [id, field])
	for id in skills:
		var s: SkillData = skills[id]
		if not SKILL_TYPES.has(s.type):
			errors.append("技能 %s：非法 type '%s'" % [id, s.type])
		if not RANGE_SHAPES.has(s.range_shape):
			errors.append("技能 %s：非法 range_shape '%s'" % [id, s.range_shape])
		if not TARGETS.has(s.target):
			errors.append("技能 %s：非法 target '%s'" % [id, s.target])
		if s.cooldown < 0 or s.rage_cost < 0:
			errors.append("技能 %s：cooldown/rage_cost 不得为负" % id)
		EffectSystem.parse_effects(s.effects)   # 解析失败会在内部 push_error 并指出技能ID/效果名
	for id in terrains:
		var t: TerrainData = terrains[id]
		if t.move_cost < 0:
			errors.append("地形 %s：move_cost 不得为负" % id)
		if t.move_cost == 99 and t.passable:
			errors.append("地形 %s：move_cost=99（不可通行）但 passable=1" % id)
	return errors
