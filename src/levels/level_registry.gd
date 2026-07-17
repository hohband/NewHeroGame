class_name LevelRegistry
extends RefCounted
## 关卡注册表：以代码构建 LevelConfig（.tres 可视化编辑工作流在 M2 接入，决策日志 D28）。

static func get_level(id: String) -> LevelConfig:
	match id:
		"debug_01":
			return _debug_01()
	push_error("LevelRegistry: 未知关卡 '%s'" % id)
	return null

## 调试关卡：3 必出 + 候选池布阵，歼灭胜利，演示 TURN/ENTER_ZONE 两类触发器。
static func _debug_01() -> LevelConfig:
	var l := LevelConfig.new()
	l.id = "debug_01"
	l.name = "调试关卡"
	l.grid_size = Vector2i(8, 8)
	l.terrain_map = {
		Vector2i(2, 2): &"forest", Vector2i(3, 2): &"forest", Vector2i(2, 3): &"forest",
		Vector2i(5, 5): &"forest", Vector2i(6, 2): &"hill", Vector2i(6, 3): &"hill",
		Vector2i(4, 4): &"barricade", Vector2i(3, 4): &"camp", Vector2i(1, 5): &"water",
		Vector2i(4, 0): &"road", Vector2i(4, 1): &"road",
	}
	l.height_map = {Vector2i(6, 2): 1, Vector2i(6, 3): 1}
	l.win_condition = {"type": "WIPE_OUT"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	l.required_units = [&"lin_chong", &"lu_zhishen", &"an_daoquan"]
	l.roster = [
		&"wu_yong", &"hua_rong", &"li_kui", &"dai_zong", &"shi_qian",
		&"sun_erniang", &"cao_zheng", &"jiao_ting", &"bao_xu", &"yu_baosi",
	]
	l.deploy_zone = Rect2i(0, 6, 8, 2)
	l.max_deploy = 6
	l.enemies = [
		{"unit": &"shi_yong", "coords": Vector2i(5, 1)},
		{"unit": &"song_wan", "coords": Vector2i(4, 1), "elite": true},
		{"unit": &"du_qian", "coords": Vector2i(6, 1)},
	]
	l.triggers = [
		{"id": "t_reinforce", "once": true,
			"on": {"type": "TURN", "turn": 2},
			"actions": [
				{"type": "dialogue", "text": "敌军援军从北面赶到了！"},
				{"type": "spawn", "units": [{"unit": &"wang_dingliu", "coords": Vector2i(7, 0), "team": "enemy"}]},
			]},
		{"id": "t_mid", "once": true,
			"on": {"type": "ENTER_ZONE", "zone": Rect2i(0, 3, 8, 2), "who": "player"},
			"actions": [{"type": "dialogue", "text": "我军已突入中场，注意两侧松林伏兵。"}]},
	]
	return l
