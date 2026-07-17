extends GutTest
## 第四章与评价系统：S/A 评价规则、挑战关武将解锁（花荣/秦明/张清，决策日志 D37）

var loader: GameDataLoader
var profile: PlayerProfile

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	profile = PlayerProfile.new_default(loader)

func _manager(level: LevelConfig) -> BattleManager:
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, level)
	m.rolls = FixedRollSource.new()
	return m

# ---------------------------------------------------------------- 评价规则

func test_rank_s_when_fast_and_no_death() -> void:
	var m := _manager(LevelRegistry.get_level("ch04_01"))
	m.round_count = 5
	var r := m.compute_result(Unit.Team.PLAYER)
	assert_eq(String(r["rank"]), "S", "≤6 回合且无阵亡 = S")

func test_rank_a_when_slow() -> void:
	var m := _manager(LevelRegistry.get_level("ch04_01"))
	m.round_count = 7
	assert_eq(String(m.compute_result(Unit.Team.PLAYER)["rank"]), "A", "超回合降 A")

func test_rank_a_when_death() -> void:
	var m := _manager(LevelRegistry.get_level("ch04_01"))
	m.round_count = 4
	m._player_deaths = 1
	assert_eq(String(m.compute_result(Unit.Team.PLAYER)["rank"]), "A", "有阵亡降 A")

func test_rank_a_for_unranked_level() -> void:
	var m := _manager(LevelRegistry.get_level("ch01_01"))
	assert_eq(String(m.compute_result(Unit.Team.PLAYER)["rank"]), "A", "无评价规则的关卡通关即 A")

# ---------------------------------------------------------------- 挑战关解锁

func test_hua_rong_unlocked_by_s_rank() -> void:
	var level := LevelRegistry.get_level("ch04_01")
	var m := _manager(level)
	m.round_count = 5
	var s := Flow.apply_battle_result(profile, level, m.compute_result(Unit.Team.PLAYER), [], loader)
	assert_true(profile.has_hero(&"hua_rong"), "S 评价解锁花荣（5.3）")
	assert_true((s["unlocked"] as Array).has(&"hua_rong"))

func test_hua_rong_not_unlocked_by_a_rank() -> void:
	var level := LevelRegistry.get_level("ch04_01")
	var m := _manager(level)
	m.round_count = 8   # A 评价
	var s := Flow.apply_battle_result(profile, level, m.compute_result(Unit.Team.PLAYER), [], loader)
	assert_false(profile.has_hero(&"hua_rong"), "A 评价不解锁花荣")
	assert_eq((s["unlocked"] as Array).size(), 0)

func test_qin_ming_unlocked_by_clear() -> void:
	var level := LevelRegistry.get_level("ch04_02")
	var m := _manager(level)
	Flow.apply_battle_result(profile, level, m.compute_result(Unit.Team.PLAYER), [], loader)
	assert_true(profile.has_hero(&"qin_ming"), "通关霹雳火解锁秦明")

func test_zhang_qing_unlocked_by_challenge() -> void:
	var level := LevelRegistry.get_level("challenge_dongchang")
	var m := _manager(level)
	assert_not_null(m.boss_unit)
	assert_eq(m.boss_unit.data.unit_id, &"zhang_qing")
	Flow.apply_battle_result(profile, level, m.compute_result(Unit.Team.PLAYER), [], loader)
	assert_true(profile.has_hero(&"zhang_qing"), "通关东昌府解锁张清")

# ---------------------------------------------------------------- 第四章内容

func test_ch04_levels_valid() -> void:
	for id in ["ch04_01", "ch04_02", "challenge_dongchang"]:
		var l := LevelRegistry.get_level(id)
		assert_not_null(l)
		assert_gt(l.enemies.size(), 0)
		for spec in l.enemies:
			assert_not_null(loader.get_unit(spec["unit"]), "%s 敌方 %s 在表内" % [id, spec["unit"]])

func test_xu_ning_granted_on_ch3_clear() -> void:
	# 徐宁 = 第4章剧情加入：通关第三章终关（生辰纲）抵达第四章时发放（D32 规则）
	var m := _manager(LevelRegistry.get_level("ch03_01"))
	var s := Flow.apply_battle_result(profile, LevelRegistry.get_level("ch03_01"),
		m.compute_result(Unit.Team.PLAYER), [], loader)
	assert_true(profile.has_hero(&"xu_ning"), "徐宁第4章剧情加入")
	assert_eq(int(profile.progress["chapter"]), 4, "进入第四章")
	assert_true((s["unlocked"] as Array).has(&"xu_ning"))
