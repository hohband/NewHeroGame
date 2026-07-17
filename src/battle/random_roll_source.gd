class_name RandomRollSource
extends RollSource
## 生产随机源：包装 RandomNumberGenerator，支持设种子复现战斗。

var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

func set_seed(value: int) -> void:
	rng.seed = value

func roll() -> float:
	return rng.randf() * 100.0
