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

enum State { DEPLOY, IDLE, MOVE_PREVIEW, TARGETING, EXECUTING, AI_TURN, BATTLE_END }

var data: GameDataLoader
var grid: Grid
var units: Array[Unit] = []
var rolls: RollSource = RandomRollSource.new()
var turn_order := TurnOrder.new()
var state: State = State.DEPLOY
var active_unit: Unit = null
var move_used := false
var action_used := false

func setup(p_data: GameDataLoader, p_grid: Grid, p_units: Array[Unit]) -> void:
	data = p_data
	grid = p_grid
	units = p_units
	for u in units:
		u.died.connect(_on_unit_died)

func set_seed(value: int) -> void:
	if rolls is RandomRollSource:
		(rolls as RandomRollSource).set_seed(value)

func change_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)

# ---------------------------------------------------------------- 指令管道

## 指令唯一入口：玩家输入与 AI 决策都走这里。
func submit_command(cmd: Command) -> Array:
	change_state(State.EXECUTING)
	var events := cmd.execute(self)
	command_executed.emit(cmd, events)
	if state != State.BATTLE_END:
		change_state(State.IDLE if (active_unit != null and active_unit.team == Unit.Team.PLAYER) else State.AI_TURN)
	return events

# ---------------------------------------------------------------- 回合流转（CTB）

func start_battle() -> void:
	advance_turn()

func advance_turn() -> void:
	var winner := check_winner()
	if winner != -1:
		change_state(State.BATTLE_END)
		battle_ended.emit(winner)
		return
	active_unit = turn_order.next_actor(units)
	if active_unit == null:
		return
	# 回合开始统一 tick：Buff/DoT（策划文档 6.7）+ 地形效果（决策日志 D18）
	var tick := active_unit.tick_turn_start()
	tick.append_array(_terrain_tick(active_unit))
	if not tick.is_empty():
		tick_events.emit(active_unit, tick)
	if not active_unit.is_alive():
		advance_turn()   # DoT/地形致死，跳过行动
		return
	move_used = false
	action_used = false
	change_state(State.AI_TURN if active_unit.team != Unit.Team.PLAYER else State.IDLE)
	turn_started.emit(active_unit)

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
		u.reset_av()
		turn_ended.emit(u)
	active_unit = null
	advance_turn()

func _on_unit_died(unit: Unit) -> void:
	turn_order.remove(unit)
	var cell := grid.get_cell(unit.coords)
	if cell != null and cell.occupant == unit:
		cell.occupant = null
	unit_died.emit(unit)

## 占位胜负判定：一方全灭。正式胜利条件系统（歼灭/护送/占领/坚守/BOSS）见 M1 第 5 阶段。
func check_winner() -> int:
	var player_side := false
	var enemy_side := false
	for u in units:
		if not u.is_alive():
			continue
		if u.team == Unit.Team.ENEMY:
			enemy_side = true
		else:
			player_side = true
	if enemy_side and not player_side:
		return Unit.Team.ENEMY
	if player_side and not enemy_side:
		return Unit.Team.PLAYER
	return -1

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

# ---------------------------------------------------------------- 占位 AI

## 【占位】朴素敌方 AI：向最近敌人靠近并攻击。正式评分制 AI 见 M1 第 4 阶段（决策日志 D10）。
func run_placeholder_ai() -> void:
	if active_unit == null or state == State.BATTLE_END:
		return
	var target := _nearest_opponent(active_unit)
	if target == null:
		finish_turn()
		return
	if not move_used and not in_attack_range(active_unit, target):
		var reachable := grid.get_reachable(active_unit, active_unit.data.move)
		var best := active_unit.coords
		var best_dist := _manhattan(active_unit.coords, target.coords)
		for c in reachable:
			var d := _manhattan(c, target.coords)
			if d < best_dist:
				best_dist = d
				best = c
		if best != active_unit.coords:
			var path := grid.find_path(active_unit, best)
			if not path.is_empty():
				path.remove_at(0)   # 去掉起点
				submit_command(MoveCommand.new(active_unit, path))
		move_used = true
	if not action_used and in_attack_range(active_unit, target):
		submit_command(AttackCommand.new(active_unit, target, basic_attack_skill(active_unit)))
		action_used = true
	finish_turn()

func _nearest_opponent(unit: Unit) -> Unit:
	var best: Unit = null
	var best_dist := 9999
	for u in units:
		if not u.is_alive() or u.team == unit.team:
			continue
		if unit.team != Unit.Team.ENEMY and u.team == Unit.Team.NPC_ALLY:
			continue   # 我方不打 NPC 友军
		var d := _manhattan(unit.coords, u.coords)
		if d < best_dist:
			best_dist = d
			best = u
	return best

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
