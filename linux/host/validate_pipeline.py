"""Hardware integration regression: ordering, buffer reuse, failure exit and pace.

Run on the Linux XDMA host. Refuses existing output directories and never programs
the FPGA or changes drivers. Video timing includes encoder finalization.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--run', type=Path, required=True)
p.add_argument('--tools', type=Path, default=Path('/usr/bin'))
p.add_argument('--input', type=Path, default=ROOT / 'data/lr')
p.add_argument('--weights', type=Path, default=ROOT / 'model/X4')
a = p.parse_args()
a.run = a.run.resolve()
a.run.mkdir(parents=True, exist_ok=False)
exe = Path('FSRCNN_X4_video').resolve()
results = {'source_sha256': hashlib.sha256(Path('FSRCNN_X4_video.cpp').read_bytes()).hexdigest(),
           'executable_sha256': hashlib.sha256(exe.read_bytes()).hexdigest(), 'runs': {}}


def run(name, mode, repeat=1, video=False, extra=(), input_dir=None, expect=None):
    out = a.run / name
    out.mkdir()
    cmd = [str(exe), '--input', str(input_dir or a.input), '--weights', str(a.weights),
           '--mode', mode, '--threads', '4', '--buffers', '3', '--fps', '60',
           '--repeat', str(repeat), '--ffmpeg', str(a.tools / 'ffmpeg'),
           '--output', str(out / 'video.mp4'), '--csv', str(out / 'frames.csv'),
           '--summary', str(out / 'summary.json'), '--snapshots', str(out / 'snapshots')]
    if not video:
        cmd += ['--no-video']
    cmd += list(extra)
    with (out / 'console.log').open('w') as log:
        r = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=120)
    text = (out / 'console.log').read_text()
    if expect:
        assert r.returncode == 1 and expect in text, (name, r.returncode, text)
        results[name] = 'PASS: exited cleanly after injected failure'
        print(name, 'PASS', flush=True)
        return
    assert r.returncode == 0, (name, r.returncode, text)
    summary = json.loads((out / 'summary.json').read_text())
    assert summary['frames'] == 100 * repeat
    if video:
        probe = json.loads(subprocess.check_output([
            str(a.tools / 'ffprobe'), '-v', 'error', '-count_frames', '-select_streams', 'v:0',
            '-show_entries', 'stream=width,height,nb_read_frames,avg_frame_rate', '-of', 'json', str(out / 'video.mp4')]))
        stream = probe['streams'][0]
        assert (stream['width'], stream['height'], int(stream['nb_read_frames']), stream['avg_frame_rate']) == (1280, 720, 100 * repeat, '60/1'), probe
        subprocess.run([str(a.tools / 'ffmpeg'), '-v', 'error', '-i', str(out / 'video.mp4'), '-f', 'null', '-'], check=True, timeout=60)
        summary['video_probe'] = probe
    results['runs'][name] = summary
    print(name, 'PASS FPS=', summary['end_to_end_fps'], flush=True)


run('serial_checks', 'serial', extra=['--checksums'])
run('pipeline_checks', 'pipeline', repeat=3, extra=['--checksums'])
with (a.run / 'serial_checks/frames.csv').open() as f:
    serial = list(csv.DictReader(f))
with (a.run / 'pipeline_checks/frames.csv').open() as f:
    pipeline = list(csv.DictReader(f))
for index, row in enumerate(pipeline):
    expected = serial[index % 100]
    for key in ('file', 'raw_fnv1a64', 'rgb_fnv1a64'):
        assert row[key] == expected[key], (index, key, row[key], expected[key])
for name in ('00000000.png', '00000050.png', '00000099.png'):
    assert (a.run / 'serial_checks/snapshots' / name).read_bytes() == (a.run / 'pipeline_checks/snapshots' / name).read_bytes()
    old = Path('run_3dic8_100/snapshots') / name
    if old.exists():
        assert old.read_bytes() == (a.run / 'pipeline_checks/snapshots' / name).read_bytes(), name
results['bit_exact'] = '300 pipelined raw tensors and RGB frames match serial100 x3; three PNG snapshots byte-identical'

# Corrupt IDAT after a valid IHDR: preflight can read dimensions but decode fails
# while other threads may own slots. Cancellation must wake blocked workers.
fault = a.run / 'fault_input'
fault.mkdir()
shutil.copyfile(a.input / '00000000.png', fault / '00000000.png')
original = (a.input / '00000001.png').read_bytes()
pos = 8
while original[pos + 4:pos + 8] != b'IDAT':
    pos += 12 + int.from_bytes(original[pos:pos + 4], 'big')
# stbi_info needs the IDAT header; stbi_load then detects its missing payload.
(fault / '00000001.png').write_bytes(original[:pos + 9])
run('decode_failure', 'pipeline', input_dir=fault, expect='Input decode/size error')
run('encoder_failure', 'pipeline', video=True, extra=['--ffmpeg', '/bin/false'], expect='Encoder pipe closed/failed')
# A subsequent complete run also proves failure cancellation left no lock or
# partially consumed FPGA descriptor behind.
run('serial_1000', 'serial', repeat=10, video=True)
run('pipeline_1000', 'pipeline', repeat=10, video=True)
run('paced60_1000', 'pipeline', repeat=10, video=True, extra=['--pace'])
with (a.run / 'paced60_1000/frames.csv').open() as f:
    rows = list(csv.DictReader(f))
latencies = [float(r['source_latency_ms']) for r in rows]
results['paced60_latency_first100_mean_ms'] = sum(latencies[:100]) / 100
results['paced60_latency_last100_mean_ms'] = sum(latencies[-100:]) / 100
results['speedup'] = results['runs']['pipeline_1000']['end_to_end_fps'] / results['runs']['serial_1000']['end_to_end_fps']
(a.run / 'validation.json').write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
