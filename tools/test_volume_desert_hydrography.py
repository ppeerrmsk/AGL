"""离线水面扫描条带的独立拓扑回归；不启动Godot、不编辑图片。"""
import json, math, tempfile, unittest
from pathlib import Path
from build_volume_desert_hydrography import ROOT, build, water_quads, Polygon, LineString, unary_union
from shapely.geometry import Point

class HydrographyTests(unittest.TestCase):
    def test_northeast_complete_way_and_partial_contour_preserved(self):
        source=ROOT/'tools/map_sources/desert_hydrography'
        raw=json.loads((source/'source-northeast-osm.json').read_text())
        entries={(e['type'],e['id']):e for e in raw['elements']}
        way=entries['way',159633265]
        data=json.loads((ROOT/'resources/maps/desert_volume_hydrography.json').read_text())
        river=next(r for r in data['rivers'] if r['way_id']==way['id'])
        self.assertEqual(river['tags'],way['tags'])
        self.assertEqual(way['tags'],{'intermittent':'yes','waterway':'river'})
        self.assertEqual(len(way['nodes']),102)
        self.assertEqual(len(river['paths']),1)
        self.assertEqual(len(river['paths'][0]),102)
        self.assertEqual(river['replaces_contours'],[20,23,25,26,28,30,33,36,38,39,40,44,47,51,62,73,74,76,77,80,83,85,87,88,89,90,93,99,100,101,102,104,105,106,109,111,112])
        self.assertIn(91,data['retained_contours'])
        relief=json.loads((ROOT/'resources/maps/desert_volume_relief.json').read_text())
        b=json.loads((ROOT/'resources/maps/desert_railway_bg_v2.json').read_text())['bbox_ll'];r=relief['world_rect']
        merc=lambda lat:math.log(math.tan(math.pi/4+math.radians(lat)/2))
        for identifier,point in zip(way['nodes'],river['paths'][0]):
            n=entries['node',identifier]
            expected=[r[0]+(n['lon']-b['lon_min'])/(b['lon_max']-b['lon_min'])*r[2],r[1]+(merc(b['lat_max'])-merc(n['lat']))/(merc(b['lat_max'])-merc(b['lat_min']))*r[3]]
            self.assertEqual(point,[round(v,5) for v in expected])
        line=LineString(river['paths'][0]);buffer=line.buffer(8)
        self.assertAlmostEqual(line.length,8508.46263765,places=3)
        self.assertEqual(river['confirmed_water_removed_length'],0)
        for index in river['replaces_contours']:
            polygon=Polygon(relief['water_contours'][index])
            self.assertGreater(polygon.intersection(buffer).area/polygon.area,.99999)
        partial=Polygon(relief['water_contours'][91])
        self.assertLess(partial.intersection(buffer).area/partial.area,.8)
        self.assertEqual(data['confirmed_water_contours'],[313,314,317,319,332])

    def test_western_supplement_preserves_source_and_confluence(self):
        source=ROOT/'tools/map_sources/desert_hydrography'
        data=json.loads((ROOT/'resources/maps/desert_volume_hydrography.json').read_text())
        raw=json.loads((source/'source-west-osm.json').read_text())
        entries={(e['type'],e['id']):e for e in raw['elements']}
        way=entries['way',343881407]
        river=next(r for r in data['rivers'] if r['way_id']==way['id'])
        main=next(r for r in data['rivers'] if r['way_id']==106879155)
        self.assertEqual(river['tags'],way['tags'])
        self.assertEqual(river['tags']['intermittent'],'yes')
        self.assertEqual(len(river['paths']),1)
        self.assertEqual(len(river['paths'][0]),48)
        self.assertEqual(way['nodes'][-1],3506676864)
        self.assertIn(river['paths'][0][-1],main['paths'][0][1:-1])
        self.assertNotIn(356276459,[r['way_id'] for r in data['rivers']])
        relief=json.loads((ROOT/'resources/maps/desert_volume_relief.json').read_text())
        meta=json.loads((ROOT/'resources/maps/desert_railway_bg_v2.json').read_text())
        b,r=meta['bbox_ll'],relief['world_rect']
        merc=lambda t:math.log(math.tan(math.pi/4+math.radians(t)/2))
        for identifier,point in zip(way['nodes'],river['paths'][0]):
            n=entries['node',identifier]
            expected=[r[0]+(n['lon']-b['lon_min'])/(b['lon_max']-b['lon_min'])*r[2],
                r[1]+(merc(b['lat_max'])-merc(n['lat']))/(merc(b['lat_max'])-merc(b['lat_min']))*r[3]]
            self.assertEqual(point,[round(v,5) for v in expected])
        self.assertEqual(data['confirmed_water_contours'],[313,314,317,319,332])
        self.assertEqual(river['replaces_contours'],[421,426,439,440,444,445,446,447,449,451,
            452,453,454,455,457,459,461,467,468,470,471,474,481,486,487,488,489,491,497,
            502,505,508,515,517,518,520,521,523])
        footprint=LineString(river['paths'][0]).buffer(8)
        for i in river['replaces_contours']:
            poly=Polygon(relief['water_contours'][i])
            self.assertGreater(poly.intersection(footprint).area/poly.area,.99999)

    def test_hole_stays_dry(self):
        outer=[[0,0],[10,0],[10,10],[0,10],[0,0]]
        hole=[[3,3],[7,3],[7,7],[3,7],[3,3]]
        fill=unary_union([Polygon(p) for p in water_quads([outer,hole])])
        self.assertAlmostEqual(fill.area,84)
        self.assertAlmostEqual(fill.intersection(Polygon(hole)).area,0)

    def test_separate_pools_do_not_bridge(self):
        a=[[0,0],[2,0],[2,2],[0,2],[0,0]]
        b=[[5,0],[7,0],[7,2],[5,2],[5,0]]
        fill=unary_union([Polygon(p) for p in water_quads([a,b])])
        self.assertEqual(len(fill.geoms),2)
        self.assertAlmostEqual(fill.area,8)

    def test_production_data_rebuilds_exactly(self):
        with tempfile.TemporaryDirectory(prefix='agl-hydrography-test-') as directory:
            path=Path(directory)/'hydrography.json'
            build(path)
            self.assertEqual(path.read_bytes(),(ROOT/'resources/maps/desert_volume_hydrography.json').read_bytes())

    def test_unclassified_color_blob_does_not_cut_western_creek(self):
        data=json.loads((ROOT/'resources/maps/desert_volume_hydrography.json').read_text(encoding='utf-8'))
        river=next(r for r in data['rivers'] if r['way_id']==106879155)
        self.assertEqual(len(river['paths']),1)
        line=LineString(river['paths'][0])
        # 旧裁边坐标取中点，允许此世界位置一个float32 ULP约0.001px；旧缺口半长仍大于40px。
        probe=Point(333.472145,9835.95134)
        self.assertGreater(min(probe.distance(Point(294.89542,9819.77344)),
                               probe.distance(Point(372.04887,9852.12924))),40)
        self.assertLess(line.distance(probe),.001)
        self.assertAlmostEqual(line.length+river['confirmed_water_removed_length'],river['in_bounds_length'],places=3)

if __name__=='__main__': unittest.main()
