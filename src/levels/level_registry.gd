class_name LevelRegistry
extends RefCounted
## 关卡注册表：以代码构建 LevelConfig（.tres 可视化编辑工作流在 M2 接入，决策日志 D28）。

## 全部关卡 id（章节顺序，关卡选择界面与章节终关判定用）
static func list_ids() -> Array[String]:
	return ["ch01_01", "ch01_02", "ch01_03", "ch01_04", "ch01_05",
		"ch02_01", "ch02_02", "ch03_01", "ch04_01", "ch04_02", "debug_01"]

## 挑战关 id（高难挑战解锁武将，5.3/挑战关「清风寨」「霹雳火」「东昌府」）
static func list_challenge_ids() -> Array[String]:
	return ["challenge_dongchang"]

## 日常副本 id（第九章：经验/金币/突破材料本，自动战斗主战场，决策日志 D34）
static func list_daily_ids() -> Array[String]:
	return ["daily_exp_1", "daily_exp_2", "daily_gold_1", "daily_gold_2", "daily_mat_1", "daily_mat_2"]

static func get_level(id: String) -> LevelConfig:
	match id:
		"debug_01":
			return _debug_01()
		"ch01_01":
			return _ch01_01()
		"ch01_02":
			return _ch01_02()
		"ch01_03":
			return _ch01_03()
		"ch01_04":
			return _ch01_04()
		"ch01_05":
			return _ch01_05()
		"ch02_01":
			return _ch02_01()
		"ch02_02":
			return _ch02_02()
		"ch03_01":
			return _ch03_01()
		"ch04_01":
			return _ch04_01()
		"ch04_02":
			return _ch04_02()
		"challenge_dongchang":
			return _challenge_dongchang()
		"daily_exp_1":
			return _daily("daily_exp_1", "演武·新兵试炼", 5, 100, {"first_clear": {"gold": 200}, "regular": {"gold": 50}},
				[{"unit": &"xiangjun_spear", "coords": Vector2i(3, 1)}, {"unit": &"xiangjun_spear", "coords": Vector2i(4, 1)},
				{"unit": &"xiangjun_spear", "coords": Vector2i(5, 1)}, {"unit": &"xiangjun_shield", "coords": Vector2i(4, 2)}])
		"daily_exp_2":
			return _daily("daily_exp_2", "演武·精锐试炼", 12, 200, {"first_clear": {"gold": 400}, "regular": {"gold": 100}},
				[{"unit": &"xiangjun_spear", "coords": Vector2i(3, 1)}, {"unit": &"xiangjun_spear", "coords": Vector2i(5, 1)},
				{"unit": &"xiangjun_shield", "coords": Vector2i(4, 1)}, {"unit": &"xiangjun_shield", "coords": Vector2i(4, 2)},
				{"unit": &"xiangjun_spear", "coords": Vector2i(3, 2)}, {"unit": &"xiangjun_spear", "coords": Vector2i(5, 2)}])
		"daily_gold_1":
			return _daily("daily_gold_1", "押镖·黄泥小道", 6, 0, {"first_clear": {"gold": 800}, "regular": {"gold": 600}},
				[{"unit": &"xiangjun_spear", "coords": Vector2i(3, 1)}, {"unit": &"xiangjun_spear", "coords": Vector2i(4, 1)},
				{"unit": &"xiangjun_shield", "coords": Vector2i(5, 2)}])
		"daily_gold_2":
			return _daily("daily_gold_2", "押镖·官道风云", 13, 0, {"first_clear": {"gold": 1500}, "regular": {"gold": 1200}},
				[{"unit": &"xiangjun_spear", "coords": Vector2i(3, 1)}, {"unit": &"xiangjun_spear", "coords": Vector2i(5, 1)},
				{"unit": &"xiangjun_shield", "coords": Vector2i(4, 1)}, {"unit": &"xiangjun_shield", "coords": Vector2i(4, 2)},
				{"unit": &"lao_duguan", "coords": Vector2i(4, 0), "elite": true}])
		"daily_mat_1":
			return _daily("daily_mat_1", "奇袭·辎重营", 7, 0, {"first_clear": {"breakthrough_mat": 3}, "regular": {"breakthrough_mat": 2}},
				[{"unit": &"xiangjun_shield", "coords": Vector2i(3, 1)}, {"unit": &"xiangjun_shield", "coords": Vector2i(5, 1)},
				{"unit": &"xiangjun_spear", "coords": Vector2i(4, 2)}])
		"daily_mat_2":
			return _daily("daily_mat_2", "奇袭·军械库", 14, 0, {"first_clear": {"breakthrough_mat": 6}, "regular": {"breakthrough_mat": 4}},
				[{"unit": &"xiangjun_shield", "coords": Vector2i(3, 1)}, {"unit": &"xiangjun_shield", "coords": Vector2i(5, 1)},
				{"unit": &"xiangjun_spear", "coords": Vector2i(3, 2)}, {"unit": &"xiangjun_spear", "coords": Vector2i(5, 2)},
				{"unit": &"lao_duguan", "coords": Vector2i(4, 0), "elite": true}])
	push_error("LevelRegistry: 未知关卡 '%s'" % id)
	return null

