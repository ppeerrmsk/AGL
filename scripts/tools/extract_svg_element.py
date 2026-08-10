#!/usr/bin/env python3
"""从 SVG 中原样保留指定 id 元素及其祖先变换；不改写目标几何。"""

from __future__ import annotations

import argparse
from pathlib import Path
import xml.etree.ElementTree as ET


ET.register_namespace("", "http://www.w3.org/2000/svg")
ET.register_namespace("inkscape", "http://www.inkscape.org/namespaces/inkscape")
ET.register_namespace("sodipodi", "http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--id", required=True, dest="element_id")
    args = parser.parse_args()

    tree = ET.parse(args.input)
    root = tree.getroot()
    parent_of = {child: parent for parent in root.iter() for child in parent}
    target = next((node for node in root.iter() if node.get("id") == args.element_id), None)
    if target is None:
        raise SystemExit(f"SVG element not found: {args.element_id}")

    keep = {target}
    node = target
    while node in parent_of:
        node = parent_of[node]
        keep.add(node)

    for parent in list(root.iter()):
        for child in list(parent):
            if child not in keep:
                parent.remove(child)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    tree.write(args.output, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
