# GH-5: rebuild the daily one-shot loader image after update-m1n1 replaced boot.bin with stock: Aura PR 268 image + the new stock
# boot.bin payload chain with the PR 933 J414s DTB swapped in. Run in a dir holding new-stock.bin (a copy of the stock boot.bin),
# then: sudo bash harness/usbtest/bootbin.sh install boot-daily-16.bin
import struct,hashlib,sys
M=b'\xd0\x0d\xfe\xed'
home='/home/jjr/Work/'
def load(p): return open(p,'rb').read()
def split(b):
    st=None;best=0
    for i in range(0,len(b)-8,4):
        if b[i:i+4]==M:
            o=i;n=0
            while b[o:o+4]==M:
                s=struct.unpack('>I',b[o+4:o+8])[0]
                if not 0x100<s<0x200000:break
                n+=1;o+=s
            if n>best:best=n;st=i
    ents=[];o=st
    for _ in range(best):
        s=struct.unpack('>I',b[o+4:o+8])[0];ents.append(b[o:o+s]);o+=s
    return st,ents,b[o:]
ns,ne,nt=split(load('new-stock.bin'))
ds,de,dt=split(load(home+'psci-test/boot-daily.bin'))
p13=load(home+'psci-test/p13-pmp.dtb')
idx=[i for i,e in enumerate(de) if e==p13]
print('p13 entry in daily:',idx)
assert len(idx)==1 and nt==dt
i=idx[0]
ne[i]=p13
aura=load(home+'src/aura-pr268/build/aura.bin')
assert load(home+'psci-test/boot-daily.bin')[:ds]==aura, 'aura image differs from daily'
out=aura+b''.join(ne)+nt
open('boot-daily-16.bin','wb').write(out)
print(len(out),hashlib.sha256(out).hexdigest()[:16],'changed entries vs daily:',[k for k in range(len(ne)) if ne[k]!=de[k]])
