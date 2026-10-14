# 东京湾既有色板恢复：四档资源与正式场景证据

本次按用户要求直接用命令推进，未调用goal系统。不是又一份仅源图候选：恢复颜色已完成四档各336页压缩、覆盖绑定和正式Loading→Survivor显示。仍不代表正常出生/近景或整图实战完成。

## 工序与复用

1. 已完成全图原生缓存在AO前恢复既有Palette，旧合成逐像素复算完全一致、alpha不变，40102240采样变化。
2. `page_restored_palette.py`与`page_palette_remaining.py`复用既有分页相位和area_mip，仅更新纹理载荷；四档原始几何/高度/189楼定义不变。
3. `build_tokyo_hlod_native_pages.reuse_geometry`核来源/UV、实际Component身份/面数/字节后复用原始原生文件。4×336页DXT5纹理全部保存回读，三份租约费用与旧页一致，无重新造楼或AO烘焙。
4. `bind_palette_all.py`逐页复核原生几何完全相同，再复制原正式楼位置证明并绑定新catalog摘要。新的`m1-hlod-package-palette-all.json`仍保持旧四档资格区间，默认游戏全图开关未推广；本地`run_m1_preview.cmd`已指向该包。

## 实际执行

- 首档打包87015退出0；两处正式场景36117退出0。
- 其余三档第一次身份字段比较因JSON浮点与资源整数字典类型差异拒绝，退出1，没有绕过错误门。改为逐字段数值比较后16454三个受保护bench均退出0；失败目录不作为成果。
- 全四档包的正常最远两处预览77891退出0：53426/4764面，same_overlay、same_viewport、预热两帧、退出stream释放通过。
- 四档独立制作尺度核验14519退出0，159224/50132/118840/53426面，均ready。报告明确`production_scales_not_gameplay_acceptance=true`，不拿超出普通滚轮范围的制作档代替玩家验收。
- 实图：`tmp/tokyo-bay-volume/m1-palette-all-review/native_00.png`及01；四档同区域图在`m1-palette-four-ranges/native_00..03.png`。图像没有AI或后期编辑。
- 对上一轮已修光照但未恢复色板的同位城区图，alpha逐像素一致；RGB均值从(98.90,108.66,102.99)变为(113.75,122.73,118.74)。粗略水色掩码257961样本均差0.49/255，仅作诊断，非逐地物精确色差结论。
- Visual仍有1 CanvasItem RID/1 ObjectDB退出提示及Wacom/证书/shader缓存提示，不能称无泄漏。未作实战帧时间通过声明。

## 后续仍需处理

全量回归终态另补。正常出生/近景接入、中景密集区预算及运动切换仍是既有缺口；正在汇总已有原生组件来源，禁止为配色再次重建全图几何。
