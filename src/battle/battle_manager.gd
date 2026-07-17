class_name BattleManager
extends Node
## 战斗总控：状态机（enum）+ 指令管道 + 信号广播（策划文档 6.1 / 第十一章）。
## 逻辑瞬时结算；表现层订阅 command_executed 后按事件队列回放，不影响逻辑结果。

signal state_changed(new_state: int)
signal turn_started(unit: Unit)
signal turn_ended(unit: Unit)
signal command_executed(command: Command, events: Array)
signal tick_events(unit: Unit, events: Array)
signal unit_died(unit: Unit)
signal battle_ended(winner_team: int)
signal round_started(round_count: int)
signal dialogue(text: String)
signal deploy_changed

enum State { DEPLOY, IDLE, MOVE_PREVIEW, TARGETING, EXECUTING, AI_TURN, BATTLE_END }
## 自动托管模式（策划文档 8.5）：手动 / 半自动（绝技按表16条件释放）/ 全自动
enum AutoMode { MANUAL, SEMI, FULL }

var data: GameDataLoader
var grid: Grid
var units: Array[Unit] = []
var rolls: RollSource = RandomRollSource.new()
var turn_order := TurnOrder.new()
var state: State = State.DEPLOY
var active_unit: Unit = null
var move_used := false
var action_used := false
var auto_mode: AutoMode = AutoMode.MANUAL
var focus_target: Unit = null   # 集火目标：AI 评分 +100（8.5）

# ---- 关卡系统（LevelConfig，策划文档 6.8/6.9）----
var level: LevelConfig = null
var boss_unit: Unit = null
var round_count := 0
var collect_counts: Dictionary = {}     # 收集/夺取进度（COLLECT 胜利条件）
var occupy_counter := 0                 # 占领连续回合数（OCCUPY）
var deployed: Array[Unit] = []          # 布阵阶段上阵的我方单位
var _round_actors: Dictionary = {}      # 本轮已行动单位（回合 = 全体各行动一次，决策日志 D28）
var _triggers: Array = []               # 触发器（含 fired 标记的运行副本）
var _escort_reached := false
var achievement_paths: Dictionary = {}  # 剧情路线标记（如 drugged_wine，成就判定用，决策日志 D31）
var _kill_teams: Dictionary = {}        # unit_id -> 击杀者所在 Team（成就「不击杀」判定）

func setup(p_data: GameDataLoader, p_grid: Grid, p_units: Array[Unit]) -> void:
	data = p_data
	grid = p_grid
	units = p_units
	for u in units:
		u.died.connect(_on_unit_died)

func set_seed(value: int) -> void:
	if rolls is RandomRollSource:
		(rolls as RandomRollSource).set_seed(value)

## 战斗中动态加入单位（召唤物/伏兵，关卡触发器与 summon 效果用）
func add_unit(u: Unit) -> void:
	units.append(u)
	add_child(u)
	u.died.connect(_on_unit_died)

# ---------------------------------------------------------------- 关卡装载与布阵（策划文档 6.8/6.9）

## 从 LevelConfig 装载关卡：棋盘、敌方、NPC 友军、场景物件、触发器。我方走布阵流程。
func setup_level(p_data: GameDataLoader, p_level: LevelConfig) -> void:
	data = p_data
	level = p_level
	grid = Grid.new()
	add_child(grid)
	grid.setup(data, level.grid_size, level.terrain_map, level.height_map)
	move_child(grid, 0)
	for spec in level.enemies:
		spawn_from_spec(spec, Unit.Team.ENEMY)
	for spec in level.npc_allies:
		spawn_from_spec(spec, Unit.Team.NPC_ALLY)
	for spec in level.objects:
		_spawn_object(spec)
	_triggers = level.triggers.duplicate(true)
	change_state(State.DEPLOY)
	# 必出武将自动落位（部署区从前到后）
	var auto_cells := _free_deploy_cells()
	for rid in level.required_units:
		if auto_cells.is_empty():
			break
		deploy_unit(rid, auto_cells.pop_front())

