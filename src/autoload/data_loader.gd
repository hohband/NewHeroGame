class_name GameDataLoader
extends Node
## AutoLoad（注册名 DataLoader）：启动时解析 data/ 各 CSV → 缓存 Resource，全项目按 ID 查询。
## CSV 是唯一数据源，禁止在代码里硬编码数值（数据表说明第四节）。
## 测试与命令行工具请自行实例化（GameDataLoader.new() + load_all()），不依赖 autoload。

const UNITS_CSV := "res://data/units.csv"
const ENEMIES_CSV := "res://data/enemies.csv"
const SKILLS_CSV := "res://data/skills.csv"
const TERRAINS_CSV := "res://data/terrains.csv"
const AI_WEIGHTS_CSV := "res://data/ai_weights.csv"
const PROGRESSION_CSV := "res://data/progression.csv"
const BATTLE_CONSTANTS_CSV := "res://data/battle_constants.csv"
const WEAPONS_CSV := "res://data/weapons.csv"
const ITEMS_CSV := "res://data/items.csv"
const RESERVED_TXT := "res://data/reserved_units.txt"

const QUALITIES: Array[StringName] = [&"orange", &"purple", &"blue", &"green"]
const CLASSES: Array[StringName] = [&"vanguard", &"infantry", &"cavalry", &"archer", &"strategist", &"healer", &"support"]
const SKILL_TYPES: Array[StringName] = [&"active", &"passive", &"ult"]
const TRIGGERS: Array[StringName] = [&"manual", &"on_attack", &"on_hit", &"turn_start"]
const RANGE_SHAPES: Array[StringName] = [&"adjacent", &"line", &"ring", &"diamond", &"all", &"self"]
const TARGETS: Array[StringName] = [&"enemy", &"ally", &"self"]

var units: Dictionary = {}      # unit_id -> UnitData
var hero_ids: Array[StringName] = []  # units.csv 武将（不含 enemies.csv 敌方），被动校验用
var skills: Dictionary = {}     # skill_id -> SkillData
var terrains: Dictionary = {}   # terrain_id -> TerrainData
var ai_weights: Dictionary = {} # class -> {factor -> float}（策划文档 8.3 权重表）
var progression: Dictionary = {} # 养成参数 key -> float（data/progression.csv）
var constants: Dictionary = {}  # 战斗常数 key -> float（data/battle_constants.csv：怒气规则 + AI 评分常数）
var weapons: Dictionary = {}    # 武器名 -> 普攻范围模板 StringName（data/weapons.csv，词表同 Targeting）
var items: Dictionary = {}      # item_id -> ItemData（data/items.csv，策划 6.5 道具）
var reserved: Dictionary = {}   # 预留武将（未实装）：StringName -> true

## 养成参数必备键（缺失视为数据错误，validate 检查）
const PROGRESSION_KEYS: Array[String] = [
	"level_exp_base", "level_stat_growth", "star_stat_mult", "star_max", "star_shard_cost",
	"breakthrough_stat_step", "skill_level_max", "skill_level_mult", "skill_book_cost",
	"weapon_enhance_max", "weapon_enhance_atk", "weapon_enhance_gold",
	"weapon_refine_max", "weapon_refine_atk", "bond_stat_bonus",
]

## 战斗常数必备键（缺失视为数据错误，validate 检查）：怒气规则 + AI 评分/绝技门常数
const CONSTANT_KEYS: Array[String] = [
	"rage_on_hit_taken", "rage_on_kill", "rage_on_wait", "rage_on_skill",
	"ai_kill_base", "ai_focus_bonus", "ai_danger_base", "ai_close_bonus",
	"ai_aura_coverage_factor", "ai_wait_base",
	"ai_target_value_default", "ai_target_value_healer", "ai_target_value_strategist",
	"ai_target_value_dps", "ai_target_value_vanguard", "ai_target_value_low_hp",
	"ai_target_value_full_rage", "ai_target_value_bond_core",
	"ai_pos_backstab", "ai_pos_side", "ai_pos_highground",
	"ai_heal_expect_factor", "ai_heal_urgent_threshold", "ai_heal_urgent_bonus",
	"ai_heal_overheal_factor", "ai_buff_target_base", "ai_support_buff_core",
	"ai_vanguard_cover", "ai_vanguard_cover_line", "ai_infantry_backstab",
	"ai_cavalry_charge_per_cell",
	"ai_cavalry_refresh_kill", "ai_archer_safe_dist", "ai_archer_danger_penalty",
	"ai_archer_highground", "ai_strategist_aoe_per_extra", "ai_strategist_control_high_value",
	"ai_obj_danger_factor", "ai_collect_interact", "ai_collect_approach_base",
	"ai_collect_approach_cell_cost", "ai_escort_base", "ai_escort_cell_cost",
	"ai_wine_stall_arrive", "ai_wine_stall_approach_base", "ai_wine_stall_cell_cost",
	"ai_ult_vanguard_hp", "ai_ult_vanguard_near", "ai_ult_dps_min_targets",
	"ai_ult_strategist_min_targets", "ai_ult_healer_urgent_hp", "ai_ult_healer_avg_hp",
	"ai_ult_support_min_targets",
]

