extends GutTest
## 梁山远征（第九章 Roguelike 爬塔）+ 专属武器形态质变（4.2/4.4，决策日志 D35）

var loader: GameDataLoader
var profile: PlayerProfile

func before_each() -> void:
	loader = autofree(GameDataLoader.new())
	loader.load_all()
	profile = PlayerProfile.new_default(loader)

# ---------------------------------------------------------------- 远征

func test_new_run_picks_top4() -> void:
	profile.add_hero(Hero.new(&"lin_chong", &"orange"))
	profile.get_hero(&"lin_chong").level = 9
	var run := ExpeditionSystem.new_run(profile)
	assert_eq((run["team"] as Array).size(), 4)
	assert_eq(run["team"][0]["unit_id"], &"lin_chong", "等级最高者优先")

func test_floor_scaling() -> void:
	var run := {"floor": 5, "team": [], "buffs": []}
	var l := ExpeditionSystem.build_floor(run, loader)
	assert_eq(l.mode, "expedition")
	assert_gt(l.enemies.size(), 0)
	var mult: float = l.enemies[0]["stat_mult"]
	assert_almost_eq(mult, 1.48, 0.001, "第 5 层敌人属性 ×(1+0.12×4)")

func test_floor_10_has_boss() -> void:
	var l := ExpeditionSystem.build_floor({"floor": 10, "team": [], "buffs": []}, loader)
	assert_true(l.enemies.any(func(s): return s.get("boss", false)), "第 10 层杨志压阵")

func test_carryover_and_buffs() -> void:
	var run := {"floor": 2, "team": [{"unit_id": &"shi_yong", "hp_ratio": 0.5, "alive": true}],
		"buffs": [{"field": &"atk", "value": 10}]}
	var l := ExpeditionSystem.build_floor(run, loader)
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, l)
	var h := profile.get_hero(&"shi_yong")
	var u := m.deploy_unit(&"shi_yong", Vector2i(3, 6), h)
	ExpeditionSystem.apply_carryover(m, run)
	assert_eq(u.hp, u.data.hp / 2, "生命按 50% 继承")
	assert_eq(u.get_stat_mod(&"atk"), 10, "远征增益上身")

func test_record_and_reward_choice() -> void:
	var run := {"floor": 1, "team": [{"unit_id": &"shi_yong", "hp_ratio": 1.0, "alive": true}], "buffs": []}
	var l := ExpeditionSystem.build_floor(run, loader)
	var m: BattleManager = autofree(BattleManager.new())
	m.setup_level(loader, l)
	var u := m.deploy_unit(&"shi_yong", Vector2i(3, 6))
	u.hp = u.data.hp / 4
	ExpeditionSystem.record_floor_result(m, run)
	assert_eq(run["team"][0]["hp_ratio"], 0.25)
	ExpeditionSystem.apply_reward_choice(run, "heal")
	assert_eq(run["team"][0]["hp_ratio"], 0.55, "休整回复 30%")
	ExpeditionSystem.apply_reward_choice(run, "atk_up")
	assert_eq((run["buffs"] as Array).size(), 1)

func test_finish_run_rewards() -> void:
	var run := {"floor": 7, "team": [], "buffs": []}
	var gold_before: int = profile.gold
	var summary := ExpeditionSystem.finish_run(profile, run)
	assert_eq(int(summary["floors_cleared"]), 6)
	assert_eq(profile.gold, gold_before + 1200, "每层 200 金币")
	assert_eq(int(profile.progress["expedition_best"]), 6)
	assert_true(run["finished"])

# ---------------------------------------------------------------- 专属武器

func test_signature_unlock_rules() -> void:
	var h := Hero.new(&"tang_long", &"green")
	profile.add_hero(h)
	profile.items["breakthrough_mat"] = 6
	assert_false(SignatureWeapon.can_unlock(h, profile), "未满 3 星不可解锁")
	h.star = 3
	assert_true(SignatureWeapon.can_unlock(h, profile))
	assert_true(SignatureWeapon.unlock(h, profile))
	assert_eq(int(profile.items["breakthrough_mat"]), 1)
	assert_true(h.has_signature_weapon)
	assert_false(SignatureWeapon.can_unlock(h, profile), "不可重复解锁")

func test_goulian_splash_with_signature() -> void:
	# 汤隆专武：act_goulian 破甲溅射 2 格（单体→群体，4.4 保值设计）
	var grid = autofree(UnitFactory.make_grid(loader, Vector2i(6, 6)))
	var tl: Unit = autofree(Unit.new())
	tl.setup(loader.get_unit(&"tang_long"), Unit.Team.PLAYER, Vector2i(0, 0))
	tl.data.range_min = 1
	tl.data.range_max = 2
	grid.place_unit(tl, Vector2i(0, 0))
	var h := Hero.new(&"tang_long", &"green")
	h.has_signature_weapon = true
	tl.hero = h
	var e1 = autofree(UnitFactory.make_unit(50, 60, 40, Unit.Team.ENEMY, Vector2i(2, 0)))
	var e2 = autofree(UnitFactory.make_unit(50, 60, 40, Unit.Team.ENEMY, Vector2i(3, 1)))
	var e3 = autofree(UnitFactory.make_unit(50, 60, 40, Unit.Team.ENEMY, Vector2i(5, 5)))
	grid.place_unit(e1, Vector2i(2, 0))
	grid.place_unit(e2, Vector2i(3, 1))
	grid.place_unit(e3, Vector2i(5, 5))
	var m: BattleManager = autofree(BattleManager.new())
	m.setup(loader, grid, [tl, e1, e2, e3])
	m.rolls = FixedRollSource.new()
	m.submit_command(SkillCommand.new(tl, loader.get_skill(&"act_goulian"), Vector2i(2, 0)))
	assert_eq(e1.get_stat_mod(&"def"), -25, "主目标破甲 25%")
	assert_eq(e2.get_stat_mod(&"def"), -25, "2 格内溅射破甲（专武质变）")
	assert_eq(e3.get_stat_mod(&"def"), 0, "范围外不受影响")

func test_goulian_no_splash_without_signature() -> void:
	var grid = autofree(UnitFactory.make_grid(loader, Vector2i(6, 6)))
	var tl: Unit = autofree(Unit.new())
	tl.setup(loader.get_unit(&"tang_long"), Unit.Team.PLAYER, Vector2i(0, 0))
	grid.place_unit(tl, Vector2i(0, 0))
	var e1 = autofree(UnitFactory.make_unit(50, 60, 40, Unit.Team.ENEMY, Vector2i(2, 0)))
	var e2 = autofree(UnitFactory.make_unit(50, 60, 40, Unit.Team.ENEMY, Vector2i(3, 1)))
	grid.place_unit(e1, Vector2i(2, 0))
	grid.place_unit(e2, Vector2i(3, 1))
	var m: BattleManager = autofree(BattleManager.new())
	m.setup(loader, grid, [tl, e1, e2])
	m.rolls = FixedRollSource.new()
	m.submit_command(SkillCommand.new(tl, loader.get_skill(&"act_goulian"), Vector2i(2, 0)))
	assert_eq(e1.get_stat_mod(&"def"), -25)
	assert_eq(e2.get_stat_mod(&"def"), 0, "无专武则不溅射")

func test_signature_weapon_saves() -> void:
	var h := Hero.new(&"tang_long", &"green")
	h.has_signature_weapon = true
	var h2 := Hero.from_dict(h.to_dict())
	assert_true(h2.has_signature_weapon, "专武状态入档")
