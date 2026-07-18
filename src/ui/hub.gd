extends Control
## 山寨主界面（垂直切片核心循环的枢纽）：主菜单 / 关卡选择 / 武将养成 / 招募。
## 占位 UI（M2 品质），正式视觉包装在后续打磨阶段。

func _ready() -> void:
	if SaveSystem.profile == null and SaveSystem.has_save():
		SaveSystem.load_game()
	if SaveSystem.profile != null:
		AudioManager.apply_settings(SaveSystem.profile.get_settings())
	AudioManager.play_bgm("bgm_main")
	_build_main()
	_focus_first()

func _clear() -> void:
	for c in get_children():
		c.queue_free()

func _panel(title_text: String) -> VBoxContainer:
	_clear()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(560, 0)
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var sep := HSeparator.new()
	vbox.add_child(sep)
	return vbox

## 手柄/键盘焦点：每个界面默认聚焦第一个按钮（Deck 适配，M2）；顺带全量接 UI 音效
func _focus_first() -> void:
	var queue := get_children()
	var first: Button = null
	while not queue.is_empty():
		var c: Node = queue.pop_front()
		if c is Button:
			if not (c as Button).pressed.is_connected(_ui_click):
				(c as Button).pressed.connect(_ui_click)
			if not (c as Button).mouse_entered.is_connected(_ui_hover):
				(c as Button).mouse_entered.connect(_ui_hover)
			if not (c as Button).focus_entered.is_connected(_ui_hover):
				(c as Button).focus_entered.connect(_ui_hover)
			if first == null and not c.disabled:
				first = c
		queue.append_array(c.get_children())
	if first != null:
		first.grab_focus()

func _ui_click() -> void:
	AudioManager.play("sfx_ui_click")

func _ui_hover() -> void:
	AudioManager.play("sfx_ui_hover")

# ---------------------------------------------------------------- 设置（音量）

func _build_settings() -> void:
	var vbox := _panel("设置")
	var s := SaveSystem.profile.get_settings()
	for entry in [
		["总音量", "volume_master"],
		["音效", "volume_sfx"],
		["音乐（BGM 待补）", "volume_music"],
	]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = entry[0]
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = float(s[entry[1]])
		slider.custom_minimum_size = Vector2(320, 0)
		var key := String(entry[1])
		slider.value_changed.connect(func(v: float):
			SaveSystem.profile.get_settings()[key] = v
			AudioManager.apply_settings(SaveSystem.profile.get_settings())
			SaveSystem.save_game())
		row.add_child(slider)
		vbox.add_child(row)
	var mute := CheckBox.new()
	mute.text = "静音"
	mute.button_pressed = bool(s.get("mute", false))
	mute.toggled.connect(func(on: bool):
		SaveSystem.profile.get_settings()["mute"] = on
		AudioManager.apply_settings(SaveSystem.profile.get_settings())
		SaveSystem.save_game())
	vbox.add_child(mute)
	_back_row(vbox)
	_focus_first()

# ---------------------------------------------------------------- 主菜单

func _build_main() -> void:
	var vbox := _panel("水浒战棋\n替天行道 · 聚义梁山")
	if SaveSystem.profile == null:
		var btn := Button.new()
		btn.text = "开始新游戏"
		btn.pressed.connect(func():
			SaveSystem.new_game(DataLoader)
			SaveSystem.save_game()
			_build_main())
		vbox.add_child(btn)
		return
	var res := Label.new()
	res.text = _resource_text()
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(res)
	for entry in [
		["出 征（主线/日常）", _build_levels],
		["演武场（异步 PVP）", _build_arena],
		["梁山远征（爬塔）", _build_expedition],
		["武 将（养成）", _build_roster],
		["山 寨（经营）", _build_village],
		["设 置（音量）", _build_settings],
	]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(entry[1])
		vbox.add_child(b)
	var new_btn := Button.new()
	new_btn.text = "重新开局（清空存档）"
	new_btn.pressed.connect(func():
		SaveSystem.new_game(DataLoader)
		SaveSystem.save_game()
		_build_main())
	vbox.add_child(new_btn)
	_focus_first()

func _resource_text() -> String:
	var p := SaveSystem.profile
	return "金币 %d ｜ 碎片 %d ｜ 技能书 %d ｜ 突破材料 %d ｜ 第 %d 章" % [
		p.gold, int(p.items.get("shard", 0)), int(p.items.get("skill_book", 0)),
		int(p.items.get("breakthrough_mat", 0)), int(p.progress.get("chapter", 1))]

