class_name BondSystem
extends RefCounted
## 羁绊系统（策划文档 4.1）：原著关系的同场出战带来属性加成。
## 规则（决策日志 D29）：仅同队生效；每名武将对其每个在场搭档各获一份加成（攻防 +X%，progression.csv）；
## 不可驱散、持续全场；预留搭档（未实装/未上阵）不生效。

static func apply_bonds(units: Array[Unit], prog: Dictionary) -> Array:
	var events: Array = []
	var bonus := int(prog.get("bond_stat_bonus", 5))
	for u in units:
		if u.is_object or u.data == null:
			continue
		for bond in u.data.bonds:
			var partner_id: StringName = bond["target"]
			var partner := _find_living(units, partner_id, u.team)
			if partner == null:
				continue
			var b := Buff.new()
			b.buff_id = StringName("bond_%s" % partner_id)
			b.name = String(bond["name"])
			b.stat_mods = {&"atk": bonus, &"def": bonus}
			b.duration = 99
			b.dispellable = false
			b.source = partner
			u.add_buff(b)
			events.append({"type": "bond", "unit": u, "partner": partner_id, "name": bond["name"]})
	return events

static func _find_living(units: Array[Unit], id: StringName, team: Unit.Team) -> Unit:
	for u in units:
		if u.is_alive() and not u.is_object and u.data != null and u.data.unit_id == id and u.team == team:
			return u
	return null
