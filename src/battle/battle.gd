extends Node2D
## 调试战斗场景（W1-2）：8×8 调试关卡，纯占位表现，验证棋盘/寻路/移动/普攻闭环。
## 操作：左键点可达格移动，左键点攻击范围内的敌人普攻，空格结束行动。
## 正式 UI、布阵阶段、关卡加载在后续阶段替换本场景的临时表现（决策日志 D10/D12）。

const CELL := 64
const ORIGIN := Vector2(384, 60)

const TERRAIN_COLORS := {
	&"plain": Color("8FBC4F"),
	&"forest": Color("4E7A3A"),
	&"hill": Color("8D7B68"),
	&"water": Color("3E7CB1"),
	&"barricade": Color("7A5230"),
	&"camp": Color("C9A86A"),
	&"fire": Color("D9642A"),
	&"road": Color("C9A86A"),
}

var grid: Grid
var manager: BattleManager
var reachable: Dictionary = {}
var pending_skill: SkillData = null   # 已选择、等待指向的技能（line 类）

func _ready() -> void:
	position = ORIGIN
	_build_battle()
	manager.turn_started.connect(_on_turn_started)
	manager.command_executed.connect(func(_cmd, _events): queue_redraw())
	manager.unit_died.connect(func(_u): queue_redraw())
	manager.battle_ended.connect(_on_battle_ended)
	manager.start_battle()

func _build_battle() -> void:
	var data: GameDataLoader = DataLoader   # autoload 单例
	grid = Grid.new()
	var terrain_map := {
		Vector2i(2, 2): &"forest", Vector2i(3, 2): &"forest", Vector2i(2, 3): &"forest",
		Vector2i(5, 5): &"forest", Vector2i(6, 2): &"hill", Vector2i(6, 3): &"hill",
		Vector2i(4, 4): &"barricade", Vector2i(3, 4): &"camp", Vector2i(1, 5): &"water",
		Vector2i(4, 0): &"road", Vector2i(4, 1): &"road",
	}
	var height_map := {Vector2i(6, 2): 1, Vector2i(6, 3): 1}
	grid.setup(data, Vector2i(8, 8), terrain_map, height_map)
	add_child(grid)

	var units_node := Node2D.new()
	units_node.name = "Units"
	add_child(units_node)

	var units: Array[Unit] = []
	# 我方：原型三将（W1-2 验证对象）；敌方：绿将客串（决策日志 D10）
	units.append(_spawn(data, &"lin_chong", Unit.Team.PLAYER, Vector2i(2, 6), units_node))
	units.append(_spawn(data, &"lu_zhishen", Unit.Team.PLAYER, Vector2i(3, 6), units_node))
	units.append(_spawn(data, &"an_daoquan", Unit.Team.PLAYER, Vector2i(1, 7), units_node))
	units.append(_spawn(data, &"shi_yong", Unit.Team.ENEMY, Vector2i(5, 1), units_node))
	units.append(_spawn(data, &"song_wan", Unit.Team.ENEMY, Vector2i(4, 1), units_node))
	units.append(_spawn(data, &"du_qian", Unit.Team.ENEMY, Vector2i(6, 1), units_node))

	manager = BattleManager.new()
	add_child(manager)
	manager.setup(data, grid, units)

func _spawn(data: GameDataLoader, id: StringName, team: Unit.Team, coords: Vector2i, parent: Node) -> Unit:
	var u := Unit.new()
	u.setup(data.get_unit(id), team, coords)
	if team == Unit.Team.PLAYER:
		u.facing = Vector2i(0, -1)
	parent.add_child(u)
	grid.place_unit(u, coords)
	return u

# ---------------------------------------------------------------- 回合与输入

func _on_turn_started(unit: Unit) -> void:
	reachable.clear()
	if unit.team == Unit.Team.PLAYER:
		reachable = grid.get_reachable(unit, unit.get_move(grid))
	queue_redraw()
	if unit.team != Unit.Team.PLAYER:
		await get_tree().create_timer(0.35).timeout
		if is_instance_valid(manager) and manager.active_unit == unit and manager.state != BattleManager.State.BATTLE_END:
			manager.run_placeholder_ai()

