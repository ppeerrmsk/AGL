"""同高度地表纹理无损裁空、图集合批；不宣称GPU采样/覆盖验收。"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from build_tokyo_layered_ground import sha
from build_tokyo_fixed_atlas import mip_bytes


def crop_pixels(pixels):
    """保留非零RGBA外两像素；仅去除全零数据，不重新采样。"""
    yy, xx = np.where(np.any(pixels != 0, axis=2))
    if not len(xx):
        raise ValueError('empty source')
    x0, y0 = max(0, int(xx.min())-2), max(0, int(yy.min())-2)
    x1, y1 = min(pixels.shape[1], int(xx.max())+3), min(pixels.shape[0], int(yy.max())+3)
    crop = pixels[y0:y1, x0:x1].copy()
    restored = np.zeros_like(pixels)
    restored[y0:y1, x0:x1] = crop
    if not np.array_equal(restored, pixels):
        raise ValueError('crop lost source pixels')
    return crop, [x0, y0, x1, y1]


def quad_vertices(row, crop, atlas_rect, atlas_size, step):
    """裁空只收缩源几何边界，纹理padding绝不能获得地表所有权。"""
    source_bounds = np.asarray(row['texture_bounds'], dtype=np.float64)
    owner = np.asarray(row['geometry_bounds'], dtype=np.float64)
    crop_world = source_bounds[:2] + np.asarray(crop).reshape(2, 2) * step
    lower = np.maximum(owner[:2], crop_world[0])
    upper = np.minimum(owner[2:], crop_world[1])
    if np.any(upper <= lower) or step <= 0:
        raise ValueError('empty geometry or invalid texel step')
    xz = np.array([lower, [upper[0], lower[1]], upper, [lower[0], upper[1]]])
    uv = ((xz-source_bounds[:2])/step-np.asarray(crop[:2])+np.asarray(atlas_rect[:2]))/atlas_size
    vertices = np.column_stack([xz[:, 0], np.full(4, row['height']), xz[:, 1], uv])
    # X/Z地面正面朝上；不把纹理Y误当世界高度。
    return vertices[[0, 2, 1, 0, 3, 2]].astype('<f4')


def pack(source, expected, output, limit=2048):
    if output.exists() or sha(source) != expected:
        raise ValueError('source drift or existing output')
    manifest = json.loads(source.read_bytes())
    if manifest.get('runtime_integrated') or not manifest.get('premultiplied_alpha'):
        raise ValueError('wrong candidate contract')
    groups = {}
    for row in manifest['rows']:
        path = (source.parent / row['file']).resolve()
        if path.parent != source.parent.resolve() or sha(path) != row['sha256']:
            raise ValueError('texture identity drift')
        pixels = np.asarray(Image.open(path).convert('RGBA'))
        crop, rect = crop_pixels(pixels)
        groups.setdefault(row['height'], []).append((row, crop, rect))
    output.mkdir(parents=True)
    atlases, packed = [], []
    for height, items in sorted(groups.items()):
        pages = []
        for row, crop, rect in sorted(items, key=lambda item: (-item[1].shape[0], item[0]['file'])):
            h, w = crop.shape[:2]
            # 独立四像素环绕防线性采样串色；深层mip仍需逐级安全图集制作。
            aw, ah = ((w+8+3)//4)*4, ((h+8+3)//4)*4
            if max(aw, ah) > limit:
                raise ValueError('crop exceeds atlas bound')
            if not pages:
                pages.append(dict(x=0, y=0, shelf=0, width=0, height=0, items=[]))
            page = pages[-1]
            if page['x']+aw > limit:
                page['x'], page['y'], page['shelf'] = 0, page['y']+page['shelf'], 0
            if page['y']+ah > limit:
                page = dict(x=0, y=0, shelf=0, width=0, height=0, items=[])
                pages.append(page)
            page['items'].append((row, crop, rect, page['x']+4, page['y']+4))
            page['x'] += aw
            page['shelf'] = max(page['shelf'], ah)
            page['width'] = max(page['width'], page['x'])
            page['height'] = max(page['height'], page['y']+ah)
        for page in pages:
            pixels = np.zeros((page['height'], page['width'], 4), dtype=np.uint8)
            index = len(atlases)
            for row, crop, rect, x, y in page['items']:
                h, w = crop.shape[:2]
                pixels[y-4:y+h+4, x-4:x+w+4] = np.pad(crop, ((4,4),(4,4),(0,0)), mode='edge')
                packed.append(dict(source=row, crop=rect, atlas=index, atlas_rect=[x,y,x+w,y+h]))
            path = output/f'atlas_{index:03}.png'
            Image.fromarray(pixels).save(path)
            decoded = np.asarray(Image.open(path))
            for row, crop, rect, x, y in page['items']:
                if not np.array_equal(decoded[y:y+crop.shape[0], x:x+crop.shape[1]], crop):
                    raise ValueError('atlas roundtrip drift')
            atlases.append(dict(file=path.name, sha256=sha(path), height=height,
                                width=page['width'], height_pixels=page['height'],
                                rgba_mip_bytes=mip_bytes(page['width'], page['height']),
                                bc3_estimate_only=mip_bytes(page['width'], page['height'],16)))
    meshes = []
    for index, atlas in enumerate(atlases):
        rows = [r for r in packed if r['atlas'] == index]
        vertices = np.concatenate([quad_vertices(r['source'], r['crop'], r['atlas_rect'],
                                  np.array([atlas['width'], atlas['height_pixels']]),
                                  manifest['step']) for r in rows])
        path = output / f'mesh_{index:03}.xyzuv'
        vertices.tofile(path)
        if not np.array_equal(vertices, np.fromfile(path, dtype='<f4').reshape(-1, 5)):
            raise ValueError('mesh roundtrip drift')
        meshes.append(dict(file=path.name, sha256=sha(path), atlas=index,
                           vertices=len(vertices), faces=len(vertices)//3, bytes=path.stat().st_size))
    result = dict(schema=1, source=str(source.resolve()), source_sha256=expected,
                  atlases=atlases, rows=packed, meshes=meshes, mesh_format='little_endian_float32_XYZ_UV',
                  mesh_bytes=sum(m['bytes'] for m in meshes), source_faces=manifest['source_faces'],
                  candidate_faces=manifest['candidate_faces'], surfaces_before=manifest['surfaces_unbatched'],
                  surfaces_after_if_batched=len(atlases), rgba_mip_bytes_before=manifest['rgba_mip_bytes'],
                  rgba_mip_bytes=sum(a['rgba_mip_bytes'] for a in atlases),
                  bc3_estimate_only=sum(a['bc3_estimate_only'] for a in atlases),
                  base_pixels_lossless=True, mip_sampling_accepted=False,
                  runtime_integrated=False, coverage_proven=False, visual_accepted=False)
    (output/'manifest.json').write_text(json.dumps(result,indent=2), encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('rows','atlases','meshes')}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('expected')
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    pack(args.source, args.expected, args.output)
