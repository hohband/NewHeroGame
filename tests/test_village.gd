extends GutTest
## 山寨经营雏形：产出/派驻/升级/通关收获（策划文档第三章、决策日志 D33）

var loader: GameDataLoader
var profile: PlayerProfile

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	profile = PlayerProfile.new_default(loader)

func test_default_village_and_production() -> void:
	var v := VillageSystem.get_village(profile)
	assert_eq(int(v[&"juyiting"]["level"]), 1)
	assert_eq(int(VillageSystem.production(profile, &"juyiting")["gold"]), 100)
	assert_eq(int(VillageSystem.production(profile, &"tiejiangpu")["breakthrough_mat"]), 1)
	assert_eq(int(VillageSystem.production(profile, &"yanwuchang")["exp"]), 30)

func test_assign_bonus_and_tang_long() -> void:
	VillageSystem.assign(profile, &"juyiting", &"shi_yong")
	assert_eq(int(VillageSystem.production(profile, &"juyiting")["gold"]), 125, "派驻 +25%")
	# 汤隆驻铁匠铺再 +25%
	profile.add_hero(Hero.new(&"tang_long", &"green"))
	VillageSystem.assign(profile, &"tiejiangpu", &"tang_long")
	assert_eq(int(VillageSystem.production(profile, &"tiejiangpu")["breakthrough_mat"]), 2, "汤隆铁匠铺 1×1.5 → 2（4.2）")

func test_assign_exclusivity() -> void:
	VillageSystem.assign(profile, &"juyiting", &"shi_yong")
	VillageSystem.assign(profile, &"tiejiangpu", &"shi_yong")
	assert_eq(String(VillageSystem.get_village(profile)[&"juyiting"]["assigned"]), "", "一人只占一岗，旧岗自动卸下")
	assert_eq(String(VillageSystem.get_village(profile)[&"tiejiangpu"]["assigned"]), "shi_yong")

func test_upgrade() -> void:
	profile.gold = 1200
	assert_true(VillageSystem.can_upgrade(profile, &"juyiting"))
	assert_true(VillageSystem.upgrade(profile, &"juyiting"))
	assert_eq(profile.gold, 700, "1→2 级 500 金")
	assert_eq(int(VillageSystem.production(profile, &"juyiting")["gold"]), 200)
	VillageSystem.upgrade(profile, &"juyiting")
	assert_false(VillageSystem.can_upgrade(profile, &"juyiting"), "满级 3 不可再升")

func test_collect_via_flow() -> void:
	# 通关一次：山寨收获一轮（金币+材料+全员经验）
	VillageSystem.assign(profile, &"juyiting", &"shi_yong")
	var gold_before: int = profile.gold
	var mats_before: int = int(profile.items.get("breakthrough_mat", 0))
	var exp_before: int = profile.get_hero(&"shi_yong").exp
	var s := Flow.apply_battle_result(profile, LevelRegistry.get_level("ch01_01"),
		{"won": true, "winner": Unit.Team.PLAYER, "achievements": []}, [], loader)
	assert_eq(profile.gold, gold_before + 400 + 125, "通关奖励 400 + 聚义厅派驻产出 125")
	assert_eq(int(profile.items["breakthrough_mat"]), mats_before + 1 + 1, "首通 1 + 铁匠铺 1")
	assert_eq(profile.get_hero(&"shi_yong").exp, exp_before + 30, "演武场全员经验 30（上阵经验另有 50 给上阵者）")
	assert_true(s.has("village"))
