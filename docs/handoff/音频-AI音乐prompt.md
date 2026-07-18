# BGM 生成 Prompt（AI 音乐服务用）

> 用途：BGM 是占位音频层唯一缺口（SFX 已由程序合成，决策日志 D39）。
> 我没有音乐生成能力——把下面三段 prompt 拿到 Suno / Udio / Stable Audio 跑一遍即可。
> 产出命名：`assets/audio/bgm/bgm_main.ogg` / `bgm_battle.ogg` / `bgm_camp.ogg`，
> 放入后 AudioManager.play_bgm 即接（接口已留）。生成记录按 Steam AI 披露要求留存。

---

## bgm_main《聚义》主题曲（90–120s，主界面/山寨）

```
 upbeat Chinese folk hero theme, bold suona lead melody over pipa strumming and taiko drums, 110 BPM, heroic tavern vibe, warm and playful wuxia energy, traditional instruments only, strong memorable hook, seamless loop
```

## bgm_battle《替天行道》战斗（90–120s 循环）

```
 driving wuxia battle groove, steady taiko pulse at 120 BPM, dizi flute and erhu call-and-response, tense but bright, no dark ambience, traditional Chinese ensemble, builds midway with extra percussion layer, seamless loop
```

## bgm_camp《大碗酒》营地/结算（60–90s）

```
 playful sanxian and banhu folk tune, 96 BPM, tipsy tavern bounce, cheerful and casual, traditional Chinese plucked strings, short loopable phrase with clear ending for result screen sting
```

**统一负面词**：

```
dark ambient, orchestral epic, electronic synth, trap beats, distorted guitar, vocals, choir
```

## 验收

- 循环无明显接缝（导出后首尾各留 0.5s 交叉淡化空间）；
- 响度与 SFX 匹配（游戏内目标 -16 LUFS）；
- 先用 15 秒片段试听三段方向，满意再出全长——返工成本最低。
