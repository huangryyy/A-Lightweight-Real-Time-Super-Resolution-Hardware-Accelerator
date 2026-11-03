"""Freeze 3DIC's actual eight-layer coefficients; export this board's DMA layout."""
from pathlib import Path
import argparse, hashlib, importlib.util, json
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--full-frame',action='store_true')
args=parser.parse_args()
REF=ROOT/'model/reference'
SRC=REF/'data_txt'
OUT=ROOT/'model/hardware/X4'
SIM=ROOT/'sim'
if args.full_frame:SIM=SIM/'full_frame'
OUT.mkdir(parents=True,exist_ok=True);SIM.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('reference',REF/'sim_CNN_3dic.py')
ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
manifest={'model':'3DIC eight layers + global signed C0 residual', 'model_id':'0x38475231',
          'bias_format':'32 logical big-endian bytes reversed, then 32 zero padding bytes; one DDR512 beat',
          'weight_format':'logical bytes with each 64-byte DDR beat reversed independently', 'layers':[]}
allweights=[];allbias=[];offset=0
for name,k,scale in ref.LAYERS_CONFIG:
    weight=bytes.fromhex((SRC/f'{name}.weight.txt').read_text())
    bias=bytes.fromhex((SRC/f'{name}.bias.txt').read_text())
    assert len(weight)==k*k*256 and len(bias)==32
    blob=b''.join(weight[i:i+64][::-1] for i in range(0,len(weight),64))
    bblob=bias[::-1]+bytes(32)
    wp=OUT/f'{name}.weight.bin';bp=OUT/f'{name}.bias.bin'
    wp.write_bytes(blob);bp.write_bytes(bblob)
    manifest['layers'].append(dict(name=name,kernel=k,scale=scale,scale_hex=f'0x{scale:04x}',
        weight_offset=offset,weight_bytes=len(blob),bias_bytes=len(bblob),
        weight_sha256=hashlib.sha256(blob).hexdigest(),bias_sha256=hashlib.sha256(bblob).hexdigest()))
    offset+=len(weight)
    allweights.extend(weight[i:i+256].hex() for i in range(0,len(weight),256))
    allbias.append(bias.hex())
for i,l in enumerate(manifest['layers']):l['bias_offset']=offset+i*64
manifest['input_offset']=offset+8*64+512
manifest['output_offset']=manifest['input_offset']+8*0x800000
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'canonical').mkdir(exist_ok=True)
for source,dest in [('input_data.txt','input_pcie.bin'),('output_data_reference.txt','expected_pcie.bin')]:
    logical=bytes.fromhex((SRC/source).read_text())
    assert len(logical)==320*180*16
    packed=b''.join(logical[i:i+64][::-1] for i in range(0,len(logical),64))
    (OUT/'canonical'/dest).write_bytes(packed)
(SIM/'weights.mem').write_text('\n'.join(allweights)+'\n')
(SIM/'bias.mem').write_text('\n'.join(allbias)+'\n')

# Input includes all signed residual byte values; each channel0 is unique across
# the four pixel lanes. This catches lane swaps and signed/before-clip mistakes.
w,h=(320,180) if args.full_frame else (16,8)
if args.full_frame:
    x=ref.load_input_feature_hex(SRC/'input_data.txt',w,h)
else:
    x=np.zeros((w,h,16),dtype=np.int32)
    x[:,:,0]=np.arange(w*h).reshape(w,h)*2
def save(p,x):
    blob=(x&255).astype(np.uint8).tobytes()
    p.write_text('\n'.join(blob[i:i+64].hex() for i in range(0,len(blob),64))+'\n')
save(SIM/'input.mem',x)
res=np.where(x[:,:,0]>=128,x[:,:,0]-256,x[:,:,0])
for i,(name,k,scale) in enumerate(ref.LAYERS_CONFIG):
    acc=ref.conv2d_int(x,ref.load_weight_hex(SRC/f'{name}.weight.txt',k),ref.load_bias_hex(SRC/f'{name}.bias.txt'))
    if i!=7:acc=np.maximum(acc,0)
    x=ref.quantize_rtl(acc,scale)
    x=np.clip(x+res[:,:,None],-128,127) if i==7 else np.clip(x,0,255)
    save(SIM/f'expected{i}.mem',x)
    print(f'Layer {i+1}: min={x.min()} max={x.max()}')
print(json.dumps(manifest,indent=2))

