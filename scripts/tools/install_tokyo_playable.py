"""安装已验证原生/贴图资源；复制产物，不改源数据，不启动引擎。"""
import argparse,json,hashlib,os,shutil,sys,re
from concurrent.futures import ThreadPoolExecutor,as_completed
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/tools'))
from install_tokyo_portable_package import copy_exact,digest
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('project',type=Path)
parser.add_argument('package',type=Path)
parser.add_argument('stage',type=Path)
parser.add_argument('--version',default='')
args=parser.parse_args()
project=args.project.resolve()
stage=args.stage.resolve()
assert stage.is_relative_to(project/'tmp')
assert args.package.resolve().is_relative_to(project/'tmp')
target=project/'resources/maps/tokyo_playable'
assert not args.version or re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*',args.version)
if args.version: target=target/args.version
assert target.resolve()==target,'Do not follow redirected installation paths'
prefix='res://resources/maps/tokyo_playable/'
if args.version: prefix+=args.version+'/'
package=json.loads(args.package.read_bytes())
inventory=json.loads((stage/'inventory.json').read_bytes())
assert inventory.get('target','res://resources/maps/tokyo_playable/')==prefix
package['native']=inventory['native']
copies={}

def source_path(value):
    value=str(value)
    source=(project/value[6:] if value.startswith('res://') else Path(value)).resolve()
    assert source.is_relative_to(project/'tmp') or source.is_relative_to(project/'resources')
    return source
def add(source,relative,sha):
    source=source_path(source)
    assert source.is_relative_to(project/'tmp') or source.is_relative_to(project/'resources')
    destination=(target/relative).resolve()
    assert destination.is_relative_to(target) and destination!=target
    entry=(source,destination,sha,source.stat().st_size)
    if destination in copies: assert copies[destination][2:]==entry[2:]
    else: copies[destination]=entry
def relocate(binding):
    item=dict(binding)
    source=source_path(item['path'])
    relative='assets/'+item['sha256']+source.suffix
    add(source,relative,item['sha256'])
    item['path']=prefix+relative
    return item
for row in inventory['copies']: add(row['source'],row['relative'],row['sha256'])
assert digest(Path(package['coverage']['path']))==package['coverage']['sha256']
coverage=json.loads(Path(package['coverage']['path']).read_bytes())
proofs=[];outputs={}
def json_output(relative,value):
    raw=json.dumps(value,indent=2).encode('utf8')
    outputs[relative]=raw
    return dict(path=prefix+relative,sha256=hashlib.sha256(raw).hexdigest())
for i,binding in enumerate(package['catalogs']):
    source=Path(binding['path']);assert digest(source)==binding['sha256']
    manifest=json.loads(source.read_bytes())
    proof=next(row for row in coverage['catalogs'] if row['manifest']['path']==binding['path'] and row['manifest']['sha256']==binding['sha256'])
    for row in manifest['rows']:
        original=dict(row['native_geometry'])
        row['native_geometry']=relocate(original)
        row['native_texture']=relocate(row['native_texture'])
        key=f"{int(row['depth'])}:{int(row['id'])}"
        assert proof['pages'][key]['geometry']['path']==original['path']
        proof['pages'][key]['geometry']=dict(row['native_geometry'])
    new=json_output(f'hlod_{i}.json',manifest)
    proof['manifest']=new;proofs.append(proof)
    binding.update(new)
coverage['catalogs']=proofs
package['coverage']=json_output('coverage.json',coverage)
json_output('package.json',package)
lock=project/'tmp/godot-bench.lock'
lock.mkdir()
owner=lock/'owner.pid'
try:
    owner.write_text(str(os.getpid()),encoding='ascii')
    missing=sum(row[3] for row in copies.values() if not row[1].exists())
    assert shutil.disk_usage(project).free>missing+1024**3
    print('Installing files',len(copies),'missing bytes',missing,flush=True)
    def copy_row(row):
        source,destination,sha,size=row
        pending=destination.with_name(destination.name+'.pending')
        if pending.exists():
            # 上次被中断的单文件不覆盖正式资源；保留可恢复副本再重做。
            quarantine=stage/'interrupted'
            quarantine.mkdir(exist_ok=True)
            saved=quarantine/pending.name
            assert not saved.exists() and saved.resolve().is_relative_to(stage)
            pending.rename(saved)
        copy_exact(source,destination,sha,size)
    # 只并行离线文件I/O；每个目标唯一，全部worker退出后才释放独占锁。
    with ThreadPoolExecutor(max_workers=8) as workers:
        pending_jobs=[workers.submit(copy_row,row) for row in copies.values()]
        for i,job in enumerate(as_completed(pending_jobs)):
            job.result()
            if i%1000==0: print('Verified files',i+1,flush=True)
    for relative,raw in outputs.items():
        path=target/relative
        if path.exists(): assert path.read_bytes()==raw
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            with path.open('xb') as f:f.write(raw)
    receipt=dict(files=len(copies),bytes=sum(row[3] for row in copies.values()),package_sha256=digest(target/'package.json'),path=prefix+'package.json',default_enabled=False)
    with (stage/'installed.json').open('x',encoding='utf8') as f:json.dump(receipt,f,indent=2)
    print(json.dumps(receipt),flush=True)
finally:
    if owner.exists() and owner.read_text()==str(os.getpid()):owner.unlink();lock.rmdir()
