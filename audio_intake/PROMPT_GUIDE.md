# AGL 音频生成提示词速查

生成平台通常更理解英文音频术语。以下是起点，不是要求每条都照抄；每次生成保留 3–6 个差异明显的
候选，比追求一次命中更有效。

## Suno 音乐

通用尾句可加入：

`instrumental game soundtrack, no vocals, clear loop-friendly ending, restrained master loudness, no trailer braam spam`

- 初期冷峻：`cold professional air operations, sparse military electronics, restrained pulse, precise and tense, 95 BPM`
- 中期升温：`tactical air battle escalating across multiple fronts, driving percussion, controlled urgency, 120 BPM`
- 后期暴走：`large-scale jet battle at the edge of control, layered rhythmic propulsion, frantic but readable, 145 BPM`
- BOSS 登场：`ominous high-altitude contact, slow reveal, unique sonic identity, 30-second arrival cue into battle-ready ending`
- BOSS 接战：`intelligent ace duel, dangerous and relentless, strong phase-change landmarks, instrumental game boss music`
- 胜利/失败：分别生成 8–20 秒独立短曲，不要从长 BGM 随机截取。

优先下载 WAV；如果某首未来要做动态层叠，同时保存 stems，并记录 BPM、调性和预计循环点。

## 世界音效

通用约束可加入：

`isolated dry sound effect, no music, no voice, no cinematic score, minimal reverb, clean tail, game-ready source`

- 机炮：`short distant 20mm rotary cannon burst, sharp mechanical attack, 0.7 seconds, [通用约束]`
- 导弹发射：`air-to-air missile ignition and launch, compact rocket motor onset, 1.2 seconds, [通用约束]`
- 导弹掠过：`fast missile pass-by, tight Doppler whip, no impact, 1 second, [通用约束]`
- 普通击毁：`small fighter aircraft breaking apart after missile hit, brief metal snap and compact explosion, [通用约束]`
- 重型击毁：`heavy armored aircraft destruction, layered internal blast and structural breakup, 2 seconds, [通用约束]`
- 舰船受击：`distant anti-ship impact on steel hull, low mechanical body with short debris tail, [通用约束]`
- 热诱弹：`fighter flare ejection burst, rapid pyrotechnic pops and short hiss, [通用约束]`
- 干扰：`electronic countermeasure activation, unstable radar texture, short one-shot, not a musical synth chord`
- UI 确认：`minimal tactical terminal confirmation click, soft pale electronic tick, 0.15 seconds, no reverb`
- 危险告警：`urgent military threat warning pulse, piercing but not harsh, 0.35 seconds, one-shot`

一次只生成一个事件。复杂声音拆成 attack / body / tail 或机械 / 爆炸 / 碎片层，后期更容易做强弱变体。

## 无线电

### 无语义含混人声纹理

无线电声音**不是屏幕台词的配音**。屏幕文字负责三语语义；声音只要让玩家感到“频道里有人正在说话”，
而且必须糊到无法辨认任何具体词句。所有界面语言共用同一套素材。

起始提示词：

`indistinct human tactical radio communication texture, non-lexical murmured phonemes, no recognizable words, no identifiable language, short urgent transmission cadence, obscured articulation, dry source, no music, no clear dialogue`

- 生成若干 0.8–2.5 秒的短通信节奏，不按每条屏幕台词逐句生成，也不要求与文字长度同步。
- 候选中只要能听出英语、中文、日文或任何具体单词，就淘汰或继续降解；不能靠换一种陌生语言假装无语义。
- 可准备平静、紧急、受干扰等强度变体，但不为阵营或语言复制整套素材。
- 不模仿现实演员、飞行员或公众人物；不使用未授权真人声音克隆。

### 蜂鸣与底噪

- 入台蜂鸣：`short military radio squelch opening chirp, 0.18 seconds, isolated, no voice`
- 退台噪声：`brief radio squelch tail closing, 0.25 seconds, isolated, no voice`
- 受干扰：`unstable tactical radio static burst with digital breakup, 0.8 seconds, isolated, no voice`
- 优先级插播：`two-tone military priority channel alert, compact and authoritative, 0.4 seconds`

AGL 的 Radio Bus 会统一做频带切割和轻失真，所以母版保留干净的无语义人声纹理。风格样板可把人声、
蜂鸣和静电混在一起试听，但正式库仍保留各层独立；最终验收标准是“明确像人在通信，但完全听不清在说什么”。