## 按配置生成单位（elite/boss 标记）
func spawn_from_spec(spec: Dictionary, default_team: Unit.Team) -> Unit:
	var ud := data.get_unit(StringName(spec.get("unit", "")))
	if ud == null:
		push_error("BattleManager: 未知单位 '%s'" % spec.get("unit", ""))
		return null
	var team := default_team
	match String(spec.get("team", "")):
		"player":
			team = Unit.Team.PLAYER
		"npc":
			team = Unit.Team.NPC_ALLY
		"enemy":
			team = Unit.Team.ENEMY
	var u := Unit.new()
	u.setup(ud, team, spec["coords"])
	u.is_elite = bool(spec.get("elite", false))
	if spec.get("boss", false):
		u.is_elite = true
		boss_unit = u
	add_unit(u)
	grid.place_unit(u, spec["coords"])
	return u

## 场景物件（生辰纲担等）：静态、不行动、不计入胜负
func _spawn_object(spec: Dictionary) -> Unit:
	var ud := UnitData.new()
	ud.unit_id = StringName("obj_" + String(spec.get("id", "object")))
	ud.name = String(spec.get("id", "object"))
	ud.hp = int(spec.get("hp", 300))
	ud.spd = 1
	var obj := Unit.new()
	obj.is_object = true
	obj.setup(ud, Unit.Team.NPC_ALLY, spec["coords"])
	add_unit(obj)
	grid.place_unit(obj, spec["coords"])
	return obj

func _free_deploy_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(level.deploy_zone.position.y, level.deploy_zone.end.y):
		for x in range(level.deploy_zone.position.x, level.deploy_zone.end.x):
			var c := Vector2i(x, y)
			var cell := grid.get_cell(c)
			if cell != null and not cell.is_blocked() and cell.occupant == null:
				out.append(c)
	return out

func can_deploy_at(coords: Vector2i) -> bool:
	if level == null or not level.deploy_zone.has_point(coords):
		return false
	var cell := grid.get_cell(coords)
	return cell != null and not cell.is_blocked() and cell.occupant == null

## 布阵：上阵/调整位置。名额与必出校验在 confirm_deploy。
func deploy_unit(unit_id: StringName, coords: Vector2i) -> Unit:
	if state != State.DEPLOY:
		push_error("布阵：当前不在布阵阶段")
		return null
	if not can_deploy_at(coords):
		push_error("布阵：%s 不在部署区或已被占用" % coords)
		return null
	if deployed.size() >= level.max_deploy:
		push_error("布阵：上阵人数已达上限 %d" % level.max_deploy)
		return null
	var u := Unit.new()
	u.setup(data.get_unit(unit_id), Unit.Team.PLAYER, coords)
	u.facing = Vector2i(0, -1)
	deployed.append(u)
	add_unit(u)
	grid.place_unit(u, coords)
	deploy_changed.emit()
	return u

## 撤下一名已上阵单位（必出武将不可撤，只可调整位置——调用方负责先 deploy 新位置）
func undeploy_unit(u: Unit) -> void:
	if state != State.DEPLOY or not deployed.has(u):
		return
	deployed.erase(u)
	units.erase(u)
	var cell := grid.get_cell(u.coords)
	if cell != null and cell.occupant == u:
		cell.occupant = null
	u.queue_free()
	deploy_changed.emit()

## 确认布阵：必出全部上阵、人数合法后开战
func confirm_deploy() -> bool:
	if state != State.DEPLOY:
		return false
	for rid in level.required_units:
		if not deployed.any(func(u): return u.data.unit_id == rid):
			push_error("布阵：必出武将 %s 未上阵" % rid)
			return false
	if deployed.is_empty() or deployed.size() > level.max_deploy:
		push_error("布阵：上阵人数不合法")
		return false
	start_battle()
	return true

func change_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)

# ---------------------------------------------------------------- 指令管道

## 指令唯一入口：玩家输入与 AI 决策都走这里。
func submit_command(cmd: Command) -> Array:
	change_state(State.EXECUTING)
	var events := cmd.execute(self)
	command_executed.emit(cmd, events)
	_fan_out_trigger_events(cmd, events)
	if state != State.BATTLE_END:
		change_state(State.IDLE if (active_unit != null and active_unit.team == Unit.Team.PLAYER) else State.AI_TURN)
	return events