## 日常副本公共底（无章节门槛、无次数限制的刷资源关，D34）
static func _daily(id: String, name: String, rec_level: int, exp_override: int, rewards: Dictionary, enemies: Array) -> LevelConfig:
	var l := LevelConfig.new()
	l.id = id
	l.name = name
	l.mode = "daily"
	l.recommended_level = rec_level
	l.grid_size = Vector2i(8, 8)
	l.terrain_map = {Vector2i(2, 2): &"forest", Vector2i(5, 3): &"hill"}
	l.height_map = {Vector2i(5, 3): 1}
	l.win_condition = {"type": "WIPE_OUT"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	l.exp_override = exp_override
	l.required_units = []
	l.roster = [&"lin_chong", &"lu_zhishen", &"wu_song", &"gongsun_sheng", &"wu_yong", &"hua_rong",
		&"li_kui", &"qin_ming", &"zhang_qing", &"hu_sanniang", &"dai_zong", &"shi_qian",
		&"sun_erniang", &"an_daoquan", &"cao_zheng", &"jiao_ting", &"bao_xu", &"yu_baosi",
		&"bai_sheng", &"tang_long", &"shi_yong", &"song_wan", &"du_qian", &"wang_dingliu"]
	l.deploy_zone = Rect2i(0, 6, 8, 2)
	l.max_deploy = 5
	l.enemies.assign(enemies)
	l.rewards = rewards
	return l

# ---------------------------------------------------------------- 第一章：教学序列（占位剧情：梁山初起，官军剿匪）

static func _ch01_01() -> LevelConfig:
	# 教学 1：移动与普攻（教学提示经剧情对话给出）
	var l := _teaching_base("ch01_01", "教学·移动与攻击", 1)
	l.enemies = [
		{"unit": &"xiangjun_recruit", "coords": Vector2i(4, 2)},
		{"unit": &"xiangjun_recruit", "coords": Vector2i(5, 2)},
	]
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "START"}, "actions": [
		{"type": "dialogue", "text": "【教学】左键点蓝色高亮格移动，点红圈敌人攻击。速度快的一方可能连续行动。"},
		{"type": "dialogue", "text": "石勇：官兵围上来了，兄弟们，跟我顶住！"}]}]
	return l

static func _ch01_02() -> LevelConfig:
	# 教学 2：地形与高低差（森林闪避、高台加成、背刺）
	var l := _teaching_base("ch01_02", "教学·地形与走位", 2)
	l.terrain_map = {
		Vector2i(2, 2): &"forest", Vector2i(3, 2): &"forest", Vector2i(2, 3): &"forest",
		Vector2i(5, 3): &"hill", Vector2i(6, 3): &"hill", Vector2i(4, 4): &"barricade",
	}
	l.height_map = {Vector2i(5, 3): 1, Vector2i(6, 3): 1}
	l.enemies = [
		{"unit": &"xiangjun_recruit", "coords": Vector2i(4, 1)},
		{"unit": &"xiangjun_recruit", "coords": Vector2i(5, 1)},
	]
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "START"}, "actions": [
		{"type": "dialogue", "text": "【教学】森林里闪避更高；高台打低处伤害更高；绕到敌人背后是背刺加成。"}]}]
	return l

