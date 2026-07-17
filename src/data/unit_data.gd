class_name UnitData
extends Resource
## 武将数据（对应 data/units.csv 一行）。字段定义见 docs/System/水浒战棋-数据表说明.md。
## 注意：CSV 列名 class 是 GDScript 保留字，此处字段名为 unit_class。

@export var unit_id: StringName
@export var name: String
@export var nickname: String
@export var star: String
@export var quality: StringName        # orange / purple / blue / green
@export var unit_class: StringName     # vanguard/infantry/cavalry/archer/strategist/healer/support
@export var hp: int
@export var atk: int
@export var def: int
@export var mgc: int
@export var spd: int
@export var crit: int                  # 暴击率 %
@export var dodge: int                 # 闪避率 %
@export var block: int                 # 格挡率 %
@export var move: int                  # 基础移动力（格）
@export var range_min: int
@export var range_max: int
@export var weapon: String
@export var skill_signature: StringName
## 羁绊列表：[{ "target": StringName, "name": String }]
@export var bonds: Array[Dictionary] = []
@export var unlock: String
## 特性标记（enemies.csv 的 traits 列；如 alert 警觉——首次睡眠减免，决策日志 D31）
@export var traits: Array[StringName] = []
