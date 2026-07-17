class_name Buff
extends RefCounted
## Buff/Debuff 统一模型（策划文档 6.7）：回合数、层数、可否驱散，持有者回合开始时统一 tick。
## 口径见决策日志 D15：同 buff_id 重复施加 = 刷新持续时间，不叠层。

## 属性修正：{atk: 15, def: -30, ...}。atk/def/mgc/spd 为百分值（%）；
## dodge/block/crit 为概率点；move 为格数。同一单位多个 buff 的修正直接相加。
var buff_id: StringName
var name: String = ""
var stat_mods: Dictionary = {}     # StringName -> int
var duration: int = 1              # 剩余回合数（持有者回合开始 -1，归零移除）
var stacks: int = 1                # 层数（暂不支持叠层，D15）
var dispellable: bool = true       # 可否驱散
var is_debuff: bool = false
## 持续效果（回合开始触发）：{"kind": "dot", "percent": 5} = 按最大生命百分比扣血
var tick_effect: Dictionary = {}
## 控制状态（stun/sleep/paralyze/bind/guard/counter），行为见决策日志 D22/D27
var status: StringName = &""
## 光环（郁保四替天行道旗）：为半径内友军提供属性修正；aura_radius = 0 表示非光环
var aura_mods: Dictionary = {}   # StringName -> int（%或概率点，与 stat_mods 同口径）
var aura_radius: int = 0
var source: Unit = null

func is_expired() -> bool:
	return duration <= 0
