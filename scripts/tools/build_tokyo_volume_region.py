"""关系型东京城区候选：保留内院/来源高度，显式审计，不覆盖正式归档。"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tmp/tokyo-r3-pydeps"))
import osmium
from shapely import constrained_delaunay_triangles, make_valid, wkb
from shapely.geometry import Polygon, box
from shapely.ops import transform, unary_union
from shapely.strtree import STRtree

from build_tokyo_volume_preview import ROAD_WIDTHS, fallback_height, simplify, world_point

FACTORY = osmium.geom.WKBFactory()
DEFAULT_BOUNDS = (-520.0, -13870.0, 1120.0, -11590.0)


def measure(text: str) -> float:
    """只接受可解释的正数；不把 -2、未知文本或区间误记成真实标高。"""
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*(m|metres?|meters?|ft|feet|')?\s*(?:(\d+(?:\.\d+)?)\s*(in|\"))?\s*", text.lower())
    if not match:
        return 0.0
    value = float(match[1])
    if match[2] in {"ft", "feet", "'"}:
        value = value * 0.3048 + float(match[3] or 0) * 0.0254
    elif match[3] is not None:
        return 0.0
    return value


def heights(tags: dict, area: float, kind: str) -> tuple[float, str, float, list[str]]:
    errors = []
    height = measure(tags.get("height", ""))
    source = "height"
    if height <= 0:
        height = measure(tags.get("building:levels", "")) * 3.2
        source = "levels"
    if height <= 0:
        height = fallback_height(area, kind)
        source = "fallback"
    base = measure(tags.get("min_height", ""))
    if not tags.get("min_height"):
        base = measure(tags.get("building:min_level", "")) * 3.2
    if height > 640:
        errors.append("height_above_640m")
    if base >= height:
        errors.append("min_height_not_below_top")
    if tags.get("height") and measure(tags["height"]) <= 0:
        errors.append("invalid_height_tag")
    return min(640.0, max(3.2, height)), source, base, errors


def above_ground(tags: dict) -> bool:
    # layer 只是交叉处的相对上下顺序，负 layer 不等于地下。
    return not (tags.get("location") == "underground"
        or tags.get("tunnel", "no") not in {"no", "false", "0", ""}
        or tags.get("indoor", "no") not in {"no", "false", "0", ""})


def polygons(geometry):
    if geometry.geom_type == "Polygon":
        return [geometry]
    return [poly for member in getattr(geometry, "geoms", []) for poly in polygons(member)]


def vertices(ring) -> list[list[float]]:
    return [[round(x, 3), round(y, 3)] for x, y in list(ring.coords)[:-1]]


def triangulate(geometry) -> list[list[float]]:
    triangles = constrained_delaunay_triangles(geometry)
    return [[round(x, 3), round(y, 3)] for tri in triangles.geoms
        for x, y in list(tri.exterior.coords)[:3]]


class RegionCollector(osmium.SimpleHandler):
    def __init__(self, bounds):
        super().__init__()
        self.bounds = tuple(bounds)
        self.clip = box(*bounds)
        self.buildings = {}
        self.surfaces = []
        self.paths = []
        self.roads = []
        self.rails = []
        self.relations = {}
        self.counts = Counter()
        self.issues = []
        self.raw_areas = []
        self.raw_paths = []
        self.coastlines = []

    def intersects(self, points) -> bool:
        return bool(points) and not (max(x for x, y in points) < self.bounds[0]
            or min(x for x, y in points) > self.bounds[2]
            or max(y for x, y in points) < self.bounds[1]
            or min(y for x, y in points) > self.bounds[3])

    def relation(self, relation):
        tags = dict(relation.tags)
        if tags.get("building") or tags.get("building:part") or tags.get("type") == "building":
            self.relations[f"r{relation.id}"] = [{"id": f"{m.type}{m.ref}", "role": m.role} for m in relation.members]

    def area(self, area):
        tags = dict(area.tags)
        is_building = tags.get("building", "") not in {"", "no", "0", "false"} or tags.get("building:part", "") not in {"", "no", "0", "false"}
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
        if not is_building and not kind:
            return
        points = [world_point(n.lon, n.lat) for ring in area.outer_rings() for n in ring]
        if not self.intersects(points):
            return
        identity = ("w" if area.from_way() else "r") + str(area.orig_id())
        geometry = transform(lambda x, y, z=None: world_point(x, y), wkb.loads(FACTORY.create_multipolygon(area), hex=True))
        if not geometry.is_valid:
            self.issues.append({"id": identity, "kind": "repaired_invalid_polygon"})
            geometry = make_valid(geometry)
        self.consume_area(identity, tags, geometry, kind)

    def consume_area(self, identity, tags, geometry, kind):
        self.raw_areas.append({"id": identity, "tags": tags, "wkb": geometry.wkb_hex, "kind": kind})
        is_building = tags.get("building", "") not in {"", "no", "0", "false"} or tags.get("building:part", "") not in {"", "no", "0", "false"}
        if is_building:
            if tags.get("building") in {"no", "proposed", "demolished", "razed", "ruins"} or not above_ground(tags):
                self.counts["excluded_buildings"] += 1
            elif geometry.area >= 2:
                building_kind = "industrial" if tags.get("building") in {"industrial", "warehouse", "factory", "hangar"} else "urban"
                height, source, base, errors = heights(tags, geometry.area, building_kind)
                if tags.get("building") == "construction":
                    errors.append("construction_state_unverified")
                for error in errors:
                    self.issues.append({"id": identity, "kind": error, "tags": tags})
                self.buildings[identity] = {"id": identity, "name": tags.get("name", ""),
                    "geometry": geometry, "height_m": round(height, 3), "height_source": source,
                    "min_height_m": round(base, 3), "area_px2": round(geometry.area, 3),
                    "kind": building_kind, "building": tags.get("building", ""),
                    "is_part": tags.get("building:part", "no") not in {"no", "0", "false", ""},
                    "roof_shape": tags.get("roof:shape", "flat"), "source_tags": tags,
                    "aliases": [], "parts": [], "parents": [], "defer_render": base >= height}
        if kind and above_ground(tags):
            clipped = geometry.intersection(self.clip)
            triangles = triangulate(clipped)
            if triangles:
                self.surfaces.append({"id": identity, "kind": kind, "triangles": triangles})
                self.counts[f"surface_{kind}"] += 1

    def way(self, way):
        tags = dict(way.tags)
        if tags.get("natural") == "coastline":
            points = [world_point(n.lon, n.lat) for n in way.nodes]
            if self.intersects(points):
                self.coastlines.append(points)
            return
        highway, railway = tags.get("highway", ""), tags.get("railway", "")
        if highway not in set(ROAD_WIDTHS) | {"footway", "path", "pedestrian", "cycleway"} and railway not in {"rail", "light_rail", "subway"}:
            return
        try:
            points = [world_point(n.lon, n.lat) for n in way.nodes]
        except osmium.InvalidLocationError:
            return
        if len(points) < 2 or not self.intersects(points):
            return
        self.consume_path(f"w{way.id}", tags, points)

    def consume_path(self, identity, tags, points):
        self.raw_paths.append({"id": identity, "tags": tags, "points": points})
        highway, railway = tags.get("highway", ""), tags.get("railway", "")
        if not above_ground(tags) or railway == "subway":
            self.counts["excluded_paths"] += 1
            return
        points = [[round(x, 3), round(y, 3)] for x, y in simplify(points, 0.1)]
        record = {"id": identity, "points": points}
        if highway in ROAD_WIDTHS:
            self.roads.append({**record, "class": highway, "width_px": ROAD_WIDTHS[highway]})
        elif railway:
            self.rails.append({**record, "class": railway, "width_px": 1.2})
        elif tags.get("area") != "yes":
            self.paths.append(record)

    def load_cache(self, data):
        if not box(*data["bounds"]).covers(self.clip):
            raise ValueError("cache does not cover requested bounds")
        self.relations = data["relations"]
        self.coastlines = data.get("coastlines", [])
        for item in data["areas"]:
            geometry = wkb.loads(item["wkb"], hex=True)
            # 与 area() 的包络筛选一致：不能因重放改用精确多边形相交而少记边角来源。
            if geometry.envelope.intersects(self.clip):
                self.consume_area(item["id"], item["tags"], geometry, item["kind"])
        for item in data["paths"]:
            if self.intersects(item["points"]):
                self.consume_path(item["id"], item["tags"], item["points"])

    def source_cache(self):
        identities = {item["id"] for item in self.raw_areas}
        relations = {key: members for key, members in self.relations.items()
            if key in identities or any(member["id"] in identities for member in members)}
        return {"schema_version": 1, "bounds": self.bounds, "areas": self.raw_areas,
            "paths": self.raw_paths, "relations": relations, "coastlines": self.coastlines}

    def resolve_relations(self):
        duplicates = set()
        for identity, members in self.relations.items():
            if identity in self.buildings:
                parent = self.buildings[identity]
                for member in members:
                    child = self.buildings.get(member["id"])
                    if not child or child["is_part"] or member["role"] != "outer":
                        continue
                    same_outer = any(Polygon(p.exterior).equals(Polygon(q.exterior))
                        for p in polygons(parent["geometry"]) for q in polygons(child["geometry"]))
                    if not same_outer:
                        continue
                    if parent["height_source"] == "fallback" and child["height_source"] != "fallback":
                        parent["height_m"], parent["height_source"] = child["height_m"], child["height_source"]
                        parent["height_owner"] = child["id"]
                    elif parent["height_source"] != "fallback" and child["height_source"] != "fallback" and abs(parent["height_m"] - child["height_m"]) > 0.05:
                        self.issues.append({"id": identity, "kind": "member_height_conflict", "member": child["id"]})
                    parent["aliases"].append(child["id"])
                    duplicates.add(child["id"])
            outlines = [m["id"] for m in members if m["role"] == "outline" and m["id"] in self.buildings]
            parts = [m["id"] for m in members if m["role"] == "part" and m["id"] in self.buildings]
            for outline in outlines:
                self.buildings[outline]["parts"].extend(parts)
                for part in parts:
                    self.buildings[part]["parents"].append(outline)
        for identity in duplicates:
            self.buildings.pop(identity, None)
        self.counts["duplicate_outer_ways"] = len(duplicates)

    def export(self, baseline_path: Path | None):
        self.resolve_relations()
        self.resolve_parts()
        records = []
        for item in sorted(self.buildings.values(), key=lambda item: item["id"]):
            rings = []
            for poly in polygons(item.get("render_geometry", item["geometry"])):
                ring = {"outer": vertices(poly.exterior), "holes": [vertices(hole) for hole in poly.interiors], "triangles": triangulate(poly)}
                if item["height_source"] != "fallback" and item["height_m"] >= 24 and item["geometry"].area >= 35:
                    inset = poly.buffer(-0.45, join_style=2)
                    ring["inset_triangles"] = triangulate(inset)
                    ring["panel_triangles"] = triangulate(inset.buffer(-1.3, join_style=2))
                rings.append(ring)
            record = {key: value for key, value in item.items() if key not in {"geometry", "render_geometry"}}
            record["source_courtyards"] = sum(len(poly.interiors) for poly in polygons(item["geometry"]))
            record.update({"rings": rings, "points": rings[0]["outer"]})
            records.append(record)
            self.counts["parts" if item["is_part"] else "buildings"] += 1
            self.counts["height_" + item["height_source"]] += 1
            self.counts["courtyards"] += record["source_courtyards"]
            self.counts["render_holes"] += sum(len(ring["holes"]) for ring in rings)
            self.counts["multipolygon_buildings"] += int(item["id"].startswith("r"))
        # 空间相交只用于审计，不能据此静默去重或删除父楼。
        identities = list(self.buildings)
        geometries = [self.buildings[identity]["geometry"] for identity in identities]
        tree = STRtree(geometries)
        overlaps = []
        for index, geometry in enumerate(geometries):
            for other_raw in tree.query(geometry):
                other = int(other_raw)
                if other <= index:
                    continue
                overlap = geometry.intersection(geometries[other]).area
                if overlap > 0.5:
                    overlaps.append({"ids": [identities[index], identities[other]], "area_px2": round(overlap, 3),
                        "has_part": self.buildings[identities[index]]["is_part"] or self.buildings[identities[other]]["is_part"]})
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))["buildings"] if baseline_path else []
        lookup = {alias: item for item in records for alias in [item["id"], *item["aliases"]]}
        comparison = {"baseline_count": len(baseline), "missing": [], "height_changes": [], "courtyard_additions": []}
        for old in baseline:
            current = lookup.get(old["id"])
            if current is None:
                comparison["missing"].append(old["id"])
            elif abs(float(current["height_m"]) - float(old["height_m"])) > 0.05:
                comparison["height_changes"].append({"id": old["id"], "old": old["height_m"], "new": current["height_m"], "source": current["height_source"]})
            if current and current["source_courtyards"] > 0:
                comparison["courtyard_additions"].append(old["id"])
        counts = dict(sorted(self.counts.items()))
        width, height = self.bounds[2] - self.bounds[0], self.bounds[3] - self.bounds[1]
        city = {"schema_version": 2, "source": "OSM Kanto; assembled areas and explicit building parts",
            "center": [(self.bounds[0] + self.bounds[2]) / 2, (self.bounds[1] + self.bounds[3]) / 2],
            "rect": [self.bounds[0], self.bounds[1], width, height], "counts": counts,
            "buildings": records, "roads": sorted(self.roads, key=lambda r: r["id"]), "rails": sorted(self.rails, key=lambda r: r["id"])}
        ground = {"schema_version": 2, "bounds": self.bounds, "counts": counts,
            "surfaces": sorted(self.surfaces, key=lambda r: (r["kind"], r["id"])), "paths": sorted(self.paths, key=lambda r: r["id"])}
        audit = {"status": "candidate only; unresolved parts/overlaps require review", "bounds": self.bounds,
            "counts": counts, "comparison": comparison, "issues": self.issues, "overlaps": overlaps}
        return city, ground, audit

    def resolve_parts(self):
        outlines = [item for item in self.buildings.values() if not item["is_part"]]
        tree = STRtree([item["geometry"] for item in outlines])
        for part in [item for item in self.buildings.values() if item["is_part"]]:
            if part["parents"]:
                part["parent_link_source"] = "relation"
                continue
            candidates = [outlines[int(index)] for index in tree.query(part["geometry"])
                if outlines[int(index)]["geometry"].buffer(0.01).covers(part["geometry"])]
            if len(candidates) == 1:
                parent = candidates[0]
                part["parents"] = [parent["id"]]
                part["parent_link_source"] = "S3DB_containment"
                parent["parts"].append(part["id"])
            elif len(candidates) > 1:
                self.issues.append({"id": part["id"], "kind": "ambiguous_part_parent", "candidates": [item["id"] for item in candidates]})
        for parent in outlines:
            parent["parts"] = sorted(set(parent["parts"]))
            parts = [self.buildings[identity] for identity in parent["parts"] if identity in self.buildings and not self.buildings[identity].get("defer_render")]
            if not parts:
                parent["render_outline"] = True
                continue
            coverage = unary_union([part["geometry"] for part in parts]).intersection(parent["geometry"]).area / parent["geometry"].area
            parent["parts_coverage"] = round(coverage, 6)
            parent["render_outline"] = coverage < 0.995
            if coverage < 0.995:
                # 未覆盖部分保留父楼既有高度；覆盖部分只画分部，不叠整栋父楼。
                parent["render_geometry"] = parent["geometry"].difference(unary_union([part["geometry"] for part in parts if not part.get("defer_render")]))
                parent["parts_render_policy"] = "source_height_residual"
                self.issues.append({"id": parent["id"], "kind": "partial_parts_coverage", "coverage": round(coverage, 6), "render_policy": "source_height_residual"})
            else:
                self.counts["complete_part_assemblies"] += 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bounds", nargs=4, type=float, default=DEFAULT_BOUNDS)
    parser.add_argument("--pbf", type=Path, default=ROOT / "tmp/full_map_detail/kanto-latest.osm.pbf")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--source-cache", type=Path)
    parser.add_argument("--baseline", type=Path, default=ROOT / "resources/maps/tokyo_volume_preview/r1_tokyo_downtown.json")
    parser.add_argument("--no-baseline", action="store_true", help="新区域不与东京站旧片做跨区域 ID 对比")
    parser.add_argument("--coastal", action="store_true", help="以闭合有向岸线生成海陆，不使用全矩形陆地底面")
    args = parser.parse_args()
    if args.bounds[2] <= args.bounds[0] or args.bounds[3] <= args.bounds[1]:
        parser.error("bounds must have positive area")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    collector = RegionCollector(args.bounds)
    if args.source_cache:
        print("Replaying bounded source cache...", flush=True)
        collector.load_cache(json.loads(args.source_cache.read_text(encoding="utf-8")))
    else:
        print("Assembling OSM areas and source-tagged heights...", flush=True)
        collector.apply_file(str(args.pbf), locations=True)
    (args.output_dir / "source_cache.json").write_text(json.dumps(collector.source_cache(), ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("Auditing relation membership, courtyards and overlaps...", flush=True)
    city, ground, audit = collector.export(None if args.no_baseline else args.baseline)
    if args.coastal:
        from tokyo_coastal_faces import coastal_faces
        land, sea, audit["coastal"] = coastal_faces(args.bounds, collector.coastlines)
        ground["base_kind"] = "water"
        ground["surfaces"].insert(0, {"id": "source-coastal-land", "kind": "land", "triangles": triangulate(land)})
        audit["coastal"]["source"] = "directed OSM coastline, no raster tracing or gap filling"
    for name, data in zip(("city", "ground", "audit"), (city, ground, audit)):
        target = args.output_dir / f"{name}.json"
        target.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"{target}: {target.stat().st_size} bytes", flush=True)
    print(json.dumps(dict(collector.counts), ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
