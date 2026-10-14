"""R66实际加载身份、共同预算、重复绘制与片区外像素独立审计。"""
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image


def screen_mask(bounds, shape, padding=2):
    """矩形先裁到屏幕；负端点不能被numpy解释为从末尾计数。"""
    mask = np.zeros(shape, dtype=bool)
    for x0, y0, x1, y1 in bounds:
        left, right = max(0, int(np.floor(x0-padding))), min(shape[1], int(np.ceil(x1+padding)))
        top, bottom = max(0, int(np.floor(y0-padding))), min(shape[0], int(np.ceil(y1+padding)))
        if right > left and bottom > top:
            mask[top:bottom, left:right] = True
    return mask


def shoreline_bytes(state):
    if not state.get('shoreline_required',False):
        return 0
    row=state.get('shoreline',{})
    faces=row.get('resident_faces')
    if isinstance(faces,bool) or not isinstance(faces,(int,float)) or not np.isfinite(faces) or faces<=0 or faces!=int(faces):
        raise ValueError('invalid resident shoreline faces')
    total=int(faces)*3*64*3
    if total>6*1024*1024 or row.get('reserved_bytes')!=total or not row.get('ready'):
        raise ValueError('shoreline reservation mismatch')
    return total


def fixed_atlas_bytes(state):
    if not state.get('fixed_atlas_required', False):
        return 0
    row = state.get('fixed_atlas', {})
    if isinstance(row.get('regions'), dict) and len(row['regions']) > 1:
        charges = {'11':1668112, '0':190912, '1':276784, '3':304000, '12':983632, '13':594928}
        for parent, member in row['regions'].items():
            step = member.get('texture_step', 2)
            if type(step) not in (int, float):
                raise ValueError('invalid fixed texture resolution')
            if step == 1 and parent == '11' and member.get('catalog_sha256') == 'c0311651371c29025b8db0a8618adb57a2faeb39ab59c4751ee743b3d9c346ca':
                charges['11'] = 6619840
            elif step != 2:
                raise ValueError('uncertified fixed texture resolution')
        if set(row['regions']) != set(charges) or not row.get('ready') or row.get('reserved_bytes') != sum(charges.values()):
            raise ValueError('fixed collection reservation mismatch')
        for parent, amount in charges.items():
            member = row['regions'][parent]
            if member.get('parent') != int(parent) or not member.get('ready') or member.get('reserved_bytes') != amount:
                raise ValueError('fixed collection member mismatch')
            warm = member.get('warm', {})
            if warm.get('state') != 'ready' or warm.get('reserved_bytes') != 0 or warm.get('peak_reserved_bytes') != 524288:
                raise ValueError('fixed collection warm viewport not released')
        return sum(charges.values())
    warm = row.get('warm', {})
    amount = 1668112
    if type(row.get('texture_step', 2)) not in (int, float):
        raise ValueError('invalid fixed texture resolution')
    if row.get('texture_step', 2) == 1 and row.get('parent') == 11 and row.get('catalog_sha256') == 'c0311651371c29025b8db0a8618adb57a2faeb39ab59c4751ee743b3d9c346ca':
        amount = 6619840
    elif row.get('texture_step', 2) != 2:
        raise ValueError('uncertified fixed texture resolution')
    if not row.get('ready') or row.get('reserved_bytes') != amount:
        raise ValueError('fixed atlas reservation mismatch')
    if warm.get('state') != 'ready' or warm.get('reserved_bytes') != 0 or warm.get('peak_reserved_bytes') != 524288:
        raise ValueError('fixed atlas warm viewport not released')
    return amount


