# 首批 10 将 AI 生成 Prompt 卡片

> 用途：解除阻塞项 #1（正式美术）时直接投产。
> 用法：以 `docs/Art/水浒战棋-风格基准-角色.png`（林冲基准图）为 `reference_image` 图生图；
> 每张卡只替换中段主体描述，配色词逐字复用（美术指导 6.2-2）。
> 验收：64px 剪影可辨职业与武将、与基准图并排不违和（指导 6.4）。
> 文件命名：`assets/units/<unit_id>.png`（透明底）；生成记录（prompt/日期/工具）按批留存。

**固定风格锚点**（逐字复用）：

```
chibi game character, 2.5-head-tall cute proportions, Song dynasty Chinese warrior from Water Margin: <主体描述>, full body front view, standing pose, clean bold outlines, soft cel shading, vibrant Clash-of-Clans-inspired cartoon style, plain warm light beige background, character reference sheet, high quality game asset
```

**通用负面词**（逐字复用）：

```
realistic, photorealistic, dark, bloody, anime style, japanese armor, extra limbs, blurry, watermark, text, signature, oversaturated
```

---

## 1. 林冲 lin_chong（已有基准图，仅存档配色词）

```
Lin Chong the Panther Head - leopard-print headband, determined eyes, dark teal cloth armor with vermillion red sash, holding a long spear diagonally
```
配色词：dark teal armor with vermillion red sash

## 2. 鲁智深 lu_zhishen

```
Lu Zhishen the Flowery Monk - bald head, large prayer beads, bare arms with floral tattoos, monk robe in dark grey-blue, holding a massive iron monk spade
```
配色词：dark grey-blue monk robe, floral tattoos
验收点：魁梧感（2.2 头身放宽）；禅杖必须比人高

## 3. 武松 wu_song

```
Wu Song the Pilgrim - black headband, short hair, tiger-hunter scar on forearm, dark brown short jacket with cloth belt, dual short sabers on back
```
配色词：dark brown short jacket, cloth belt
验收点：行者头箍是辨识核心；双戒刀背在身后

## 4. 安道全 an_daoquan

```
An Daoquan the Divine Physician - gentle round face, long white-grey beard, moon-white robe with medicine-green trim, carrying a medicine gourd and a small medicine chest
```
配色词：moon-white robe with medicine-green trim
验收点：药箱/药葫芦为机制道具，必须醒目

## 5. 吴用 wu_yong

```
Wu Yong the Resourceful Strategist - scholarly goatee, calm smiling eyes, indigo-blue Taoist robe with wide sleeves, holding a feather fan
```
配色词：indigo-blue Taoist robe
验收点：羽扇；书生气质不可带武将甲

## 6. 花荣 hua_rong

```
Hua Rong the Little Li Guang - handsome sharp eyebrows, bamboo-green cloak over leather-brown archer gear, long bow on shoulder, quiver full of arrows on back
```
配色词：bamboo-green cloak, leather-brown archer gear
验收点：瘦高 2.8 头身；长弓比例可略夸张

## 7. 李逵 li_kui

```
Li Kui the Black Whirlwind - fierce round eyes, bristly black beard, bare-chested with dark cloth pants, holding two oversized broad axes wider than his body
```
配色词：bare-chested, dark cloth pants
验收点：双板斧是全游最宽武器（绰号视觉化）

## 8. 白胜 bai_sheng

```
Bai Sheng the White Rat - sly squinting eyes, thin face, patched grey-brown peasant cloth, carrying a large wooden wine barrel on back with a ladle
```
配色词：grey-brown peasant cloth
验收点：酒桶为机制道具，必须醒目（生辰纲功臣）

## 9. 杨志 yang_zhi

```
Yang Zhi the Blue-faced Beast - blue-black birthmark on left face, stern frown, dark green general armor with bronze trims, holding a long spear upright
```
配色词：dark green general armor with bronze trims
验收点：面部青记是辨识核心；将门气质比厢军华贵

## 10. 公孙胜 gongsun_sheng

```
Gongsun Sheng the Dragon in the Clouds - long flowing beard, mysterious half-closed eyes, deep indigo Taoist robe with cloud patterns, holding a horsetail whisk, small lightning sparks around
```
配色词：deep indigo Taoist robe with cloud patterns
验收点：拂尘而非羽扇（区别于吴用）；雷光点缀克制

---

## 后续批次（同一管线扩产）

- 第二批 6 将已有基础词：徐宁（金枪+金甲）、张顺（水战短打+鱼篓）、王英（矮壮双刀）、龚旺/丁得孙（飞枪/飞叉）、燕青（弩+浪子纹身）
- 场景/特效/UI 边框按指导第三、四节另行成批
