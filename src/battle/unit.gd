class_name Unit
extends Node
## 战斗单位逻辑：UnitData + 运行时状态。表现层另设（逻辑/表现分离，策划文档第十一章）。

signal died(unit: Unit)

enum Team { PLAYER, ENEMY, NPC_ALLY }

const MAX_RAGE := 100

var data: UnitData
var team: Team = Team.PLAYER
var coords: Vector2i
var facing: Vector2i = Vector2i(0, 1)   # 朝向，用于背刺/侧击判定（决策日志 D5）
var hp: int = 1
var rage: int = 0
var av: float = 0.0   # CTB 行动值（策划文档 6.4），由 TurnOrder 管理

func setup(p_data: UnitData, p_team: Team, p_coords: Vector2i) -> void:
	data = p_data
	team = p_team
	coords = p_coords
	hp = data.hp
	reset_av()

func reset_av() -> void:
	av = 1000.0 / float(maxi(1, data.spd))

func is_alive() -> bool:
	return hp > 0

func display_name() -> String:
	return data.name

# ---------------------------------------------------------------- 战斗数值（含地形修正）

func get_atk(grid: Grid) -> int:
	return _with_terrain_mod(grid, data.atk, &"atk_mod")

func get_def(grid: Grid) -> int:
	return _with_terrain_mod(grid, data.def, &"def_mod")

## 闪避为概率点，地形修正直接相加（森林 +15）
func get_dodge(grid: Grid) -> int:
	var cell := grid.get_cell(coords)
	return data.dodge + (cell.terrain.dodge_mod if cell != null else 0)

func get_block() -> int:
	return data.block

func _with_terrain_mod(grid: Grid, base: int, mod_field: StringName) -> int:
	var cell := grid.get_cell(coords)
	var mod := 0
	if cell != null:
		mod = int(cell.terrain.get(mod_field))
	return maxi(0, roundi(float(base) * float(100 + mod) / 100.0))

# ---------------------------------------------------------------- 生命与怒气

func take_damage(amount: int) -> int:
	var applied := mini(maxi(amount, 0), hp)
	hp -= applied
	if hp == 0:
		died.emit(self)
	return applied

func heal(amount: int) -> int:
	var applied := mini(maxi(amount, 0), data.hp - hp)
	hp += applied
	return applied

func gain_rage(value: int) -> void:
	rage = clampi(rage + value, 0, MAX_RAGE)
