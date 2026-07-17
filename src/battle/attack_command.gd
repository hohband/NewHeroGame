class_name AttackCommand
extends Command
## 攻击/技能：通过 EffectSystem 按技能的原子效果序列结算。普攻与技能共用同一管道。

var target: Unit
var skill: SkillData

func _init(p_actor: Unit = null, p_target: Unit = null, p_skill: SkillData = null) -> void:
	super(p_actor)
	target = p_target
	skill = p_skill

func execute(battle: BattleManager) -> Array:
	if actor == null or target == null or skill == null:
		return []
	if target.coords != actor.coords:
		actor.facing = DamageCalculator.dominant_dir(target.coords - actor.coords)
	var ctx := EffectContext.new(actor, target, battle.grid, battle.rolls, battle)
	return EffectSystem.execute(skill, ctx)
