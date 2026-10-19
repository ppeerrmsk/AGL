"""R143同源范围重新认证：不重烘AO/固定地表，不修改原资产或运行时身份门。"""
import argparse
import copy
import hashlib
import json
import shutil
from collections import Counter
from pathlib import Path

BASE_SHA = '3f3842acb66ddb133cc1738dbaf775fb09f4ddbb7d2df13f8f7b0677f2aaca92'
DERIVED_SHA = 'f4139942c2708b515de82aa32f48c1de1f7cac6fe7b2eab37d9eee9047e2bc85'
RAIL_SHA = 'b2590118e3073a24099ee1b661a89238a796d6c4069d71122238246e7fc620d9'
RESIDENTIAL_SHA = 'c0311651371c29025b8db0a8618adb57a2faeb39ab59c4751ee743b3d9c346ca'
FIXED_SOURCE_SHA = 'fb133c7c1d5ee2f4b508752103d006e8083a266bab69b5549343f99fb1dfbf5d'
FIXED_INPUTS = (
    (11, 'r167-fixed-p11-bc3-a', '420384d7f4cb8a1ebbe2add04a2005548b24bf4eea4554257e53c87b76ffd422'),
    (0, 'r145-fixed-p0-bc3-c', '24bd9b383cee8a18ac0c1e4115b97f4eef1fb971cd4a5357d5aa7953ce53743b'),
    (1, 'r145-fixed-p1-bc3-c', 'f57dfced4940cbbf39b1f460bd76b99ff243a2fb0b3dcaccaee0a8ac99845904'),
    (3, 'r145-fixed-p3-bc3-c', '661803338bc24b2280064e2f2303bcc6b8e58e1419df5cdd42864087b3a2c089'),
    (12, 'r167-fixed-p12-bc3-a', 'e321424feef35744fc8a874fd1aebab01443340c5e5b2f2d2df37dff919599ff'),
    (13, 'r145-fixed-p13-bc3-c', '66313a032c1922ab0c08df7bab4e7215a23a56c15ee1e3e27b200123748523cc'),
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fixed_source_matches(data, row, source_dir, collision_sha, catalog_sha):
    """完整角点载荷和原生来源均相同才允许复用；不以面数相同代替同源。"""
    if (data.get('catalog_sha256') != catalog_sha or data.get('collision_sha256') != collision_sha
            or data.get('parent') != row.get('parent') or data.get('source') != row
            or data.get('original_fixed_faces') != row.get('triangles')):
        return False
    filename = row.get('file', '')
    count = row.get('triangles')
    if (not filename or Path(filename).name != filename or not isinstance(count, int)
            or isinstance(count, bool) or count <= 0):
        return False
    payload = source_dir / filename
    native = Path(row['source'])
    return (payload.is_file() and native.is_file() and payload.stat().st_size == count * 120
            and digest(payload) == row['sha256'] and digest(native) == row['source_sha256'])


def revalidate_residential_fixed(root, output):
    """四片逐源认证加两片新烘焙组成有限集合，不改运行时许可或AO。"""
    root, output = root.resolve(), output.resolve()
    if output.parent != root or output.exists():
        raise ValueError('new sibling output required')
    source_dir = root / 'r164-fixed-source-a'
    source_path = source_dir / 'manifest.json'
    if (digest(root/'r162-native-b/catalog.res') != RESIDENTIAL_SHA
            or digest(root/'r143-native-a/catalog.res') != DERIVED_SHA
            or digest(source_path) != FIXED_SOURCE_SHA):
        raise ValueError('pinned catalog or source changed')
    native = json.loads(source_path.read_bytes())
    if native['catalog_sha256'] != RESIDENTIAL_SHA or native['configuration'] != 'lod2_full':
        raise ValueError('wrong native configuration')
    bundles = []
    for parent, directory, expected in FIXED_INPUTS:
        source = root / directory
        if digest(source/'manifest.json') != expected:
            raise ValueError('pinned compressed manifest changed')
        data = json.loads((source/'manifest.json').read_bytes())
        row = next(r for r in native['rows'] if r['parent'] == parent)
        fresh = parent in (11, 12)
        catalog = RESIDENTIAL_SHA if fresh else DERIVED_SHA
        if not fixed_source_matches(data, row, source_dir, native['collision_sha256'], catalog):
            raise ValueError('native fixed source mismatch')
        if fresh and data['source_manifest_sha256'] != FIXED_SOURCE_SHA:
            raise ValueError('rebaked source mismatch')
        files = {}
        for texture in data['rows']:
            filename = texture['file']
            if (Path(filename).name != filename or filename in files
                    or digest(source/filename) != texture['sha256']
                    or (source/filename).stat().st_size != texture['actual_bc3_bytes']):
                raise ValueError('unsafe, duplicate or changed texture')
            files[filename] = texture['sha256']
        data['catalog_sha256'] = RESIDENTIAL_SHA
        data['source_manifest_sha256'] = FIXED_SOURCE_SHA
        data['revalidation'] = dict(base_manifest_sha256=expected, base_catalog_sha256=catalog,
            native_source_sha256=FIXED_SOURCE_SHA, exact_native_payload_equal=True,
            unchanged_texture_payloads=True, reused_old_catalog=not fresh)
        bundles.append((parent, source, files, data))
    # 所有输入核验结束后才创建输出；不覆盖旧集合或认证不相关AO/Guard2。
    output.mkdir()
    entries = []
    for parent, source, files, data in bundles:
        target = output / ('parent_%02d' % parent)
        target.mkdir()
        for filename, expected in files.items():
            shutil.copy2(source/filename, target/filename)
            if digest(target/filename) != expected:
                raise ValueError('copied texture mismatch')
        (target/'manifest.json').write_text(json.dumps(data, indent=2), encoding='utf8')
        entries.append(dict(parent=parent, directory=target.as_posix(),
                            manifest_sha256=digest(target/'manifest.json')))
    collection = dict(schema=1, catalog_sha256=RESIDENTIAL_SHA, regions=entries)
    (output/'regions.json').write_text(json.dumps(collection, indent=2), encoding='utf8')
    report = dict(fail=0, catalog_sha256=RESIDENTIAL_SHA, source_manifest_sha256=FIXED_SOURCE_SHA,
        collection_sha256=digest(output/'regions.json'), regions=entries,
        source_verified_parents=[r[0] for r in bundles], reused_parents=[0,1,3,13],
        rebaked_parents=[11,12], unchanged_texture_payloads=12,
        step2_bytes=sum(b[3]['rows'][0]['actual_bc3_bytes'] for b in bundles),
        runtime_integrated=False, ao_certified=False, guard2_certified=False)
    (output/'revalidation.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(report))


def same_ao_source(before, after, rail=False):
    for key in ('schema', 'bounds', 'radius', 'collision_sha256', 'configuration'):
        if key not in before or before[key] != after.get(key):
            return False
    expected = (DERIVED_SHA, RAIL_SHA) if rail else (BASE_SHA, DERIVED_SHA)
    if (before.get('catalog_sha256'), after.get('catalog_sha256')) != expected:
        return False
    def faces(source):
        result = Counter()
        for row in source.get('triangles', []):
            points = tuple(tuple(p) for p in row['points'])
            if len(points) != 3 or any(len(p) != 3 for p in points):
                raise ValueError('malformed native AO triangle')
            # 允许面序及循环起点重排，不允许反转、丢失、重复或更改高度。
            ring = min(points[n:] + points[:n] for n in range(3))
            result[(row['parent'], row['kind'], ring)] += 1
        return result
    original = faces(before)
    return bool(original) and original == faces(after)


def revalidate_rail_ao(root, output):
    """仅认证有限铁路目录的AO，不把固定地表误纳入等价证明。"""
    root, output = root.resolve(), output.resolve()
    if output.parent != root or output.exists():
        raise ValueError('new sibling output required')
    paths = [root/'r143-west-source-a.json', root/'r151-west-source-a.json']
    before, after = [json.loads(p.read_bytes()) for p in paths]
    if digest(root/'r143-native-a/catalog.res') != DERIVED_SHA or digest(root/'r150-native-a/catalog.res') != RAIL_SHA or not same_ao_source(before, after, rail=True):
        raise ValueError('native catalog or AO window changed')
    for source in (before, after):
        if len(source['sources']) != 16 or any(digest(Path(r['path'])) != r['sha256'] for r in source['sources']):
            raise ValueError('native source payload changed after export')
    source = root/'r143-auxiliary-a/ao'
    data = json.loads((source/'manifest.json').read_bytes())
    if data['catalog_sha256'] != DERIVED_SHA or data['source_sha256'] != digest(paths[0]):
        raise ValueError('baked source identity mismatch')
    files = {data['palette']: data['palette_sha256']}
    for row in data['rows']:
        for key in ('ao', 'height'):
            filename, expected = row[key], row[key+'_sha256']
            if filename in files and files[filename] != expected:
                raise ValueError('conflicting payload identity')
            files[filename] = expected
    for filename, expected in files.items():
        if Path(filename).name != filename or digest(source/filename) != expected:
            raise ValueError('unsafe or changed texture')
    data['catalog_sha256'] = RAIL_SHA
    data['source_sha256'] = digest(paths[1])
    data['revalidation'] = dict(base_manifest_sha256=digest(source/'manifest.json'),
        base_catalog_sha256=DERIVED_SHA, native_source_sha256=digest(paths[1]),
        unchanged_texture_payloads=True, exact_directed_faces_equal=True,
        fixed_atlas_certified=False)
    output.mkdir()
    target = output/'ao'
    target.mkdir()
    for filename, expected in files.items():
        shutil.copy2(source/filename, target/filename)
        if digest(target/filename) != expected:
            raise ValueError('copied texture mismatch')
    (target/'manifest.json').write_text(json.dumps(data, indent=2), encoding='utf8')
    report = dict(fail=0, catalog_sha256=RAIL_SHA, native_ao_triangles=len(after['triangles']),
        no_rebake=True, payloads=len(files), manifest_sha256=digest(target/'manifest.json'),
        fixed_atlas_certified=False, runtime_integrated=False)
    (output/'revalidation.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(report))


def revalidate(root, output):
    root, output = root.resolve(), output.resolve()
    if output.parent != root or output.exists():
        raise ValueError('new sibling output required')
    old_source_path, new_source_path = root/'r140-west-source-a.json', root/'r143-west-source-a.json'
    before, after = [json.loads(p.read_bytes()) for p in (old_source_path, new_source_path)]
    if digest(root/'r139-native-b/catalog.res') != BASE_SHA or digest(root/'r143-native-a/catalog.res') != DERIVED_SHA or not same_ao_source(before, after):
        raise ValueError('native catalog or AO window changed')
    for source in (before, after):
        if len(source['sources']) != 16 or any(digest(Path(r['path'])) != r['sha256'] for r in source['sources']):
            raise ValueError('native source payload changed after export')
    audit_path = root/'r143-native-a/saved_audit.json'
    audit = json.loads(audit_path.read_bytes())
    if audit.get('catalog_sha256') != DERIVED_SHA or audit.get('fail') != 0 or audit.get('high_fixed_unchanged') is not True or audit.get('other_configurations_unchanged') is not True or audit.get('saved_faces') != 139694:
        raise ValueError('independent canonical conservation required')
    bundles = []
    for name, directory in [('ao', 'r140-west-bits-a'), ('fixed', 'r141-fixed-bc3-b')]:
        source = root/directory
        data = json.loads((source/'manifest.json').read_bytes())
        if data['catalog_sha256'] != BASE_SHA or (name == 'ao' and data['source_sha256'] != digest(old_source_path)):
            raise ValueError('baked source identity mismatch')
        files = {}
        for row in data['rows']:
            for key in (('ao', 'height') if name == 'ao' else ('file',)):
                filename = row[key]
                expected = row['sha256' if key == 'file' else key+'_sha256']
                if Path(filename).name != filename or digest(source/filename) != expected:
                    raise ValueError('unsafe or changed texture')
                files[filename] = expected
        if name == 'ao':
            filename = data['palette']
            if Path(filename).name != filename or digest(source/filename) != data['palette_sha256']:
                raise ValueError('changed height palette')
            files[filename] = data['palette_sha256']
        changed = copy.deepcopy(data)
        changed['catalog_sha256'] = DERIVED_SHA
        if name == 'ao':
            changed['source_sha256'] = digest(new_source_path)
        changed['revalidation'] = dict(base_manifest_sha256=digest(source/'manifest.json'),
            base_catalog_sha256=BASE_SHA, native_source_sha256=digest(new_source_path),
            saved_audit_sha256=digest(audit_path), unchanged_texture_payloads=True)
        bundles.append((name, source, files, changed))
    output.mkdir()
    for name, source, files, data in bundles:
        target = output/name
        target.mkdir()
        for filename, expected in files.items():
            shutil.copy2(source/filename, target/filename)
            if digest(target/filename) != expected:
                raise ValueError('copied texture mismatch')
        (target/'manifest.json').write_text(json.dumps(data, indent=2), encoding='utf8')
    report = dict(fail=0, native_ao_triangles=len(after['triangles']), catalog_sha256=DERIVED_SHA,
        saved_audit_sha256=digest(audit_path), no_rebake=True,
        manifests={name:digest(output/name/'manifest.json') for name, *_ in bundles})
    (output/'revalidation.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('output', type=Path)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--rail-ao-only', action='store_true')
    modes.add_argument('--residential-fixed-only', action='store_true')
    args = parser.parse_args()
    operation = revalidate_residential_fixed if args.residential_fixed_only else (revalidate_rail_ao if args.rail_ao_only else revalidate)
    operation(args.root, args.output)
