"""补资源而不改选档策略时，独立核对候选与基线的全部调度字段。"""
import argparse
import json
from pathlib import Path


def policy(package):
    return [{k: v for k, v in row.items() if k not in ("path", "sha256")}
            for row in package["catalogs"]]


def verify(baseline, candidate):
    assert policy(candidate) == policy(baseline), "LOD scheduling policy changed or lost"
    ordered = sorted(row["range"] for row in candidate["catalogs"])
    assert all(a < b for a, b in ordered), "Invalid LOD interval"
    assert all(left[1] == right[0] for left, right in zip(ordered, ordered[1:])), "LOD intervals overlap or have gaps"
    for row in candidate["catalogs"]:
        if "prefer_native_above" in row:
            assert row["range"][0] <= row["prefer_native_above"] <= row["range"][1]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    verify(json.loads(args.baseline.read_bytes()), json.loads(args.candidate.read_bytes()))
    print("LOD scheduling policy preserved; all intervals contiguous, disjoint, and preferences retained")