func _ready() -> void:
	load_all()

func load_all() -> void:
	terrains = _load_terrains(TERRAINS_CSV)
	skills = _load_skills(SKILLS_CSV)
	units = _load_units(UNITS_CSV)
	hero_ids.assign(units.keys())   # 敌方并入前的纯武将名单
	# 敌方/剧情单位（enemies.csv）并入同一查询空间，id 不得与武将表冲突
	var enemy_units := _load_units(ENEMIES_CSV)
	for id in enemy_units:
		if units.has(id):
			push_error("DataLoader: enemies.csv 与武将表 id 冲突 '%s'" % id)
		else:
			units[id] = enemy_units[id]
	ai_weights = _load_ai_weights(AI_WEIGHTS_CSV)
	progression = _load_key_values(PROGRESSION_CSV)
	constants = _load_key_values(BATTLE_CONSTANTS_CSV)
	weapons = _load_weapons(WEAPONS_CSV)
	items = _load_items(ITEMS_CSV)
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

## 按持有者 + 触发点查被动技能（被动体系，策划文档 4.3；PassiveSystem 触发用）
func get_passives_for_unit(unit_id: StringName, trigger: StringName) -> Array[SkillData]:
	var out: Array[SkillData] = []
	for id in skills:
		var s: SkillData = skills[id]
		if s.type == &"passive" and s.trigger == trigger and s.owner == String(unit_id):
			out.append(s)
	return out

## 职业 AI 权重（ai_weights.csv）；缺行时退回全 1.0 并告警
func get_ai_weights(class_id: StringName) -> Dictionary:
	if not ai_weights.has(class_id):
		push_warning("DataLoader: 职业 %s 缺少 AI 权重行，按全 1.0 处理" % class_id)
		return {"damage_expect": 1.0, "kill_bonus": 1.0, "target_value": 1.0, "danger": 1.0, "aura_coverage": 1.0, "position": 1.0}
	return ai_weights[class_id]

## 战斗常数（battle_constants.csv）；缺 key 时告警并返回 default
func get_constant(key: String, default: float = 0.0) -> float:
	if not constants.has(key):
		push_warning("DataLoader: 战斗常数缺失 '%s'，按 %s 处理" % [key, default])
		return default
	return float(constants[key])

## 武器的普攻范围模板（weapons.csv，策划 6.5）；未登记时退回 diamond（旧曼哈顿口径）并告警
func get_weapon_shape(weapon_name: String) -> StringName:
	if not weapons.has(weapon_name):
		push_warning("DataLoader: 武器 '%s' 未登记范围模板（weapons.csv），按 diamond 处理" % weapon_name)
		return &"diamond"
	return weapons[weapon_name]

## 按 ID 查道具（items.csv，策划 6.5）
func get_item(id: StringName) -> ItemData:
	return items.get(id) as ItemData

## 标准道具栏默认内容：items.csv 全部道具及其每场次数（写进表即全员可用；meta 可经 set_item_stock 覆盖）
func default_item_stock() -> Dictionary:
	var out: Dictionary = {}
	for id in items:
		out[id] = (items[id] as ItemData).uses_per_battle
	return out

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
		u.traits = _parse_string_list(row.get("traits", ""))
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

static func _load_key_values(path: String) -> Dictionary:
	var out: Dictionary = {}
	for row in _read_table(path):
		out[String(row.get("key", ""))] = float(str(row.get("value", "0")))
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

static func _load_weapons(path: String) -> Dictionary:
	var out: Dictionary = {}
	for row in _read_table(path):
		var w := String(row.get("weapon", ""))
		if out.has(w):
			push_error("DataLoader: 重复武器 '%s'" % w)
		out[w] = StringName(row.get("range_shape", ""))
	return out

static func _load_items(path: String) -> Dictionary:
	var out: Dictionary = {}
	for row in _read_table(path):
		var it := ItemData.new()
		it.item_id = StringName(row.get("item_id", ""))
		it.name = row.get("name", "")
		it.range_shape = StringName(row.get("range_shape", ""))
		it.range_min = _int(row, "range_min")
		it.range_max = _int(row, "range_max")
		it.target = StringName(row.get("target", ""))
		it.uses_per_battle = _int(row, "uses_per_battle")
		it.effects = row.get("effects", "")
		it.desc = row.get("desc", "")
		if out.has(it.item_id):
			push_error("DataLoader: 重复 item_id '%s'" % it.item_id)
		out[it.item_id] = it
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

