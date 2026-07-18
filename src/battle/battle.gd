extends Node2D
## 调试战斗场景（M1）：布阵阶段 → CTB 战斗循环，全部内容经 LevelConfig 驱动。
## 布阵：左键点候选（左侧竖条，稀有度配色）→ 点部署区空格上阵；点已上阵单位撤下；回车开战。
## 战斗：左键移动/普攻，Q 主动技 / W 绝技（line 技能点击指向，ESC/右键取消），空格待机，
## 　　　1/2/3 手动/半自动/全自动，F 集火。占位表现，正式 UI 在 M2 替换（决策日志 D12/D28）。

const CELL := 64
const ORIGIN := Vector2(320, 40)

const TERRAIN_COLORS := {
	&"plain": Color("8FBC4F"),
	&"forest": Color("4E7A3A"),
	&"hill": Color("8D7B68"),
	&"water": Color("3E7CB1"),
	&"barricade": Color("7A5230"),
	&"camp": Color("C9A86A"),
	&"fire": Color("D9642A"),
	&"road": Color("C9A86A"),
	&"wine_stall": Color("B85C8A"),
}
## 稀有度配色（美术指导第四节：赤金/绛紫/靛青/竹绿）
const QUALITY_COLORS := {
	&"orange": Color("C99B3F"),
	&"purple": Color("7E57C2"),
	&"blue": Color("3A7BD5"),
	&"green": Color("8FBC4F"),
}

var grid: Grid
var manager: BattleManager
var reachable: Dictionary = {}
var pending_skill: SkillData = null   # 已选择、等待指向的技能（line 类）
var selected_roster := -1             # 布阵：选中的候选序号（roster_ids 下标）
var roster_ids: Array[StringName] = []  # 候选池（按档案拥有情况过滤后）
var _result_shown := false
var cursor := Vector2i(0, 0)            # 手柄虚拟光标（Deck 适配，M2）

func _ready() -> void:
	position = ORIGIN
	var level: LevelConfig
	if not GameState.expedition.is_empty():
		# 梁山远征：按层生成关卡
		level = ExpeditionSystem.build_floor(GameState.expedition, DataLoader)
	else:
		level = GameState.custom_level
		GameState.custom_level = null
		if level == null:
			level = LevelRegistry.get_level(GameState.current_level_id)
	manager = BattleManager.new()
	add_child(manager)
	manager.setup_level(DataLoader, level)
	if level.pvp_template != "":
		ArenaSystem.apply_template(manager, level.pvp_template)
	if SaveSystem.profile != null:
		manager.apply_profile_to_deployed(SaveSystem.profile)
	grid = manager.grid
	roster_ids = level.roster.filter(func(id): return SaveSystem.profile == null or SaveSystem.profile.has_hero(id))
	manager.turn_started.connect(_on_turn_started)
	manager.command_executed.connect(_on_command_executed)
	manager.tick_events.connect(_on_tick_events)
	manager.unit_died.connect(func(_u): queue_redraw())
	manager.battle_ended.connect(_on_battle_ended)
	manager.deploy_changed.connect(func(): queue_redraw())
	manager.dialogue.connect(func(text): print("【剧情】%s" % text))
	manager.round_started.connect(func(n): print("—— 第 %d 回合 ——" % n))
	if not GameState.expedition.is_empty():
		_expedition_deploy()   # 远征：跳过手动布阵，自动上阵并继承状态
	queue_redraw()

## 远征布阵：存活队员自动落位（生命跨层继承 + 远征增益）
func _expedition_deploy() -> void:
	var cells := manager._free_deploy_cells()
	for t in GameState.expedition["team"]:
		if not t["alive"] or cells.is_empty():
			continue
		var id: StringName = t["unit_id"]
		manager.deploy_unit(id, cells.pop_front(), SaveSystem.profile.get_hero(id))
	ExpeditionSystem.apply_carryover(manager, GameState.expedition)
	manager.confirm_deploy()

# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if manager == null or manager.state == BattleManager.State.BATTLE_END:
		return
	if manager.state == BattleManager.State.DEPLOY:
		_handle_deploy_input(event)
		return
	_handle_battle_input(event)

# ---- 布阵 ----

