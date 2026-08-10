"""Build the self-contained Tokyo Bay V11 runtime preview resource.

The inputs intentionally live under tmp/ so Godot never scans research files.
The emitted JSON contains only ordinary vector geometry and provenance text;
no raster content or machine-local source paths are copied into the game.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / "tmp" / "vector_map_research"
OUTPUT = ROOT / "resources" / "maps" / "tokyo_bay_vector_preview.json"


def _read(name: str) -> dict:
    with (RESEARCH / name).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _flat_line(points: list[list[float]]) -> list[float]:
    out: list[float] = []
    for point in points:
        if len(point) >= 2:
            out.extend((round(float(point[0]), 2), round(float(point[1]), 2)))
    return out


def _lines(source: dict, key: str) -> list[list[float]]:
    return [flat for line in source.get(key, []) if len(flat := _flat_line(line)) >= 4]


def _polygons(source: dict, key: str) -> list[list[float]]:
    return [flat for poly in source.get(key, []) if len(flat := _flat_line(poly)) >= 6]


def main() -> None:
    water = _read("basemap_water_vectors.json")
    minor = _read("minor_roads_vectors.json")
    supplement = _read("v11_supplement_vectors.json")

    rings: list[dict] = []
    for entry in water.get("rings", []):
        flat = _flat_line(entry.get("points", []))
        if len(flat) < 6:
            continue
        rings.append(
            {
                "role": str(entry.get("role", "water")),
                "area_px2": round(float(entry.get("area_px2", 0.0)), 2),
                "points": flat,
            }
        )

    payload = {
        "schema_version": 1,
        "source": "OpenStreetMap plus V11 research vector bake, 2026-08-05",
        "trace_rect": [round(float(v), 3) for v in water.get("world_rect", [])],
        "water_rings": rings,
        "roads_tertiary": _lines(minor, "tertiary"),
        "roads_residential": _lines(supplement, "residential_roads"),
        "roads_service": _lines(supplement, "service_roads"),
        "runways": _lines(supplement, "runways"),
        "taxiways": _lines(supplement, "taxiways"),
        "aprons": _polygons(supplement, "aprons"),
        "port_lines": _lines(supplement, "port_lines"),
        "industrial": _polygons(supplement, "industrial"),
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")

    counts = {key: len(value) for key, value in payload.items() if isinstance(value, list)}
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size} bytes): {counts}")


if __name__ == "__main__":
    main()