func _back_row(vbox: VBoxContainer) -> void:
	var b := Button.new()
	b.text = "返 回"
	b.pressed.connect(_build_main)
	vbox.add_child(b)

# ---------------------------------------------------------------- 关卡选择

func _build_levels() -> void:
	var vbox := _panel("选择关卡")
	var chapter := int(SaveSystem.profile.progress.get("chapter", 1))
	var cleared: Array = SaveSystem.profile.progress.get("cleared", [])
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 420)
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	var story_label := Label.new()
	story_label.text = "—— 主线 ——"
	list.add_child(story_label)
	for id in LevelRegistry.list_ids():
		if id == "debug_01":
			continue
		var l := LevelRegistry.get_level(id)
		var locked: bool = l.chapter > chapter
		var b := Button.new()
		var mark := "✓ " if cleared.has(id) else ""
		b.text = "%s第%d章 · %s（推荐 Lv.%d）%s" % [mark, l.chapter, l.name, l.recommended_level, "　🔒" if locked else ""]
		b.disabled = locked
		var level_id := id
		b.pressed.connect(func():
			GameState.current_level_id = level_id
			get_tree().change_scene_to_file("res://scenes/battle/battle.tscn"))
		list.add_child(b)
	# 终章双路线提示（第七章解锁后显示结局状态）
	if chapter >= 7:
		var end_label := Label.new()
		var ending := String(SaveSystem.profile.progress.get("ending", ""))
		end_label.text = "—— 大聚义·路线抉择已解锁 ——" if ending == "" \
			else "—— 已达成结局：%s（可重打另一路线）——" % ("招安" if ending == "zhaoan" else "不招安")
		list.add_child(end_label)
	var daily_label := Label.new()
	daily_label.text = "—— 日常副本（刷资源，自动战斗主战场）——"
	list.add_child(daily_label)
	for id in LevelRegistry.list_daily_ids():
		var l := LevelRegistry.get_level(id)
		var b := Button.new()
		b.text = "%s（推荐 Lv.%d）" % [l.name, l.recommended_level]
		var level_id := id
		b.pressed.connect(func():
			GameState.current_level_id = level_id
			get_tree().change_scene_to_file("res://scenes/battle/battle.tscn"))
		list.add_child(b)
	var ch_label := Label.new()
	ch_label.text = "—— 挑战关（高难，解锁名将）——"
	list.add_child(ch_label)
	for id in LevelRegistry.list_challenge_ids():
		var l := LevelRegistry.get_level(id)
		var b := Button.new()
		var owned := SaveSystem.profile.has_hero(StringName(l.unlock_grant.get("unit", "")))
		b.text = "%s%s（推荐 Lv.%d）" % ["✓ " if owned else "", l.name, l.recommended_level]
		var level_id := id
		b.pressed.connect(func():
			GameState.current_level_id = level_id
			get_tree().change_scene_to_file("res://scenes/battle/battle.tscn"))
		list.add_child(b)
	_back_row(vbox)
	_focus_first()

# ---------------------------------------------------------------- 演武场（异步 PVP，8.6）

func _build_arena() -> void:
	var defense := ArenaSystem.get_defense(SaveSystem.profile)
	var template := String(defense.get("template", "steady"))
	var vbox := _panel("演武场　攻方手动 vs 守方预设阵容 AI")
	var team_label := Label.new()
	var names: Array[String] = []
	for id in defense.get("team", []):
		names.append(DataLoader.get_unit(StringName(id)).name)
	team_label.text = "守方阵容（等级前 4）：%s" % "、".join(names)
	vbox.add_child(team_label)
	var tpl_btn := Button.new()
	tpl_btn.text = "守方策略模板：%s（点击切换）" % ArenaSystem.TEMPLATES[template]["name"]
	tpl_btn.pressed.connect(func():
		var idx := (ArenaSystem.TEMPLATE_ORDER.find(template) + 1) % ArenaSystem.TEMPLATE_ORDER.size()
		ArenaSystem.set_template(SaveSystem.profile, ArenaSystem.TEMPLATE_ORDER[idx])
		SaveSystem.save_game()
		_build_arena())
	vbox.add_child(tpl_btn)
	var desc := Label.new()
	desc.text = _template_desc(template)
	vbox.add_child(desc)
	var fight := Button.new()
	fight.text = "开始切磋（挑战自己的守方阵容）"
	fight.pressed.connect(func():
		GameState.custom_level = ArenaSystem.build_arena_level(SaveSystem.profile, DataLoader)
		get_tree().change_scene_to_file("res://scenes/battle/battle.tscn"))
	vbox.add_child(fight)
	_back_row(vbox)
	_focus_first()

