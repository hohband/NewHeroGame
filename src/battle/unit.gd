class_name Unit
extends Node
## 战斗单位逻辑：UnitData + 运行时状态。表现层另设（逻辑/表现分离，策划文档第十一章）。

signal died(unit: Unit)
signal buffs_changed(unit: Unit)

enum Team { PLAYER, ENEMY, NPC_ALLY }

const MAX_RAGE := 100

var data: UnitData
var team: Team = Team.PLAYER
var coords: Vector2i
var facing: Vector2i = Vector2i(0, 1)   # 朝向，用于背刺/侧击判定（决策日志 D5）
var hp: int = 1
var rage: int = 0
var av: float = 0.0                     # CTB 行动值（策划文档 6.4），由 TurnOrder 管理
var buffs: Array[Buff] = []             # Buff/Debuff 统一管理（策划文档 6.7）
var cooldowns: Dictionary = {}          # skill_id -> 剩余冷却回合（持有者回合开始 -1）
var extra_action_pending := false       # 击杀刷新等待再动（决策日志 D22）
var is_elite := false                   # 精英/BOSS 标记（关卡配置投放，bonus_vs_elite 用）
var is_object := false                  # 场景物件/召唤物（旗帜等）：不行动、不计入胜负（决策日志 D27）
var hero: Hero = null                   # 养成档案（来自玩家阵容；技能等级等养成数值经此生效）

func setup(p_data: UnitData, p_team: Team, p_coords: Vector2i) -> void:
	data = p_data
	team = p_team
	coords = p_coords
	hp = data.hp
	reset_av()

func reset_av() -> void:
	av = 1000.0 / float(get_spd())

func is_alive() -> bool:
	return hp > 0

func display_name() -> String:
	return data.name

# ---------------------------------------------------------------- 战斗数值
# 攻击/防御/谋略/速度：基础 × (100 + 地形% + Buff%) / 100；闪避/格挡/暴击为概率点直接相加。

func get_atk(grid: Grid) -> int:
	return _with_mods(grid, data.atk, &"atk_mod", &"atk")

func get_def(grid: Grid) -> int:
	return _with_mods(grid, data.def, &"def_mod", &"def")

func get_mgc() -> int:
	return _apply_percent(data.mgc, get_stat_mod(&"mgc"))

func get_spd() -> int:
	return maxi(1, _apply_percent(data.spd, get_stat_mod(&"spd")))

func get_dodge(grid: Grid) -> int:
	var cell := grid.get_cell(coords)
	return data.dodge + get_stat_mod(&"dodge") + (cell.terrain.dodge_mod if cell != null else 0)

func get_block() -> int:
	return data.block + get_stat_mod(&"block")

func get_crit() -> int:
	return data.crit + get_stat_mod(&"crit")

## 移动力：基础 + Buff 修正（格）+ 地形规则（水面 -1，水军系免疫为后续扩展，决策日志 D18）
func get_move(grid: Grid) -> int:
	var mod := get_stat_mod(&"move")
	var cell := grid.get_cell(coords)
	if cell != null and cell.terrain.terrain_id == &"water":
		mod -= 1
	return maxi(0, data.move + mod)

func _with_mods(grid: Grid, base: int, terrain_field: StringName, buff_field: StringName) -> int:
	var mod := get_stat_mod(buff_field)
	var cell := grid.get_cell(coords)
	if cell != null and terrain_field != &"":
		mod += int(cell.terrain.get(terrain_field))
	# 光环：半径内友军光环携带者提供修正（替天行道旗，决策日志 D27）
	for c in grid.cells.values():
		var other: Unit = (c as GridCell).occupant
		if other == null or other == self or other.team != team or not other.is_alive():
			continue
		for b in other.buffs:
			if b.aura_radius > 0 and b.aura_mods.has(buff_field):
				if _manhattan(other.coords, coords) <= b.aura_radius:
					mod += int(b.aura_mods[buff_field])
	return _apply_percent(base, mod)

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

static func _apply_percent(base: int, mod: int) -> int:
	return maxi(0, roundi(float(base) * float(100 + mod) / 100.0))

