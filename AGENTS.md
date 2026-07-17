# 水浒战棋 —— 工程说明

战棋（SRPG）＋ 卡牌养成，Godot 4.7 + GDScript。设计与计划文档都在 `docs/`：
游戏策划文档（.docx）、开发计划、美术指导、数据表说明、**决策日志**（规则空白处的拍板记录，改代码前先看）。

## 常用命令（项目根目录）

```bash
# 单元测试（GUT，应全部通过）
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit

# 数据表校验（改 CSV 后必跑）
godot --headless --path . -s src/tools/validate_data.gd

# 导入/刷新类缓存（新增含 class_name 的脚本后必须执行，否则全局类找不到）
godot --headless --path . --import

# 运行调试战斗场景（左键移动/攻击，空格结束行动）
godot --path .
```

## 工程红线（详见 docs/水浒战棋-开发计划.md 第六章）

1. **CSV 是唯一数据源**：数值只改 `data/*.csv`，禁止代码硬编码；`docs/System/` 的 CSV 是设计快照，不要改、不要以它为准。
2. **逻辑与表现分离**：逻辑层（`src/battle/` 除 battle.gd 外）不依赖场景显示；指令执行瞬时结算，表现事件排队回放。
3. **指令管道统一**：玩家输入与 AI 都生成 `Command` 子类，经 `BattleManager.submit_command()` 执行。
4. **技能零程序介入**：新技能 = skills.csv 加一行拼原子效果；新原子效果才动 `EffectSystem`，并同步数据表说明的词表。
5. 数值读取必须走 Resource（`DataLoader` AutoLoad，生产环境）或注入的 `GameDataLoader` 实例（测试/工具），逻辑类不得直接访问 autoload 单例。

## 代码约定

- GDScript，**Tab 缩进**，静态类型；公开类加 `class_name` 并配一句中文文档注释。
- 新增 `class_name` 脚本后跑 `--import` 刷新类缓存。
- 测试用 GUT（extends GutTest），放 `tests/test_*.gd`；夹具在 `tests/helpers/`。
  注意 GUT 9.6 无 `assert_empty`（用 `assert_eq(x.size(), 0)`）；`autofree()` 返回 Variant，声明别用 `:=`。
- 随机判定必须经 `RollSource` 注入（生产 RandomRollSource / 测试 FixedRollSource），不得直接用全局 rand。

## 目录

```
data/       CSV 数据表（唯一数据源）+ reserved_units.txt 预留武将名单
src/
  autoload/ DataLoader（GameDataLoader）
  data/     UnitData / SkillData / TerrainData（Resource）
  battle/   战斗逻辑层：Grid/Unit/TurnOrder/DamageCalculator/EffectSystem/Command/BattleManager
  tools/    命令行工具（数据校验等）
scenes/battle/  调试战斗场景（占位表现）
tests/      GUT 单元测试
docs/       策划文档、开发计划、决策日志等
addons/gut/ 测试框架（随仓库携带）
```
