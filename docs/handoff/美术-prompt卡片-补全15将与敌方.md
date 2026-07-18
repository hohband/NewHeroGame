# 补全 Prompt 卡片：首发剩余 15 将 + 敌方 5 种

> 配套：《美术-prompt卡片-首批10将.md》（锚点/负面词/验收流程相同）。
> 用法：以林冲基准图（docs/Art/水浒战棋-风格基准-角色.png）为 `reference_image` 图生图，只替换中段主体描述；配色词逐字复用。
> 杂兵建议**一批同产**（先出厢军枪兵作基准，其余换装备/微调），减少模型状态漂移（指导 6.2-3）。
> 文件命名：`assets/units/<unit_id>.png`（透明底）；生成记录按批留存（Steam AI 披露）。

**固定风格锚点**（逐字复用）：

```
chibi game character, 2.5-head-tall cute proportions, Song dynasty Chinese warrior from Water Margin: <主体描述>, full body front view, standing pose, clean bold outlines, soft cel shading, vibrant Clash-of-Clans-inspired cartoon style, plain warm light beige background, character reference sheet, high quality game asset
```

**通用负面词**（逐字复用）：

```
realistic, photorealistic, dark, bloody, anime style, japanese armor, extra limbs, blurry, watermark, text, signature, oversaturated
```

---

## 一、紫将（3）

### 秦明 qin_ming（霹雳火 · 马军）

```
Qin Ming the Fiery Thunderbolt - fierce bulging eyes, bushy eyebrows, crimson-red heavy cavalry armor with flame patterns, holding a spiked wolf-tooth mace raised high
```
配色词：crimson-red heavy cavalry armor with flame patterns
验收点：狼牙棒尖刺夸张化（一个夸张特征）；烈火朱砂色与花荣竹青拉开

### 张清 zhang_qing（没羽箭 · 神射）

```
Zhang Qing the Featherless Arrow - sharp confident smirk, light leather armor in stone grey and teal, one hand tossing three smooth pebbles into the air, the other hand on hip
```
配色词：stone grey and teal leather armor
验收点：**不用弓**（与花荣区分）——飞石在掌心上方三颗必须可见

### 扈三娘 hu_sanniang（一丈青 · 马军）

```
Hu Sanniang the Ten Feet of Blue - heroic female warrior with high ponytail, blue-white cavalry armor with red accents, dual sabers at waist, a very long flowing red cotton lasso ribbon swirling around her body
```
配色词：blue-white cavalry armor, very long red cotton lasso ribbon
验收点：红棉套索飘带是全游标志物，必须最长最醒目；首发唯一女将，英气不可媚态

## 二、蓝将（7）

### 戴宗 dai_zong（神行太保 · 辅助）

```
Dai Zong the Magic Traveller - lean runner build, wind-swept scarf trailing behind, light yellow-brown traveller outfit, two paper talismans tied to his lower legs, captured mid-stride in a dynamic running pose
```
配色词：light yellow-brown traveller outfit, paper leg talismans
验收点：甲马绑腿是神行符号；站姿也要带速度感（前倾）

### 时迁 shi_qian（鼓上蚤 · 步军）

```
Shi Qian the Flea on the Drum - tiny wiry thief with mouse-like eyes and pointy nose, dark grey sneaking outfit, climbing claws strapped on hands, crouching low like a flea about to jump
```
配色词：dark grey sneaking outfit
验收点：全队最小体型（比标准 2.5 头身再瘦小）；爪钩道具清晰

### 孙二娘 sun_erniang（母夜叉 · 步军）

```
Sun Erniang the Night Hag - wild red-haired woman with dangerous grin, dark green innkeeper dress with rolled sleeves, dual willow-leaf daggers, a small poison pouch at her waist
```
配色词：dark green innkeeper dress, red hair
验收点：柳叶双刀+蒙汗药包双道具；泼辣凶相，不可端庄

### 曹正 cao_zheng（操刀鬼 · 步军）

```
Cao Zheng the Butcher - burly chef with rolled-up sleeves showing thick arms, stained white butcher apron over brown cloth, holding a long thin boning knife, cleaver tucked at belt
```
配色词：stained white butcher apron over brown cloth
验收点：剔骨尖刀细而长；屠夫烟火气，不是战将气质

### 焦挺 jiao_ting（没面目 · 步军）

```
Jiao Ting the Faceless - deliberately plain forgettable face with flat nose, sumo wrestler build with big muscular belly, grey wrestling loincloth outfit, bare feet, hands open in a grappling stance
```
配色词：grey wrestling outfit
验收点：相扑宽腰体型；「没面目」=五官平庸无记忆点（反识别度设计，仅此一例）

### 鲍旭 bao_xu（丧门神 · 步军）

