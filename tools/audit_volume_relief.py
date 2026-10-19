"""只读复算历史 R11 曲面偏差；不执行当前 GDScript，不能用来判定 R12 修复失败。"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def audit(path: Path) -> dict:
    data = json.loads(path.read_text(encoding='utf-8'))
    if data['version'] != 11:
        raise ValueError('This historical R11 reproduction requires the v11 data layout.')
    n = data['grid_size']
    heights = np.asarray(data['heights']).reshape(n, n)
    rect = np.asarray(data['world_rect'])
    step = rect[2:] / (n - 1)

    def raw(points):
        uv = np.clip((np.asarray(points) - rect[:2]) / step, 0, n - 1.001)
        base = uv.astype(int)
        x, y = base.T
        u, v = (uv - base).T
        return ((1-u)*(1-v)*heights[y, x] + u*(1-v)*heights[y, x+1]
                + (1-u)*v*heights[y+1, x] + u*v*heights[y+1, x+1])

    def rendered(points):
        # 与 plane_mesh 的统一两格格网及 NW-SE 对角三角形一致；不计层偏置。
        uv = np.clip((np.asarray(points) - rect[:2]) / step, 0, n - 1.001)
        base = (uv / 2).astype(int) * 2
        x, y = base.T
        u, v = ((uv - base) / 2).T
        a, b, c, d = heights[y, x], heights[y, x+2], heights[y+2, x+2], heights[y+2, x]
        return np.where(u >= v, a*(1-u)+b*(u-v)+c*v, a*(1-v)+c*u+d*(v-u))

    plants = np.asarray(data['vegetation'])
    positions = plants[:, :2]
    residual = raw(positions) - rendered(positions)
    worst = np.argsort(np.abs(residual))[-5:][::-1]
    # 同一底面位置：瓦片裁边插入的 raw 高度未必落在 Strategic 的三角面上。
    manifest = json.loads((ROOT/'resources/maps/basemap_tiles/desert/manifest.json').read_text())
    boundaries = {}
    for name in ('operational', 'detail'):
        level = manifest['levels'][name]
        world_vertices = []
        for tile in level['tiles']:
            x, y, w, h = tile['content_rect']
            low = rect[:2] + np.array([x, y])/level['size']*rect[2:]
            high = rect[:2] + np.array([x+w, y+h])/level['size']*rect[2:]
            axes = []
            for axis in (0, 1):
                fixed = rect[axis] + np.arange(0, n, 2)*step[axis]
                axes.append(np.r_[low[axis], fixed[(fixed > low[axis]+0.01) & (fixed < high[axis]-0.01)], high[axis]])
            for px in (low[0], high[0]):
                world_vertices.extend((px, pz) for pz in axes[1])
            for pz in (low[1], high[1]):
                world_vertices.extend((px, pz) for px in axes[0])
        probes = np.asarray(world_vertices)
        error = raw(probes) - rendered(probes)
        boundaries[name] = {'samples': len(probes), 'over_1px': int(np.sum(np.abs(error) > 1)),
                            'max_abs_error_px': float(np.max(np.abs(error)))}
    half = np.array([1600, 900]) / (2*0.65)
    counts = np.array([np.all(np.abs(positions-center) < half, axis=1).sum() for center in positions])
    best = int(np.argmax(counts))
    sites = {}
    for label, center in [('lake', (11227, 43)), ('rail', (2450, 1150)),
                          ('relief', (-11000, -10500)), ('ridge', (-5900, -6250)),
                          ('industrial', (4800, 400))]:
        site = {}
        for zoom in (0.26, 0.65):
            # 1600x900 无旋转底面矩形；HUD/云/高度位移遮挡不在离线证明范围内。
            half = np.array([1600, 900]) / (2*zoom)
            visible = np.all(np.abs(positions - center) < half, axis=1)
            xs = np.linspace(center[0]-half[0], center[0]+half[0], 41)
            zs = np.linspace(center[1]-half[1], center[1]+half[1], 25)
            points = np.array(np.meshgrid(xs, zs)).reshape(2, -1).T
            levels = rendered(points)
            site[str(zoom)] = {'candidate_plant_centers': int(visible.sum()),
                               'height_span_px': round(float(np.ptp(levels)), 3)}
        sites[label] = site
    return {'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'version': data['version'], 'plant_count': len(plants),
            'height_percentiles_px': np.percentile(heights, [0, 25, 50, 75, 95, 100]).tolist(),
            'plant_base_vs_strategic_surface': {
                'max_abs_error_px': float(np.max(np.abs(residual))),
                'above_2px': int(np.sum(residual > 2)), 'below_minus_2px': int(np.sum(residual < -2)),
                'worst': [{'point': positions[i].tolist(), 'delta_px': float(residual[i])} for i in worst]},
            'tile_boundary_vs_strategic_surface': boundaries,
            'additional_scrub_view': {'point': positions[best].tolist(), 'zoom': 0.65,
                                      'candidate_plant_centers': int(counts[best]),
                                      'rule': 'maximum center count among all existing plant centers; retain original views too'},
            'view_estimates': sites,
            'scope': 'Historical R11 CPU reproduction, NOT a check of the current R12 GDScript or Visual proof'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT/'resources/maps/desert_volume_relief.json')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = audit(args.source)
    text = json.dumps(result, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    print(text)
