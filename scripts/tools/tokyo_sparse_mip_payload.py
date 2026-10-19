"""无损分块mip字节流：纯色/局部索引/原RGBA；只制作资源，不授予GPU资格。"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def encode_block(block, bitpacked=False):
    colors, ids = np.unique(block, return_inverse=True)
    if len(colors) == 1:
        return 0, 1, colors.astype('<u4').tobytes()
    if bitpacked and len(colors) <= 16:
        bits = 1 if len(colors) <= 2 else (2 if len(colors) <= 4 else 4)
        slots = np.arange(block.size)
        packed = np.zeros((block.size*bits+7)//8, dtype='u1')
        np.bitwise_or.at(packed, slots*bits//8, ids.astype('u1').reshape(-1) << (slots*bits%8))
        return 4+bits, len(colors), colors.astype('<u4').tobytes()+packed.tobytes()
    stride = 1 if len(colors) <= 256 else 2
    encoded = colors.astype('<u4').tobytes() + ids.astype('u1' if stride == 1 else '<u2').tobytes()
    if len(encoded) >= block.nbytes:
        return 3, 0, block.astype('<u4').tobytes()
    return stride, len(colors), encoded


def decode_block(payload, descriptor, height):
    mode, words, count, width = map(int, descriptor)
    offset = words * 4
    if min(height, width) <= 0 or words < 0:
        raise ValueError('invalid block dimensions or offset')
    if mode == 0:
        return np.full((height, width), np.frombuffer(payload, '<u4', 1, offset)[0], dtype='<u4')
    if mode == 3:
        return np.frombuffer(payload, '<u4', height * width, offset).reshape(height, width)
    if mode in (5, 6, 8):
        bits = mode-4
        if not 2 <= count <= 1 << bits:
            raise ValueError('invalid bit palette')
        palette = np.frombuffer(payload, '<u4', count, offset)
        packed = np.frombuffer(payload, 'u1', (height*width*bits+7)//8, offset+count*4)
        slots = np.arange(height*width)
        ids = (packed[slots*bits//8] >> (slots*bits%8)) & ((1 << bits)-1)
        if np.any(ids >= count):raise ValueError('invalid palette index')
        return palette[ids].reshape(height,width)
    if mode not in (1, 2):
        raise ValueError('invalid block mode')
    palette = np.frombuffer(payload, '<u4', count, offset)
    ids = np.frombuffer(payload, 'u1' if mode == 1 else '<u2', height * width, offset + count * 4)
    return palette[ids].reshape(height, width)


def build(bindings, output, block_size=32, bitpacked=False, deduplicate=False):
    output = Path(output)
    if output.exists() or block_size not in (32, 64):
        raise ValueError('invalid destination or block size')
    payload = bytearray(); descriptors = []; mips = []; tiles = []; sources = []; physical = {}
    for binding in bindings:
        if sha(binding['path']) != binding['sha256']:
            raise ValueError('manifest drift')
        manifest = json.loads(Path(binding['path']).read_text(encoding='utf-8'))
        for row in manifest['rows']:
            if sha(row['path']) != row['sha256']:
                raise ValueError('mip stream drift')
            raw = Path(row['path']).read_bytes()
            tiles.append([len(mips), len(row['levels'])]); sources.append(row)
            expected_offset = 0
            for level in row['levels']:
                w, h = int(level['width']), int(level['height'])
                if level['offset'] != expected_offset or min(w, h) <= 0:
                    raise ValueError('invalid mip offsets')
                expected_offset += w*h*4
                pixels = np.frombuffer(raw, '<u4', w*h, level['offset']).reshape(h, w)
                mips.append([w, h, len(descriptors), (w+block_size-1)//block_size])
                for y in range(0, h, block_size):
                    for x in range(0, w, block_size):
                        block = pixels[y:y+block_size, x:x+block_size]
                        mode, count, encoded = encode_block(block, bitpacked=bitpacked)
                        identity = (mode,count,block.shape,encoded)
                        if deduplicate and identity in physical:
                            word = physical[identity]
                        else:
                            payload.extend(bytes((-len(payload)) % 4));word=len(payload)//4
                            payload.extend(encoded)
                            if deduplicate:physical[identity]=word
                        descriptors.append([mode, word, count, block.shape[1]])
            if expected_offset != len(raw):
                raise ValueError('trailing mip data')
    payload.extend(bytes((-len(payload)) % 4))
    if max(len(payload)//4, len(descriptors), len(mips)) >= 2**24:
        raise ValueError('float table identity exceeds exact range')
    # RGBA8字节纹理宽4096，保存完整末行；表采用float32精确整数，避免兼容渲染器整数纹理要求。
    payload.extend(bytes((-len(payload)) % (4096*4)))
    output.mkdir(parents=True)
    files = {}
    arrays = {'payload': bytes(payload), 'blocks': np.asarray(descriptors, '<f4').tobytes(),
              'mips': np.asarray(mips, '<f4').tobytes(), 'tiles': np.asarray(tiles, '<f4').tobytes()}
    for name, raw in arrays.items():
        texel_bytes = 4 if name == 'payload' else (8 if name == 'tiles' else 16)
        raw += bytes((-len(raw)) % (4096*texel_bytes))
        arrays[name] = raw
        path = output/(name+'.bin'); path.write_bytes(raw)
        if path.read_bytes() != raw: raise ValueError('save mismatch')
        files[name] = {'path': str(path.resolve()), 'sha256': sha(path), 'bytes': len(raw),
                       'width':4096, 'height':len(raw)//(4096*texel_bytes),
                       'format':'RGBA8' if name=='payload' else ('RGF' if name=='tiles' else 'RGBAF')}
    saved = Path(files['payload']['path']).read_bytes()
    table = np.fromfile(files['blocks']['path'], dtype='<f4').reshape(-1, 4)
    for tile_id, row in enumerate(sources):
        raw = Path(row['path']).read_bytes()
        for level_id, level in enumerate(row['levels']):
            w, h, first, columns = mips[tiles[tile_id][0]+level_id]
            restored = np.empty((h,w), dtype='<u4')
            for y in range(0,h,block_size):
                for x in range(0,w,block_size):
                    desc = table[first+(y//block_size)*columns+x//block_size]
                    restored[y:y+block_size,x:x+block_size] = decode_block(saved, desc, min(block_size,h-y))
            expected = np.frombuffer(raw, '<u4', w*h, level['offset']).reshape(h,w)
            if not np.array_equal(expected, restored):raise ValueError('saved mip differs')
    report = {'sources':bindings, 'files':files, 'block_size':block_size, 'tile_count':len(tiles),
              'mip_count':len(mips), 'block_count':len(descriptors), 'payload_width':4096,
              'payload_height':len(payload)//(4096*4), 'three_copy_bytes':sum(len(v) for v in arrays.values())*3,
              'bitpacked':bitpacked, 'deduplicated':deduplicate,
              'all_saved_mip_pixels_exact':True, 'gpu_verified':False, 'runtime_integrated':False}
    (output/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    return report


if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('bindings');p.add_argument('output');a=p.parse_args()
    report=build(json.loads(Path(a.bindings).read_text())['source_bindings'],a.output)
    print(json.dumps({k:v for k,v in report.items() if k not in ('sources','files')}))
