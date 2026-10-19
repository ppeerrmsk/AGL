"""同一PBF的有界海岸构筑物面/线清单；不复用已过滤的城市缓存。"""
import argparse
import hashlib
import json
import time
from pathlib import Path
from build_tokyo_volume_region import osmium, FACTORY, wkb, transform, world_point
from build_tokyo_coastal_addendum import KINDS


class Collector(osmium.SimpleHandler):
    def __init__(self, bounds):
        super().__init__()
        self.bounds = bounds
        self.areas = []
        self.ways = []

    def intersects(self, points):
        return bool(points) and not (max(p[0] for p in points)<self.bounds[0]
            or min(p[0] for p in points)>self.bounds[2] or max(p[1] for p in points)<self.bounds[1]
            or min(p[1] for p in points)>self.bounds[3])

    def area(self, area):
        tags = dict(area.tags)
        if tags.get('man_made') not in KINDS:
            return
        points = [world_point(n.lon,n.lat) for ring in area.outer_rings() for n in ring]
        if not self.intersects(points):
            return
        shape = transform(lambda x,y,z=None: world_point(x,y),wkb.loads(FACTORY.create_multipolygon(area),hex=True))
        self.areas.append({'id':('w' if area.from_way() else 'r')+str(area.orig_id()),
            'tags':tags,'valid':shape.is_valid,'bounds':shape.bounds,'area_px2':shape.area,'wkb':shape.wkb_hex})

    def way(self, way):
        tags = dict(way.tags)
        if tags.get('man_made') not in KINDS:
            return
        points = [world_point(n.lon,n.lat) for n in way.nodes]
        if self.intersects(points):
            self.ways.append({'id':'w'+str(way.id),'tags':tags,'points':points,'closed':way.is_closed()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pbf',type=Path,required=True)
    parser.add_argument('--bounds',type=float,nargs=4,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output exists; keep previous evidence')
    if not args.bounds[0]<args.bounds[2] or not args.bounds[1]<args.bounds[3]:
        parser.error('invalid bounds')
    started = time.monotonic()
    collector = Collector(args.bounds)
    collector.apply_file(str(args.pbf),locations=True)
    with args.pbf.open('rb') as file:
        digest = hashlib.file_digest(file,'sha256').hexdigest()
    result = {'pbf':str(args.pbf.resolve()),'pbf_bytes':args.pbf.stat().st_size,'pbf_sha256':digest,
        'bounds':args.bounds,'areas':collector.areas,'ways':collector.ways,'elapsed_seconds':time.monotonic()-started}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x',encoding='utf-8') as file:
        json.dump(result,file,ensure_ascii=False,separators=(',',':'))
    print(json.dumps({'areas':len(result['areas']),'ways':len(result['ways']),'seconds':result['elapsed_seconds']}))


if __name__=='__main__':
    main()
