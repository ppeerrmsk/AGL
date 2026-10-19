import hashlib,importlib.util,json,pathlib,shutil,subprocess,sys,tempfile,unittest,zipfile
from unittest import mock
R=pathlib.Path(__file__).resolve().parents[1];O=R/'tmp/map-handoff-tool-tests';O.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('installer',R/'tools/install_tokyo_map_handoff.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=O);self.root=pathlib.Path(self.temp.name);(self.root/'project.godot').write_text('config_version=5\n');self.bundle=self.root/'bundle';self.bundle.mkdir()
        self.rows=[];name='tokyo-m20-runtime-20261014-part01.zip';self.archive=self.bundle/name
        with zipfile.ZipFile(self.archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
            for path,raw in [(m.PACKAGE,b'{"schema":1}'),(m.GATE,b'fixture')]:
                sha=hashlib.sha256(raw).hexdigest();z.writestr('blobs/'+sha,raw);self.rows.append({'path':path,'sha256':sha,'bytes':len(raw),'delivery':'release','archive':name})
        self.data={'schema':1,'package':m.PACKAGE,'package_sha256':self.rows[0]['sha256'],'files':self.rows,'archives':[{'name':name,'sha256':m.digest(self.archive),'bytes':self.archive.stat().st_size}]}
        raw=json.dumps(self.data).encode();(self.bundle/m.MANIFEST).write_bytes(raw);self.sha=hashlib.sha256(raw).hexdigest();self.loaded=m.load_manifest(self.bundle,self.sha)
    def tearDown(self):self.temp.cleanup()
    def test_manifest_identity_rejected(self):
        with self.assertRaises(ValueError):m.load_manifest(self.bundle,'0'*64)
    def test_escape_rejected(self):
        for path in ['resources/maps/../../../outside','C:/private','resources/maps/../../.git/config','resources\\maps\\x']:
            with self.assertRaises(ValueError):m.safe_path(self.root,path)
    def test_duplicate_paths_rejected(self):
        self.data['files'].append(self.rows[0]);raw=json.dumps(self.data).encode();(self.bundle/m.MANIFEST).write_bytes(raw)
        with self.assertRaises(ValueError):m.load_manifest(self.bundle,hashlib.sha256(raw).hexdigest())
    def test_archive_corruption_rejected(self):
        with self.archive.open('ab') as f:f.write(b'corrupt')
        with self.assertRaises(ValueError):m.verify_archive(self.bundle,self.loaded['archives'][0],{x['sha256']:x['bytes'] for x in self.rows})
    def test_unlisted_zip_entry_rejected(self):
        with zipfile.ZipFile(self.archive,'a') as z:z.writestr('../escape',b'bad')
        a=dict(self.loaded['archives'][0],sha256=m.digest(self.archive),bytes=self.archive.stat().st_size)
        with self.assertRaises(ValueError):m.verify_archive(self.bundle,a,{x['sha256']:x['bytes'] for x in self.rows})
    def test_existing_mismatch_preserved(self):
        p=self.root/m.GATE;p.parent.mkdir(parents=True);p.write_bytes(b'user-data')
        with self.assertRaises(ValueError):m.inspect_existing(self.root,self.rows[1])
        self.assertEqual(p.read_bytes(),b'user-data')
    def test_missing_git_dependency_rejected(self):
        with self.assertRaises(ValueError):m.inspect_existing(self.root,dict(self.rows[0],delivery='git'))
    def test_lock_preserved(self):
        p=self.root/'tmp/godot-bench.lock';p.mkdir(parents=True);(p/'owner.pid').write_text('123456')
        with mock.patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'','')):
            with self.assertRaises(FileExistsError):m.install(self.root,self.bundle,self.loaded,self.rows)
        self.assertEqual((p/'owner.pid').read_text(),'123456')
    def test_install_roundtrip_and_resume(self):
        m.verify_archive(self.bundle,self.loaded['archives'][0],{x['sha256']:x['bytes'] for x in self.rows})
        with mock.patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'','')):m.install(self.root,self.bundle,self.loaded,self.rows)
        for row in self.rows:self.assertTrue(m.inspect_existing(self.root,row)[1])
        self.assertFalse((self.root/'tmp/godot-bench.lock').exists());self.assertFalse((self.root/'resources/maps/tokyo_playable/m20/.gdignore').exists())
        m.install(self.root,self.bundle,self.loaded,[])
    def test_resume_after_all_files_written_removes_own_guards(self):
        with mock.patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'','')):
            m.install(self.root,self.bundle,self.loaded,self.rows)
            guards=[self.root/'resources/maps/tokyo_playable/m20/.gdignore',self.root/'resources/maps/tokyo_volume_preview/.gdignore']
            for guard in guards:guard.write_bytes(('map handoff installation '+self.sha+'\n').encode('ascii'))
            m.install(self.root,self.bundle,self.loaded,[])
        for guard in guards:self.assertFalse(guard.exists())
        for row in self.rows:self.assertTrue(m.inspect_existing(self.root,row)[1])
    def test_runner_preserves_nonzero_result_and_clears_overrides(self):
        (self.root/'tools').mkdir();shutil.copyfile(R/'tools/run_tokyo_map_handoff.ps1',self.root/'tools/run_tokyo_map_handoff.ps1')
        package=self.root/m.PACKAGE;package.parent.mkdir(parents=True);package.write_bytes(b'{"schema":1}')
        runner=self.root/'tools/run_tokyo_map_handoff.ps1';text=runner.read_text(encoding='utf-8-sig').replace('424e4aa1db195308389ffcce30ff672bc5b23851810801847199b4d9d572d858',m.digest(package));runner.write_text(text,encoding='utf-8-sig')
        gate=self.root/m.GATE;gate.parent.mkdir(parents=True);gate.write_bytes(b'fixture')
        (self.root/'.godot').mkdir();(self.root/'.godot/global_script_class_cache.cfg').write_text('fixture')
        (self.root/'bench').mkdir();(self.root/'bench/run.cmd').write_text('@echo off\necho ARGS=%*\nset AGL_\necho expected failure 1>&2\nexit /b 1\n')
        driver=self.root/'driver.ps1';driver.write_text("function Get-CimInstance { [pscustomobject]@{FreePhysicalMemory=16777216} }\n$env:AGL_TOKYO_VOLUME='off'\n$env:AGL_TOKYO_DIAGNOSTIC_VSYNC='off'\n& \"$PSScriptRoot/tools/run_tokyo_map_handoff.ps1\" -Scenario C1 -Duration 36\nexit $LASTEXITCODE\n",encoding='utf8')
        p=subprocess.run(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(driver)],capture_output=True,text=True,timeout=30)
        self.assertEqual(p.returncode,1,p.stderr)
        files=list((self.root/'tmp/map-runtime-repro').glob('*/result.json'));self.assertEqual(len(files),1,p.stderr)
        result=json.loads(files[0].read_text(encoding='utf-8-sig'));self.assertEqual(result['wrapper_exit'],1)
        request=json.loads((files[0].parent/'request.json').read_text(encoding='utf-8-sig'));self.assertNotIn('AGL_TOKYO_VOLUME',request['environment']);self.assertNotIn('AGL_TOKYO_DIAGNOSTIC_VSYNC',request['environment'])
        log=(files[0].parent/'wrapper.log').read_bytes()
        self.assertIn('ARGS=tokyo_volume_c1 36 300 Shadow Visual',log.decode('utf-16' if log.startswith(b'\xff\xfe') else 'utf-8-sig'))
if __name__=='__main__':unittest.main(verbosity=2)
