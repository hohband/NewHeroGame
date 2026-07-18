extends SceneTree
## 武将立绘裁切工具（决策日志 D39 注）：
## 从 assets/units/<id>.png（AI 生成的整页设定图）裁出
##   - 战斗 sprite：透明边修剪后规范到高 160px（assets/units/sprite/<id>.png）
##   - 头像 portrait：取修剪图头顶部方图（2.5 头身，头部落在顶部约 55%），规范到 96×96（assets/units/portrait/<id>.png）
## 版式异常的整页图（如林冲设定页）在 MANUAL_CROPS 手动框定主立绘区域。
## 用法：godot --headless --path . -s src/tools/crop_unit_art.gd

const SRC_DIR := "res://assets/units/"
const SPRITE_DIR := "res://assets/units/sprite/"
const PORTRAIT_DIR := "res://assets/units/portrait/"
const SPRITE_H := 160
const PORTRAIT_SIZE := 96

## 手动框（整页设定图的主立绘区域）：unit_id -> Rect2i（原图坐标）
const MANUAL_CROPS := {
	&"lin_chong": Rect2i(0, 0, 720, 820),
}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SPRITE_DIR)
	DirAccess.make_dir_recursive_absolute(PORTRAIT_DIR)
	var dir := DirAccess.open(SRC_DIR)
	if dir == null:
		printerr("无源目录 " + SRC_DIR)
		quit(1)
		return
	var ok := 0
	for f in dir.get_files():
		if not f.ends_with(".png"):
			continue
		var id := StringName(f.trim_suffix(".png"))
		if _crop_one(id):
			ok += 1
	print("完成：%d 张" % ok)
	quit(0)

func _crop_one(id: StringName) -> bool:
	var img := Image.load_from_file(SRC_DIR + String(id) + ".png")
	if img == null or img.is_empty():
		printerr("加载失败：", id)
		return false
	if MANUAL_CROPS.has(id):
		img = img.get_region(MANUAL_CROPS[id])
	# 透明边修剪（无内容时保底跳过）
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		printerr("透明边修剪后为空：", id)
		return false
	var sprite := img.get_region(used)
	# sprite：规范高度
	var w := int(round(float(used.size.x) * SPRITE_H / float(used.size.y)))
	sprite.resize(w, SPRITE_H, Image.INTERPOLATE_LANCZOS)
	sprite.save_png(SPRITE_DIR + String(id) + ".png")
	# portrait：头顶部方图（水平居中、贴顶；2.5 头身头部约占上 55%）
	var side := int(min(w, round(SPRITE_H * 0.55)))
	var px := int((w - side) / 2.0)
	var portrait := sprite.get_region(Rect2i(px, 0, side, side))
	portrait.resize(PORTRAIT_SIZE, PORTRAIT_SIZE, Image.INTERPOLATE_LANCZOS)
	portrait.save_png(PORTRAIT_DIR + String(id) + ".png")
	print("  %s  sprite %dx%d  portrait %dx%d" % [id, w, SPRITE_H, PORTRAIT_SIZE, PORTRAIT_SIZE])
	return true
