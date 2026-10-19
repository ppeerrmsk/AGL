# 沙漠河道离线来源

R113（2026-09-07）追加 source-northeast-osm.json：API https://api.openstreetmap.org/api/0.6/map.json?bbox=119.701,-23.129,119.749,-23.088 ，SHA256 0d393c5b707c4f4b5021e3182db05ec18b1ace38e1cb7d366100c9214649b4df。完整way159633265与102节点；37个旧符号在8px源关联缓冲内完整对应，91仅78.63%故仍未分类，不扩大缓冲吞并。当前合计384符号对应7河，217保留轮廓，其中210未分类/2无效/5确认湖面。原R83裁决和6份来源不改；完整增量记录在source-classification.json的northeast_supplement，原版哈希及候选证据在tmp/desert-volume/r112-water-fragments与r113-river-integration。下文R83数字为历史批次记录。

2026-09-07 获取的 OpenStreetMap 公开 API 原始 JSON，保留原始字节。来源：OpenStreetMap contributors，ODbL；https://www.openstreetmap.org/copyright 。仅用于表现层来源对应，不修改玩法道路/铁路/机场/建筑坐标。

- source-stream-osm.json：API bbox=119.56,-23.217,119.576,-23.205。
- source-lake-osm.json：API bbox=119.8261,-23.3707,119.9068,-23.3200。
- 其余三个 source-region 文件的完整请求 URL 见 fetch-results.jsonl。
- source-west-osm.json：API https://api.openstreetmap.org/api/0.6/map.json?bbox=119.418,-23.546,119.466,-23.518 ，SHA256 5e7c27ab675ffb978c2fcef040dbefbec82b45efacdc24a5742447d06b5c5abf3。
- source-classification.json 保留6份哈希、每轮廓来源对应与未匹配项；347河道候选映射到6条way，254其他轮廓保留。R83只新增38个原未分类轮廓，均与way343881407源缓冲重合约100%，旧裁决不变；原分类哈希与增量索引存入supplement。8世界px缓冲仅用于源像素对应，不代表测绘河宽。

`tools/build_volume_desert_hydrography.py --output <path>` 离线重建消费的JSON；可选`--source <directory>`先核对隔离来源候选。需要Shapely 2.1.2，可通过进程级AGL_GEOMETRY_PYTHONPATH指向已有依赖目录。构建不联网，默认不覆盖生产资源；输出经比对后再替换resources/maps/desert_volume_hydrography.json并通过volume_terrain_build重建归档。

源水面扫描条带仍使用原0.01世界px交点量化；替换范围面积差门在构建器独立验证。河道只在5个已确认湖面轮廓与保留even-odd水面的交集处裁剪，未分类色斑不得重新制造河道断口；整河长度及真实Western断口另有回归。旧地图、高程及原始源图完整保留，尚未核实的247轮廓与2个自接触轮廓不据此删除。新way343881407的intermittent=yes与fixme:position原样保留，终点接旧106879155内部节点3506676864；新源stream356276459无对应旧符号，不额外加入。来源日期差异与候选状态见沙漠地图规格R75/R76/R83。