static func _ch01_03() -> LevelConfig:
	# 教学 3：技能与怒气（Q/W 施放、待机回怒）
	var l := _teaching_base("ch01_03", "教学·技能与怒气", 3)
	l.enemies = [
		{"unit": &"xiangjun_recruit", "coords": Vector2i(4, 2)},
		{"unit": &"xiangjun_recruit", "coords": Vector2i(5, 2)},
		{"unit": &"xiangjun_recruit", "coords": Vector2i(4, 1)},
	]
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "START"}, "actions": [
		{"type": "dialogue", "text": "【教学】Q 放主动技，W 放绝技（怒气满 100）。攻击、受击、待机都会攒怒气。"}]}]
	return l

static func _ch01_04() -> LevelConfig:
	# 坚守关：坚持 5 回合（非歼灭胜利教学）
	var l := _teaching_base("ch01_04", "坚守·山寨大门", 4)
	l.terrain_map = {Vector2i(3, 3): &"camp", Vector2i(4, 3): &"camp",
		Vector2i(2, 2): &"barricade", Vector2i(5, 2): &"barricade"}
	l.win_condition = {"type": "SURVIVE_TURNS", "turns": 5}
	l.enemies = [
		{"unit": &"xiangjun_spear", "coords": Vector2i(3, 0)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(4, 0)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(2, 1)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(5, 1)},
	]
	l.triggers = [
		{"id": "t1", "once": true, "on": {"type": "START"}, "actions": [
			{"type": "dialogue", "text": "【教学】坚守 5 回合即胜，不必硬拼。营帐格每回合回血。"}]},
		{"id": "t2", "once": true, "on": {"type": "TURN", "turn": 3}, "actions": [
			{"type": "dialogue", "text": "官军增援从北面杀到！"},
			{"type": "spawn", "units": [{"unit": &"xiangjun_spear", "coords": Vector2i(4, 0), "team": "enemy"}]}]},
	]
	return l

static func _ch01_05() -> LevelConfig:
	# 章末 BOSS 关：击杀头目即胜（老都管客串小头目）
	var l := _teaching_base("ch01_05", "头目·都监亲兵", 5)
	l.win_condition = {"type": "KILL_BOSS"}
	l.enemies = [
		{"unit": &"lao_duguan", "coords": Vector2i(4, 1), "elite": true, "boss": true},
		{"unit": &"xiangjun_recruit", "coords": Vector2i(3, 2)},
		{"unit": &"xiangjun_recruit", "coords": Vector2i(5, 2)},
		{"unit": &"pai_recruit", "coords": Vector2i(4, 2)},
	]
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "START"}, "actions": [
		{"type": "dialogue", "text": "【教学】斩杀头目即胜。老都管会给亲兵鼓劲，优先集火（F 键标记）。"}]}]
	l.rewards = {"first_clear": {"gold": 800, "breakthrough_mat": 2}, "regular": {"gold": 200}}
	return l

