class_name TerrainData
extends Resource
## 地形数据（对应 data/terrains.csv 一行）。

@export var terrain_id: StringName
@export var name: String
@export var move_cost: int             # 进入消耗；99 = 不可通行
@export var dodge_mod: int             # 闪避修正（概率点，直接加）
@export var def_mod: int               # 防御修正 %
@export var atk_mod: int               # 攻击修正 %
@export var range_mod: int             # 射程修正（山地 +1）
@export var passable: bool
@export var destructible: bool
@export var hp: int                    # 可破坏物耐久（拒马 300）
@export var special: String            # 特殊效果描述（脚本钩子按 terrain_id 实现）
