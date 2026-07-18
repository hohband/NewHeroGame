class_name LevelConfig
extends Resource
## 关卡配置（策划文档 6.9/7.6）：棋盘数据 + 双方配置 + 触发器列表 + 胜负条件。
## 当前由代码构建（src/levels/）；设计师可视化编辑的 .tres 工作流在 M2 接入（决策日志 D28）。

@export var id: String = ""
@export var name: String = ""
## 玩法模式（第九章）：story 主线 / daily 日常副本 / arena 演武场 / expedition 梁山远征
@export var mode: String = "story"
## 结局路线 id（终章双路线：zhaoan 招安 / kangzhao 不招安；空 = 非结局关）
@export var ending: String = ""
@export var chapter: int = 1
@export var recommended_level: int = 1
## 覆盖通关经验（0 = 按章节公式 30+20×章，日常副本用）
@export var exp_override: int = 0
## PVP 守方策略模板 id（arena 模式，8.6；空 = 无修正）
@export var pvp_template: String = ""
@export var grid_size: Vector2i = Vector2i(8, 8)
## 地形：{Vector2i: StringName(terrain_id)}，缺省 plain
@export var terrain_map: Dictionary = {}
## 高度：{Vector2i: int}，缺省 0
@export var height_map: Dictionary = {}

## 胜利条件：{"type": "WIPE_OUT"} / {"type": "KILL_BOSS"} / {"type": "SURVIVE_TURNS", "turns": N}
## 　　　　　{"type": "COLLECT", "target": "cargo", "count": N} / {"type": "ESCORT", "unit": id, "zone": Rect2i}
## 　　　　　{"type": "OCCUPY", "zone": Rect2i, "turns": N}
@export var win_condition: Dictionary = {"type": "WIPE_OUT"}
## 失败条件列表：{"type": "WIPED_OUT"} / {"type": "TURN_LIMIT", "turns": N} / {"type": "ESCORT_DEAD", "unit": id}
@export var lose_conditions: Array[Dictionary] = []

## 布阵（策划文档 6.8）：必出 + 候选 + 部署区 + 上限
@export var required_units: Array[StringName] = []
@export var roster: Array[StringName] = []        # 候选池（必出之外的备选）
@export var deploy_zone: Rect2i = Rect2i(0, 5, 8, 3)
@export var max_deploy: int = 8

## NPC 友军与敌方：[{"unit": StringName, "coords": Vector2i, "elite": bool, "boss": bool}]
@export var npc_allies: Array[Dictionary] = []
@export var enemies: Array[Dictionary] = []
## 场景物件（生辰纲担等）：[{"id": String, "coords": Vector2i, "hp": int}]
@export var objects: Array[Dictionary] = []

## 触发器（6.9）：[{"id", "once", "on": {...}, "actions": [...]}]
## on: {"type": "TURN", "turn": N} / {"type": "UNIT_DEAD", "unit": id} /
##     {"type": "ENTER_ZONE", "zone": Rect2i, "who": "player"|"enemy"|"any"} /
##     {"type": "HP_BELOW", "unit": id, "ratio": 0.5}
## actions: [{"type": "spawn", "units": [{unit, coords, team}]}] / [{"type": "dialogue", "text"}] /
##          [{"type": "terrain", "cells": {Vector2i: terrain_id}}] /
##          [{"type": "buff", "side": "enemy"|"player", "field": &"atk", "value": 10, "duration": 99, "name"}]
@export var triggers: Array[Dictionary] = []

@export var rewards: Dictionary = {}
## 评价规则（挑战关 S 评价，决策日志 D37）：{"s_max_rounds": N, "s_no_death": true}
## 全满足 = S，其余通关 = A；空表不参与评价
@export var rank_rules: Dictionary = {}
## 通关/达成评价后的武将解锁：{"unit": unit_id, "requires_rank": "S"|""}（挑战关渠道，D37）
@export var unlock_grant: Dictionary = {}
## 成就（7.5）：[{"id", "name", "requires": {...}, "exclusive_group"}]
## requires: {"path": 剧情路线标记} / {"no_player_kills": [unit_id...]} / {"boss_dead": unit_id}，可组合
@export var achievements: Array[Dictionary] = []
