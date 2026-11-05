"""构建显式远景概括候选：复用原生粗街区及其纹理，不修改正式资源。"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_binding(root: Path, binding: dict) -> dict:
    name = binding['path']
    if not name.startswith('res://resources/maps/tokyo_playable/') or '..' in name:
        raise ValueError('资源必须位于项目地图目录')
    path = root / name.removeprefix('res://')
    if digest(path) != binding['sha256']:
        raise ValueError(f'来源摘要不符：{name}')
    return json.loads(path.read_text(encoding='utf-8-sig'))


def validate_reuse(coarse: dict, original: dict, proof: dict, old_proof: dict) -> None:
    """覆盖凭据只随完全相同的真实几何复用；正式楼体与旧档逐页一致。"""
    if coarse['boundary_source_sha256'] != original['boundary_source_sha256']:
        raise ValueError('来源边界不同')
    if len(coarse['rows']) != 336 or len(original['rows']) != 336:
        raise ValueError('缺少完整空间树')
    old_rows = {(int(r['depth']), int(r['id'])): r for r in original['rows']}
    seen = set()
    for row in coarse['rows']:
        pair = (int(row['depth']), int(row['id']))
        if pair in seen or pair not in old_rows:
            raise ValueError('重复或未知页')
        seen.add(pair)
        old = old_rows[pair]
        for field in ['bounds', 'parent', 'children', 'formal_source_ids']:
            if row[field] != old[field]:
                raise ValueError(f'空间/正式来源变化：{pair}/{field}')
        key = f'{pair[0]}:{pair[1]}'
        page = proof['pages'][key]
        previous = old_proof['pages'][key]
        if page['geometry'] != row['native_geometry'] or previous['geometry'] != old['native_geometry']:
            raise ValueError('凭据不能迁移到不同几何')
        for field in ['formal_faces', 'formal_positions_sha256', 'formal_sources']:
            if page[field] != previous[field]:
                raise ValueError(f'正式楼体变化：{key}/{field}')


def build(root: Path, source: Path, output: Path, far_upper_scale: float = 0.25, motion_summary: bool = False) -> dict:
    if far_upper_scale not in [0.25, 0.4, 0.8]:
        raise ValueError('只支持已声明的远景候选范围')
    if motion_summary and far_upper_scale != 0.8:
        raise ValueError('运动概括只支持独立 0.8 远景候选')
    root, source, output = root.resolve(), source.resolve(), output.resolve()
    allowed = root / 'resources/maps/tokyo_playable'
    if not output.is_relative_to(allowed) or output == allowed or output.exists():
        raise ValueError('输出必须是尚不存在的项目地图候选目录')
    package = json.loads(source.read_text(encoding='utf-8-sig'))
    if len(package['catalogs']) != 7:
        raise ValueError('预期完整七档来源')
    coverage = read_binding(root, package['coverage'])
    coarse_binding = {k: package['catalogs'][1][k] for k in ['path', 'sha256']}
    coarse = read_binding(root, coarse_binding)
    proof_by_sha = {p['manifest']['sha256']: p for p in coverage['catalogs']}
    coarse_proof = proof_by_sha[coarse_binding['sha256']]
    replacements = {}
    for index in [3, 6]:
        binding = package['catalogs'][index]
        original = read_binding(root, binding)
        validate_reuse(coarse, original, coarse_proof, proof_by_sha[binding['sha256']])
        replacements[index] = original
    physical = {r[field]['path']: r[field]['sha256']
                for r in coarse['rows'] for field in ['native_geometry', 'native_texture']}
    for name, expected in physical.items():
        if not name.startswith('res://resources/maps/tokyo_playable/m20/'):
            raise ValueError('只复用已有 M20 物理资源')
        if digest(root / name.removeprefix('res://')) != expected:
            raise ValueError(f'真实资源摘要失败：{name}')
    # 所有来源验证完成后再写；任意失败都不覆盖旧候选或正式目录。
    output.mkdir()
    def save(name: str, data: dict) -> dict:
        path = output / name
        path.write_text(json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n', encoding='utf-8')
        return {'path': 'res://' + path.relative_to(root).as_posix(), 'sha256': digest(path)}
    recipe = {
        'schema': 1, 'candidate_only': True,
        'intent': '用户允许远景普通街区概括；复用较粗原生体块和同源纹理，主要地理轮廓与正式楼体保持。',
        'source_package': {'path': 'res://' + source.relative_to(root).as_posix(), 'sha256': digest(source)},
        'coarse_catalog': coarse_binding, 'replaced_catalog_indices': [3, 6],
        'source_quality_range': [coarse['min_scale'], coarse['max_scale']],
        'texture_world_units_per_texel': 8,
        'quality_changed': True, 'visual_accepted': False, 'performance_accepted': False,
        'display_budget_bytes': 96 * 1024 * 1024, 'faces_limit': 240000, 'page_limit': 16,
        'cache_budget_mib': 384, 'catalog_assets_unchanged': [0, 1, 2, 4, 5],
        'far_upper_scale': far_upper_scale,
        'resident_motion_summary': motion_summary,
        'motion_quality': '近景资源未齐时显示同源概括模型，正式楼体不变，后台继续细化；不阻塞镜头。' if motion_summary else '',
        'preferred_ranges_changed': [4, 6] if far_upper_scale > 0.625 else ([5, 6] if far_upper_scale > 0.25 else []),
    }
    recipe_binding = save('far_summary_recipe.json', recipe)
    result = copy.deepcopy(package)
    result['candidate_only'] = True
    result['far_summary_recipe'] = recipe_binding
    new_coverage = copy.deepcopy(coverage)
    for index, original in replacements.items():
        data = copy.deepcopy(coarse)
        data['min_scale'], data['max_scale'] = original['min_scale'], original['max_scale']
        if index == 6:
            data['max_scale'] = 10.0 if motion_summary else far_upper_scale
            if motion_summary:
                data['resident_motion_summary'] = {'schema': 1, 'preferred_max_scale': 0.8, 'formal_unchanged': True}
        # 显式新质量合同，不伪称原始精度不变或已经获得人工验收。
        data['far_summary_recipe'] = recipe_binding
        data['native_visual_accepted'] = False
        data['texture_error_accepted'] = False
        data['runtime_integrated'] = False
        binding = save(f'hlod_{index}.json', data)
        result['catalogs'][index].update(binding)
        new_proof = copy.deepcopy(coarse_proof)
        new_proof['manifest'] = binding
        new_coverage['catalogs'][index] = new_proof
    if far_upper_scale > 0.25:
        result['catalogs'][6]['range'][1] = far_upper_scale
        # 更宽概括层在运行时优先采用；保留中档作可用的交接表示，不能写出反向区间。
        result['catalogs'][4 if far_upper_scale > 0.625 else 5]['range'][0] = far_upper_scale
    new_coverage['installed'] = False
    new_coverage['native_runtime_verified'] = False
    result['coverage'] = save('coverage.json', new_coverage)
    package_binding = save('package.json', result)
    root_rows = [r for r in coarse['rows'] if r['depth'] == 0]
    return {
        'package': package_binding, 'recipe': recipe_binding, 'physical_files_verified': len(physical),
        'root_faces': sum(int(r['faces']) for r in root_rows),
        'root_mesh_bytes': sum(int(r['native_geometry']['bytes']) for r in root_rows),
        'root_texture_charge': sum(int(r['native_texture']['three_copy_charge']) for r in root_rows),
        'formal_sources': sum(len(r['formal_source_ids']) for r in root_rows),
        'default_changed': False, 'accepted': False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--far-upper-scale', type=float, default=0.25, choices=[0.25, 0.4, 0.8])
    parser.add_argument('--motion-summary', action='store_true')
    args = parser.parse_args()
    report = build(args.root, args.source, args.output, args.far_upper_scale, args.motion_summary)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
