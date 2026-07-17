class_name GameSaveSystem
extends Node
## AutoLoad（注册名 SaveSystem）：存档读写与当前档案持有。
## JSON 存于 user://save1.json（Steam 云存档后续映射该目录，决策日志 D30）。

const SAVE_PATH := "user://save1.json"

var profile: PlayerProfile = null

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func new_game(loader: GameDataLoader) -> void:
	profile = PlayerProfile.new_default(loader)

func save_game() -> Error:
	if profile == null:
		push_error("SaveSystem: 无档案可存")
		return ERR_INVALID_DATA
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: 无法写入 " + SAVE_PATH)
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(profile.to_dict(), "\t"))
	return OK

## 读取存档到 profile；成功返回 true
func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text := f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("SaveSystem: 存档损坏")
		return false
	profile = PlayerProfile.from_dict(parsed)
	return true