## 指令结果扇出为触发器事件：移动（ENTER_ZONE）、受击（HP_BELOW）、护送到达（ESCORT）
func _fan_out_trigger_events(cmd: Command, events: Array) -> void:
	if _triggers.is_empty() and level == null:
		return
	for e in events:
		match String(e.get("type", "")):
			"move", "pull", "push", "teleport", "swap":
				var u := e.get("unit") as Unit
				if u == null:
					u = e.get("target") as Unit
				if u != null:
					_check_triggers({"type": "UNIT_MOVED", "unit": u})
					_check_escort_arrival(u)
			"damage":
				var t := e.get("target") as Unit
				if t != null and t.is_alive():
					_check_triggers({"type": "UNIT_DAMAGED", "unit": t})
				if t != null and bool(e.get("died", false)) and e.get("source") != null:
					_kill_teams[t.data.unit_id] = (e["source"] as Unit).team

func _check_escort_arrival(u: Unit) -> void:
	if level == null or String(level.win_condition.get("type")) != "ESCORT":
		return
	if u.data.unit_id != StringName(level.win_condition.get("unit", "")):
		return
	var zone: Rect2i = level.win_condition.get("zone", Rect2i())
	if zone.has_point(u.coords):
		_escort_reached = true

# ---------------------------------------------------------------- 回合流转（CTB）

func start_battle() -> void:
	# 羁绊：同队原著搭档同场激活（策划文档 4.1、决策日志 D29）
	var bond_events := BondSystem.apply_bonds(units, data.progression)
	if not bond_events.is_empty():
		tick_events.emit(null, bond_events)
	# 开局触发器（T1 剧情等）
	_check_triggers({"type": "START"})
	advance_turn()

func advance_turn() -> void:
	var winner := evaluate_outcome()
	if winner != -1:
		change_state(State.BATTLE_END)
		battle_ended.emit(winner)
		return
	active_unit = turn_order.next_actor(units)
	if active_unit == null:
		return
	# 阶段一：DoT/地形效果（策划文档 6.7、决策日志 D18）
	var tick := active_unit.tick_effects()
	tick.append_array(_terrain_tick(active_unit))
	if not active_unit.is_alive():
		if not tick.is_empty():
			tick_events.emit(active_unit, tick)
		advance_turn()   # DoT/地形致死，跳过行动
		return
	# 行动能力判定（眩晕/麻痹/睡眠），必须在阶段二递减之前（决策日志 D22 注）
	var incapacitated := not active_unit.can_act()
	# 阶段二：Buff 回合数与技能冷却递减
	tick.append_array(active_unit.tick_durations())
	if incapacitated:
		tick.append({"type": "turn_skipped", "unit": active_unit})
		tick_events.emit(active_unit, tick)
		finish_turn()
		return
	if not tick.is_empty():
		tick_events.emit(active_unit, tick)
	# 引导夺取完成（上回合开始引导，本回合开始时收讫，策划文档 7.3）
	if active_unit.channeling != null:
		var channel_events := _complete_collect(active_unit)
		tick_events.emit(active_unit, channel_events)
	move_used = false
	action_used = false
	change_state(State.AI_TURN if active_unit.team != Unit.Team.PLAYER else State.IDLE)
	turn_started.emit(active_unit)

## 开始引导夺取（InteractCommand 调用）：需相邻、消耗本回合行动
func can_channel(unit: Unit, obj: Unit) -> bool:
	return unit != null and obj != null and obj.is_object and obj.is_alive() \
		and unit.channeling == null and not unit.is_object \
		and absi(unit.coords.x - obj.coords.x) + absi(unit.coords.y - obj.coords.y) == 1

func _complete_collect(unit: Unit) -> Array:
	var obj := unit.channeling
	unit.channeling = null
	if obj == null or not obj.is_alive():
		return [{"type": "collect_failed", "unit": unit}]
	var obj_id := String(obj.data.unit_id).trim_prefix("obj_")
	var cell := grid.get_cell(obj.coords)
	if cell != null and cell.occupant == obj:
		cell.occupant = null
	units.erase(obj)
	obj.queue_free()
	collect(obj_id)
	return [{"type": "collect", "unit": unit, "object": obj_id,
		"count": int(collect_counts[obj_id])}]

## 地形回合开始效果：营帐回血 8% 最大生命，火堆灼烧 5% 最大生命（地形表 special，决策日志 D18）
func _terrain_tick(unit: Unit) -> Array:
	var events: Array = []
	var cell := grid.get_cell(unit.coords)
	if cell == null:
		return events
	match String(cell.terrain.terrain_id):
		"camp":
			var applied := unit.heal(roundi(float(unit.data.hp) * 0.08))
			if applied > 0:
				events.append({"type": "terrain_heal", "unit": unit, "terrain": &"camp", "amount": applied})
		"fire":
			var applied := unit.take_damage(roundi(float(unit.data.hp) * 0.05))
			events.append({"type": "terrain_dot", "unit": unit, "terrain": &"fire", "amount": applied})
	return events

