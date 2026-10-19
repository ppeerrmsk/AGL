import unittest
import numpy as np
from pack_tokyo_ao_bits import pack5,unpack5


class HeightBitsTests(unittest.TestCase):
    def test_all_values_and_shifts(self):
        data=np.tile(np.arange(32,dtype=np.uint8),(8,1))
        for i in range(8):data[i]=np.roll(data[i],i)
        packed=pack5(data)
        np.testing.assert_array_equal(unpack5(packed),data)
        # 独立模拟GPU相邻字节解码，包括每行最后一个像素，不复用unpack5。
        for y in range(data.shape[0]):
            for x in range(data.shape[1]):
                bit=x*5; byte=bit//8
                value=(int(packed[y,byte])|(int(packed[y,min(byte+1,packed.shape[1]-1)])<<8))>>(bit%8)&31
                self.assertEqual(value,int(data[y,x]))

    def test_known_lsb_layout(self):
        data=np.zeros((1,8),dtype=np.uint8);data[0,0]=31;data[0,1]=31
        self.assertEqual(pack5(data).tolist(),[[255,3,0,0,0]])

    def test_full_deterministic_field(self):
        data=np.random.default_rng(105).integers(0,18,(2048,2048),dtype=np.uint8)
        packed=pack5(data)
        self.assertEqual(packed.shape,(2048,1280))
        self.assertEqual(packed.nbytes,2621440)
        np.testing.assert_array_equal(unpack5(packed),data)

    def test_reject(self):
        for value in [np.zeros((1,7),dtype=np.uint8),np.full((1,8),32,dtype=np.uint8),np.zeros((0,8),dtype=np.uint8),np.zeros((1,8)),np.zeros(8,dtype=np.uint8)]:
            with self.assertRaises(ValueError):pack5(value)
        for value in [np.zeros((1,4),dtype=np.uint8),np.zeros((0,5),dtype=np.uint8),np.zeros((1,5))]:
            with self.assertRaises(ValueError):unpack5(value)


if __name__=='__main__':unittest.main()