# ---------------------------------------------------------------- Buff 管理（决策日志 D15）

## 同 buff_id 重复施加：刷新持续时间，不叠层。
func add_buff(buff: Buff) -> void:
	for b in buffs:
		if b.buff_id == buff.buff_id:
			b.duration = maxi(b.duration, buff.duration)
			buffs_changed.emit(self)
			return
	buffs.append(buff)
	buffs_changed.emit(self)

func get_stat_mod(field: StringName) -> int:
	var total := 0
	for b in buffs:
		total += int(b.stat_mods.get(field, 0))
	return total

func has_status(status: StringName) -> bool:
	for b in buffs:
		if b.status == status:
			return true
	return false

## 控制状态行为（决策日志 D22）：stun/paralyze/sleep = 跳过行动；bind = 不可移动、可行动
func can_act() -> bool:
	return not (has_status(&"stun") or has_status(&"sleep") or has_status(&"paralyze"))

func can_move() -> bool:
	return can_act() and not has_status(&"bind")

func skill_cooldown(skill_id: StringName) -> int:
	return int(cooldowns.get(skill_id, 0))

func set_cooldown(skill: SkillData) -> void:
	if skill.cooldown > 0:
		cooldowns[skill.skill_id] = skill.cooldown

## 阶段一：持续效果结算（DoT），回合开始立即执行。
func tick_effects() -> Array:
	var events: Array = []
	for b in buffs.duplicate():
		if not b.tick_effect.is_empty():
			var amount := roundi(float(data.hp) * float(b.tick_effect.get("percent", 0)) / 100.0)
			if b.tick_effect.get("kind") == "dot" and amount > 0:
				var applied := take_damage(amount)
				events.append({"type": "dot", "unit": self, "buff": b.buff_id, "amount": applied})
	return events

## 阶段二：回合数与技能冷却递减、过期移除。
## 必须在行动能力（can_act）判定【之后】执行，否则眩晕 1 回合会在判定前先过期（决策日志 D22 注）。
func tick_durations() -> Array:
	var events: Array = []
	for skill_id in cooldowns.keys():
		cooldowns[skill_id] = int(cooldowns[skill_id]) - 1
		if int(cooldowns[skill_id]) <= 0:
			cooldowns.erase(skill_id)
	var expired: Array[Buff] = []
	for b in buffs.duplicate():
		b.duration -= 1
		if b.is_expired():
			expired.append(b)
	for b in expired:
		buffs.erase(b)
		events.append({"type": "buff_expired", "unit": self, "buff": b.buff_id})
	if not expired.is_empty():
		buffs_changed.emit(self)
	return events

## 便捷入口：两阶段一起（测试与工具用；战斗流程由 BattleManager 分阶段调用）。
func tick_turn_start() -> Array:
	var events := tick_effects()
	events.append_array(tick_durations())
	return events

## 驱散最多 count 个可驱散的减益，返回被驱散的 buff_id 列表
func dispel_debuffs(count: int) -> Array:
	var removed: Array[Buff] = []
	for b in buffs:
		if removed.size() >= count:
			break
		if b.is_debuff and b.dispellable:
			removed.append(b)
	for b in removed:
		buffs.erase(b)
	if not removed.is_empty():
		buffs_changed.emit(self)
	var ids: Array = []
	for b in removed:
		ids.append(b.buff_id)
	return ids

# ---------------------------------------------------------------- 生命与怒气

func take_damage(amount: int) -> int:
	var applied := mini(maxi(amount, 0), hp)
	hp -= applied
	if applied > 0 and has_status(&"sleep"):
		# 睡眠受击解除（决策日志 D22）
		for b in buffs.duplicate():
			if b.status == &"sleep":
				buffs.erase(b)
		buffs_changed.emit(self)
	if hp == 0:
		died.emit(self)
	return applied

func heal(amount: int) -> int:
	var applied := mini(maxi(amount, 0), data.hp - hp)
	hp += applied
	return applied

func gain_rage(value: int) -> void:
	rage = clampi(rage + value, 0, MAX_RAGE)
