"""离线颜色谱系审计反例：侧墙不能混进屋顶，读取不得修改原始载荷。"""
import tempfile
import unittest
from pathlib import Path

import numpy as np

from audit_tokyo_art_lineage import digest, roof_colors


class ArtLineageTest(unittest.TestCase):
    def test_only_upward_roofs_and_no_source_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.attributes'
            data = np.zeros((3, 3, 10), dtype='<f4')
            data[:, :, 9] = 1
            data[0, :, 4] = 1
            data[1, :, 3] = 1
            data[2, :, 4] = -1
            data[0, :, 6:9] = np.array([146, 151, 137]) / 255
            data[1:, :, 6:9] = np.array([116, 124, 121]) / 255
            data.tofile(path)
            before = digest(path)
            self.assertEqual(roof_colors(path), {'929789': 1})
            self.assertEqual(digest(path), before)


if __name__ == '__main__':
    unittest.main()
