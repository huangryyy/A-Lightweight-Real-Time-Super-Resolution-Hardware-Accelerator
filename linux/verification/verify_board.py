"""Full-frame, bit-exact board comparison against 3DIC's frozen integer golden.

Requires the new 8GR1 bitstream. Does not program the board or load a driver.
"""
import argparse,ctypes,hashlib,json,mmap,os,struct,time
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--model',type=Path,required=True)
p.add_argument('--output',type=Path,default=Path('board_3dic8'))
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
manifest=json.loads((a.model/'manifest.json').read_text())
def digest(b):return hashlib.sha256(b).hexdigest()
def transfer(fd,data,address,writing):
    done=0
    if writing:
        while done<len(data):
            n=os.pwrite(fd,data[done:],address+done)
            if not n:raise RuntimeError('Short/zero H2C transfer')
            done+=n
        return
    result=bytearray()
    while len(result)<data:
        piece=os.pread(fd,data-len(result),address+len(result))
        if not piece:raise RuntimeError('Short/zero C2H transfer')
        result.extend(piece)
    return bytes(result)

with open('/dev/xdma0_user','r+b',buffering=0) as u, open('/dev/xdma0_h2c_0','r+b',buffering=0) as h,open('/dev/xdma0_c2h_0','r+b',buffering=0) as c:
    with mmap.mmap(u.fileno(),4096) as regs:
        def read(off):return ctypes.c_uint32.from_buffer(regs,off).value
        def write(off,v):ctypes.c_uint32.from_buffer(regs,off).value=v
        assert read(68)==0x38475231,'Wrong bitstream: expected 8GR1; refusing DMA'
        assert read(84)==2,'Wrong control revision: requires latched-payload revision 2'
        assert read(64)==0,'Completion not idle; inspect/reset before retry'
        assert read(72)&15==0,'Controller busy: inspect/reset before retry'
        write(60,0)
        for l in manifest['layers']:
            for kind in ('weight','bias'):
                b=(a.model/f'{l["name"]}.{kind}.bin').read_bytes()
                assert digest(b)==l[f'{kind}_sha256']
                transfer(h.fileno(),b,l[f'{kind}_offset'],True)
        inp=(a.model/'canonical/input_pcie.bin').read_bytes()
        transfer(h.fileno(),inp,manifest['input_offset'],True)
        for i,l in enumerate(manifest['layers']):
            k=l['kernel'];src=manifest['input_offset']+i*0x800000;dst=src+0x800000
            values=[src,len(inp)//64,l['weight_offset'],k*k*256//64,l['bias_offset'],7,dst,len(inp)//64,
                    (16<<24)+(16<<16)+l['scale'],(180<<19)+(320<<6)+(k<<3)+k//2]
            for j,v in enumerate(values):write(j*4,v)
        start=time.monotonic();write(60,1)
        while read(64)!=1:
            if time.monotonic()-start>5:
                state={off:hex(read(off)) for off in [60,64,68,72,76,80,84,88,92,96]}
                (a.output/'timeout_state.json').write_text(json.dumps(state,indent=2))
                raise RuntimeError('FPGA timeout: STOP and inspect/reset; '+str(state))
        elapsed=(time.monotonic()-start)*1000
        write(60,2)
        actual=transfer(c.fileno(),len(inp),manifest['output_offset'],False)
        expected=(a.model/'canonical/expected_pcie.bin').read_bytes()
        (a.output/'output_pcie.bin').write_bytes(actual)
        mismatch=sum(x!=y for x,y in zip(actual,expected))+abs(len(actual)-len(expected))
        result=dict(model_id='0x38475231',bytes=len(actual),mismatched_bytes=mismatch,
                    fpga_wait_ms=elapsed,actual_sha256=digest(actual),expected_sha256=digest(expected))
        (a.output/'result.json').write_text(json.dumps(result,indent=2))
        print(json.dumps(result,indent=2))
        if mismatch:
            print('First mismatches:',[(i,x,y) for i,(x,y) in enumerate(zip(actual,expected)) if x!=y][:12])
            raise SystemExit(1)
