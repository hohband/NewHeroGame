extends SceneTree
## 数据表校验工具（命令行）：
##   godot --headless --path . -s src/tools/validate_data.gd
## 规则见 docs/System/水浒战棋-数据表说明.md 第五节。全部通过退出码 0，否则 1。

func _initialize() -> void:
	var loader := GameDataLoader.new()
	loader.load_all()
	var errors := loader.validate()
	if errors.is_empty():
		print("✓ 数据校验通过：%d 武将 / %d 技能 / %d 地形 / %d 预留" % [
			loader.units.size(), loader.skills.size(), loader.terrains.size(), loader.reserved.size()])
	else:
		printerr("✗ 数据校验未通过（%d 项）：" % errors.size())
		for e in errors:
			printerr("  - " + e)
	loader.free()
	quit(0 if errors.is_empty() else 1)