func _handle_deploy_input(event: InputEvent) -> void:
	if _joy_cursor(event):
		return
	if event.is_action_pressed("battle_rb"):
		_cycle_roster(1)
		return
	if event.is_action_pressed("battle_lb"):
		_cycle_roster(-1)
		return
	if event.is_action_pressed("battle_confirm"):
		_deploy_at_cell(cursor)
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER \
			or event.is_action_pressed("battle_wait"):
		if manager.confirm_deploy():
			print("开战！")
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := get_local_mouse_position()
		# 点候选条
		var idx := _roster_index_at(pos)
		if idx != -1:
			selected_roster = idx if selected_roster != idx else -1
			queue_redraw()
			return
		# 点部署区
		_deploy_at_cell(_pos_to_cell(pos))

func _deploy_at_cell(cell_coords: Vector2i) -> void:
	if not manager.level.deploy_zone.has_point(cell_coords):
		return
	var cell := grid.get_cell(cell_coords)
	if cell.occupant != null and manager.deployed.has(cell.occupant):
		manager.undeploy_unit(cell.occupant)   # 点已上阵单位：撤下
		AudioManager.play("sfx_ui_click")
		return
	if selected_roster != -1:
		var id: StringName = roster_ids[selected_roster]
		var hero := SaveSystem.profile.get_hero(id) if SaveSystem.profile != null else null
		manager.deploy_unit(id, cell_coords, hero)
		AudioManager.play("sfx_ui_click")
		selected_roster = -1

func _cycle_roster(dir: int) -> void:
	if roster_ids.is_empty():
		return
	selected_roster = (selected_roster + dir + roster_ids.size()) % roster_ids.size()
	queue_redraw()

## 手柄虚拟光标移动；事件被消费时返回 true
func _joy_cursor(event: InputEvent) -> bool:
	var d := Vector2i.ZERO
	if event.is_action_pressed("battle_left"):
		d = Vector2i(-1, 0)
	elif event.is_action_pressed("battle_right"):
		d = Vector2i(1, 0)
	elif event.is_action_pressed("battle_up"):
		d = Vector2i(0, -1)
	elif event.is_action_pressed("battle_down"):
		d = Vector2i(0, 1)
	if d == Vector2i.ZERO:
		return false
	cursor = (cursor + d).clamp(Vector2i.ZERO, grid.size - Vector2i.ONE)
	queue_redraw()
	return true

func _roster_index_at(pos: Vector2) -> int:
	for i in roster_ids.size():
		var center := Vector2(-360.0, 24.0 + i * 44.0)
		if pos.distance_to(center) <= 18.0:
			return i
	return -1

func _pos_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))

# ---- 战斗 ----

func _handle_battle_input(event: InputEvent) -> void:
	if _joy_cursor(event):
		return
	if event.is_action_pressed("battle_confirm"):
		_handle_cell_click(cursor)
		return
	if event.is_action_pressed("battle_cancel"):
		pending_skill = null
		queue_redraw()
		return
	if event.is_action_pressed("battle_skill"):
		var u := manager.active_unit
		if u != null and u.team == Unit.Team.PLAYER and manager.state == BattleManager.State.IDLE and not manager.action_used:
			_try_skill(u, false)
		return
	if event.is_action_pressed("battle_ult"):
		var u := manager.active_unit
		if u != null and u.team == Unit.Team.PLAYER and manager.state == BattleManager.State.IDLE and not manager.action_used:
			_try_skill(u, true)
		return
	if event.is_action_pressed("battle_lb"):
		var u := manager.active_unit
		if u != null and u.team == Unit.Team.PLAYER and manager.state == BattleManager.State.IDLE and not manager.action_used:
			_try_interact(u)
		return
	if event.is_action_pressed("battle_rb"):
		var cell := grid.get_cell(cursor)
		if cell != null and cell.occupant != null and cell.occupant.team == Unit.Team.ENEMY:
			manager.set_focus_target(null if manager.focus_target == cell.occupant else cell.occupant)
		return
	if event.is_action_pressed("battle_wait"):
		var u := manager.active_unit
		if u != null and u.team == Unit.Team.PLAYER and manager.state == BattleManager.State.IDLE:
			manager.submit_command(WaitCommand.new(u))
			manager.finish_turn()
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		# E：夺取相邻物件（生辰纲担，1 回合引导，策划文档 7.3）
		var u := manager.active_unit
		if u != null and u.team == Unit.Team.PLAYER and manager.state == BattleManager.State.IDLE and not manager.action_used:
			_try_interact(u)
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_1, KEY_2, KEY_3]:
		# 1=手动 2=半自动 3=全自动（8.5）
		manager.auto_mode = [BattleManager.AutoMode.MANUAL, BattleManager.AutoMode.SEMI, BattleManager.AutoMode.FULL][event.keycode - KEY_1]
		print("托管模式：%s" % ["手动", "半自动", "全自动"][event.keycode - KEY_1])
		var u := manager.active_unit
		if manager.auto_mode != BattleManager.AutoMode.MANUAL and u != null and u.team == Unit.Team.PLAYER:
			manager.run_ai()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		var cell := grid.get_cell(cursor)
		if cell != null and cell.occupant != null and cell.occupant.team == Unit.Team.ENEMY:
			if manager.focus_target == cell.occupant:
				manager.set_focus_target(null)
				print("取消集火")
			else:
				manager.set_focus_target(cell.occupant)
				print("集火目标：%s" % cell.occupant.display_name())
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

