import sys, struct
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 're'))
import dax
def load(file='GEO4', blk=21):
    b=[x for x in dax.read_dax(str(ROOT / 'poolrad' / ('%s.DAX' % file))) if x['id']==blk][0]
    p=dax.unrle(b['data'])[2:]
    ne,sw,ev,dr=p[0:256],p[256:512],p[512:768],p[768:1024]
    cells={}
    for r in range(16):
        for c in range(16):
            i=r*16+c
            cells[(r,c)]=dict(
              N=ne[i]>>4, E=ne[i]&15, S=sw[i]>>4, W=sw[i]&15,
              ev=ev[i]&0x7f, interior=bool(ev[i]&0x80),
              dN=dr[i]&3, dE=(dr[i]>>2)&3, dS=(dr[i]>>4)&3, dW=(dr[i]>>6)&3)
    return cells
if __name__=='__main__':
    cells=load()
    import collections
    k=collections.Counter()
    for (r,c),x in cells.items():
        for d in 'NESW':
            k[(x[d], x['d'+d])]+=1
    for key in sorted(k): print('wallid %2d doorbits %d : %d'%(key[0],key[1],k[key]))
