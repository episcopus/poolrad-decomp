import sys
def dzx0(c):
    out=bytearray(); i=0; bm=0; bv=0; back=False; lastb=0
    def rb():
        nonlocal i
        v=c[i]; i+=1; return v
    def bit():
        nonlocal bm,bv,back
        if back:
            back=False; return lastb&1
        if bm==0:
            bm=128; bv=rb()
        b=1 if bv&bm else 0; bm>>=1; return b
    def gamma(inv):
        v=1
        while not bit():
            v=(v<<1)|(bit()^inv)
        return v
    last=1
    state='lit'
    while True:
        if state=='lit':
            n=gamma(0)
            for _ in range(n): out.append(rb())
            state='new' if bit() else 'rep'
        elif state=='rep':
            n=gamma(0)
            for _ in range(n): out.append(out[-last])
            state='new' if bit() else 'lit'
        else:
            m=gamma(1)
            if m==256: break
            lastb=rb()
            last=m*128-(lastb>>1)
            back=True
            n=gamma(0)+1
            for _ in range(n): out.append(out[-last])
            state='new' if bit() else 'lit'
    return bytes(out)
if __name__=='__main__':
    print(len(dzx0(open(sys.argv[1],'rb').read())))