## 对相邻物件执行夺取（引导期间受击打断）
func _try_interact(u: Unit) -> void:
	for obj in manager.units:
		if manager.can_channel(u, obj):
			manager.submit_command(InteractCommand.new(u, obj))
			manager.action_used = true
			print("%s 开始引导夺取……（下回合收讫，受击打断）" % u.display_name())
			_after_player_action()
			return
	print("没有相邻可夺取的物件")

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

# ---------------------------------------------------------------- 回合与信号

func _on_turn_started(unit: Unit) -> void:
	reachable.clear()
	pending_skill = null
	if unit.team == Unit.Team.PLAYER and manager.auto_mode == BattleManager.AutoMode.MANUAL:
		reachable = grid.get_reachable(unit, unit.get_move(grid))
	AudioManager.play("sfx_turn")
	queue_redraw()

## 指令回放音效（逻辑已瞬时结算，此处纯表现层，决策日志 D39）
func _on_command_executed(cmd: Command, events: Array) -> void:
	if cmd is SkillCommand:
		AudioManager.play_skill(cmd.skill)
	elif cmd is AttackCommand:
		AudioManager.play_skill(cmd.skill)
	for e in events:
		AudioManager.play_event(e)
	queue_redraw()

## 回合开始 tick 音效：DoT/再生/地形/跳过（D39）
func _on_tick_events(_unit: Unit, events: Array) -> void:
	for e in events:
		match String(e.get("type", "")):
			"dot":
				AudioManager.play("sfx_debuff")
			"hot", "terrain_heal":
				AudioManager.play("sfx_heal")
			"turn_skipped":
				AudioManager.play("sfx_debuff")
	# 敌方固定 AI；我方在自动/半自动托管下也由评分 AI 驱动（策划文档 8.5）
	var ai_driven := unit.team != Unit.Team.PLAYER or manager.auto_mode != BattleManager.AutoMode.MANUAL
	if ai_driven:
		await get_tree().create_timer(0.35).timeout
		if is_instance_valid(manager) and manager.active_unit == unit and manager.state != BattleManager.State.BATTLE_END:
			manager.run_ai()

func _on_battle_ended(winner: int) -> void:
	reachable.clear()
	if _result_shown:
		return
	_result_shown = true
	AudioManager.play("sfx_win" if winner == Unit.Team.PLAYER else "sfx_lose")
	if not GameState.expedition.is_empty():
		_expedition_end(winner)
		return
	var result := manager.compute_result(winner)
	if SaveSystem.profile != null:
		GameState.last_result = Flow.apply_battle_result(SaveSystem.profile, manager.level, result, manager.deployed, DataLoader)
		SaveSystem.save_game()
	else:
		GameState.last_result = result
	_show_result_panel(GameState.last_result)
	queue_redraw()

