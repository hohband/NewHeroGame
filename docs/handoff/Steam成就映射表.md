# Steam 成就映射表（GodotSteam 接入用）

> 用途：解除阻塞项 #3（Steam 接入）。游戏内成就数据已全部就绪（档案 achievements/progress），
> 本表给出 Steam 后端 API 名与解锁条件的一一映射，接入时照表登记即可。
> 命名规范：`ACH_大写蛇形`。统计类（stat）单独列于文末。

## 一、关卡/剧情成就

| Steam API | 名称 | 解锁条件（游戏内数据） |
|---|---|---|
| ACH_CH01_CLEAR | 梁山初起 | 通关第一章终关（progress.cleared 含 ch01_05） |
| ACH_CH02_CLEAR | 七星聚义 | 通关第二章终关（ch02_02） |
| ACH_SHENGChengang | 智取生辰纲 | 通关 ch03_01 |
| ACH_BUZHAN | 不战而屈人之兵 | achievements 含 buzhan（药酒路线且未杀厢军） |
| ACH_BIAOSHI | 黄泥冈镖师 | achievements 含 biaoshi（击杀杨志通关） |
| ACH_CH04_CLEAR | 大闹清风寨 | 通关第四章终关（ch04_02） |
| ACH_CH05_CLEAR | 江州劫法场 | 通关第五章终关（ch05_02） |
| ACH_CH06_CLEAR | 三打祝家庄 | 通关第六章终关（ch06_03） |
| ACH_RANK_S | 武艺超群 | 任一评价关卡取得 S 评价（结算 rank == "S"） |
| ACH_END_ZHAOAN | 奉诏安民 | 达成招安结局（progress.ending == "zhaoan"） |
| ACH_END_KANGZHAO | 义旗不倒 | 达成不招安结局（progress.ending == "kangzhao"） |

## 二、收集/养成成就

| Steam API | 名称 | 解锁条件 |
|---|---|---|
| ACH_HERO_10 | 小聚义 | 拥有武将 ≥ 10（profile.heroes.size） |
| ACH_HERO_24 | 三十六天罡 | 拥有全部首发 24 将 |
| ACH_FIRST_ORANGE | 天罡下凡 | 首次拥有橙将 |
| ACH_FULL_STAR | 升星圆满 | 任一武将升至 5 星 |
| ACH_BREAKTHROUGH | 聚义升星 | 首次品质突破（绿→蓝→紫） |
| ACH_SIGNATURE | 神兵认主 | 首次解锁专属武器 |
| ACH_BOND_TEAM | 情义千秋 | 同场战斗激活 ≥ 3 对羁绊（开战时统计） |

## 三、玩法模式成就

| Steam API | 名称 | 解锁条件 |
|---|---|---|
| ACH_EXPEDITION_5 | 远征·半途 | 梁山远征推进 ≥ 5 层（progress.expedition_best） |
| ACH_EXPEDITION_10 | 远征·登顶 | 通关远征 10 层 |
| ACH_ARENA_FIRST | 切磋初胜 | 演武场首胜 |
| ACH_DAILY_WEEK | 勤劳山寨 | 日常副本累计通关 20 次（stat，见文末） |

## 四、Steam 统计（stats，非成就）

| Stat API | 类型 | 用途 |
|---|---|---|
| STAT_DAILY_CLEARS | INT 累计 | 日常副本通关次数（ACH_DAILY_WEEK 依据） |
| STAT_BATTLES_WON | INT 累计 | 总胜场（商店页「平均玩家进度」参考） |
| STAT_EXPEDITION_BEST | INT 最大 | 远征最佳层数（排行榜候选，远期） |

## 五、接入注意

- 成就判定点集中在 `Flow.apply_battle_result` 与 `VillageSystem/Progression` 的完成回调——接入时在 GodotSteam 监听对应信号/调用即可，无需侵入战斗逻辑。
- 云存档：存档已在 `user://save1.json`，直接映射 Steam Cloud 该路径；注意首启时本地存档与云端冲突策略（建议「时间新者胜」）。
- 集换式卡牌：建议 8 张（宋江/林冲/鲁智深/武松/李逵/花荣/扈三娘/公孙胜立绘卡），依赖阻塞项 #1 美术。