func finish_turn() -> void:
	var u := active_unit
	if u != null:
		if u.extra_action_pending:
			# 再动：行动后 AV 直接清零重置（策划文档 6.4、决策日志 D22）
			u.extra_action_pending = false
			u.av = 0.0
		else:
			u.reset_av()
		turn_ended.emit(u)
		if u.is_alive():
			_round_actors[u] = true
	active_unit = null
	_check_round_complete()
	advance_turn()

# ---------------------------------------------------------------- 回合（round）与胜负条件（策划文档 6.9、决策日志 D28）

## 回合 = 全体存活非物件单位各行动一次（CTB 无自然轮次；再动不重复计数）
func _check_round_complete() -> void:
	for u in units:
		if u.is_alive() and not u.is_object and not _round_actors.has(u):
			return
	_round_actors.clear()
	round_count += 1
	if level != null and String(level.win_condition.get("type")) == "OCCUPY":
		_update_occupy_counter()
	round_started.emit(round_count)
	_check_triggers({"type": "TURN", "turn": round_count})

func _update_occupy_counter() -> void:
	var zone: Rect2i = level.win_condition.get("zone", Rect2i())
	var held := false
	for u in units:
		if u.is_alive() and u.team == Unit.Team.PLAYER and zone.has_point(u.coords):
			held = true
			break
	occupy_counter = occupy_counter + 1 if held else 0   # 连续占领（D28）

## 结果评估：-1 继续；否则胜方 Team。失败条件优先于胜利条件；我方全灭必败（D28）。
func evaluate_outcome() -> int:
	if _side_wiped(Unit.Team.PLAYER):
		return Unit.Team.ENEMY
	var wc: Dictionary = level.win_condition if level != null else {"type": "WIPE_OUT"}
	if level != null:
		for lc in level.lose_conditions:
			if _lose_met(lc):
				return Unit.Team.ENEMY
	if _win_met(wc):
		return Unit.Team.PLAYER
	# 敌方全灭：除 COLLECT/ESCORT 必须目标达成外，一律判胜（D28）
	if _side_wiped(Unit.Team.ENEMY) and String(wc.get("type")) not in ["COLLECT", "ESCORT"]:
		return Unit.Team.PLAYER
	return -1

func _win_met(wc: Dictionary) -> bool:
	match String(wc.get("type", "WIPE_OUT")):
		"WIPE_OUT":
			return _side_wiped(Unit.Team.ENEMY)
		"KILL_BOSS":
			return boss_unit == null or not boss_unit.is_alive()
		"SURVIVE_TURNS":
			return round_count >= int(wc.get("turns", 1))
		"COLLECT":
			return int(collect_counts.get(String(wc.get("target", "")), 0)) >= int(wc.get("count", 1))
		"ESCORT":
			return _escort_reached
		"OCCUPY":
			return occupy_counter >= int(wc.get("turns", 1))
	return false

func _lose_met(lc: Dictionary) -> bool:
	match String(lc.get("type", "")):
		"WIPED_OUT":
			return _side_wiped(Unit.Team.PLAYER)
		"TURN_LIMIT":
			return round_count > int(lc.get("turns", 99))
		"ESCORT_DEAD":
			var target := _find_unit(StringName(lc.get("unit", "")))
			return target != null and not target.is_alive()
	return false

func _side_wiped(team: Unit.Team) -> bool:
	for u in units:
		if u.is_alive() and not u.is_object and u.team == team:
			return false
	return true

func _find_unit(id: StringName) -> Unit:
	for u in units:
		if u.data != null and u.data.unit_id == id:
			return u
	return null

## 兼容旧接口：等同于 evaluate_outcome（无关卡时按歼灭/全灭）。
func check_winner() -> int:
	return evaluate_outcome()

## 收集/夺取进度（COLLECT 胜利条件；夺取动作随示范关卡落地）
func collect(object_id: String) -> void:
	collect_counts[object_id] = int(collect_counts.get(object_id, 0)) + 1

# ---------------------------------------------------------------- 结算与成就（策划文档 7.5、决策日志 D31）

