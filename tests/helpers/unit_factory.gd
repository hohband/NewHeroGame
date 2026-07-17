class_name UnitFactory
extends RefCounted
## 测试夹具：快速构造内存中的 UnitData / Unit / Grid，不依赖 CSV。

static func make_unit(atk: int, def: int, spd: int, team: Unit.Team, coords: Vector2i, id: StringName = &"test_unit") -> Unit:
	var data := UnitData.new()
	data.unit_id = id
	data.name = String(id)
	data.quality = &"blue"
	data.unit_class = &"infantry"
	data.hp = 500
	data.atk = atk
	data.def = def
	data.mgc = 0
	data.spd = spd
	data.crit = 0
	data.dodge = 0
	data.block = 0
	data.move = 3
	data.range_min = 1
	data.range_max = 1
	var u := Unit.new()
	u.setup(data, team, coords)
	return u

static func make_grid(loader: GameDataLoader, size: Vector2i, terrain_map: Dictionary = {}, height_map: Dictionary = {}) -> Grid:
	var grid := Grid.new()
	grid.setup(loader, size, terrain_map, height_map)
	return grid
