class_name Grid
extends Node
## 格子逻辑层：格子数据 + 寻路（AStarGrid2D，地形移动消耗写入权重，策划文档 6.2）。
## 移动规则（决策日志 D4）：4 方向；友军可穿过、不可停留；敌军不可穿过；障碍不可通行。

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var data: GameDataLoader
var size: Vector2i = Vector2i.ZERO
var cells: Dictionary = {}   # Vector2i -> GridCell

## terrain_map: Vector2i -> StringName(terrain_id)，缺省 plain；height_map: Vector2i -> int，缺省 0。
func setup(p_data: GameDataLoader, p_size: Vector2i, terrain_map: Dictionary = {}, height_map: Dictionary = {}) -> void:
	data = p_data
	size = p_size
	cells.clear()
	for y in size.y:
		for x in size.x:
			var coords := Vector2i(x, y)
			var cell := GridCell.new()
			cell.coords = coords
			var tid: StringName = terrain_map.get(coords, &"plain")
			cell.terrain = data.get_terrain(tid)
			if cell.terrain == null:
				push_error("Grid: 未知地形 '%s' @ %s，按平原处理" % [tid, coords])
				cell.terrain = data.get_terrain(&"plain")
			cell.height = int(height_map.get(coords, 0))
			if cell.terrain.destructible and cell.terrain.hp > 0:
				cell.obstacle_hp = cell.terrain.hp
			cells[coords] = cell

func is_inside(coords: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, size).has_point(coords)

func get_cell(coords: Vector2i) -> GridCell:
	return cells.get(coords) as GridCell

## 可进入（不要求可停留）：地形可通行、无障碍、无敌军占位。
func can_pass(coords: Vector2i, mover: Unit) -> bool:
	if not is_inside(coords):
		return false
	var cell: GridCell = cells[coords]
	if cell.is_blocked():
		return false
	if cell.occupant != null and cell.occupant != mover and cell.occupant.team != mover.team:
		return false
	return true

## 可停留：可进入且无人占位。
func can_stop(coords: Vector2i, mover: Unit) -> bool:
	if not can_pass(coords, mover):
		return false
	var cell: GridCell = cells[coords]
	return cell.occupant == null or cell.occupant == mover

## 移动范围：按地形消耗的 Dijkstra 洪水填充。返回 {Vector2i: 到达消耗}，不含起点，仅可停留格。
func get_reachable(mover: Unit, budget: int) -> Dictionary:
	var cost: Dictionary = {mover.coords: 0}
	var frontier: Array[Vector2i] = [mover.coords]
	while not frontier.is_empty():
		var current := _pop_lowest_cost(frontier, cost)
		for d in DIRS:
			var next: Vector2i = current + d
			if not can_pass(next, mover):
				continue
			var new_cost: int = cost[current] + move_cost_of(cells[next], mover)
			if new_cost > budget:
				continue
			if cost.has(next) and cost[next] <= new_cost:
				continue
			cost[next] = new_cost
			frontier.append(next)
	cost.erase(mover.coords)
	var out: Dictionary = {}
	for c in cost:
		var cell: GridCell = cells[c]
		if cell.occupant == null or cell.occupant == mover:
			out[c] = cost[c]
	return out

## 点对点寻路（与 get_reachable 同规则）。返回含起点的路径；不可达返回空数组。
func find_path(mover: Unit, to: Vector2i) -> Array[Vector2i]:
	if not is_inside(to) or not can_pass(to, mover):
		return []
	var astar := _build_astar(mover)
	return astar.get_id_path(mover.coords, to)

func _build_astar(mover: Unit) -> AStarGrid2D:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for coords: Vector2i in cells:
		var cell: GridCell = cells[coords]
		var solid := cell.is_blocked()
		if cell.occupant != null and cell.occupant != mover and cell.occupant.team != mover.team:
			solid = true   # 敌军不可穿过
		astar.set_point_solid(coords, solid)
		if not solid:
			astar.set_point_weight_scale(coords, float(maxi(1, move_cost_of(cell, mover))))
	return astar

## 格子进入消耗：水军系（traits=water_walker）视水面为坦途（策划文档 6.3 水面留坑，决策日志 D36）
func move_cost_of(cell: GridCell, mover: Unit) -> int:
	if cell.terrain.terrain_id == &"water" and mover != null and mover.data.traits.has(&"water_walker"):
		return 1
	return cell.terrain.move_cost

func place_unit(unit: Unit, at: Vector2i) -> void:
	unit.coords = at
	cells[at].occupant = unit

## 运行时改变格子地形（触发器「地形变化」，策划文档 6.9）
func set_terrain(coords: Vector2i, tid: StringName) -> void:
	var cell := get_cell(coords)
	if cell == null:
		return
	cell.terrain = data.get_terrain(tid)
	if cell.terrain == null:
		push_error("Grid.set_terrain: 未知地形 '%s'" % tid)
		cell.terrain = data.get_terrain(&"plain")
	cell.obstacle_hp = cell.terrain.hp if (cell.terrain.destructible and cell.terrain.hp > 0) else 0

func move_unit(unit: Unit, to: Vector2i) -> void:
	var from_cell := get_cell(unit.coords)
	if from_cell != null and from_cell.occupant == unit:
		from_cell.occupant = null
	unit.coords = to
	cells[to].occupant = unit

func _pop_lowest_cost(frontier: Array[Vector2i], cost: Dictionary) -> Vector2i:
	var best_i := 0
	for i in range(1, frontier.size()):
		if cost[frontier[i]] < cost[frontier[best_i]]:
			best_i = i
	return frontier.pop_at(best_i)
