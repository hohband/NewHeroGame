class_name EffectContext
extends RefCounted
## 原子效果执行上下文：谁（actor）对谁（target）在哪张棋盘（grid），用哪个随机源（rolls）。

var actor: Unit
var target: Unit
var grid: Grid
var rolls: RollSource
## 修正类效果集中（前置扫描，决策日志 D21）：sure_hit / hit_rate / bonus_* / execute_below 等
var mods: Dictionary = {}
## 反击递归深度（防止无限互反，决策日志 D27）
var depth := 0
## 本次施放召唤出的物件（summon 效果写入，aura 效果读取）
var summoned: Unit = null
## 战斗总控引用（summon 注册新单位用）
var battle: BattleManager = null
## 技能等级效果倍率（养成系统；无档案时为 1.0）
var effect_mult := 1.0

func _init(p_actor: Unit = null, p_target: Unit = null, p_grid: Grid = null, p_rolls: RollSource = null, p_battle: BattleManager = null) -> void:
	actor = p_actor
	target = p_target
	grid = p_grid
	rolls = p_rolls
	battle = p_battle
