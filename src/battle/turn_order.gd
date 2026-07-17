class_name TurnOrder
extends RefCounted
## CTB 速度排队（策划文档 6.4）：AV = 1000 ÷ 速度；全体 AV 同时递减，归零者行动，行动后重置自身 AV。
## 同刻归零平局（决策日志 D3）：速度高者优先 → 我方优先 → unit_id 字典序。
## 加速/减速/再动 = 直接修改单位 AV（戴宗技能等，后续接入）。

var _ready: Array[Unit] = []

## 取出下一个行动单位；调用方负责在行动结束后 unit.reset_av()。
func next_actor(units: Array[Unit]) -> Unit:
	var guard := 0
	while guard < 10000:
		guard += 1
		if _ready.is_empty():
			_tick(units)
		if _ready.is_empty():
			return null   # 无存活单位
		var u := _ready.pop_front() as Unit
		if u != null and u.is_alive():
			return u
	push_error("TurnOrder: 迭代超限")
	return null

func remove(unit: Unit) -> void:
	_ready.erase(unit)

func _tick(units: Array[Unit]) -> void:
	var alive: Array[Unit] = []
	for u in units:
		if u.is_alive():
			alive.append(u)
	if alive.is_empty():
		return
	var min_av := INF
	for u in alive:
		min_av = minf(min_av, u.av)
	for u in alive:
		u.av -= min_av
	var zeroed: Array[Unit] = []
	for u in alive:
		if u.av <= 0.0001:
			zeroed.append(u)
	zeroed.sort_custom(func(a: Unit, b: Unit) -> bool:
		if a.data.spd != b.data.spd:
			return a.data.spd > b.data.spd
		if a.team != b.team:
			return a.team < b.team
		return String(a.data.unit_id) < String(b.data.unit_id)
	)
	for u in zeroed:
		_ready.append(u)
