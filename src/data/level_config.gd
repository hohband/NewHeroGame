class_name LevelConfig
extends Resource
## 关卡配置（策划文档 6.9/7.6）：棋盘数据 + 双方配置 + 触发器列表 + 胜负条件。
## 当前由代码构建（src/levels/）；设计师可视化编辑的 .tres 工作流在 M2 接入（决策日志 D28）。

@export var id: String = ""
@export var name: String = ""
@export var chapter: int = 1
@export var recommended_level: int = 1
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
