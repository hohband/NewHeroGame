extends GutTest
## 关卡系统：LevelConfig 装载、布阵、胜负条件（6 类）、回合制、事件触发器（策划文档 6.8/6.9、决策日志 D28）

var loader: GameDataLoader

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()

func _base_level() -> LevelConfig:
	var l := LevelConfig.new()
	l.id = "test"
	l.grid_size = Vector2i(6, 6)
	l.deploy_zone = Rect2i(0, 4, 6, 2)
	l.max_deploy = 4
	l.required_units = [&"lin_chong"]
	l.roster = [&"wu_yong", &"hua_rong"]
	l.enemies = [{"unit": &"shi_yong", "coords": Vector2i(3, 1)}]
	l.win_condition = {"type": "WIPE_OUT"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	return l

func _manager(level: LevelConfig) -> BattleManager:
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, level)
	m.rolls = FixedRollSource.new()
	return m

func _drive_rounds(m: BattleManager, max_turns: int) -> void:
	## 空转回合（所有单位直接 finish_turn），用于触发回合类逻辑
	for i in range(max_turns):
		if m.state == BattleManager.State.BATTLE_END:
			break
		m.finish_turn()

# ---------------------------------------------------------------- 装载与布阵

func test_setup_level_builds_level() -> void:
	var m := _manager(_base_level())
	assert_eq(m.grid.size, Vector2i(6, 6))
	assert_eq(m.state, BattleManager.State.DEPLOY)
	assert_not_null(m.grid.get_cell(Vector2i(3, 1)).occupant, "敌方已落位")
	assert_eq(m.deployed.size(), 1, "必出武将自动上阵")
	assert_eq(m.deployed[0].data.unit_id, &"lin_chong")

func test_deploy_validation() -> void:
	var m := _manager(_base_level())
	var bad := m.deploy_unit(&"wu_yong", Vector2i(0, 0))
	assert_null(bad, "部署区外不可上阵")
	assert_push_error("部署区")
	var ok := m.deploy_unit(&"wu_yong", Vector2i(1, 4))
	assert_not_null(ok)
	m.undeploy_unit(ok)
	assert_eq(m.deployed.size(), 1)

func test_confirm_deploy_starts_battle() -> void:
	var m := _manager(_base_level())
	assert_true(m.confirm_deploy())
	assert_ne(m.state, BattleManager.State.DEPLOY, "确认后进入战斗循环")

func test_confirm_requires_required_units() -> void:
	var l := _base_level()
	l.required_units = [&"lin_chong", &"wu_yong"]   # 吴用不会自动上阵（只有 1 个自动位给必出？两个都自动）
	var m := _manager(l)
	m.undeploy_unit(m.deployed[1])   # 撤下吴用
	assert_false(m.confirm_deploy(), "必出未齐不可开战")
	assert_push_error("必出武将")

# ---------------------------------------------------------------- 胜负条件

func test_win_wipe_out() -> void:
	var m := _manager(_base_level())
	m.confirm_deploy()
	watch_signals(m)
	m.grid.get_cell(Vector2i(3, 1)).occupant.take_damage(99999)
	m.advance_turn()
	assert_signal_emitted(m, "battle_ended")
	assert_eq(m.state, BattleManager.State.BATTLE_END)

func test_win_kill_boss_ignores_adds() -> void:
	var l := _base_level()
	l.win_condition = {"type": "KILL_BOSS"}
	l.enemies = [
		{"unit": &"shi_yong", "coords": Vector2i(3, 1), "boss": true},
		{"unit": &"du_qian", "coords": Vector2i(4, 1)},
	]
	var m := _manager(l)
	m.confirm_deploy()
	assert_not_null(m.boss_unit)
	m.boss_unit.take_damage(99999)
	assert_eq(m.evaluate_outcome(), Unit.Team.PLAYER, "BOSS 阵亡即胜，杂兵生死无关（6.9）")

func test_lose_turn_limit() -> void:
	var l := _base_level()
	l.win_condition = {"type": "SURVIVE_TURNS", "turns": 99}
	l.lose_conditions = [{"type": "WIPED_OUT"}, {"type": "TURN_LIMIT", "turns": 1}]
	var m := _manager(l)
	m.confirm_deploy()
	_drive_rounds(m, 20)
	assert_eq(m.state, BattleManager.State.BATTLE_END, "超过回合上限应判负")

func test_win_survive_turns() -> void:
	var l := _base_level()
	l.win_condition = {"type": "SURVIVE_TURNS", "turns": 2}
	var m := _manager(l)
	m.confirm_deploy()
	watch_signals(m)
	_drive_rounds(m, 20)
	assert_signal_emitted(m, "battle_ended")
	assert_eq(m.round_count, 2, "坚守 2 回合达标")