```
Bao Xu the Grim Reaper - gaunt skull-like fierce face, tattered black-brown robe, holding a huge grim executioner sword with a chipped blunt edge
```
配色词：tattered black-brown robe
验收点：丧门剑大、钝、带缺口；凶神恶相（绞肉机小队气质）

### 郁保四 yu_baosi（险道神 · 辅助）

```
Yu Baosi the God of Perilous Roads - towering thin giant in simple grey-white outfit, planting a massive crimson banner flag into the ground, the flag pole taller than himself with a big red banner cloth and tassels
```
配色词：grey-white outfit, massive crimson banner
验收点：**替天行道旗是全游独一份机制道具，必须比人还大**；旗面用纹样/图腾，不要文字

## 三、绿将（5）

### 汤隆 tang_long（金钱豹子 · 辅助）

```
Tang Long the Golden Leopard - sturdy blacksmith with sweaty grin, leather work apron over rolled sleeves, holding a hooked sickle-spear in one hand, small forge hammer at his belt, a few sparks flying
```
配色词：leather work apron, bronze hammer
验收点：钩镰枪+铁匠锤双道具（兵种与身份都要读得出）

### 石勇 shi_yong（石将军 · 先锋）

```
Shi Yong the Stone General - square-jawed blunt gambler look, plain grey-green cloth armor, holding a bronze cudgel staff, simple honest stance
```
配色词：grey-green cloth armor, bronze cudgel
验收点：熟铜棍；憨厚老实人（赌命技能的莽劲）

### 宋万 song_wan（云里金刚 · 先锋）

```
Song Wan the Diamond in the Clouds - tall broad calm guardian, dark iron heavy armor, holding a large rectangular shield in front and a long broad saber at side
```
配色词：dark iron heavy armor, large rectangular shield
验收点：大盾占画面三分之一（挡刀机制）；与杜迁并排要有元老兄弟相

### 杜迁 du_qian（摸着天 · 步军）

```
Du Qian the Sky Toucher - lanky tall warrior with notably long arms, weathered leather armor, holding a long spear pointed high to the sky
```
配色词：weathered leather armor
验收点：长手长脚（摸着天梗）；与宋万成对生产保持系列感

### 王定六 wang_dingliu（活闪婆 · 步军）

```
Wang Dingliu the Quick Flash - small nimble scout with sharp alert eyes, grass-green lightweight outfit, holding a short spear, leaning forward ready to sprint
```
配色词：grass-green lightweight outfit
验收点：全队最轻捷体态；短枪短小

## 四、敌方（5 种，一批同产）

> 生产顺序建议：厢军枪兵 → 厢军刀牌手 → 新兵×2 → 老都管。
> 敌方统一朱砂/暗红制服（美术指导第三节：敌方红色旗号标识），朴素度必须低于主角团。

### 厢军枪兵 xiangjun_spear

```
Song dynasty imperial army spearman - plain soldier face, dark red government army uniform with simple iron helmet, holding a standard infantry spear upright
```
配色词：dark red government army uniform, iron helmet
验收点：普通到没有个性（杂兵基准）；枪制式统一

### 厢军刀牌手 xiangjun_shield

```
Song dynasty imperial army shieldman - stocky soldier, dark red government army uniform, holding a big round wooden shield and a broadsword
```
配色词：dark red government army uniform, round wooden shield
验收点：盾牌占画面三分之一（格挡机制读得出）

### 厢军新兵 xiangjun_recruit

```
young inexperienced Song dynasty army recruit - nervous boyish face, oversized loose dark red uniform, holding a plain wooden spear awkwardly
```
配色词：oversized loose dark red uniform
验收点：明显稚嫩/不合身（教学关炮灰感）

### 刀牌新兵 pai_recruit

```
young inexperienced Song dynasty shield recruit - nervous boyish face, oversized loose dark red uniform, holding a plain wooden shield and a short blade awkwardly
```
配色词：oversized loose dark red uniform, plain wooden shield
验收点：与厢军新兵同系列，只换装备

### 老都管 lao_duguan

```
Old Duguan the scheming steward - fat arrogant old official with thin goatee, expensive dark purple silk robe with wide sleeves, leaning on a walking cane, sneering expression
```
配色词：dark purple silk robe
验收点：奸相+富态；非战斗感（每回合鼓劲的文职辅助）

---

## 验收与批量建议

1. 每张图过 64px 剪影测试（指导 6.4）：紫蓝绿三档细节递减，但**机制道具一个都不能少**（旗、索、石、棒、药包）。
2. 同批生产顺序：紫 → 蓝 → 绿 → 敌方，每批改完统一描边/调色/缩放（指导 6.2-4）。
3. 全部到齐后交给程序：统一裁主立绘 sprite + 表情头像，接入棋盘与界面（命名即 `<unit_id>`，程序侧已按此约定）。
