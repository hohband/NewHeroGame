class_name RollSource
extends RefCounted
## 百分率判定的随机源抽象：产出 [0, 100) 的判定值。
## 生产环境用 RandomRollSource；测试注入固定序列（FixedRollSource，见 tests/helpers）。

func roll() -> float:
	push_error("RollSource.roll() 需要在子类中实现")
	return 0.0
