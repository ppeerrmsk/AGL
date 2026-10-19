"""离线安装已验证迁址清单；独占原bench锁，只复制原生文件，不启动引擎或改变默认路由。"""
import hashlib,json,os,shutil
from pathlib import Path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def child(base,relative):
    assert isinstance(relative,str) and relative and '\\' not in relative
    target=(base/relative).resolve()
    assert target.is_relative_to(base.resolve()) and target!=base.resolve(),('unsafe relative path',relative)
    return target


def copy_exact(source,target,expected,size):
    assert source.is_file() and source.stat().st_size==size
    if target.exists():
        assert target.is_file() and target.stat().st_size==size and digest(target)==expected,('existing target differs; no overwrite',str(target))
        assert digest(source)==expected
        return
    target.parent.mkdir(parents=True,exist_ok=True)
    partial=target.with_name(target.name+'.pending')
    checksum=hashlib.sha256()
    with source.open('rb') as source_file,partial.open('xb') as output:
        for block in iter(lambda:source_file.read(4*1024*1024),b''):
            output.write(block);checksum.update(block)
    assert checksum.hexdigest()==expected and partial.stat().st_size==size and digest(partial)==expected,('copy hash mismatch',str(source))
    partial.rename(target)


def install(project,package,source_root):
    project=project.resolve();package=package.resolve();source_root=source_root.resolve()
    assert package.is_relative_to(project/'tmp') and source_root.is_relative_to(project/'tmp')
    inventory_path=package/'inventory.json';inventory=json.loads(inventory_path.read_bytes())
    assert inventory['schema']==1 and inventory['paths_reversible'] is True and inventory['target']=='res://resources/maps/tokyo_full/'
    assert inventory['installed'] is False and inventory['geometry_copy_verified'] is False and len(inventory['coverage'])==11
    destination=project/'resources/maps/tokyo_full'
    assert destination.resolve()==destination,'Do not follow redirected installation paths'
    receipt=package/'copy-started.json';completed=package/'copy-completed.json'
    owner=dict(inventory_sha256=digest(inventory_path),destination=destination.as_posix())
    if receipt.exists():assert json.loads(receipt.read_bytes())==owner
    else:
        assert not destination.exists(),'Existing production directory has no matching receipt; preserve it'
        with receipt.open('x',encoding='utf8') as file:json.dump(owner,file,indent=2)
    tasks=[];targets=set()
    for row in inventory['copies']:
        source=Path(row['source']).resolve();target=child(destination,row['relative'])
        assert source.is_relative_to(source_root) and source.suffix=='.res' and target not in targets
        targets.add(target);tasks.append((source,target,row['sha256'],row['disk_bytes']))
    assert sum(row[3] for row in tasks)==inventory['geometry_disk_bytes']
    metadata=[('catalog.res',inventory['catalog_sha256']),('components.bin',inventory['components_sha256'])]
    metadata.extend((row['relative'],row['sha256']) for row in inventory['coverage'])
    for relative,expected in metadata:
        source=child(package,relative);target=child(destination,relative)
        assert target not in targets;targets.add(target)
        tasks.append((source,target,expected,source.stat().st_size))
    missing=sum(row[3] for row in tasks if not row[1].exists())
    assert shutil.disk_usage(project).free>=missing+1024**3,('insufficient free disk',missing)
    lock=project/'tmp/godot-bench.lock'
    lock.mkdir() # 原子拒绝任何活bench；不偷锁，不覆盖他人owner。
    pid=lock/'owner.pid'
    try:
        with pid.open('x',encoding='ascii') as file:file.write(str(os.getpid()))
        for index,args in enumerate(tasks):
            copy_exact(*args)
            if index%500==0:print('Verified portable files',index+1,'/',len(tasks),flush=True)
        report=dict(owner,files=len(tasks),geometry_files=len(inventory['copies']),geometry_bytes=inventory['geometry_disk_bytes'],
                    geometry_copy_verified=True,metadata_only_relocation=True,installed_candidate=True,default_enabled=False,visual_pass=False,performance_pass=False)
        if completed.exists():assert json.loads(completed.read_bytes())==report
        else:
            with completed.open('x',encoding='utf8') as file:json.dump(report,file,indent=2)
        return report
    finally:
        if pid.exists() and pid.read_text().strip()==str(os.getpid()):
            pid.unlink();lock.rmdir()


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('project',type=Path);parser.add_argument('package',type=Path);parser.add_argument('source_root',type=Path)
    args=parser.parse_args();print(json.dumps(install(args.project,args.package,args.source_root),indent=2))