func test_round_counting_and_signal() -> void:
	var m := _manager(_base_level())
	m.confirm_deploy()
	watch_signals(m)
	_drive_rounds(m, 2)   # 林冲+石勇 各行动一次 = 1 回合
	assert_eq(m.round_count, 1, "全体各行动一次为 1 回合（决策日志 D28）")
	assert_signal_emitted(m, "round_started")

func test_win_escort() -> void:
	var l := _base_level()
	l.win_condition = {"type": "ESCORT", "unit": "wu_yong", "zone": Rect2i(4, 0, 2, 2)}
	l.npc_allies = [{"unit": &"wu_yong", "coords": Vector2i(1, 1)}]
	var m := _manager(l)
	m.confirm_deploy()
	var npc := m._find_unit(&"wu_yong")
	assert_not_null(npc)
	var path := m.grid.find_path(npc, Vector2i(4, 1))
	path.remove_at(0)
	m.submit_command(MoveCommand.new(npc, path))
	assert_eq(m.evaluate_outcome(), Unit.Team.PLAYER, "护送目标到达即胜（6.9）")

func test_win_occupy() -> void:
	var l := _base_level()
	l.win_condition = {"type": "OCCUPY", "zone": Rect2i(0, 0, 2, 2), "turns": 2}
	var m := _manager(l)
	m.confirm_deploy()
	m.grid.move_unit(m.deployed[0], Vector2i(0, 0))
	_drive_rounds(m, 20)
	assert_eq(m.occupy_counter, 2, "连续占领计数")
	assert_eq(m.state, BattleManager.State.BATTLE_END)

# ---------------------------------------------------------------- 触发器

func test_trigger_turn_spawn() -> void:
	var l := _base_level()
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "TURN", "turn": 1},
		"actions": [{"type": "spawn", "units": [{"unit": &"du_qian", "coords": Vector2i(5, 0), "team": "enemy"}]}]}]
	var m := _manager(l)
	m.confirm_deploy()
	var before := m.units.size()
	_drive_rounds(m, 2)
	assert_eq(m.units.size(), before + 1, "第 1 回合伏兵出现（6.9）")
	assert_not_null(m.grid.get_cell(Vector2i(5, 0)).occupant)

func test_trigger_unit_dead_dialogue() -> void:
	var l := _base_level()
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "UNIT_DEAD", "unit": "shi_yong"},
		"actions": [{"type": "dialogue", "text": "石勇倒下了"}]}]
	var m := _manager(l)
	m.confirm_deploy()
	watch_signals(m)
	m.grid.get_cell(Vector2i(3, 1)).occupant.take_damage(99999)
	assert_signal_emitted(m, "dialogue")

func test_trigger_enter_zone_buff() -> void:
	var l := _base_level()
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "ENTER_ZONE", "zone": Rect2i(0, 2, 6, 2), "who": "player"},
		"actions": [{"type": "buff", "side": "player", "field": &"atk", "value": 10, "duration": 99, "name": "士气"}]}]
	var m := _manager(l)
	m.confirm_deploy()
	var lc := m.deployed[0]
	m.grid.move_unit(lc, Vector2i(3, 4))
	m.submit_command(MoveCommand.new(lc, [Vector2i(3, 3)]))
	assert_eq(lc.get_stat_mod(&"atk"), 10, "进入区域触发我方增益")

func test_trigger_hp_below() -> void:
	var l := _base_level()
	l.enemies = [{"unit": &"shi_yong", "coords": Vector2i(3, 1), "boss": true}]
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "HP_BELOW", "unit": "shi_yong", "ratio": 0.5},
		"actions": [{"type": "buff", "side": "enemy", "field": &"atk", "value": 30, "duration": 99, "name": "狂暴"}]}]
	var m := _manager(l)
	m.confirm_deploy()
	var boss: Unit = m.grid.get_cell(Vector2i(3, 1)).occupant
	boss.hp = 300   # 43%，低于 50% 阈值
	var lc := m.deployed[0]
	m.grid.move_unit(lc, Vector2i(3, 2))
	m.submit_command(AttackCommand.new(lc, boss, m.basic_attack_skill(lc)))
	assert_eq(boss.get_stat_mod(&"atk"), 30, "半血触发狂暴（如杨志羞刀难入鞘）")

func test_trigger_fires_only_once() -> void:
	var l := _base_level()
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "TURN", "turn": 1},
		"actions": [{"type": "dialogue", "text": "只播一次"}]}]
	var m := _manager(l)
	m.confirm_deploy()
	watch_signals(m)
	_drive_rounds(m, 30)
	assert_signal_emit_count(m, "dialogue", 1, "once 触发器只触发一次")
