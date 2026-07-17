class_name LevelRegistry
extends RefCounted
## 关卡注册表：以代码构建 LevelConfig（.tres 可视化编辑工作流在 M2 接入，决策日志 D28）。

static func get_level(id: String) -> LevelConfig:
	match id:
		"debug_01":
			return _debug_01()
		"ch03_01":
			return _ch03_01()
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

## 示范关卡：智取生辰纲（策划文档第七章，主线第三章剧情关/教学关）。
## 教学目标：非歼灭型胜利条件（夺取）、场景互动（酒摊）、剧情彩蛋路线（药酒/硬打双路线）。
static func _ch03_01() -> LevelConfig:
	var l := LevelConfig.new()
	l.id = "ch03_01"
	l.name = "智取生辰纲"
	l.chapter = 3
	l.recommended_level = 12
	l.grid_size = Vector2i(10, 8)
	# 黄泥冈（7.2）：中央土路纵贯南北，两侧松林，东北角高台，土路中段旁酒摊
	var terrain: Dictionary = {}
	for y in range(8):
		terrain[Vector2i(4, y)] = &"road"
		terrain[Vector2i(5, y)] = &"road"
	for c in [Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, 3), Vector2i(2, 3), Vector2i(1, 4), Vector2i(2, 4),
			Vector2i(7, 2), Vector2i(8, 2), Vector2i(7, 3), Vector2i(8, 3), Vector2i(7, 4), Vector2i(8, 4)]:
		terrain[c] = &"forest"
	for c in [Vector2i(8, 0), Vector2i(9, 0), Vector2i(9, 1)]:
		terrain[c] = &"hill"
	terrain[Vector2i(6, 4)] = &"wine_stall"
	l.terrain_map = terrain
	l.height_map = {Vector2i(8, 0): 1, Vector2i(9, 0): 1, Vector2i(9, 1): 1}
	l.win_condition = {"type": "COLLECT", "target": "cargo", "count": 3}
	l.lose_conditions = [{"type": "WIPED_OUT"}, {"type": "TURN_LIMIT", "turns": 10}]
	# 我方（7.3）：吴用、白胜必出 + 自选 2 席
	l.required_units = [&"wu_yong", &"bai_sheng"]
	l.roster = [&"lin_chong", &"lu_zhishen", &"gongsun_sheng", &"hua_rong", &"an_daoquan", &"li_kui"]
	l.deploy_zone = Rect2i(0, 6, 10, 2)
	l.max_deploy = 4
	l.npc_allies = [
		{"unit": &"chao_gai_npc", "coords": Vector2i(3, 5)},
		{"unit": &"liu_tang_npc", "coords": Vector2i(6, 5)},
	]
	l.enemies = [
		{"unit": &"yang_zhi_boss", "coords": Vector2i(5, 2), "elite": true, "boss": true},
		{"unit": &"lao_duguan", "coords": Vector2i(4, 2)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(3, 2)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(6, 2)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(3, 3)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(6, 3)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(4, 1)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(5, 1)},
	]
	l.objects = [
		{"id": "cargo", "coords": Vector2i(4, 3), "hp": 300},
		{"id": "cargo", "coords": Vector2i(5, 3), "hp": 300},
		{"id": "cargo", "coords": Vector2i(4, 4), "hp": 300},
	]
	l.triggers = [
		# T1 开局剧情（教学提示：本关目标是夺担而非全歼）
		{"id": "t1_intro", "once": true, "on": {"type": "START"},
			"actions": [
				{"type": "dialogue", "text": "吴用：杨志押的是梁中书的生辰纲，硬拼不得。白胜，看你的了。"},
				{"type": "dialogue", "text": "【教学】本关目标是夺取 3 副生辰纲担，不必全歼敌军。白胜进酒摊有妙用。"},
			]},
		# 公孙胜彩蛋（7.3：若已解锁，上阵触发彩蛋对话）
		{"id": "t1b_gongsun", "once": true, "on": {"type": "START"},
			"if": {"type": "unit_deployed", "unit": "gongsun_sheng"},
			"actions": [{"type": "dialogue", "text": "公孙胜：贫道夜观天象，今日黄泥冈上，合该有这一桩富贵。"}]},
		# T2 蒙汗药酒事件
		{"id": "t2_drugged_wine", "once": true,
			"on": {"type": "ENTER_ZONE", "zone": Rect2i(6, 4, 1, 1), "who": "bai_sheng"},
			"actions": [
				{"type": "dialogue", "text": "白胜：「好酒！烈得很哪——」杨志军汉饮了蒙汗药，一个个都倒了！"},
				{"type": "status", "side": "enemy", "status": "sleep", "duration": 2,
					"except": {"unit": "yang_zhi_boss", "duration": 1}, "name": "蒙汗药酒"},
				{"type": "buff", "unit": "bai_sheng", "field": &"atk", "value": 20, "duration": 99, "name": "生辰纲功臣"},
				{"type": "achievement_path", "path": "drugged_wine"},
				{"type": "dialogue", "text": "【教学】敌军已麻倒，快夺取生辰纲！"},
			]},
		# T3 杨志半血狂暴
		{"id": "t3_yangzhi_rage", "once": true,
			"on": {"type": "HP_BELOW", "unit": "yang_zhi_boss", "ratio": 0.5},
			"actions": [
				{"type": "dialogue", "text": "杨志：「羞刀难入鞘！」——杨志攻势大振，枪枪拼命。"},
				{"type": "buff", "unit": "yang_zhi_boss", "field": &"atk", "value": 30, "duration": 99, "name": "羞刀难入鞘"},
				{"type": "regen", "unit": "yang_zhi_boss", "percent": 5, "duration": 99, "name": "羞刀难入鞘·回血"},
			]},
		# T4 第 6 回合援军（若未集齐 3 担）
		{"id": "t4_reinforce", "once": true, "on": {"type": "TURN", "turn": 6},
			"if": {"type": "collect_below", "target": "cargo", "count": 3},
			"actions": [
				{"type": "dialogue", "text": "老都管：援军到了！都给我顶住！"},
				{"type": "spawn", "units": [
					{"unit": &"xiangjun_spear", "coords": Vector2i(2, 7), "team": "enemy"},
					{"unit": &"xiangjun_spear", "coords": Vector2i(7, 7), "team": "enemy"},
				]},
			]},
		# T6 白胜阵亡（硬打路线）
		{"id": "t6_baisheng_down", "once": true, "on": {"type": "UNIT_DEAD", "unit": "bai_sheng"},
			"actions": [
				{"type": "dialogue", "text": "杨志：「卖酒的贼厮，也敢算计爷爷！」——敌军士气大振。"},
				{"type": "buff", "side": "enemy", "field": &"atk", "value": 10, "duration": 99, "name": "士气"},
			]},
	]
	# T5：夺取第 3 副担即通关（由 COLLECT 胜利条件承载）
	l.rewards = {
		"first_clear": {"shard_bai_sheng": 10, "skill_book": 3, "gold": 2000},
		"regular": {"breakthrough_mat": 1},
	}
	l.achievements = [
		{"id": "buzhan", "name": "不战而屈人之兵", "exclusive_group": "shengchengang",
			"requires": {"path": "drugged_wine", "no_player_kills": ["xiangjun_spear", "xiangjun_shield"]}},
		{"id": "biaoshi", "name": "黄泥冈镖师", "exclusive_group": "shengchengang",
			"requires": {"boss_dead": "yang_zhi_boss"}},
	]
	return l