func _template_desc(template: String) -> String:
	match template:
		"steady":
			return "稳健防守：危险度×1.5、伤害期望×0.8、远离布阵区每格 −10（远程+治疗阵）"
		"aggressive":
			return "激进突进：伤害期望×1.3、击杀奖励×1.5、危险度×0.6（爆发阵）"
		"protect_core":
			return "保护核心：队友距核心 ≤2 格 +20、核心承伤风险 ×2（四保一阵）"
	return ""

# ---------------------------------------------------------------- 梁山远征（Roguelike 爬塔，第九章）

func _build_expedition() -> void:
	var best := int(SaveSystem.profile.progress.get("expedition_best", 0))
	var vbox := _panel("梁山远征　最佳纪录：%d 层" % best)
	var tip := Label.new()
	tip.text = "等级前 4 的好汉组队连闯 10 层，生命跨层继承、阵亡不进下赛季。\n每层胜利后三选一奖励，敌人逐层变强。"
	vbox.add_child(tip)
	var start := Button.new()
	start.text = "开始新的远征"
	start.pressed.connect(func():
		GameState.expedition = ExpeditionSystem.new_run(SaveSystem.profile)
		get_tree().change_scene_to_file("res://scenes/battle/battle.tscn"))
	vbox.add_child(start)
	_back_row(vbox)
	_focus_first()

# ---------------------------------------------------------------- 武将养成

func _build_roster() -> void:
	var vbox := _panel("武将　（%s）" % _resource_text())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 400)
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	var prog := DataLoader.progression
	for id in SaveSystem.profile.heroes:
		var h: Hero = SaveSystem.profile.get_hero(id)
		var ud := DataLoader.get_unit(id)
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		var info := Label.new()
		info.text = "%s %s　Lv.%d　%s星" % [ud.name, ud.nickname, h.level, _stars(h.star)]
		info.custom_minimum_size = Vector2(200, 0)
		box.add_child(info)
		# 升星
		var star_btn := Button.new()
		var star_cost := Progression.star_up_cost(h, prog)
		star_btn.text = "升星(%d碎片)" % star_cost
		star_btn.disabled = not Progression.can_star_up(h, int(SaveSystem.profile.items.get("shard", 0)), prog)
		star_btn.pressed.connect(func():
			SaveSystem.profile.spend_item(&"shard", star_cost)
			Progression.star_up(h, prog)
			AudioManager.play("sfx_levelup")
			SaveSystem.save_game()
			_build_roster())
		box.add_child(star_btn)
		# 突破
		var bt_btn := Button.new()
		bt_btn.text = "突破品质" if h.quality != &"orange" else "已满品质"
		bt_btn.disabled = not Progression.can_breakthrough(h, prog) \
			or int(SaveSystem.profile.items.get("breakthrough_mat", 0)) < 3
		bt_btn.pressed.connect(func():
			SaveSystem.profile.spend_item(&"breakthrough_mat", 3)
			Progression.breakthrough(h, prog)
			AudioManager.play("sfx_unlock")
			SaveSystem.save_game()
			_build_roster())
		box.add_child(bt_btn)
		# 武器强化
		var en_btn := Button.new()
		var en_cost := Progression.weapon_enhance_cost(h, prog)
		en_btn.text = "强化+%d(%d金)" % [h.weapon_enhance, en_cost]
		en_btn.disabled = h.weapon_enhance >= int(prog["weapon_enhance_max"]) or SaveSystem.profile.gold < en_cost
		en_btn.pressed.connect(func():
			SaveSystem.profile.spend_gold(en_cost)
			Progression.weapon_enhance(h, prog)
			AudioManager.play("sfx_levelup")
			SaveSystem.save_game()
			_build_roster())
		box.add_child(en_btn)
		# 技能升级（招牌技能）
		var sk_btn := Button.new()
		var sid := ud.skill_signature
		var sk_cost := Progression.skill_upgrade_cost(h, sid, prog)
		sk_btn.text = "技能Lv.%d(%d书)" % [h.skill_level(sid), sk_cost]
		sk_btn.disabled = h.skill_level(sid) >= int(prog["skill_level_max"]) \
			or int(SaveSystem.profile.items.get("skill_book", 0)) < sk_cost
		sk_btn.pressed.connect(func():
			SaveSystem.profile.spend_item(&"skill_book", sk_cost)
			Progression.skill_upgrade(h, sid, prog)
			AudioManager.play("sfx_levelup")
			SaveSystem.save_game()
			_build_roster())
		box.add_child(sk_btn)
		# 专属武器（4.2/4.4：技能形态质变）
		var sw_btn := Button.new()
		sw_btn.text = "专武✓" if h.has_signature_weapon else "专武(%d材料)" % SignatureWeapon.UNLOCK_MAT_COST
		sw_btn.disabled = h.has_signature_weapon or not SignatureWeapon.can_unlock(h, SaveSystem.profile)
		var hero_ref := h
		sw_btn.pressed.connect(func():
			SignatureWeapon.unlock(hero_ref, SaveSystem.profile)
			AudioManager.play("sfx_unlock")
			SaveSystem.save_game()
			_build_roster())
		box.add_child(sw_btn)
		list.add_child(box)
	# 招募（聚义厅）
	var any_recruit := false
	for id in DataLoader.units:
		if Flow.can_recruit(SaveSystem.profile, id, DataLoader):
			if not any_recruit:
				var sep := HSeparator.new()
				list.add_child(sep)
				var tip := Label.new()
				tip.text = "—— 聚义厅招募（碎片 ×%d）——" % Flow.RECRUIT_COST
				list.add_child(tip)
				any_recruit = true
			var ud := DataLoader.get_unit(id)
			var b := Button.new()
			b.text = "招募 %s %s" % [ud.name, ud.nickname]
			b.pressed.connect(func():
				Flow.recruit(SaveSystem.profile, id, DataLoader)
				AudioManager.play("sfx_unlock")
				SaveSystem.save_game()
				_build_roster())
			list.add_child(b)
	_back_row(vbox)
	_focus_first()