## 第一章公共底：歼灭胜利、教学三人组必出、奖励占位
static func _teaching_base(id: String, name: String, rec_level: int) -> LevelConfig:
	var l := LevelConfig.new()
	l.id = id
	l.name = name
	l.chapter = 1
	l.recommended_level = rec_level
	l.grid_size = Vector2i(8, 8)
	l.win_condition = {"type": "WIPE_OUT"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	l.required_units = [&"shi_yong"]
	l.roster = [&"song_wan", &"du_qian"]
	l.deploy_zone = Rect2i(0, 6, 8, 2)
	l.max_deploy = 4
	l.rewards = {"first_clear": {"gold": 400, "breakthrough_mat": 1}, "regular": {"gold": 120}}
	return l

# ---------------------------------------------------------------- 第二章：七星聚义（生辰纲前奏，占位剧情）

static func _ch02_01() -> LevelConfig:
	var l := LevelConfig.new()
	l.id = "ch02_01"
	l.name = "聚义·东溪村"
	l.chapter = 2
	l.recommended_level = 8
	l.grid_size = Vector2i(8, 8)
	l.terrain_map = {Vector2i(2, 2): &"forest", Vector2i(3, 2): &"forest", Vector2i(4, 4): &"road", Vector2i(4, 3): &"road"}
	l.win_condition = {"type": "WIPE_OUT"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	l.required_units = [&"shi_yong"]
	l.roster = [&"song_wan", &"du_qian", &"wang_dingliu"]
	l.deploy_zone = Rect2i(0, 6, 8, 2)
	l.max_deploy = 4
	l.npc_allies = [{"unit": &"chao_gai_npc", "coords": Vector2i(3, 5)}]
	l.enemies = [
		{"unit": &"xiangjun_spear", "coords": Vector2i(3, 1)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(4, 1)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(5, 1)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(4, 2)},
	]
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "START"}, "actions": [
		{"type": "dialogue", "text": "晁盖：官兵查到东溪村来了！诸位兄弟，随我杀出去！"},
		{"type": "dialogue", "text": "【教学】绿圈是 AI 操控的友军，会自行作战。"}]}]
	l.rewards = {"first_clear": {"gold": 600, "breakthrough_mat": 1}, "regular": {"gold": 150}}
	return l

static func _ch02_02() -> LevelConfig:
	# 章末：护送晁盖突围（ESCORT 胜利教学）
	var l := LevelConfig.new()
	l.id = "ch02_02"
	l.name = "突围·石碣村"
	l.chapter = 2
	l.recommended_level = 10
	l.grid_size = Vector2i(10, 8)
	for y in range(8):
		l.terrain_map[Vector2i(4, y)] = &"road"
	for c in [Vector2i(1, 2), Vector2i(2, 2), Vector2i(7, 3), Vector2i(8, 3)]:
		l.terrain_map[c] = &"forest"
	l.win_condition = {"type": "ESCORT", "unit": "chao_gai_npc", "zone": Rect2i(0, 0, 10, 1)}
	l.lose_conditions = [{"type": "WIPED_OUT"}, {"type": "ESCORT_DEAD", "unit": "chao_gai_npc"}]
	l.required_units = [&"shi_yong"]
	l.roster = [&"song_wan", &"du_qian", &"wang_dingliu"]
	l.deploy_zone = Rect2i(0, 6, 10, 2)
	l.max_deploy = 4
	l.npc_allies = [
		{"unit": &"chao_gai_npc", "coords": Vector2i(4, 6)},
		{"unit": &"liu_tang_npc", "coords": Vector2i(5, 6)},
	]
	l.enemies = [
		{"unit": &"xiangjun_spear", "coords": Vector2i(3, 2)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(5, 2)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(4, 2)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(4, 1)},
		{"unit": &"lao_duguan", "coords": Vector2i(4, 0), "elite": true},
	]
	l.triggers = [
		{"id": "t1", "once": true, "on": {"type": "START"}, "actions": [
			{"type": "dialogue", "text": "【教学】护送晁盖抵达北面村口（第一排）即胜；晁盖阵亡即败。"}]},
		{"id": "t2", "once": true, "on": {"type": "TURN", "turn": 3}, "actions": [
			{"type": "dialogue", "text": "两侧芦苇荡杀出伏兵！"},
			{"type": "spawn", "units": [
				{"unit": &"xiangjun_spear", "coords": Vector2i(1, 3), "team": "enemy"},
				{"unit": &"xiangjun_spear", "coords": Vector2i(8, 2), "team": "enemy"},
			]}]},
	]
	l.rewards = {"first_clear": {"gold": 800, "breakthrough_mat": 2}, "regular": {"gold": 200}}
	return l

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

