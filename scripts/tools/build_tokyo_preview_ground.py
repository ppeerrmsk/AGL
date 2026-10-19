"""东京小片地表：OSM 面/孔洞裁切与离线三角化；不改正式地图。"""
from __future__ import annotations
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tmp/tokyo-r3-pydeps"))
import osmium
from shapely import wkb, constrained_delaunay_triangles, make_valid
from shapely.geometry import box
from shapely.ops import transform

PBF = ROOT / "tmp/full_map_detail/kanto-latest.osm.pbf"
OUTPUT = ROOT / "resources/maps/tokyo_volume_preview/r3_ground.json"
BOUNDS = (-520.0, -13870.0, 1120.0, -12730.0)
CLIP = box(*BOUNDS)
FACTORY = osmium.geom.WKBFactory()


def world(lon, lat, z=None):
    return (lon - 139.76) * 45217.136632614195, -(lat - 35.44) * 55500.0


def intersects(points):
    return points and not (max(x for x, y in points) < BOUNDS[0]
        or min(x for x, y in points) > BOUNDS[2]
        or max(y for x, y in points) < BOUNDS[1]
        or min(y for x, y in points) > BOUNDS[3])


class Collector(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.surfaces = []
        self.paths = []
        self.counts = Counter()

    def area(self, area):
        tags = dict(area.tags)
        kind = ""
        if tags.get("natural") == "water" or tags.get("water") or tags.get("waterway") == "riverbank":
            kind = "water"
        elif tags.get("natural") in {"wood", "scrub", "grassland"} or tags.get("landuse") in {"grass", "forest", "meadow", "village_green"}:
            kind = "green"
        elif tags.get("leisure") in {"park", "garden", "recreation_ground"}:
            kind = "park"
        elif tags.get("landuse") == "railway":
            kind = "rail_yard"
        elif tags.get("highway") in {"pedestrian", "platform"} or tags.get("amenity") == "parking":
            kind = "paved"
        if not kind:
            return
        points = [world(n.lon, n.lat) for ring in area.outer_rings() for n in ring]
        if not intersects(points):
            return
        geometry = transform(world, wkb.loads(FACTORY.create_multipolygon(area), hex=True))
        geometry = make_valid(geometry).intersection(CLIP)
        triangles = constrained_delaunay_triangles(geometry)
        vertices = [[round(x, 3), round(y, 3)] for tri in triangles.geoms
                    for x, y in list(tri.exterior.coords)[:3]]
        if vertices:
            self.surfaces.append({"id": f"a{area.id}", "kind": kind, "triangles": vertices})
            self.counts[kind] += 1

    def way(self, way):
        tags = dict(way.tags)
        if tags.get("highway") not in {"footway", "path", "pedestrian", "cycleway"}:
            return
        if tags.get("area") == "yes" or tags.get("tunnel") == "yes":
            return
        try:
            points = [world(n.lon, n.lat) for n in way.nodes]
        except osmium.InvalidLocationError:
            return
        if intersects(points):
            self.paths.append({"id": f"w{way.id}", "points": [[round(x, 3), round(y, 3)] for x, y in points]})


if __name__ == "__main__":
    collector = Collector()
    collector.apply_file(str(PBF), locations=True)
    collector.surfaces.sort(key=lambda v: (v["kind"], v["id"]))
    collector.paths.sort(key=lambda v: v["id"])
    payload = {"schema_version": 1, "source": "OSM Kanto; original area rings including holes",
               "bounds": list(BOUNDS), "counts": dict(collector.counts),
               "surfaces": collector.surfaces, "paths": collector.paths}
    OUTPUT.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "counts": payload["counts"], "paths": len(collector.paths)}))
