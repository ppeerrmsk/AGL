"""把已标高坡顶离线恢复为封闭屋面/墙面；不改原始建筑记录的总高。"""
import math

from shapely import constrained_delaunay_triangles
from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union


def tagged_roof(poly, height_m, roof_height_m, shape, orientation="along", min_height_m=0):
    if shape not in {"gabled", "hipped", "pyramidal"}:
        raise ValueError("unsupported_roof_shape")
    if orientation not in {"along", "across", ""}:
        raise ValueError("unsupported_roof_orientation")
    if roof_height_m <= 0 or roof_height_m >= height_m:
        raise ValueError("invalid_roof_height")
    if poly.is_empty or not poly.is_valid or poly.geom_type != "Polygon":
        raise ValueError("invalid_footprint")
    corners = list(poly.minimum_rotated_rectangle.exterior.coords)
    edges = [(math.dist(a, b), (b[0]-a[0], b[1]-a[1])) for a, b in zip(corners, corners[1:])]
    length, direction = max(edges)
    u = (direction[0]/length, direction[1]/length)
    v = (-u[1], u[0])
    if orientation == "across":
        u, v = v, (-v[1], v[0])
    center = poly.minimum_rotated_rectangle.centroid
    def local(p):
        x, y = p[0]-center.x, p[1]-center.y
        return (x*u[0]+y*u[1], x*v[0]+y*v[1])
    def world(p):
        return (center.x+p[0]*u[0]+p[1]*v[0], center.y+p[0]*u[1]+p[1]*v[1])
    ring = [local(p) for p in poly.exterior.coords]
    holes = [[local(p) for p in hole.coords] for hole in poly.interiors]
    local_poly = Polygon(ring, holes)
    half_l = max(abs(p[0]) for p in ring)
    half_w = max(abs(p[1]) for p in ring)
    planes = [(0, 1/half_w, 1), (0, -1/half_w, 1)]
    if shape != "gabled":
        slope = min(half_w, half_l*0.5) if shape == "hipped" else half_l
        planes += [(1/slope, 0, half_l/slope), (-1/slope, 0, half_l/slope)]
    # 每个坡面取自身为最低平面的凸域，再裁原 footprint；不延长无效交线制造细缝。
    reach = max(half_l, half_w)*4
    faces = []
    for p in planes:
        domain = [(-reach, -reach), (reach, -reach), (reach, reach), (-reach, reach)]
        for q in planes:
            a, b, c = p[0]-q[0], p[1]-q[1], p[2]-q[2]
            if a*a+b*b < 1e-16:
                continue
            result = []
            for start, end in zip(domain, domain[1:]+domain[:1]):
                fs, fe = a*start[0]+b*start[1]+c, a*end[0]+b*end[1]+c
                if fs <= 0:
                    result.append(start)
                if (fs < 0 < fe) or (fe < 0 < fs):
                    t = fs/(fs-fe)
                    result.append((start[0]+t*(end[0]-start[0]), start[1]+t*(end[1]-start[1])))
            domain = result
        clipped = local_poly.intersection(Polygon(domain))
        if clipped.geom_type == "Polygon":
            faces.append(clipped)
        else:
            faces.extend(part for part in getattr(clipped, "geoms", []) if part.geom_type == "Polygon")
    top = height_m*0.5
    eave = (height_m-roof_height_m)*0.5
    bottom = max(0.12, min_height_m*0.5)
    if eave <= bottom:
        raise ValueError("roof_eave_below_source_min_height")
    def vertex(p):
        x, y = world(p)
        factor = max(0, min(1, min(a*p[0]+b*p[1]+c for a, b, c in planes)))
        return [x, eave + roof_height_m*0.5*factor, y]
    roof, walls, projected, boundary_edges = [], [], [], []
    for face in faces:
        for tri in constrained_delaunay_triangles(face).geoms:
            if tri.area < 1e-9:
                continue # 相交直线在浮点下产生的零宽三角，不是可见屋面。
            pts = list(tri.exterior.coords)[:3]
            if (pts[1][0]-pts[0][0])*(pts[2][1]-pts[0][1])-(pts[1][1]-pts[0][1])*(pts[2][0]-pts[0][0]) > 0:
                pts.reverse() # 3D 叉积向上；Geometry.triangle 再转 Godot 正面绕序。
            verts = [vertex(p) for p in pts]
            roof.extend(verts)
            projected.append(Polygon([world(p) for p in pts]))
            for j in range(3):
                edge = LineString([pts[j], pts[(j+1)%3]])
                if not local_poly.boundary.buffer(1e-6).covers(edge):
                    continue
                boundary_edges.append(edge)
                a, b = verts[j], verts[(j+1)%3]
                low_a, low_b = [a[0], bottom, a[2]], [b[0], bottom, b[2]]
                walls.extend([low_a, low_b, b, low_a, b, a])
    coverage = unary_union(projected)
    error = poly.symmetric_difference(coverage).area
    overlap = sum(p.area for p in projected)-coverage.area
    seam_error = abs(sum(edge.length for edge in boundary_edges)-local_poly.length)
    if error > 1e-5 or overlap > 1e-5 or seam_error > 1e-5 or abs(max(v[1] for v in roof)-top) > 1e-5:
        raise ValueError(f"roof_topology_or_peak_mismatch: {error}, {overlap}, {seam_error}")
    return {"shape": shape, "top_px": top, "eave_px": eave, "roof": roof, "walls": walls,
        "area_error": error, "overlap": overlap, "boundary_error": seam_error}
