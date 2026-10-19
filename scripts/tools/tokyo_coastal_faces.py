"""从有向 OSM 岸线闭合海陆面；输入必须已使用游戏的 Y 向下坐标。"""
from math import hypot

from shapely.geometry import LineString, Point, box
from shapely.ops import polygonize, unary_union


def coastal_faces(bounds, coastlines):
    """不猜缺口、不以陆地填海；任一断岸/方向矛盾/无法分类即拒绝构建。"""
    clip = box(*bounds)
    segments = []
    probes = []
    for points in coastlines:
        for a, b in zip(points, points[1:]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = hypot(dx, dy)
            if length < 1e-8:
                continue
            line = LineString([a, b]).intersection(clip)
            if line.geom_type != "LineString" or line.length < 1e-6:
                continue
            segments.append(line)
            middle = line.interpolate(0.5, normalized=True)
            offset = min(0.001, line.length * 0.01)
            # OSM 经纬度中陆在左侧；翻转 Y 后叉积为负。
            probes.append((Point(middle.x + dy / length * offset, middle.y - dx / length * offset),
                Point(middle.x - dy / length * offset, middle.y + dx / length * offset)))
    if not segments:
        raise ValueError("coastal region contains no source coastline")
    network = unary_union([clip.boundary, *segments])
    faces = list(polygonize(network))
    land, sea = [], []
    for face in faces:
        labels = set()
        for land_point, sea_point in probes:
            if face.contains(land_point):
                labels.add("land")
            if face.contains(sea_point):
                labels.add("sea")
        if len(labels) != 1:
            raise ValueError(f"unclosed or inconsistent coastline: face labels={labels}, area={face.area}")
        (land if "land" in labels else sea).append(face)
    land_face, sea_face = unary_union(land), unary_union(sea)
    coverage_error = clip.symmetric_difference(unary_union([land_face, sea_face])).area
    overlap = land_face.intersection(sea_face).area
    if coverage_error > 1e-5 or overlap > 1e-5:
        raise ValueError("coastal faces do not partition the region")
    return land_face, sea_face, {"faces": len(faces), "segments": len(segments),
        "land_area_px2": land_face.area, "sea_area_px2": sea_face.area,
        "coverage_error_px2": coverage_error, "overlap_px2": overlap}
