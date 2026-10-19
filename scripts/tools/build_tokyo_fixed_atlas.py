"""R141从原生固定三角烘焙远景图块；不消费屏幕截图或低清瓦片。"""
import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image
from build_tokyo_ao import height_field

CATALOG_SHA = '3f3842acb66ddb133cc1738dbaf775fb09f4ddbb7d2df13f8f7b0677f2aaca92'
RESIDENTIAL_CATALOG_SHA = 'c0311651371c29025b8db0a8618adb57a2faeb39ab59c4751ee743b3d9c346ca'
RESIDENTIAL_SOURCE_SHA = 'fb133c7c1d5ee2f4b508752103d006e8083a266bab69b5549343f99fb1dfbf5d'
CATALOG_SHAS = frozenset((CATALOG_SHA, 'f4139942c2708b515de82aa32f48c1de1f7cac6fe7b2eab37d9eee9047e2bc85', RESIDENTIAL_CATALOG_SHA))
MAX_SCALE = .3888


def valid_source_manifest(manifest):
    return (isinstance(manifest, dict) and manifest.get('schema') == 1 and
            manifest.get('record_bytes') == 120 and
            manifest.get('format') == 'little_endian_float32_3x_XYZ_NXYZ_RGBA' and
            isinstance(manifest.get('catalog_sha256'), str) and
            manifest['catalog_sha256'] in CATALOG_SHAS and manifest.get('configuration') == 'lod2_full')


def read_native(source, parent):
    manifest_raw = (source / 'manifest.json').read_bytes()
    manifest = json.loads(manifest_raw)
    if not valid_source_manifest(manifest):
        raise ValueError('native fixed source contract drift')
    # 新目录重新烘焙，不声明与旧固定层相同，更不放宽运行时复用门。
    if manifest['catalog_sha256'] == RESIDENTIAL_CATALOG_SHA and hashlib.sha256(manifest_raw).hexdigest() != RESIDENTIAL_SOURCE_SHA:
        raise ValueError('residential fixed source manifest drift')
    rows = manifest.get('rows', [])
    if len(rows) != 16 or sorted(r['parent'] for r in rows) != list(range(16)):
        raise ValueError('incomplete or duplicate parent matrix')
    row = next(r for r in rows if r['parent'] == parent)
    data_path = source / row['file']
    if data_path.resolve().parent != source.resolve():
        raise ValueError('source path escapes directory')
    raw = data_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != row['sha256'] or len(raw) != row['triangles'] * 120:
        raise ValueError('native fixed bytes drift')
    if hashlib.sha256(Path(row['source']).read_bytes()).hexdigest() != row['source_sha256']:
        raise ValueError('native resource drift')
    data = np.frombuffer(raw, dtype='<f4').reshape(-1, 3, 10)
    validate(data)
    return data, manifest, row


def validate(data):
    if data.ndim != 3 or data.shape[1:] != (3, 10) or not len(data) or not np.isfinite(data).all():
        raise ValueError('invalid fixed corners')
    if (np.any(data[:, :, 1] < -1) or np.any(data[:, :, 1] > 1) or
            not np.all(data[:, :, 1] == data[:, :1, 1]) or
            not np.all(data[:, :, 6:10] == data[:, :1, 6:10]) or
            not np.allclose(data[:, :, 3:6], [0, 1, 0], atol=2e-5) or
            np.any(data[:, :, 6:10] < 0) or np.any(data[:, :, 6:10] > 1) or
            not np.all(data[:, :, 9] == 1)):
        raise ValueError('unsupported slope, alpha, normal or corner interpolation')


