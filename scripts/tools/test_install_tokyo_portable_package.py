import tempfile,unittest
from pathlib import Path
from install_tokyo_portable_package import child,copy_exact,digest


class CopyTests(unittest.TestCase):
    def test_exact_copy_and_reuse(self):
        with tempfile.TemporaryDirectory(prefix='agl-portable-test-') as name:
            root=Path(name);source=root/'source.res';source.write_bytes(bytes(range(256))*100)
            target=root/'new/file.res';expected=digest(source)
            copy_exact(source,target,expected,25600);copy_exact(source,target,expected,25600)
            self.assertEqual(source.read_bytes(),target.read_bytes())
            self.assertFalse(target.with_suffix('.res.pending').exists())

    def test_existing_conflict_is_preserved(self):
        with tempfile.TemporaryDirectory(prefix='agl-portable-test-') as name:
            root=Path(name);source=root/'source.res';source.write_bytes(b'original')
            target=root/'target.res';target.write_bytes(b'user work')
            with self.assertRaises(AssertionError):copy_exact(source,target,digest(source),source.stat().st_size)
            self.assertEqual(target.read_bytes(),b'user work')

    def test_bad_hash_does_not_publish(self):
        with tempfile.TemporaryDirectory(prefix='agl-portable-test-') as name:
            root=Path(name);source=root/'source.res';source.write_bytes(b'original');target=root/'target.res'
            with self.assertRaises(AssertionError):copy_exact(source,target,'0'*64,8)
            self.assertFalse(target.exists())

    def test_outside_relative_rejected(self):
        with tempfile.TemporaryDirectory(prefix='agl-portable-test-') as name:
            root=Path(name)
            for relative in ('../elsewhere','.','sub/../../elsewhere','sub\\bad'):
                with self.assertRaises(AssertionError):child(root,relative)
            self.assertEqual(child(root,'parts/good.res'),root/'parts/good.res')


if __name__=='__main__':unittest.main()