static func _parse_string_list(raw: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for part in raw.split(";", false):
		var s := part.strip_edges()
		if not s.is_empty():
			out.append(StringName(s))
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
		if u.skill_signature != &"" and not skills.has(u.skill_signature):
			errors.append("武将 %s：skill_signature '%s' 不在技能表" % [id, u.skill_signature])
		if u.weapon.is_empty() or not weapons.has(u.weapon):
			errors.append("武将 %s：武器 '%s' 未登记范围模板（weapons.csv）" % [id, u.weapon])
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
		if not TRIGGERS.has(s.trigger):
			errors.append("技能 %s：非法 trigger '%s'" % [id, s.trigger])
		if not RANGE_SHAPES.has(s.range_shape):
			errors.append("技能 %s：非法 range_shape '%s'" % [id, s.range_shape])
		if not TARGETS.has(s.target):
			errors.append("技能 %s：非法 target '%s'" % [id, s.target])
		if s.cooldown < 0 or s.rage_cost < 0:
			errors.append("技能 %s：cooldown/rage_cost 不得为负" % id)
		if s.type == &"passive":
			# 被动规则（策划 4.3、「被动触发语义」）：trigger 必须非 manual；target 限 self/enemy；
			# turn_start 无涉事对方故 target 必须为 self；不耗资源
			if s.trigger == &"manual":
				errors.append("被动 %s：trigger 不得为 manual" % id)
			if s.target == &"ally":
				errors.append("被动 %s：target 限 self/enemy（自身/涉事对方）" % id)
			if s.trigger == &"turn_start" and s.target != &"self":
				errors.append("被动 %s：turn_start 无涉事对方，target 必须为 self" % id)
			if s.cooldown != 0 or s.rage_cost != 0:
				errors.append("被动 %s：cooldown/rage_cost 必须为 0" % id)
		EffectSystem.parse_effects(s.effects)   # 解析失败会在内部 push_error 并指出技能ID/效果名
	# 每名武将（units.csv，不含敌方）恰好 2 个被动（策划 4.3）
	for uid in hero_ids:
		var passive_count := 0
		for sid in skills:
			var ps: SkillData = skills[sid]
			if ps.type == &"passive" and ps.owner == String(uid):
				passive_count += 1
		if passive_count != 2:
			errors.append("武将 %s：被动数量 %d ≠ 2（策划 4.3 每人 2 被动）" % [uid, passive_count])
	for id in terrains:
		var t: TerrainData = terrains[id]
		if t.move_cost < 0:
			errors.append("地形 %s：move_cost 不得为负" % id)
		if t.move_cost == 99 and t.passable:
			errors.append("地形 %s：move_cost=99（不可通行）但 passable=1" % id)
	for w in weapons:
		if not RANGE_SHAPES.has(weapons[w]):
			errors.append("武器 %s：非法 range_shape '%s'（weapons.csv）" % [w, weapons[w]])
	# 道具表（items.csv，策划 6.5）：范围/目标词表同技能表；效果串必须全部落在已实现词表内
	if items.is_empty():
		errors.append("道具表缺失或无数据（items.csv）")
	for id in items:
		var it: ItemData = items[id]
		if not RANGE_SHAPES.has(it.range_shape):
			errors.append("道具 %s：非法 range_shape '%s'" % [id, it.range_shape])
		if not TARGETS.has(it.target):
			errors.append("道具 %s：非法 target '%s'" % [id, it.target])
		if it.uses_per_battle < 1:
			errors.append("道具 %s：uses_per_battle 必须 ≥1" % id)
		if it.range_min < 0 or it.range_max < it.range_min:
			errors.append("道具 %s：range_min/max 不合法（%d-%d）" % [id, it.range_min, it.range_max])
		var parsed := EffectSystem.parse_effects(it.effects)   # 解析失败会在内部 push_error
		if parsed.is_empty():
			errors.append("道具 %s：效果串为空或无法解析" % id)
		for eff in parsed:
			var eff_name := String(eff["name"])
			if not EffectSystem.KNOWN_EFFECTS.has(eff_name):
				errors.append("道具 %s：未知原子效果 '%s'（需先在 EffectSystem 实现）" % [id, eff_name])
			if ["refresh_on_kill", "extra_action"].has(eff_name):
				errors.append("道具 %s：%s 为技能指令专属后处理，道具不生效" % [id, eff_name])
	for key in PROGRESSION_KEYS:
		if not progression.has(key):
			errors.append("养成参数缺失：%s（progression.csv）" % key)
	if constants.is_empty():
		errors.append("战斗常数表缺失或无数据（battle_constants.csv）")
	for key in CONSTANT_KEYS:
		if not constants.has(key):
			errors.append("战斗常数缺失：%s（battle_constants.csv）" % key)
	return errors
