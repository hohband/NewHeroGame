extends GutTest
## 立绘实装验收（阻塞项 #1）：35 张源图裁出的 sprite/portrait 有效、别名覆盖、规格正确

func test_sprite_and_portrait_exist_for_all_art() -> void:
	var src := DirAccess.open("res://assets/units/")
	var count := 0
	for f in src.get_files():
		if not f.ends_with(".png"):
			continue
		var id := f.trim_suffix(".png")
		var sp := "res://assets/units/sprite/%s.png" % id
		var pp := "res://assets/units/portrait/%s.png" % id
		assert_true(FileAccess.file_exists(sp), "sprite 缺失：%s" % id)
		assert_true(FileAccess.file_exists(pp), "portrait 缺失：%s" % id)
		count += 1
	assert_eq(count, 36, "36 张源图（35 单位 + 杨志别名图源）全部有裁切产物")

func test_crop_specs() -> void:
	for id in ["lin_chong", "bai_sheng", "xiangjun_spear"]:
		var st: Texture2D = load("res://assets/units/sprite/%s.png" % id)
		assert_not_null(st, "%s sprite 可加载" % id)
		assert_eq(st.get_height(), 160, "sprite 规范高 160px")
		assert_gt(st.get_width(), 0)
		var pt: Texture2D = load("res://assets/units/portrait/%s.png" % id)
		assert_not_null(pt)
		assert_eq(pt.get_width(), 96, "portrait 规范 96×96")
		assert_eq(pt.get_height(), 96)

func test_boss_alias_covers_missing_art() -> void:
	# 杨志 BOSS 未单独出图，经别名复用杨志立绘（战斗场景 ART_ALIASES）
	assert_true(FileAccess.file_exists("res://assets/units/sprite/yang_zhi.png"),
		"yang_zhi 图存在，yang_zhi_boss 经别名引用")
