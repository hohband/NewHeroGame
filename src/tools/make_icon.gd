extends SceneTree
## 生成应用图标：取林冲源图主立绘 → 512×512 icon.png（桌面 app 用，D40）
## 用法：godot --headless --path . -s src/tools/make_icon.gd

const MANUAL_RECT := Rect2i(0, 0, 720, 760)   # 林冲源图为整页设定页，手动框定主立绘（去掉底部头像行）

func _initialize() -> void:
	var img := Image.load_from_file("res://assets/units/lin_chong.png")
	if img == null:
		printerr("源图缺失")
		quit(1)
		return
	img = img.get_region(MANUAL_RECT)
	var used := img.get_used_rect()
	var side := int(max(used.size.x, used.size.y))
	# 以主立绘为中心的正方形画布（透明底）
	var icon := Image.create(side, side, false, Image.FORMAT_RGBA8)
	icon.blit_rect(img, used, Vector2i.ZERO)
	icon.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	icon.save_png("res://icon.png")
	print("icon.png 生成：512×512（源区域 %dx%d）" % [used.size.x, used.size.y])
	quit(0)