func _stars(n: int) -> String:
	return "★".repeat(n)

# ---------------------------------------------------------------- 山寨经营

func _build_village() -> void:
	var vbox := _panel("山寨经营　（%s）" % _resource_text())
	var village := VillageSystem.get_village(SaveSystem.profile)
	for id in VillageSystem.BUILDING_NAMES:
		var b: Dictionary = village[id]
		var prod := VillageSystem.production(SaveSystem.profile, id)
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		var info := Label.new()
		info.custom_minimum_size = Vector2(290, 0)
		var assigned := String(b.get("assigned", ""))
		var assigned_name := "空岗" if assigned == "" else DataLoader.get_unit(StringName(assigned)).name
		info.text = "%s Lv.%d｜派驻：%s｜每通关：%s" % [
			VillageSystem.BUILDING_NAMES[id], int(b["level"]), assigned_name, _prod_text(prod)]
		box.add_child(info)
		# 升级
		var up_btn := Button.new()
		var maxed := int(b["level"]) >= VillageSystem.MAX_LEVEL
		up_btn.text = "已满级" if maxed else "升级(%d金)" % VillageSystem.upgrade_cost(int(b["level"]))
		up_btn.disabled = maxed or not VillageSystem.can_upgrade(SaveSystem.profile, id)
		var bid: StringName = id
		up_btn.pressed.connect(func():
			VillageSystem.upgrade(SaveSystem.profile, bid)
			SaveSystem.save_game()
			_build_village())
		box.add_child(up_btn)
		# 派驻（循环切换：空岗 → 各武将）
		var as_btn := Button.new()
		as_btn.text = "调换岗位"
		as_btn.pressed.connect(func():
			_cycle_assign(bid)
			SaveSystem.save_game()
			_build_village())
		box.add_child(as_btn)
		vbox.add_child(box)
	var tip := Label.new()
	tip.text = "派驻加成 +25%；汤隆驻铁匠铺再 +25%。每通关一次关卡收获一轮。"
	vbox.add_child(tip)
	_back_row(vbox)
	_focus_first()

func _prod_text(prod: Dictionary) -> String:
	if prod.has("gold"):
		return "金币 %d" % int(prod["gold"])
	if prod.has("breakthrough_mat"):
		return "突破材料 %d" % int(prod["breakthrough_mat"])
	if prod.has("exp"):
		return "全员经验 %d" % int(prod["exp"])
	return ""

func _cycle_assign(building: StringName) -> void:
	var village := VillageSystem.get_village(SaveSystem.profile)
	var current := String(village[building].get("assigned", ""))
	var ids := SaveSystem.profile.heroes.keys()
	if ids.is_empty():
		return
	# 空岗 → 第 1 个；依次轮换；最后回到空岗
	var idx := ids.find(current)
	if idx == -1:
		VillageSystem.assign(SaveSystem.profile, building, ids[0])
	elif idx == ids.size() - 1:
		VillageSystem.unassign(SaveSystem.profile, building)
	else:
		VillageSystem.assign(SaveSystem.profile, building, ids[idx + 1])
