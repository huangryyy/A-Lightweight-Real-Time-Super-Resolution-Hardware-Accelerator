#!/usr/bin/env python3
"""Export this project's trained Brevitas QAT parameters, then verify every byte."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from export_data.extract import extract, sha256
from export_data.layout import (bias_layout, ceil16, inverse_weight_layout, pack_stream,
                                   parse_text, reference_weight_layout, reverse64,
                                   validate_hardware, weight_layout)


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode('utf-8')


def prepare(layers, quant, hardware):
    validate_hardware(hardware)
    by_id = {r['id']: r for r in quant['records']}
    weights, biases, manifest_layers = [], [], []
    for layer in layers:
        w = layer['weight_integers']
        co, ci, kh, kw = w.shape
        laid = weight_layout(w)
        np.testing.assert_array_equal(laid.reshape(-1), reference_weight_layout(w))
        np.testing.assert_array_equal(inverse_weight_layout(laid, w.shape), w)
        weights.append(laid)
        entry = {k: v for k, v in layer.items() if not k.endswith('_integers')}
        entry.update(padded_weight_shape=[ceil16(co), ceil16(ci), kh, kw],
                     weight_layout_shape=list(laid.shape),
                     weight_layout_axes=['Co_group', 'Kw', 'Kh', 'Ci_group', 'Co_in', 'Ci_in'],
                     channel_padding=dict(Co=ceil16(co) - co, Ci=ceil16(ci) - ci,
                                          weight_elements=int(laid.size - w.size), integer_value=0),
                     original_bias_shape=[co] if layer['bias_present'] else None,
                     padded_bias_shape=[ceil16(co)], bias_layout_shape=[ceil16(co) // 16, 16],
                     bias_layout_axes=['Co_group', 'Co_in'])
        if layer['bias_present']:
            b = bias_layout(layer['bias_integers'], co)
            entry['bias_policy'] = 'actual_quantized_int16'
            entry['bias_channel_padding_elements'] = ceil16(co) - co
        else:
            policy = hardware['missing_bias'] if hardware else 'error'
            if policy == 'error':
                raise ValueError(f"{layer['name']}: bias=None requires an explicit omit/zeros hardware policy")
            b = np.zeros((ceil16(co) // 16, 16), dtype=np.int16) if policy == 'zeros' else np.zeros(0, dtype=np.int16)
            entry['bias_policy'] = policy
            entry['bias_channel_padding_elements'] = ceil16(co) - co if policy == 'zeros' else 0
            entry['bias_placeholder_elements'] = co if policy == 'zeros' else 0
            if policy == 'omit':
                entry['padded_bias_shape'] = [0]
                entry['bias_layout_shape'] = [0, 16]
        biases.append(b)
        for key in ('weight_quant_id', 'bias_quant_id', 'input_quant_id'):
            if key not in layer:
                continue
            zp = np.asarray(by_id[layer[key]]['zero_point']['values'])
            if np.any(zp != 0):
                if not hardware or hardware['nonzero_zero_point_padding'] != 'masked':
                    raise ValueError('Nonzero zero point: integer 0 padding differs from real-zero encoding. '
                                     'Hardware must explicitly mask padded input/output channels')
                entry['nonzero_zero_point_warning'] = 'Integer 0 padding is not necessarily real zero; hardware masks padded channels'
        manifest_layers.append(entry)
    files, streams = {}, {}
    for kind, arrays, bits in [('weight', weights, 8), ('bias', biases, 16)]:
        txt, binary, entries, info = pack_stream(arrays, bits, hardware)
        files[kind + '.txt'] = txt.encode('ascii')
        if binary is not None:
            files[kind + '.bin'] = binary
        streams[kind] = info
        for layer, location in zip(manifest_layers, entries):
            layer[kind] = location
    manifest = dict(schema_version=1, status='complete' if hardware else 'pending_hardware_contract',
                    provenance=quant['provenance'], hardware=hardware,
                    parallelism=dict(P=16, Q=16, H=4, weight_copies=1),
                    layer_order='observed eval forward Conv2d call order, checked against FSRCNN_ECB.forward; hardware must load in this order',
                    index_base=dict(layer=0, txt_line=0, byte_offset=0, element_offset=0),
                    text=dict(format='uppercase fixed-width two-complement hex; no separators; LF after every row',
                              leftmost='element 0 is the most significant field of a packed simulation word',
                              weight='element k=16*Co_in+Ci_in maps to bits [2047-8*k : 2040-8*k]',
                              bias='element k=Co_in maps to bits [255-16*k : 240-16*k]',
                              testbench_status='No RTL/testbench supplied; loader must use the stated mapping'),
                    binary=dict(block_bytes=64, rule='reverse all 64 bytes within each block; not bits or int16 elements',
                                addressing='logical_byte offsets include preceding transfer padding. '
                                'Map EACH byte with physical=64*(logical//64)+63-logical%64. '
                                'Do not treat a layer logical range as a contiguous physical range when blocks cross layers.',
                                bias_byte_order_before_reversal=hardware['bias_endian'] if hardware else None,
                                tail='Incomplete blocks are rejected unless explicit zero_pad policy is supplied',
                                padding='Channel zeros are in layer payloads. Transfer zeros are separate stored TXT rows/BIN bytes; regions listed in streams'),
                    streams=streams, layers=manifest_layers,
                    limitations=['Parameter export only; no integer accelerator execution or RTL numerical equivalence tested.',
                                 'Adapter supports this fused FSRCNN_ECB, ordinary groups=1 Conv2d; unsupported layouts fail explicitly.',
                                 'Known fixed eval scales only; dynamic quantization is rejected before shape probing.'])
    return files, manifest


def verify_data(files, manifest, layers, quant):
    """Read TXT and BIN independently; reverse layout back to actual QAT integers."""
    hardware = manifest['hardware']
    validate_hardware(hardware)
    recs = {r['id']: r for r in quant['records']}
    if len(recs) != len(quant['records']) or len(layers) != len(manifest['layers']):
        raise ValueError('Duplicate quantization IDs or wrong layer count')
    checks = []
    for kind, bits in [('weight', 8), ('bias', 16)]:
        text = files[kind + '.txt'].decode('ascii')
        integers = parse_text(text, bits)
        info = manifest['streams'][kind]
        row_bytes = 256 if bits == 8 else 32
        if integers.nbytes != info['byte_length'] or len(text.splitlines()) != info['txt_line_count']:
            raise ValueError('Stream length mismatch')
        if hardware:
            binary = files[kind + '.bin']
            logical = reverse64(binary)
            dtype = 'i1' if bits == 8 else '<i2' if hardware['bias_endian'] == 'little' else '>i2'
            decoded = np.frombuffer(logical, dtype=dtype)
            np.testing.assert_array_equal(decoded, integers)
            if len(binary) != info['byte_length']:
                raise ValueError('BIN length mismatch')
        intervals = []
        for source, layer in zip(layers, manifest['layers']):
            if source['name'] != layer['name'] or source['index'] != layer['index']:
                raise ValueError('Layer order/name mismatch')
            loc = layer[kind]
            start, length = loc['logical_byte_offset'], loc['byte_length']
            if loc['txt_start_line'] * row_bytes != start or loc['txt_line_count'] * row_bytes != length:
                raise ValueError('TXT layer location mismatch')
            if loc['logical_element_offset'] * (bits // 8) != start or loc['element_count'] * (bits // 8) != length:
                raise ValueError('Element location mismatch')
            chunk = integers[start // (bits // 8):(start + length) // (bits // 8)]
            intervals.append((start, start + length))
            if kind == 'weight':
                w = source['weight_integers']
                co, ci, kh, kw = w.shape
                expected_rows = ceil16(co) // 16 * kw * kh * (ceil16(ci) // 16)
                if loc['txt_line_count'] != expected_rows:
                    raise ValueError('Weight row count mismatch')
                np.testing.assert_array_equal(chunk, reference_weight_layout(w))
                np.testing.assert_array_equal(inverse_weight_layout(chunk, w.shape), w)
            elif source['bias_present']:
                b = source['bias_integers']
                if loc['txt_line_count'] != ceil16(b.size) // 16:
                    raise ValueError('Bias row count mismatch')
                np.testing.assert_array_equal(chunk[:b.size], b)
                if np.any(chunk[b.size:]):
                    raise ValueError('Nonzero channel padding')
            elif np.any(chunk):
                raise ValueError('Nonzero missing-bias placeholder')
            if kind + '_quant_id' in source:
                r = recs[source[kind + '_quant_id']]
                if r['associated_module'] != source['name'] or r['role'] != kind or r['bit_width'] != bits:
                    raise ValueError('Quantization record mismatch')
                if r['logical_tensor_shape'] != list(source[kind + '_integers'].shape):
                    raise ValueError('Quantization channel shape mismatch')
        for region in info['transfer_padding_regions']:
            start, length = region['logical_byte_offset'], region['byte_length']
            if start % row_bytes or length % row_bytes:
                raise ValueError('Transfer padding cannot be represented by complete TXT rows')
            if np.any(integers[start // (bits // 8):(start + length) // (bits // 8)]):
                raise ValueError('Nonzero transfer padding')
            intervals.append((start, start + length))
        pos = 0
        for start, end in sorted(intervals):
            if start != pos:
                raise ValueError('Address gap or overlap')
            pos = end
        if pos != info['byte_length'] or sum(e - s for s, e in intervals) != pos:
            raise ValueError('Unaccounted bytes')
        checks.append(dict(stream=kind, byte_length=info['byte_length'], txt_rows=info['txt_line_count'],
                           transfer_padding_bytes=info['transfer_padding_bytes'],
                           txt_verified=True, bin_verified=hardware is not None, inverse_layout_verified=True))
    return dict(passed=True, streams=checks, layer_count=len(layers),
                quantization_record_count=len(recs), state_unchanged=quant['provenance']['state_unchanged'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, default=ROOT / 'model_data/QAT/best_qat.pth')
    parser.add_argument('--output-dir', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--hardware-config', type=Path, help='Explicit confirmed hardware contract JSON; absent = TXT/JSON only')
    parser.add_argument('--file-organization', choices=('per_layer', 'combined'),
                        help='Default: per_layer; verify-only infers the saved organization')
    parser.add_argument('--input-npy', type=Path, help='Optional normalized float NCHW probe; not calibration data')
    parser.add_argument('--verify-only', action='store_true', help='Re-extract checkpoint and verify existing output without rewriting')
    parser.add_argument('--threads', type=int, default=1)
    args = parser.parse_args()
    import torch
    if args.threads < 1:
        parser.error('--threads must be positive')
    torch.set_num_threads(args.threads)
    hardware = json.loads(args.hardware_config.read_text()) if args.hardware_config else None
    saved = json.loads((args.output_dir / 'manifest.json').read_text()) if args.verify_only else None
    if saved is not None and hardware is None:
        hardware = saved['hardware']
    organization = args.file_organization or (saved.get('file_organization', 'combined') if saved else 'per_layer')
    if organization == 'per_layer':
        from export_data.per_layer import prepare_per_layer, verify_per_layer
        build, verify = prepare_per_layer, verify_per_layer
    else:
        build, verify = prepare, verify_data
    validate_hardware(hardware)
    layers, quant = extract(args.checkpoint, args.input_npy)
    files, manifest = build(layers, quant, hardware)
    report = verify(files, manifest, layers, quant)
    files['quant_params.json'] = json_bytes(quant)
    manifest['files'] = {name: dict(byte_length=len(data), sha256=hashlib.sha256(data).hexdigest()) for name, data in files.items()}
    manifest['validation'] = report
    if not args.verify_only:
        if hardware is None and any(args.output_dir.rglob('*.bin')):
            raise ValueError('Pending export would leave stale BIN files. Use a fresh output directory')
        args.output_dir.mkdir(parents=True, exist_ok=True)
        files['manifest.json'] = json_bytes(manifest)
        # Everything has been validated in memory before replacing output files.
        for name, data in files.items():
            tmp = args.output_dir / (name + '.tmp')
            tmp.parent.mkdir(parents=True, exist_ok=True)
            tmp.write_bytes(data)
            tmp.replace(args.output_dir / name)
    # Verify actual files on disk, including a fresh comparison against checkpoint extraction.
    stored_manifest = json.loads((args.output_dir / 'manifest.json').read_text())
    if stored_manifest != manifest:
        raise ValueError('Stored manifest differs from current checkpoint/config/layout')
    stored_quant = json.loads((args.output_dir / 'quant_params.json').read_text())
    if stored_quant != quant:
        raise ValueError('Stored quantization metadata differs from actual quantizers')
    stored = {name: (args.output_dir / name).read_bytes() for name in manifest['files']}
    for name, entry in manifest['files'].items():
        if len(stored[name]) != entry['byte_length'] or sha256(args.output_dir / name) != entry['sha256']:
            raise ValueError(f'File hash/length mismatch: {name}')
    verify(stored, stored_manifest, layers, stored_quant)
    print(json.dumps(dict(status=manifest['status'], output_dir=str(args.output_dir.resolve()), validation=report), indent=2))


if __name__ == '__main__':
    main()
