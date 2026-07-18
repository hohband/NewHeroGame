class_name Flow
extends RefCounted
## 游戏流程：战斗结算 → 档案应用（核心循环：战斗 → 资源 → 升级 → 更高难度）。
## 奖励/经验/成就/章节进度/武将解锁的集中规则（决策日志 D32），全部可单元测试。

## 通关经验：基础 30 + 每章 20（占位，D32）；关卡可用 exp_override 覆盖（日常副本，D34）
static func exp_reward(level: LevelConfig) -> int:
	return level.exp_override if level.exp_override > 0 else 30 + 20 * level.chapter

## 应用战斗结果到档案。deployed 为实际上阵单位（取其 hero 发放经验）。
## 返回摘要：{won, first_clear, rewards, achievements, exp_each, level_ups, unlocked, chapter_now}
static func apply_battle_result(profile: PlayerProfile, level: LevelConfig, result: Dictionary, deployed: Array[Unit], loader: GameDataLoader) -> Dictionary:
	var summary := {
		"won": bool(result.get("won", false)),
		"first_clear": false,
		"rewards": {},
		"achievements": result.get("achievements", []),
		"exp_each": 0,
		"level_ups": {},
		"unlocked": [],
		"chapter_now": int(profile.progress.get("chapter", 1)),
	}
	if not summary["won"]:
		return summary
	summary["rank"] = result.get("rank", "")
	# 挑战关武将解锁（花荣 S 评价/秦明通关等，D37）
	var grant: Dictionary = level.unlock_grant
	if not grant.is_empty():
		var uid := StringName(grant.get("unit", ""))
		var need_rank := String(grant.get("requires_rank", ""))
		if uid != &"" and not profile.has_hero(uid) and (need_rank == "" or summary["rank"] == need_rank):
			profile.add_hero(Hero.new(uid, loader.get_unit(uid).quality))
			summary["unlocked"].append(uid)
	# 奖励：首通给 first_clear，之后给 regular
	var cleared: Array = profile.progress.get("cleared", [])
	summary["first_clear"] = not cleared.has(level.id)
	var rewards: Dictionary = level.rewards.get("first_clear" if summary["first_clear"] else "regular", {})
	summary["rewards"] = rewards
	for key in rewards:
		if key == "gold":
			profile.gold += int(rewards[key])
		else:
			profile.gain_item(StringName(key), int(rewards[key]))
	# 成就
	for ach in summary["achievements"]:
		profile.achievements[ach] = true
	# 进度与章节
	if summary["first_clear"]:
		cleared.append(level.id)
	profile.progress["cleared"] = cleared
	if is_chapter_final(level, loader):
		var next_chapter: int = level.chapter + 1
		if next_chapter > summary["chapter_now"]:
			profile.progress["chapter"] = next_chapter
			summary["chapter_now"] = next_chapter
		summary["unlocked"] = grant_chapter_heroes(profile, level.chapter, loader)
	# 经验：上阵武将人人有份（含未升级的统计）
	summary["exp_each"] = exp_reward(level)
	for u in deployed:
		var h := u.hero if u.hero != null else profile.get_hero(u.data.unit_id)
		if h == null:
			continue
		var ups := Progression.add_exp(h, summary["exp_each"], loader.progression)
		if ups > 0:
			summary["level_ups"][u.data.unit_id] = ups
	# 山寨产出：每通关一次收获一轮（策划文档第三章）
	summary["village"] = VillageSystem.collect(profile, loader)
	return summary

## 章节的最后一关（解锁下一章与「通关解锁」武将的判定；只看 ch 前缀的主线关卡）
static func is_chapter_final(level: LevelConfig, loader: GameDataLoader) -> bool:
	for id in LevelRegistry.list_ids():
		if id == level.id or not id.begins_with("ch"):
			continue
		var other := LevelRegistry.get_level(id)
		if other != null and other.chapter == level.chapter and other.id > level.id:
			return false
	return true

## 章节通关后的武将解锁（决策日志 D32/D37 注）：
## 「第N章…通关…」（如 第4章通关解锁 / 第6章「三打祝家庄」通关）在通关第 N 章终关时发放；
## 「第N章剧情加入」在抵达第 N 章（通关第 N-1 章终关）时发放。挑战关渠道另走 unlock_grant。
static func grant_chapter_heroes(profile: PlayerProfile, cleared_chapter: int, loader: GameDataLoader) -> Array:
	var unlocked: Array = []
	for id in loader.units:
		var ud: UnitData = loader.units[id]
		if profile.has_hero(id):
			continue
		var chapter_clear := ud.unlock.contains("第%d章" % cleared_chapter) and ud.unlock.contains("通关")
		if chapter_clear or ud.unlock.contains("第%d章剧情加入" % (cleared_chapter + 1)):
			profile.add_hero(Hero.new(id, ud.quality))
			unlocked.append(id)
	return unlocked

## 聚义厅招募（CSV unlock=聚义厅招募；占位：通用碎片 ×20，D32）
const RECRUIT_COST := 20

static func can_recruit(profile: PlayerProfile, unit_id: StringName, loader: GameDataLoader) -> bool:
	return not profile.has_hero(unit_id) \
		and loader.get_unit(unit_id).unlock == "聚义厅招募" \
		and int(profile.items.get("shard", 0)) >= RECRUIT_COST

static func recruit(profile: PlayerProfile, unit_id: StringName, loader: GameDataLoader) -> bool:
	if not can_recruit(profile, unit_id, loader):
		return false
	profile.spend_item(&"shard", RECRUIT_COST)
	profile.add_hero(Hero.new(unit_id, loader.get_unit(unit_id).quality))
	return true
