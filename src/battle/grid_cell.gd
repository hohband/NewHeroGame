class_name GridCell
extends RefCounted
## 棋盘最小单位：地形类型、高度、占位单位、可破坏障碍（策划文档 6.2）。

var coords: Vector2i
var terrain: TerrainData
var height: int = 0
var occupant: Unit = null
var obstacle_hp: int = 0   # >0 表示存在可破坏障碍（如拒马）

func has_obstacle() -> bool:
	return obstacle_hp > 0

func is_blocked() -> bool:
	return not terrain.passable or has_obstacle()
