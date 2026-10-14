"""为既有来源生成独立坡顶候选；不重扫 PBF，不覆盖既有目录。"""
import argparse
import json
import shutil
import re
from collections import Counter
from pathlib import Path

from build_tokyo_volume_region import measure
from shapely.geometry import Polygon
from tokyo_tagged_roofs import tagged_roof


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--water-color", help="显式继承已验收地区的六位水色；不改海陆几何")
    args = parser.parse_args()
    if args.water_color and not re.fullmatch(r"[0-9a-fA-F]{6}", args.water_color):
        parser.error("water-color must contain exactly six hexadecimal digits")
    args.output.mkdir(parents=True, exist_ok=False)
    city = json.loads((args.source / "city.json").read_text(encoding="utf-8"))
    audit = {"built": [], "deferred": [], "shapes": {}}
    for raw in city["buildings"]:
        if raw.get("roof_shape", "flat") == "flat" or not raw.get("render_outline", True) or raw.get("defer_render"):
            continue
        tags = raw.get("source_tags", {})
        try:
            if tags.get("roof:direction"):
                raise ValueError("explicit_direction_not_yet_supported")
            if len(raw["rings"]) != 1:
                raise ValueError("multiple_roof_components")
            ring = raw["rings"][0]
            raw["roof_volume"] = tagged_roof(Polygon(ring["outer"], ring["holes"]), raw["height_m"],
                measure(tags.get("roof:height", "")), raw["roof_shape"], tags.get("roof:orientation", "along"), raw["min_height_m"])
            audit["built"].append({"id": raw["id"], "name": raw["name"], "shape": raw["roof_shape"],
                "height_m": raw["height_m"], "eave_px": raw["roof_volume"]["eave_px"],
                "triangles": (len(raw["roof_volume"]["roof"])+len(raw["roof_volume"]["walls"]))//3})
        except ValueError as error:
            audit["deferred"].append({"id": raw["id"], "shape": raw["roof_shape"], "reason": str(error)})
    audit["shapes"] = dict(Counter(item["shape"] for item in audit["built"]))
    (args.output / "city.json").write_text(json.dumps(city, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    if args.water_color:
        ground = json.loads((args.source / "ground.json").read_text(encoding="utf-8"))
        ground["water_color"] = args.water_color.lower()
        (args.output / "ground.json").write_text(json.dumps(ground, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    else:
        shutil.copyfile(args.source / "ground.json", args.output / "ground.json")
    (args.output / "roof_audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(audit, ensure_ascii=True))


if __name__ == "__main__":
    main()