## 战斗结算：胜负、奖励、成就。成就互斥：同 exclusive_group 只取先列出者。
func compute_result(winner: int) -> Dictionary:
	var result := {
		"winner": winner,
		"won": winner == Unit.Team.PLAYER,
		"rounds": round_count,
		"rewards": {},
		"achievements": [],
	}
	if level == null or winner != Unit.Team.PLAYER:
		return result
	result["rewards"] = level.rewards.duplicate(true)
	var earned_groups: Array = []
	for ach in level.achievements:
		if _achievement_met(ach) and not earned_groups.has(String(ach.get("exclusive_group", ""))):
			earned_groups.append(String(ach.get("exclusive_group", "")))
			result["achievements"].append(ach.get("id", ""))
	return result

func _achievement_met(ach: Dictionary) -> bool:
	var req: Dictionary = ach.get("requires", {})
	if req.has("path") and not achievement_paths.has(String(req["path"])):
		return false
	# 我方未击杀名单内单位（「不战而屈人之兵」：不击杀任何厢军，NPC 友军击杀不算）
	for id in req.get("no_player_kills", []):
		if int(_kill_teams.get(StringName(id), -1)) == Unit.Team.PLAYER:
			return false
	if req.has("boss_dead"):
		var u := _find_unit(StringName(req["boss_dead"]))
		if u != null and u.is_alive():
			return false
	return true

# ---------------------------------------------------------------- 事件触发器（策划文档 6.9）

func _check_triggers(event: Dictionary) -> void:
	for t in _triggers:
		if t.get("fired", false) and t.get("once", true):
			continue
		if not _trigger_condition_met(t.get("on", {}), event):
			continue
		if not _trigger_if_met(t.get("if", {})):
			continue
		t["fired"] = true
		_run_trigger_actions(t.get("actions", []))