# ---------------------------------------------------------------- 第四章：大闹清风寨

## 清风寨·花灯夜（S 评价解锁花荣，5.3 挑战关「清风寨」S评价）
static func _ch04_01() -> LevelConfig:
	var l := LevelConfig.new()
	l.id = "ch04_01"
	l.name = "清风寨·花灯夜"
	l.chapter = 4
	l.recommended_level = 14
	l.grid_size = Vector2i(10, 8)
	for y in range(8):
		l.terrain_map[Vector2i(4, y)] = &"road"
	for c in [Vector2i(2, 2), Vector2i(2, 3), Vector2i(7, 2), Vector2i(7, 3), Vector2i(3, 5), Vector2i(6, 5)]:
		l.terrain_map[c] = &"camp"
	for c in [Vector2i(1, 3), Vector2i(8, 3), Vector2i(1, 4), Vector2i(8, 4)]:
		l.terrain_map[c] = &"forest"
	l.win_condition = {"type": "WIPE_OUT"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	l.required_units = []
	l.roster = [&"lin_chong", &"lu_zhishen", &"wu_song", &"gongsun_sheng", &"wu_yong", &"bai_sheng",
		&"li_kui", &"xu_ning", &"shi_yong", &"song_wan", &"du_qian", &"an_daoquan"]
	l.deploy_zone = Rect2i(0, 6, 10, 2)
	l.max_deploy = 5
	l.enemies = [
		{"unit": &"lao_duguan", "coords": Vector2i(4, 1), "elite": true},   # 刘高亲兵头目（占位）
		{"unit": &"xiangjun_spear", "coords": Vector2i(3, 1)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(5, 1)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(4, 2)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(3, 2)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(5, 2)},
	]
	l.triggers = [
		{"id": "t1", "once": true, "on": {"type": "START"}, "actions": [
			{"type": "dialogue", "text": "花灯夜，清风寨前火光冲天。刘高的亲兵把守住各条巷口。"},
			{"type": "dialogue", "text": "【挑战】6 回合内无阵亡通关可获 S 评价，花荣闻讯来投。"}]},
		{"id": "t2", "once": true, "on": {"type": "TURN", "turn": 2}, "actions": [
			{"type": "dialogue", "text": "巷口两侧杀出伏兵！"},
			{"type": "spawn", "units": [
				{"unit": &"xiangjun_spear", "coords": Vector2i(0, 2), "team": "enemy"},
				{"unit": &"xiangjun_spear", "coords": Vector2i(9, 2), "team": "enemy"},
			]}]},
	]
	l.rank_rules = {"s_max_rounds": 6, "s_no_death": true}
	l.unlock_grant = {"unit": &"hua_rong", "requires_rank": "S"}
	l.rewards = {"first_clear": {"gold": 1000, "breakthrough_mat": 2}, "regular": {"gold": 250}}
	return l

## 霹雳火·秦明（通关解锁秦明，5.3 挑战关「霹雳火」通关）
static func _ch04_02() -> LevelConfig:
	var l := LevelConfig.new()
	l.id = "ch04_02"
	l.name = "霹雳火·秦明"
	l.chapter = 4
	l.recommended_level = 16
	l.grid_size = Vector2i(10, 8)
	for c in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3)]:
		l.terrain_map[c] = &"road"
	for c in [Vector2i(2, 2), Vector2i(7, 2), Vector2i(2, 4), Vector2i(7, 4)]:
		l.terrain_map[c] = &"hill"
	l.height_map = {Vector2i(2, 2): 1, Vector2i(7, 2): 1, Vector2i(2, 4): 1, Vector2i(7, 4): 1}
	l.win_condition = {"type": "KILL_BOSS"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	l.required_units = []
	l.roster = [&"lin_chong", &"lu_zhishen", &"wu_song", &"gongsun_sheng", &"wu_yong", &"bai_sheng",
		&"li_kui", &"xu_ning", &"hua_rong", &"shi_yong", &"song_wan", &"du_qian", &"an_daoquan"]
	l.deploy_zone = Rect2i(0, 6, 10, 2)
	l.max_deploy = 5
	l.enemies = [
		{"unit": &"qin_ming", "coords": Vector2i(4, 1), "elite": true, "boss": true},
		{"unit": &"xiangjun_spear", "coords": Vector2i(3, 1)},
		{"unit": &"xiangjun_spear", "coords": Vector2i(5, 1)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(3, 2)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(5, 2)},
	]
	l.triggers = [
		{"id": "t1", "once": true, "on": {"type": "START"}, "actions": [
			{"type": "dialogue", "text": "秦明：「反贼休走，吃我一棒！」——霹雳火当先来搦战。"},
			{"type": "dialogue", "text": "【挑战】击退秦明即胜。他攻高性烈，半血后愈发凶猛。"}]},
		{"id": "t2", "once": true, "on": {"type": "HP_BELOW", "unit": "qin_ming", "ratio": 0.5}, "actions": [
			{"type": "dialogue", "text": "秦明怒火攻心，狼牙棒势如霹雳！"},
			{"type": "buff", "unit": "qin_ming", "field": &"atk", "value": 20, "duration": 99, "name": "霹雳怒火"}]},
	]
	l.unlock_grant = {"unit": &"qin_ming"}
	l.rewards = {"first_clear": {"gold": 1200, "breakthrough_mat": 3}, "regular": {"gold": 300}}
	return l

## 挑战关·东昌府（通关解锁张清，5.3）
static func _challenge_dongchang() -> LevelConfig:
	var l := LevelConfig.new()
	l.id = "challenge_dongchang"
	l.name = "挑战·东昌府张清"
	l.mode = "challenge"
	l.chapter = 4
	l.recommended_level = 18
	l.grid_size = Vector2i(10, 8)
	for c in [Vector2i(4, 1), Vector2i(4, 2), Vector2i(5, 1), Vector2i(5, 2)]:
		l.terrain_map[c] = &"hill"
	l.height_map = {Vector2i(4, 1): 1, Vector2i(4, 2): 1, Vector2i(5, 1): 1, Vector2i(5, 2): 1}
	for c in [Vector2i(1, 4), Vector2i(2, 4), Vector2i(7, 4), Vector2i(8, 4)]:
		l.terrain_map[c] = &"forest"
	l.win_condition = {"type": "KILL_BOSS"}
	l.lose_conditions = [{"type": "WIPED_OUT"}]
	l.required_units = []
	l.roster = [&"lin_chong", &"lu_zhishen", &"wu_song", &"gongsun_sheng", &"wu_yong", &"bai_sheng",
		&"li_kui", &"xu_ning", &"hua_rong", &"qin_ming", &"shi_yong", &"song_wan", &"du_qian", &"an_daoquan"]
	l.deploy_zone = Rect2i(0, 6, 10, 2)
	l.max_deploy = 5
	l.enemies = [
		{"unit": &"zhang_qing", "coords": Vector2i(4, 1), "elite": true, "boss": true},
		{"unit": &"gong_wang", "coords": Vector2i(3, 2)},
		{"unit": &"ding_desun", "coords": Vector2i(5, 2)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(3, 3)},
		{"unit": &"xiangjun_shield", "coords": Vector2i(5, 3)},
	]
	l.triggers = [{"id": "t1", "once": true, "on": {"type": "START"}, "actions": [
		{"type": "dialogue", "text": "没羽箭张清坐镇东昌府，飞石打人百发百中。"},
		{"type": "dialogue", "text": "【挑战】龚旺、丁得孙两员副将护翼左右，先剪羽翼再擒主将。"}]}]
	l.unlock_grant = {"unit": &"zhang_qing"}
	l.rewards = {"first_clear": {"gold": 1500, "breakthrough_mat": 3}, "regular": {"gold": 350}}
	return l
