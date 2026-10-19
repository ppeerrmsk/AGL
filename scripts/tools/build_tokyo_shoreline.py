"""从有来源的自然岸线制作静态描边；绝不描绘裁切框。"""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path
from shapely import constrained_delaunay_triangles, line_merge, unary_union
from shapely.geometry import LineString, Polygon, box


def f32(value):
    return struct.unpack('f', struct.pack('f', value))[0]


def parts(shape):
    if shape.is_empty:
        return []
    if shape.geom_type == 'LineString':
        return [shape] if shape.length > 0 else []
    if hasattr(shape, 'geoms'):
        return [line for child in shape.geoms for line in parts(child)]
    return []


def collect(sources):
    lines, windows, records = [], [], []
    for identity, data in sources:
        bounds = data['bounds']
        if len(bounds) != 4 or not all(math.isfinite(v) for v in bounds) or bounds[0] >= bounds[2] or bounds[1] >= bounds[3]:
            raise ValueError('invalid source bounds')
        window = box(*bounds)
        windows.append(window)
        for ordinal, points in enumerate(data['coastlines']):
            if len(points) < 2 or any(len(p) != 2 or not all(math.isfinite(v) for v in p) for p in points):
                raise ValueError('invalid coastline source')
            line = LineString(points)
            if line.length <= 0:
                raise ValueError('zero length coastline')
            clipped = parts(line.intersection(window))
            lines.extend(clipped)
            if clipped:
                records.append(dict(source=identity, ordinal=ordinal, points=points,
                                    clipped=[list(p.coords) for p in clipped]))
    if not lines:
        raise ValueError('no source coastline intersects source windows')
    joined = line_merge(unary_union(lines))
    return joined, unary_union(windows), records


def build(lines, window, width):
    if width not in (.35, 1.0, 2.0):
        raise ValueError('unreviewed coastline width')
    shape = lines.buffer(width*.5, cap_style=2, join_style=2, mitre_limit=2).intersection(window)
    if shape.is_empty or not shape.is_valid:
        raise ValueError('invalid coastline surface')
    faces = list(constrained_delaunay_triangles(shape).geoms)
    vertices = [[f32(x), f32(y)] for tri in faces for x, y in list(tri.exterior.coords)[:3]]
    native_faces = [Polygon(vertices[i:i+3]) for i in range(0, len(vertices), 3)]
    if any(not tri.is_valid or tri.area <= 0 for tri in native_faces):
        raise ValueError('degenerate native coastline face')
    native = unary_union(native_faces)
    area_error = native.symmetric_difference(shape).area/shape.area
    tolerance = .005
    if not native.covered_by(shape.buffer(tolerance)) or not shape.covered_by(native.buffer(tolerance)) or area_error > .002:
        raise ValueError('native precision budget exceeded')
    if abs(sum(t.area for t in native_faces)-native.area) > max(1e-7, native.area*1e-9):
        raise ValueError('overlapping native coastline triangles')
    conservative_bytes = len(vertices)*64*3
    if len(faces) > 12000 or conservative_bytes > 4*1024*1024:
        raise ValueError('static coastline budget exceeded')
    return dict(width=width, height=.03, rgb=[70,82,83], triangles=vertices,
                stats=dict(faces=len(faces), conservative_bytes=conservative_bytes,
                           area=shape.area, native_area=native.area, relative_area_error=area_error,
                           bounds=list(shape.bounds)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--lod', action='store_true', help='三档原生消费；旧两版输出默认不变')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('refuse to overwrite candidate')
    sources, provenance = [], []
    for path in args.source:
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        sources.append((digest, json.loads(raw)))
        provenance.append(dict(path=str(path.resolve()), sha256=digest))
    lines, window, records = collect(sources)
    output = dict(schema=2 if args.lod else 1, sources=provenance, records=records,
                  centerlines=[list(p.coords) for p in parts(lines)],
                  centerline_length=lines.length,
                  candidates=[build(lines, window, w) for w in ((2.,1.,.35) if args.lod else (1.,2.))])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, separators=(',', ':')), encoding='utf-8')
    print(json.dumps(dict(paths=len(output['centerlines']), segments=sum(len(p)-1 for p in output['centerlines']),
                          length=lines.length, candidates=[c['stats'] for c in output['candidates']])))


if __name__ == '__main__':
    main()
