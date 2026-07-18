class_name ItemData
extends Resource
## 道具数据（对应 data/items.csv 一行，策划 6.5 行动类型「道具：每局限用次数」）。
## 道具 = 效果序列 + 目标规则 + 每局次数：范围/目标列语义同 skills.csv，
## effects 复用技能原子效果词表（不加新原子效果），经 to_skill_data() 投影借道 Targeting/EffectSystem 结算。

@export var item_id: StringName
@export var name: String
@export var range_shape: StringName    # adjacent / line / ring / diamond / all / self（词表同技能表）
@export var range_min: int
@export var range_max: int
@export var target: StringName         # enemy / ally / self
@export var uses_per_battle: int = 1   # 每局限用次数（标准道具栏默认值，meta 可覆盖）
@export var effects: String            # 原子效果序列，分号分隔，按顺序执行
@export var desc: String

## 投影为 SkillData：Targeting/EffectSystem 按技能口径结算道具效果，效果系统零改动。
func to_skill_data() -> SkillData:
	var s := SkillData.new()
	s.skill_id = item_id
	s.name = name
	s.type = &"active"
	s.trigger = &"manual"
	s.range_shape = range_shape
	s.range_min = range_min
	s.range_max = range_max
	s.target = target
	s.effects = effects
	s.desc = desc
	return s
