"""轮廓距离门的正反例，不复跑未改动的采样/图集测试。"""
import unittest
from review_tokyo_path_candidate import within_ribbon_error


class RibbonReviewTests(unittest.TestCase):
    def test_minor_road_uses_real_width(self):
        self.assertTrue(within_ribbon_error([[0,0],[1,.01],[2,0]],[[0,0],[2,0]],width=3.0))
        self.assertFalse(within_ribbon_error([[0,0],[1,1],[2,0]],[[0,0],[2,0]],width=3.0))

    def test_small_bend(self):
        self.assertTrue(within_ribbon_error([[0,0],[1,.05],[2,0]],[[0,0],[2,0]]))

    def test_large_bend_rejected(self):
        self.assertFalse(within_ribbon_error([[0,0],[1,1],[2,0]],[[0,0],[2,0]]))

    def test_end_extension_rejected(self):
        self.assertFalse(within_ribbon_error([[0,0],[2,0]],[[0,0],[3,0]]))


if __name__=='__main__':
    unittest.main()