func _unhandled_input(event: InputEvent) -> void:
	if manager == null or manager.state == BattleManager.State.BATTLE_END:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		var u := manager.active_unit
		if u != null and u.team == Unit.Team.PLAYER and manager.state == BattleManager.State.IDLE:
			manager.submit_command(WaitCommand.new(u))   # 待机：防御+20%、怒气+15（表格9）
			manager.finish_turn()
		return
	if event is InputEventKey and event.pressed and (event.keycode == KEY_Q or event.keycode == KEY_W):
		var u := manager.active_unit
		if u != null and u.team == Unit.Team.PLAYER and manager.state == BattleManager.State.IDLE and not manager.action_used:
			_try_skill(u, KEY_W == event.keycode)
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		pending_skill = null
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		pending_skill = null
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_cell_click(_mouse_cell())

## Q = 主动技，W = 绝技（怒气 100）。需要指向的技能（line）进入待指向状态，其余直接施放。
func _try_skill(u: Unit, is_ult: bool) -> void:
	var skill := DataLoader.get_skill_for_unit(u.data.unit_id, &"ult" if is_ult else &"active")
	if skill == null:
		print("%s 没有%s" % [u.display_name(), "绝技" if is_ult else "主动技"])
		return
	if not manager.can_use_skill(u, skill):
		print("%s 的 %s 暂不可用（怒气 %d/%d，冷却 %d）" % [
			u.display_name(), skill.name, u.rage, skill.rage_cost, u.skill_cooldown(skill.skill_id)])
		return
	if Targeting.needs_aim(skill):
		pending_skill = skill
		queue_redraw()
		return
	manager.submit_command(SkillCommand.new(u, skill))
	manager.action_used = true
	_after_player_action()

func _handle_cell_click(cell_coords: Vector2i) -> void:
	var u := manager.active_unit
	if u == null or u.team != Unit.Team.PLAYER or manager.state != BattleManager.State.IDLE:
		return
	if not grid.is_inside(cell_coords):
		return
	var cell := grid.get_cell(cell_coords)
	# 待指向技能：点击敌人所在格作为 aim 方向
	if pending_skill != null:
		if cell.occupant != null and cell.occupant.team != u.team:
			var skill := pending_skill
			pending_skill = null
			manager.submit_command(SkillCommand.new(u, skill, cell_coords))
			manager.action_used = true
			_after_player_action()
		return
	# 攻击：点击范围内的敌人
	if cell.occupant != null and cell.occupant.team == Unit.Team.ENEMY:
		if not manager.action_used and manager.in_attack_range(u, cell.occupant):
			manager.submit_command(AttackCommand.new(u, cell.occupant, manager.basic_attack_skill(u)))
			manager.action_used = true
			_after_player_action()
		return
	# 移动：点击可达格（移动可拆成两段，策划文档 6.5）
	if not manager.move_used and reachable.has(cell_coords):
		var path := grid.find_path(u, cell_coords)
		if path.is_empty():
			return
		path.remove_at(0)
		manager.submit_command(MoveCommand.new(u, path))
		manager.move_used = true
		var remaining: int = u.get_move(grid) - int(reachable[cell_coords])
		reachable = grid.get_reachable(u, remaining) if remaining > 0 else {}
		_after_player_action()

func _after_player_action() -> void:
	if manager.move_used and manager.action_used:
		manager.finish_turn()
	else:
		queue_redraw()

func _on_battle_ended(winner: int) -> void:
	reachable.clear()
	print("战斗结束，胜方：%s" % ("我方" if winner == Unit.Team.PLAYER else "敌方"))
	queue_redraw()

func _mouse_cell() -> Vector2i:
	var local := get_local_mouse_position()
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))

# ---------------------------------------------------------------- 占位表现

func _draw() -> void:
	if grid == null:
		return
	_draw_terrain()
	_draw_highlights()
	_draw_units()
	_draw_preview_bar()

