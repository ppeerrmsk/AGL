"""离线融合云团；运行时只加载三角网格，不计算体积场。仅依赖 numpy。"""
from pathlib import Path
import json
import numpy as np


def bake(style, seed):
    rng = np.random.default_rng(seed)
    # x/y/z 为长轴/高度/横向；不同大小肩部围绕主团融合，不重复椭圆壳。
    presets = {
        'a': [(-1.2,0,.1,1,.55,.7),(-.3,.15,-.3,1,.7,.9),(.65,0,.1,1.1,.6,.75),(1.5,-.12,-.15,.7,.4,.55),(-.7,.35,.65,.6,.48,.55),(.45,.4,-.8,.55,.4,.55)],
        'b': [(-.9,0,0,1,.7,.8),(0,.3,.1,1.25,.95,1),(.95,.05,0,.9,.65,.85),(-.7,.65,-.4,.65,.65,.65),(.5,.85,-.2,.7,.75,.7),(.45,.1,.9,.7,.45,.65)],
        'c': [(-1.6,0,.05,.85,.55,.7),(-.8,.1,.3,.85,.55,.75),(.05,-.05,-.15,.9,.45,.65),(.85,-.15,-.3,.7,.35,.45),(1.45,-.2,-.05,.55,.25,.35),(1.9,-.25,-.25,.35,.18,.23),(-1.25,.3,-.65,.5,.35,.45)]
    }
    lobes = np.array(presets[style], dtype=float)
    lobes[:,:3] += rng.uniform(-.13,.13,lobes[:,:3].shape)
    lobes[:,3:] *= rng.uniform(.85,1.15,lobes[:,3:].shape)
    # 中尺度肩部打破大轮廓，附着主团，不撒独立球体。
    extra = []
    for l in lobes[:4]:
        for side in [-1,1]:
            extra.append([l[0]+rng.uniform(-.3,.3),l[1]+.15,l[2]+side*l[5]*.7,.35,.28,.35])
    lobes = np.concatenate([lobes,np.array(extra)])
    def field(p):
        q=(np.asarray(p)[...,None,:]-lobes[:,:3])/lobes[:,3:]
        return np.exp(-2*np.sum(q*q,axis=-1)).sum(axis=-1)-.62
    def normal(p):
        delta=(np.asarray(p)[...,None,:]-lobes[:,:3])
        w=np.exp(-2*np.sum((delta/lobes[:,3:])**2,axis=-1))
        n=np.sum(w[...,None]*delta/lobes[:,3:]**2,axis=-2)
        return n/np.maximum(np.linalg.norm(n,axis=-1,keepdims=True),1e-12)
    step=.18
    axes=[np.arange(-3.1,3.2,step),np.arange(-1.3,2.2,step),np.arange(-2,2.1,step)]
    grid=np.stack(np.meshgrid(*axes,indexing='ij'),axis=-1)
    vals=field(grid)
    offsets=np.array([(0,0,0),(1,0,0),(1,1,0),(0,1,0),(0,0,1),(1,0,1),(1,1,1),(0,1,1)])
    tets=[(0,1,2,6),(0,2,3,6),(0,3,7,6),(0,7,4,6),(0,4,5,6),(0,5,1,6)]
    edges=[(0,1),(0,2),(0,3),(1,2),(1,3),(2,3)]
    triangles=[]
    for idx in np.ndindex(*(np.array(vals.shape)-1)):
        ids=offsets+idx
        vs=vals[tuple(ids.T)]
        if np.all(vs>=0) or np.all(vs<0): continue
        ps=grid[tuple(ids.T)]
        for tet in tets:
            p=ps[list(tet)];v=vs[list(tet)]
            cuts=[p[a]+(p[b]-p[a])*v[a]/(v[a]-v[b]) for a,b in edges if (v[a]>=0)!=(v[b]>=0)]
            if len(cuts)<3: continue
            cuts=np.array(cuts);center=cuts.mean(axis=0);n=normal(center)
            u=cuts[0]-center;u/=np.linalg.norm(u);w=np.cross(n,u)
            order=np.argsort(np.arctan2((cuts-center)@w,(cuts-center)@u));cuts=cuts[order]
            for j in range(1,len(cuts)-1):
                face=np.array([cuts[0],cuts[j],cuts[j+1]])
                cross=np.cross(face[2]-face[0],face[1]-face[0])
                if np.linalg.norm(cross)<1e-16: continue
                if cross@n<0: face=face[[0,2,1]]
                triangles.extend(face)
    p=np.array(triangles);n=normal(p)
    assert np.isfinite(p).all() and len(p)//3<=6000
    return {'vertices':np.round(p,8).ravel().tolist(),'normals':np.round(n,6).ravel().tolist(),'triangles':len(p)//3}


def main():
    data={s:[bake(s,2700+i) for i in range(3)] for s in ['a','b','c']}
    path=Path(__file__).resolve().parents[1]/'resources/weather_cloud_shapes/compare.json'
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,separators=(',',':')),encoding='utf-8')
    print({s:[m['triangles'] for m in shapes] for s,shapes in data.items()})


if __name__=='__main__':
    main()
