import unittest
import numpy as np
from tokyo_prepare_native_remainders import removal_ids


class RemainderTests(unittest.TestCase):
    def test_partition_preserves_retained_and_nonplanar(self):
        np.testing.assert_array_equal(removal_ids([0,2,4],[2],6),[0,4])
        np.testing.assert_array_equal(removal_ids([0,2],[0,2],3),[])

    def test_invalid_id_contract_rejected(self):
        for eligible,retained,faces in [([0,0],[],2),([0],[0,0],2),([0],[1],2),([3],[],3)]:
            with self.assertRaises(ValueError):removal_ids(eligible,retained,faces)


if __name__=='__main__':unittest.main()
