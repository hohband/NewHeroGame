class_name SkillData
extends Resource
## 技能数据（对应 data/skills.csv 一行）。
## 技能 = 原子效果序列 + 范围模板 + 目标规则（策划文档 6.7），effects 原文由 EffectSystem 解析执行。

@export var skill_id: StringName
@export var name: String
@export var owner: String              # 持有武将ID；"通用" 表示所有单位可用
@export var type: StringName           # active / passive / ult
@export var trigger: StringName        # manual / on_attack / on_hit / turn_start ...
@export var range_shape: StringName    # adjacent / line / ring / diamond / all / self
@export var range_min: int
@export var range_max: int
@export var target: StringName         # enemy / ally / self
@export var cooldown: int
@export var rage_cost: int
@export var effects: String            # 原子效果序列，分号分隔，按顺序执行
@export var desc: String