## 触发器附加条件（如「若未集齐3担」「若公孙胜已上阵」，决策日志 D31）
func _trigger_if_met(cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	match String(cond.get("type", "")):
		"collect_below":
			return int(collect_counts.get(String(cond.get("target", "")), 0)) < int(cond.get("count", 1))
		"unit_deployed":
			var u := _find_unit(StringName(cond.get("unit", "")))
			return u != null and u.is_alive()
		"unit_alive":
			var u := _find_unit(StringName(cond.get("unit", "")))
			return u != null and u.is_alive()
	return true

func _trigger_condition_met(cond: Dictionary, event: Dictionary) -> bool:
	match String(cond.get("type", "")):
		"START":
			return String(event.get("type")) == "START"
		"TURN":
			return String(event.get("type")) == "TURN" and int(event.get("turn", 0)) >= int(cond.get("turn", 1))
		"UNIT_DEAD":
			if String(event.get("type")) != "UNIT_DEAD":
				return false
			var want := StringName(cond.get("unit", ""))
			return want == &"" or (event.get("unit") as Unit).data.unit_id == want
		"HP_BELOW":
			if String(event.get("type")) != "UNIT_DAMAGED":
				return false
			var u := event.get("unit") as Unit
			return u.data.unit_id == StringName(cond.get("unit", "")) \
				and float(u.hp) / float(u.data.hp) < float(cond.get("ratio", 0.5))
		"ENTER_ZONE":
			if String(event.get("type")) != "UNIT_MOVED":
				return false
			var u := event.get("unit") as Unit
			var who := String(cond.get("who", "any"))
			if who == "player" and u.team != Unit.Team.PLAYER:
				return false
			if who == "enemy" and u.team != Unit.Team.ENEMY:
				return false
			var zone: Rect2i = cond.get("zone", Rect2i())
			return zone.has_point(u.coords)
	return false

func _run_trigger_actions(actions: Array) -> void:
	for a in actions:
		match String(a.get("type", "")):
			"spawn":
				for spec in a.get("units", []):
					spawn_from_spec(spec, Unit.Team.ENEMY)
			"dialogue":
				dialogue.emit(String(a.get("text", "")))
			"terrain":
				for c in a.get("cells", {}):
					grid.set_terrain(c, StringName(a["cells"][c]))
			"buff":
				_apply_side_buff(a)
			"status":
				_apply_side_status(a)
			"regen":
				_apply_regen(a)
			"achievement_path":
				achievement_paths[String(a.get("path", ""))] = true

func _apply_side_buff(a: Dictionary) -> void:
	if a.has("unit"):
		# 单目标标记（如白胜「生辰纲功臣」本关攻+20%）
		var u := _find_unit(StringName(a.get("unit", "")))
		if u != null and u.is_alive():
			_add_trigger_buff(u, a)
		return
	var side := String(a.get("side", "enemy"))
	for u in units:
		if not u.is_alive() or u.is_object:
			continue
		if (side == "enemy") != (u.team == Unit.Team.ENEMY):
			continue
		_add_trigger_buff(u, a)

func _add_trigger_buff(u: Unit, a: Dictionary) -> void:
	var b := Buff.new()
	b.buff_id = StringName("trigger_%s" % String(a.get("name", "buff")))
	b.name = String(a.get("name", "触发器增益"))
	b.stat_mods = {a.get("field", &"atk"): int(a.get("value", 0))}
	b.duration = int(a.get("duration", 99))
	b.dispellable = bool(a.get("dispellable", false))
	u.add_buff(b)

## 阵营范围控制状态（如 T2 蒙汗药酒：敌方全体睡眠，杨志例外时长，决策日志 D31）
func _apply_side_status(a: Dictionary) -> void:
	var side := String(a.get("side", "enemy"))
	var status := StringName(a.get("status", "sleep"))
	for u in units:
		if not u.is_alive() or u.is_object:
			continue
		if (side == "enemy") != (u.team == Unit.Team.ENEMY):
			continue
		var duration := int(a.get("duration", 1))
		if a.has("except") and u.data.unit_id == StringName(a["except"].get("unit", "")):
			duration = int(a["except"].get("duration", duration))
		var b := Buff.new()
		b.buff_id = status
		b.name = String(a.get("name", status))
		b.status = status
		b.duration = duration
		b.is_debuff = true
		u.add_buff(b)

## 每回合回血（杨志狂暴「羞刀难入鞘」回血 5%）
func _apply_regen(a: Dictionary) -> void:
	var u := _find_unit(StringName(a.get("unit", "")))
	if u == null or not u.is_alive():
		return
	var b := Buff.new()
	b.buff_id = StringName("regen_%s" % String(a.get("unit", "")))
	b.name = String(a.get("name", "再生"))
	b.tick_effect = {"kind": "hot", "percent": int(a.get("percent", 5))}
	b.duration = int(a.get("duration", 99))
	b.dispellable = false
	u.add_buff(b)

# ---------------------------------------------------------------- 攻击辅助

## 攻击范围：曼哈顿距离区间（武器范围模板后续细化，决策日志 D9）。
func in_attack_range(attacker: Unit, target: Unit) -> bool:
	var dist := absi(attacker.coords.x - target.coords.x) + absi(attacker.coords.y - target.coords.y)
	return dist >= attacker.data.range_min and dist <= attacker.data.range_max

func enemies_in_range(attacker: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.is_alive() and u.team != attacker.team and in_attack_range(attacker, u):
			out.append(u)
	return out

## 普攻选择：远程单位（range_min >= 2）用 generic_ranged，否则 generic_melee。
func basic_attack_skill(unit: Unit) -> SkillData:
	if unit.data.range_min >= 2:
		return data.get_skill(&"generic_ranged")
	return data.get_skill(&"generic_melee")

# ---------------------------------------------------------------- 技能

## 技能可用性：怒气足够且不在冷却中。
func can_use_skill(unit: Unit, skill: SkillData) -> bool:
	return unit.rage >= skill.rage_cost and unit.skill_cooldown(skill.skill_id) <= 0

# ---------------------------------------------------------------- 评分制 AI（策划文档第八章）

## 评分制 AI 驱动当前行动单位（敌方固定全自动；我方由 auto_mode 决定，8.5）。
func run_ai() -> void:
	if active_unit == null or state == State.BATTLE_END:
		return
	var plan := BattleAI.decide(active_unit, self)
	for cmd in plan:
		if state == State.BATTLE_END:
			break
		submit_command(cmd)
	finish_turn()

## 设置/切换集火目标（死亡自动清除）
func set_focus_target(u: Unit) -> void:
	focus_target = u

func _on_unit_died(unit: Unit) -> void:
	turn_order.remove(unit)
	var cell := grid.get_cell(unit.coords)
	if cell != null and cell.occupant == unit:
		cell.occupant = null
	if focus_target == unit:
		focus_target = null
	_round_actors.erase(unit)
	unit_died.emit(unit)
	_check_triggers({"type": "UNIT_DEAD", "unit": unit})
