import unittest
import numpy as np
from tokyo_sparse_mip_payload import encode_block, decode_block


class SparseMipTests(unittest.TestCase):
    def test_all_modes_and_unaligned_block_width(self):
        cases=[(np.full((7,5),0x12345678,dtype='<u4'),0),
               ((np.arange(1024)%3).astype('<u4').reshape(32,32),1),
               ((np.arange(1024)%300).astype('<u4').reshape(32,32),2),
               (np.arange(1024,dtype='<u4').reshape(32,32),3)]
        for block,expected in cases:
            mode,count,raw=encode_block(block)
            self.assertEqual(mode,expected)
            payload=b'\0'*8+raw
            restored=decode_block(payload,[mode,2,count,block.shape[1]],block.shape[0])
            self.assertTrue(np.array_equal(restored,block))

    def test_invalid_mode_rejected(self):
        with self.assertRaises(ValueError):decode_block(b'\0'*16,[4,0,1,1],1)

    def test_bitpacked_modes_and_tail(self):
        for count,mode in [(2,5),(3,6),(4,6),(5,8),(16,8)]:
            for w,h in [(31,17),(32,32),(1,31)]:
                block=(np.arange(w*h,dtype='<u4')%count).reshape(h,w)
                actual,n,raw=encode_block(block,bitpacked=True)
                self.assertEqual(actual,mode)
                self.assertTrue(np.array_equal(decode_block(b'\0'*12+raw,[actual,3,n,w],h),block))

    def test_invalid_bitpacked_payload(self):
        for payload,desc in [(b'', [5,0,2,4]), (b'\0'*20,[5,0,3,1]),
                             (b'\0'*12+b'\xff',[6,0,3,1])]:
            with self.assertRaises(ValueError):decode_block(payload,desc,1)


if __name__=='__main__':unittest.main()