def reduce_rgba(rgba, factor):
    if factor < 1 or isinstance(factor, bool) or rgba.shape[0] % factor or rgba.shape[1] % factor:
        raise ValueError('invalid area filter')
    h, w = rgba.shape[:2]
    area = rgba.reshape(h // factor, factor, w // factor, factor, 4)
    alpha = area[..., 3:4]
    mean_alpha = alpha.mean(axis=(1, 3))
    premul = (area[..., :3] * alpha).mean(axis=(1, 3))
    rgb = np.divide(premul, mean_alpha, out=np.zeros_like(premul), where=mean_alpha > 0)
    return np.concatenate([rgb, mean_alpha], axis=2)


def mip_bytes(width, height, block_bytes=None):
    total = 0
    while True:
        total += width * height * 4 if block_bytes is None else math.ceil(width / 4) * math.ceil(height / 4) * block_bytes
        if width == height == 1:
            return total
        width, height = max(1, width // 2), max(1, height // 2)


def opaque_rectangular_padding(filtered, data):
    # 只有真实矩形quad能拥有覆盖；不能把透明图块的洞无条件填满。
    import shapely
    triangles = data[:, :, [0, 2]].astype(np.float64)
    footprint = shapely.union_all(shapely.polygons(triangles))
    x0, y0, x1, y1 = footprint.bounds
    rectangle = shapely.box(x0, y0, x1, y1)
    if not footprint.equals(rectangle):
        # 全层浮点布尔运算可产生1e-12面积碎缝；不调容差。
        # 不透明最低层子集若已精确铺满AABB，且所有顶点都在其中，全集必然覆盖。
        lowest = triangles[data[:, 0, 1] == data[:, 0, 1].min()]
        if not shapely.union_all(shapely.polygons(lowest)).equals(rectangle):
            raise ValueError('opaque padding requires exact native rectangular footprint')
    occupied = filtered[:, :, 3] > 0
    yy, xx = np.where(occupied)
    if not len(xx) or not occupied[yy.min():yy.max()+1, xx.min():xx.max()+1].all():
        raise ValueError('opaque padding requires complete sampled rectangle')
    ys = np.clip(np.arange(filtered.shape[0]), yy.min(), yy.max())
    xs = np.clip(np.arange(filtered.shape[1]), xx.min(), xx.max())
    result = filtered[ys[:, None], xs[None, :]].copy()
    result[:, :, 3] = 1
    return result


def raster(data, step, supersample=2, opaque_padding=False):
    validate(data)
    if not math.isfinite(step) or step <= 0 or step * MAX_SCALE > 1.25:
        raise ValueError('far texture would exceed clarity bound')
    points = data[:, :, [0, 2]].reshape(-1, 2)
    lower = np.floor(points.min(axis=0) / step) * step - 2 * step
    count = np.ceil((points.max(axis=0) - lower) / step).astype(int) + 2
    count = ((count + 3) // 4) * 4
    # 复用已验像素中心最高面算法，方形工作区裁到实际NPOT尺寸，保留真实步长。
    width, height = map(int, count)
    size = max(width, height) * supersample
    bounds = [*lower, *(lower + max(width, height) * step)]
    field = np.full((height * supersample, width * supersample), -256, dtype=np.float32)
    rgba = np.zeros((*field.shape, 4), dtype=np.float32)
    ambiguous = np.zeros(field.shape, dtype=bool)
    # 每种原生颜色独立求最高面；同高不同色仅在真正可见重叠时拒绝。
    for color in np.unique(data[:, 0, 6:10], axis=0):
        selected = np.all(data[:, 0, 6:10] == color, axis=1)
        layer = height_field(data[selected, :, :3], bounds, size)[:height * supersample, :width * supersample]
        nearer = layer > field
        ambiguous[nearer] = False
        ambiguous |= (layer >= -1) & (layer == field) & np.any(rgba != color, axis=2)
        rgba[nearer] = color
        field[nearer] = layer[nearer]
    if ambiguous.any():
        raise ValueError(f'ambiguous visible coplanar samples: {int(ambiguous.sum())}')
    covered = field >= -1
    filtered = reduce_rgba(rgba, supersample)
    if opaque_padding:
        filtered = opaque_rectangular_padding(filtered, data)
    # 明确存预乘颜色；GPU线性/mip过滤后除alpha，避免透明padding染黑边缘。
    filtered[:, :, :3] *= filtered[:, :, 3:4]
    encoded = np.rint(np.clip(filtered, 0, 1) * 255).astype(np.uint8)
    return encoded, dict(bounds=[*lower.tolist(), *(lower + count * step).tolist()],
        native_bounds=[*points.min(axis=0).tolist(), *points.max(axis=0).tolist()],
        rectangular_coverage=bool(covered.sum() == round(float(np.prod(points.max(axis=0)-points.min(axis=0))) / step**2 * supersample**2)),
        premultiplied_alpha=True,
        opaque_rectangular_padding=bool(opaque_padding),
        width=width, height=height, world_step=step, max_scale=MAX_SCALE,
        source_pixel_output=step * MAX_SCALE, supersample=supersample,
        covered_samples=int(covered.sum()), total_samples=int(covered.size),
        height_range=[float(data[:, :, 1].min()), float(data[:, :, 1].max())],
        rgba_mip_bytes=mip_bytes(width, height),
        bc3_mip_bytes_estimate=mip_bytes(width, height, 16),
        bc3_three_copy_estimate=mip_bytes(width, height, 16) * 3,
        pixel_rounding_max=float(np.abs(encoded / 255 - filtered).max()))


def build(source, output, parent=11, opaque_padding=False):
    if output.exists():
        raise ValueError('never overwrite evidence')
    data, manifest, row = read_native(source, parent)
    output.mkdir(parents=True)
    rows = []
    for step in [2., 1.]:
        pixels, info = raster(data, step, opaque_padding=opaque_padding)
        path = output / f'parent_{parent:02d}_step_{int(step)}.png'
        Image.fromarray(pixels).save(path)
        if not np.array_equal(pixels, np.asarray(Image.open(path))):
            raise ValueError('PNG roundtrip drift')
        info.update(file=path.name, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        rows.append(info)
        print(json.dumps(info), flush=True)
    result = dict(schema=1, preview_only=True, catalog_sha256=manifest['catalog_sha256'],
        collision_sha256=manifest['collision_sha256'], source_manifest_sha256=hashlib.sha256((source/'manifest.json').read_bytes()).hexdigest(),
        source=row, parent=parent, original_fixed_faces=len(data), candidate_plane_faces=2,
        height_flattened=True, projected_height_error_accepted=False, gpu_compression_verified=False,
        native_visual_accepted=False, runtime_integrated=False, rows=rows)
    (output/'manifest.json').write_text(json.dumps(result, indent=2), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--parent', type=int, choices=range(16), default=11)
    parser.add_argument('--opaque-padding', action='store_true')
    args = parser.parse_args()
    build(args.source, args.output, args.parent, args.opaque_padding)
