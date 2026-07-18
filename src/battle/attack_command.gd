class_name AttackCommand
extends Command
## 攻击/技能：通过 EffectSystem 按技能的原子效果序列结算。普攻与技能共用同一管道。
## 普攻也可指定可破坏障碍格（拒马，策划文档 6.3）：target_cell 有效时打障碍而非单位。

var target: Unit
var skill: SkillData
var target_cell := Vector2i(-1, -1)   # 可破坏障碍格；(-1,-1) 表示普通单位目标

func _init(p_actor: Unit = null, p_target: Unit = null, p_skill: SkillData = null, p_target_cell: Vector2i = Vector2i(-1, -1)) -> void:
	super(p_actor)
	target = p_target
	skill = p_skill
	target_cell = p_target_cell

func execute(battle: BattleManager) -> Array:
	if actor == null or skill == null:
		return []
	if target_cell != Vector2i(-1, -1):
		return _execute_obstacle(battle)
	if target == null:
		return []
	if target.coords != actor.coords:
		actor.facing = DamageCalculator.dominant_dir(target.coords - actor.coords)
	var ctx := EffectContext.new(actor, target, battle.grid, battle.rolls, battle)
	return EffectSystem.execute(skill, ctx)

## 打可破坏障碍：障碍无防御/闪避/格挡/暴击，伤害 = 攻击力（普攻倍率 1.0，简化口径）。
## 耐久归零后走 Grid.set_terrain（与触发器「地形变化」同一路径）变为平原，恢复通行。
func _execute_obstacle(battle: BattleManager) -> Array:
	var cell := battle.grid.get_cell(target_cell)
	if cell == null or not cell.has_obstacle():
		return []
	if target_cell != actor.coords:
		actor.facing = DamageCalculator.dominant_dir(target_cell - actor.coords)
	var amount := maxi(1, actor.get_atk(battle.grid))
	cell.obstacle_hp = maxi(0, cell.obstacle_hp - amount)
	var events: Array = [{"type": "obstacle_damage", "unit": actor, "coords": target_cell,
		"amount": amount, "remaining": cell.obstacle_hp}]
	if cell.obstacle_hp <= 0:
		var from: StringName = cell.terrain.terrain_id
		battle.grid.set_terrain(target_cell, &"plain")
		events.append({"type": "terrain_change", "coords": target_cell, "from": from, "to": &"plain"})
	return events
