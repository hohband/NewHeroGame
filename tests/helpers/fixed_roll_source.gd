class_name FixedRollSource
extends RollSource
## 按预设序列循环返回判定值的随机源，用于确定性测试。
## DamageCalculator 的判定顺序：闪避 → 暴击 → 格挡（前序失败则短路）。

var values: Array[float] = [99.0]
var index := 0

func _init(p_values: Array[float] = [99.0]) -> void:
	values = p_values

func roll() -> float:
	var v := values[index % values.size()]
	index += 1
	return v