func _draw_terrain() -> void:
	for coords: Vector2i in grid.cells:
		var cell := grid.cells[coords] as GridCell
		var rect := Rect2(Vector2(coords) * CELL, Vector2(CELL, CELL))
		draw_rect(rect, TERRAIN_COLORS.get(cell.terrain.terrain_id, Color.MAGENTA))
		if cell.height > 0:
			draw_rect(rect, Color(1, 1, 1, 0.12), false, 4.0)   # 高台白框提示
		if cell.has_obstacle():
			draw_line(rect.position, rect.position + rect.size, Color(0.2, 0.1, 0.05), 3.0)
			draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(0, rect.size.y), Color(0.2, 0.1, 0.05), 3.0)
		draw_rect(rect, Color(0.15, 0.22, 0.25, 0.6), false, 1.0)   # 格子边界（墨色）

func _draw_highlights() -> void:
	for c: Vector2i in reachable:
		draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)), Color(0.3, 0.55, 1.0, 0.30))
	var u := manager.active_unit
	if u != null and u.team == Unit.Team.PLAYER and manager.state == BattleManager.State.IDLE:
		if pending_skill != null:
			# 待指向技能：亮出技能覆盖格，朱砂圈出可指向的敌人
			for c in Targeting.cells_in_range(pending_skill, u, grid):
				draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)), Color(0.62, 0.17, 0.15, 0.25))
			for e in manager.units:
				if e.is_alive() and e.team != u.team and Targeting.cells_in_range(pending_skill, u, grid).has(e.coords):
					draw_arc(Vector2(e.coords) * CELL + Vector2(CELL, CELL) / 2, CELL * 0.42, 0, TAU, 24, Color("C99B3F"), 3.0)
		elif not manager.action_used:
			for e in manager.enemies_in_range(u):
				draw_arc(Vector2(e.coords) * CELL + Vector2(CELL, CELL) / 2, CELL * 0.42, 0, TAU, 24, Color("9E2B25"), 3.0)

func _draw_units() -> void:
	for u in manager.units:
		if not u.is_alive():
			continue
		var center := Vector2(u.coords) * CELL + Vector2(CELL, CELL) / 2
		var body := Color("3A7BD5") if u.team == Unit.Team.PLAYER else Color("9E2B25")
		draw_circle(center, CELL * 0.32, body)
		draw_arc(center, CELL * 0.32, 0, TAU, 24, Color("263238"), 2.0)
		if u == manager.active_unit:
			draw_arc(center, CELL * 0.40, 0, TAU, 24, Color.WHITE, 3.0)
		# 朝向指示
		draw_line(center, center + Vector2(u.facing) * CELL * 0.30, Color("F5F1E8"), 3.0)
		# HP 条（宣纸底 + 甲青/朱砂）与怒气细条
		var bar := Rect2(center + Vector2(-CELL * 0.32, -CELL * 0.46), Vector2(CELL * 0.64, 5))
		draw_rect(bar, Color("263238"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(u.hp) / float(u.data.hp), 5)), Color("8FBC4F"))
		var rage_bar := Rect2(bar.position + Vector2(0, 6), Vector2(bar.size.x * float(u.rage) / float(Unit.MAX_RAGE), 3))
		draw_rect(rage_bar, Color("C99B3F"))
		# Buff 指示点：绿=增益，朱砂=减益（最多 3 个，占位表现）
		var bi := 0
		for b in u.buffs:
			if bi >= 3:
				break
			var dot_color := Color("9E2B25") if b.is_debuff else Color("C99B3F")
			draw_circle(center + Vector2(-CELL * 0.32 + bi * 9, -CELL * 0.54), 3.0, dot_color)
			bi += 1

## 行动预览条：棋盘右侧显示接下来 6 个行动单位（策划文档 6.4）
func _draw_preview_bar() -> void:
	if manager == null:
		return
	var seq := manager.turn_order.preview(manager.units, 6)
	var x := float(grid.size.x * CELL) + 18.0
	for i in seq.size():
		var u := seq[i]
		var center := Vector2(x + 14.0, 22.0 + i * 36.0)
		var body := Color("3A7BD5") if u.team == Unit.Team.PLAYER else Color("9E2B25")
		draw_circle(center, 12.0, body)
		draw_arc(center, 12.0, 0, TAU, 20, Color("263238"), 1.5)
		if i == 0:
			draw_arc(center, 16.0, 0, TAU, 20, Color.WHITE, 2.5)