## 结算面板：胜负、奖励、经验/升级、成就、新武将，返回山寨
func _show_result_panel(summary: Dictionary) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(430, 150)
	panel.custom_minimum_size = Vector2(420, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "—— 胜 利 ——" if summary.get("won", false) else "—— 战 败 ——"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	if summary.get("won", false):
		var lines: Array[String] = []
		if String(summary.get("rank", "")) != "":
			lines.append("评价：%s" % String(summary["rank"]))
		var rewards: Dictionary = summary.get("rewards", {})
		if not rewards.is_empty():
			var parts: Array[String] = []
			for k in rewards:
				parts.append("%s ×%d" % [_reward_name(k), int(rewards[k])])
			lines.append(("【首通奖励】" if summary.get("first_clear", false) else "【通关奖励】") + "、".join(parts))
		if int(summary.get("exp_each", 0)) > 0:
			lines.append("上阵武将经验 +%d" % int(summary["exp_each"]))
		for id in summary.get("level_ups", {}):
			lines.append("  %s 升 %d 级！" % [DataLoader.get_unit(id).name, int(summary["level_ups"][id])])
		if not (summary.get("level_ups", {}) as Dictionary).is_empty():
			AudioManager.play("sfx_levelup")
		for ach in summary.get("achievements", []):
			lines.append("成就达成：%s" % _achievement_name(ach))
		for id in summary.get("unlocked", []):
			lines.append("新武将加入：%s！" % DataLoader.get_unit(id).name)
		if not (summary.get("unlocked", []) as Array).is_empty():
			AudioManager.play("sfx_unlock")
		if summary.get("chapter_now", 0) > manager.level.chapter:
			lines.append("—— 第 %d 章开启 ——" % int(summary["chapter_now"]))
		for line in summary.get("epilogue", []):
			lines.append(line)
		for text in lines:
			var l := Label.new()
			l.text = text
			vbox.add_child(l)
	else:
		var hint := Label.new()
		hint.text = "整顿兵马，再接再厉。"
		vbox.add_child(hint)
	var btn := Button.new()
	btn.text = "返回山寨"
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub/hub.tscn"))
	vbox.add_child(btn)
	layer.add_child(panel)

# ---------------------------------------------------------------- 梁山远征流程

func _expedition_end(winner: int) -> void:
	ExpeditionSystem.record_floor_result(manager, GameState.expedition)
	if winner == Unit.Team.PLAYER:
		GameState.expedition["floor"] = int(GameState.expedition["floor"]) + 1
		if int(GameState.expedition["floor"]) > ExpeditionSystem.MAX_FLOOR:
			_expedition_finish(true)
		else:
			_show_reward_choice()
	else:
		_expedition_finish(false)

## 层间三选一奖励
func _show_reward_choice() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(430, 200)
	panel.custom_minimum_size = Vector2(420, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "—— 第 %d 层告破！择一奖励 ——" % (int(GameState.expedition["floor"]) - 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	for r in ExpeditionSystem.FLOOR_REWARDS:
		var b := Button.new()
		b.text = String(r["name"])
		var rid := String(r["id"])
		b.pressed.connect(func():
			ExpeditionSystem.apply_reward_choice(GameState.expedition, rid)
			SaveSystem.save_game()
			get_tree().reload_current_scene())
		vbox.add_child(b)
	layer.add_child(panel)

func _expedition_finish(completed: bool) -> void:
	var summary := ExpeditionSystem.finish_run(SaveSystem.profile, GameState.expedition)
	GameState.expedition = {}
	SaveSystem.save_game()
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(430, 200)
	panel.custom_minimum_size = Vector2(420, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "—— 远征成功！通关 10 层 ——" if completed else "—— 远征结束 ——"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var info := Label.new()
	info.text = "推进 %d 层｜获得金币 ×%d、突破材料 ×%d" % [
		int(summary["floors_cleared"]), int(summary["gold"]), int(summary["breakthrough_mat"])]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	var btn := Button.new()
	btn.text = "返回山寨"
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub/hub.tscn"))
	vbox.add_child(btn)
	layer.add_child(panel)

func _reward_name(key: Variant) -> String:
	match String(key):
		"gold":
			return "金币"
		"shard":
			return "通用碎片"
		"skill_book":
			return "技能书"
		"breakthrough_mat":
			return "突破材料"
		"shard_bai_sheng":
			return "白胜碎片"
	return String(key)

func _achievement_name(id: Variant) -> String:
	for ach in manager.level.achievements:
		if ach.get("id") == id:
			return String(ach.get("name", id))
	return String(id)

func _mouse_cell() -> Vector2i:
	return _pos_to_cell(get_local_mouse_position())

# ---------------------------------------------------------------- 占位表现

func _draw() -> void:
	if grid == null:
		return
	_draw_terrain()
	if manager.state == BattleManager.State.DEPLOY:
		_draw_deploy()
	else:
		_draw_highlights()
	_draw_units()
	_draw_preview_bar()
	# 手柄虚拟光标
	if grid.is_inside(cursor):
		draw_rect(Rect2(Vector2(cursor) * CELL, Vector2(CELL, CELL)), Color(1, 1, 1, 0.85), false, 2.0)

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

## 布阵阶段：部署区高亮、敌方危险范围热力图（6.8）、左侧候选条
func _draw_deploy() -> void:
	var zone := manager.level.deploy_zone
	# 危险范围热力图：敌方移动力+射程曼哈顿覆盖（近似，不含地形/阻挡，D28 注）
	for e in manager.units:
		if e.team != Unit.Team.ENEMY or not e.is_alive():
			continue
		var reach: int = e.data.move + e.data.range_max
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if absi(dx) + absi(dy) > reach:
					continue
				var c: Vector2i = e.coords + Vector2i(dx, dy)
				if grid.is_inside(c):
					draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)), Color(0.62, 0.17, 0.15, 0.13))
	# 部署区
	for y in range(zone.position.y, zone.end.y):
		for x in range(zone.position.x, zone.end.x):
			var rect := Rect2(Vector2(Vector2i(x, y)) * CELL, Vector2(CELL, CELL))
			draw_rect(rect, Color(0.3, 0.55, 1.0, 0.18))
			draw_rect(rect, Color(0.3, 0.55, 1.0, 0.5), false, 1.0)
	# 候选条（稀有度配色 + 姓名；选中的加白圈）
	var font := ThemeDB.fallback_font
	for i in roster_ids.size():
		var id: StringName = roster_ids[i]
		var center := Vector2(-360.0, 24.0 + i * 44.0)
		var ud := DataLoader.get_unit(id)
		draw_circle(center, 16.0, QUALITY_COLORS.get(ud.quality, Color.GRAY))
		draw_arc(center, 16.0, 0, TAU, 20, Color("263238"), 1.5)
		var label := ud.name
		if SaveSystem.profile != null and SaveSystem.profile.has_hero(id):
			var h := SaveSystem.profile.get_hero(id)
			label = "%s Lv.%d" % [ud.name, h.level]
		draw_string(font, center + Vector2(24, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("263238"))
		if i == selected_roster:
			draw_arc(center, 20.0, 0, TAU, 20, Color.WHITE, 2.5)

func _draw_highlights() -> void:
	for c: Vector2i in reachable:
		draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)), Color(0.3, 0.55, 1.0, 0.30))
	var u := manager.active_unit
	if u != null and u.team == Unit.Team.PLAYER and manager.state == BattleManager.State.IDLE:
		if pending_skill != null:
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
		if u.team == Unit.Team.NPC_ALLY:
			body = Color("4E7A3A")
		if u.is_object:
			draw_rect(Rect2(center - Vector2(10, 10), Vector2(20, 20)), Color("C9A86A"))
			draw_rect(Rect2(center - Vector2(10, 10), Vector2(20, 20)), Color("263238"), false, 2.0)
			continue
		draw_circle(center, CELL * 0.32, body)
		draw_arc(center, CELL * 0.32, 0, TAU, 24, Color("263238"), 2.0)
		if u.is_elite:
			draw_arc(center, CELL * 0.36, 0, TAU, 24, Color("C99B3F"), 2.5)   # 精英金圈
		if u == manager.active_unit:
			draw_arc(center, CELL * 0.40, 0, TAU, 24, Color.WHITE, 3.0)
		if u == manager.focus_target:
			draw_arc(center, CELL * 0.46, 0, TAU, 24, Color("C99B3F"), 3.0)   # 集火标记（赤金）
		if u.channeling != null:
			draw_circle(center + Vector2(0, CELL * 0.42), 5.0, Color("F5F1E8"))   # 引导中标记
		draw_line(center, center + Vector2(u.facing) * CELL * 0.30, Color("F5F1E8"), 3.0)
		var bar := Rect2(center + Vector2(-CELL * 0.32, -CELL * 0.46), Vector2(CELL * 0.64, 5))
		draw_rect(bar, Color("263238"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(u.hp) / float(u.data.hp), 5)), Color("8FBC4F"))
		var rage_bar := Rect2(bar.position + Vector2(0, 6), Vector2(bar.size.x * float(u.rage) / float(Unit.MAX_RAGE), 3))
		draw_rect(rage_bar, Color("C99B3F"))
		var bi := 0
		for b in u.buffs:
			if bi >= 3:
				break
			var dot_color := Color("9E2B25") if b.is_debuff else Color("C99B3F")
			draw_circle(center + Vector2(-CELL * 0.32 + bi * 9, -CELL * 0.54), 3.0, dot_color)
			bi += 1

## 行动预览条：棋盘右侧显示接下来 6 个行动单位（策划文档 6.4）
func _draw_preview_bar() -> void:
	if manager == null or manager.state == BattleManager.State.DEPLOY:
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