def audit(directory):
    destination = directory/'r66_independent_audit.json'
    if destination.exists():
        raise ValueError('never overwrite evidence')
    route = json.loads((directory/'tokyo_r48_route.json').read_bytes())
    review = json.loads((directory/'r66_ao_preload_review.json').read_bytes())
    joint = route.get('city_state', {}).get('fixed_atlas_required', False)
    fail = route['fail']+review['fail']+int(len(review['rows']) != (11 if joint else 9))
    if joint:
        fail += int(not route.get('fixed_atlas_released_after_menu', False))
    fail += int(route['rendered_frames'] < 2 or not route['prepared_ao']['preloaded'])
    for key in ['same_overlay', 'same_viewport', 'no_same_view_reloads', 'released_after_menu', 'ao_released_after_menu']:
        fail += int(not route[key])
    records = []
    first = None
    for row in review['rows']:
        if row.get('rejected'):
            fail += 1
            continue
        state = row['state']
        fail += int(not row['same_resources'] or not row['geometry_collision_unchanged'] or not state['ao_ready'])
        encoding = state['ao_preloaded'].get('ao_encoding', 'r8')
        fail += int(encoding not in ['r8', 'bc4_unorm_mips'])
        ao_reservation = 20973096 if encoding == 'bc4_unorm_mips' else 29361664
        height_encoding=state['ao_preloaded'].get('height_encoding')
        fail+=int(height_encoding not in ['global_palette_r8','global_palette_r5_lsb'])
        if height_encoding=='global_palette_r5_lsb':
            ao_reservation-=4718592
            fail+=int(state['ao_preloaded'].get('height_storage_width')!=1280 or state['ao_preloaded'].get('height_size')!=2048)
        fail += int(state['ao_preloaded']['conservative_bytes'] != ao_reservation)
        if encoding == 'bc4_unorm_mips':
            fail += int(state['ao_preloaded'].get('ao_gpu_format') != 20 or not state['ao_preloaded'].get('rgtc_supported'))
            fail += int(state['ao_preloaded']['size'] != 2048 or state['ao_preloaded']['height_size'] != 2048)
        expected_auxiliary = ao_reservation + (128*1024 if state.get('projected_source_reserved', False) else 0) + shoreline_bytes(state) + fixed_atlas_bytes(state)
        fail += int(state['stream']['peak_total_bytes'] > 96*1024*1024 or state['stream']['auxiliary_bytes'] != expected_auxiliary)
        fail += int(state['ao_preloaded']['texture_id'] != route['prepared_ao']['texture_id'])
        zero, ao, repeated = [np.asarray(Image.open(row['stem']+'_'+name+'_native.png').convert('RGBA'), dtype=np.int16)
                              for name in ['zero', 'ao45', 'repeat']]
        mask = screen_mask(row['allowed_screen_bounds'], zero.shape[:2])
        delta = np.abs(ao-zero)
        outside = int(((delta.max(2)>1)&~mask).sum())
        repeat = int(np.abs(ao-repeated).max())
        fail += int(outside != 0 or repeat > 1 or not np.array_equal(zero[:,:,3],ao[:,:,3]))
        fail += int(not (delta.max() > 1))
        records.append({'pose': row['pose'], 'outside_gt1': outside, 'repeat_max': repeat,
                        'ao_pixels_gt1': int((delta.max(2)>1).sum()), 'ao_max': int(delta.max())})
        if row.get('native_atlas_pair'):
            native_zero, native_ao = [np.asarray(Image.open(row['stem']+'_'+name+'_native.png').convert('RGBA'), dtype=np.int16)
                                      for name in ['native_ground_zero', 'native_ground_ao45']]
            atlas_darkening = zero[:,:,:3] - ao[:,:,:3]
            native_darkening = native_zero[:,:,:3] - native_ao[:,:,:3]
            error = np.abs(atlas_darkening - native_darkening)
            records[-1]['same_cut_ground_pair'] = dict(
                native_ao_pixels_gt1=int((native_darkening.max(2)>1).sum()),
                atlas_ao_pixels_gt1=int((atlas_darkening.max(2)>1).sum()),
                native_darkening_sum=int(native_darkening.sum()), atlas_darkening_sum=int(atlas_darkening.sum()),
                delta_disagreement_gt1=int((error.max(2)>1).sum()), delta_error_max=int(error.max()),
                pixel_equivalence_claim=False)
        if 'variants' in row:
            fail += int(row['variants'] != ['ao25', 'ao45', 'ao65'])
            variant_records = []
            previous = zero
            for name in row['variants']:
                current = np.asarray(Image.open(row['stem']+'_'+name+'_native.png').convert('RGBA'), dtype=np.int16)
                change = np.abs(current-zero)
                outside_count = int(((change.max(2)>1)&~mask).sum())
                brighter = int(((current[:,:,:3]-previous[:,:,:3]).max(2)>1).sum())
                changed = int((change[:,:,:3].max(2)>1).sum())
                fail += int(outside_count != 0 or brighter != 0 or changed == 0 or not np.array_equal(current[:,:,3],zero[:,:,3]))
                variant_records.append(dict(name=name, outside_gt1=outside_count, brighter_gt1=brighter, changed_gt1=changed, max_delta=int(change.max())))
                previous = current
            restored = np.asarray(Image.open(row['stem']+'_restored_native.png').convert('RGBA'), dtype=np.int16)
            restore_max = int(np.abs(restored-zero).max())
            fail += int(restore_max > 1)
            records[-1].update(variants=variant_records, restore_max=restore_max)
        if first is None:
            first = ao
    roundtrip = int(np.abs(first-ao).max())
    # 往返机位差明确报告，不能把离散重复绘制等同连续相机的全轨迹门。
    result = {'fail': fail, 'records': records, 'roundtrip_max': roundtrip,
              'continuous_camera_gate': False, 'fps_evidence': False, 'cold_poses': review.get('cold_poses',False)}
    destination.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result))
    return int(fail > 0)


if __name__ == '__main__':
    raise SystemExit(audit(Path(sys.argv[1])))
