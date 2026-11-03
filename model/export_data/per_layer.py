"""One file pair per layer and parameter; transfer padding exists in BIN only."""
import copy

from export_data.export_qat import prepare, verify_data


def prepare_per_layer(layers, quant, hardware):
    if hardware is not None and hardware['block_scope'] != 'per_layer':
        raise ValueError('Independent layer files require block_scope=per_layer; cross-layer reversal is not valid here')
    # Reuse the validated layout and aligned serialization, but never write aggregate files.
    packed, base = prepare(layers, quant, hardware)
    manifest = copy.deepcopy(base)
    manifest['schema_version'] = 2
    manifest['file_organization'] = 'per_layer'
    manifest['data_directory'] = 'weight'
    manifest['binary']['addressing'] = (
        'Offsets are local to the named layer file. Append transfer zeros to the logical payload, '
        'then map each byte: physical=64*(logical//64)+63-logical%64. No block crosses files.')
    manifest['binary']['padding'] = (
        'Channel padding is present in TXT and BIN. Transfer padding is BIN-only; '
        'append the recorded zero bytes to serialized TXT before applying reversal.')
    manifest['text']['transfer_padding'] = 'omitted; TXT contains channel-padded layer payload only'
    manifest['streams'] = {}
    files = {}
    for layer in manifest['layers']:
        if '/' in layer['name'] or '\\' in layer['name']:
            raise ValueError('Layer name must not contain path separators')
        for kind, bits in [('weight', 8), ('bias', 16)]:
            loc = layer[kind]
            start = loc['logical_byte_offset']
            padding = loc['transfer_padding_bytes_after']
            length = loc['byte_length']
            stem = 'weight/' + layer['name'] + '.' + kind
            txt_name, bin_name = stem + '.txt', stem + '.bin'
            lines = packed[kind + '.txt'].splitlines(keepends=True)
            files[txt_name] = b''.join(lines[loc['txt_start_line']:loc['txt_start_line'] + loc['txt_line_count']])
            if hardware is not None:
                if start % 64 or (length + padding) % 64:
                    raise ValueError('Cannot split a reversal block at a layer boundary')
                files[bin_name] = packed[kind + '.bin'][start:start + length + padding]
            stream_id = layer['name'] + '.' + kind
            info = dict(base['streams'][kind])
            info.update(byte_length=length + padding, payload_bytes=length,
                        txt_line_count=loc['txt_line_count'], transfer_padding_bytes=padding,
                        txt_file=txt_name, bin_file=bin_name if hardware else None,
                        txt_contains_transfer_padding=False,
                        transfer_padding_regions=[dict(logical_byte_offset=length, byte_length=padding,
                                                       after_layer=layer['index'], value=0,
                                                       txt_start_line=None, txt_line_count=0,
                                                       bin_only=True)] if padding else [])
            manifest['streams'][stream_id] = info
            loc.update(logical_byte_offset=0, logical_element_offset=0, payload_byte_offset=0,
                       txt_start_line=0, txt_file=txt_name, bin_file=bin_name if hardware else None,
                       bin_byte_length=length + padding if hardware else None, stream_id=stream_id)
    return files, manifest


def verify_per_layer(files, manifest, layers, quant):
    if len(layers) != len(manifest['layers']):
        raise ValueError('Layer count mismatch')
    checks, expected_files = [], set()
    for source, layer in zip(layers, manifest['layers']):
        one = copy.deepcopy(manifest)
        one['layers'] = [copy.deepcopy(layer)]
        one['streams'] = {}
        one_files = {}
        for kind in ('weight', 'bias'):
            loc = layer[kind]
            stem = 'weight/' + layer['name'] + '.' + kind
            if loc['txt_file'] != stem + '.txt' or loc['stream_id'] != layer['name'] + '.' + kind:
                raise ValueError('Wrong per-layer filename or stream identifier')
            if any(loc[k] != 0 for k in ('logical_byte_offset', 'logical_element_offset',
                                         'payload_byte_offset', 'txt_start_line')):
                raise ValueError('Layer-file offsets must start at zero')
            info = copy.deepcopy(manifest['streams'][loc['stream_id']])
            raw_text = files[loc['txt_file']]
            if len(raw_text.splitlines()) != loc['txt_line_count'] or info['txt_line_count'] != loc['txt_line_count']:
                raise ValueError('TXT must contain only layer payload rows')
            pad = info['transfer_padding_bytes']
            row_bytes = info['row_bytes']
            if pad != loc['transfer_padding_bytes_after'] or pad % row_bytes:
                raise ValueError('Invalid transfer-padding metadata')
            if manifest['hardware'] is not None:
                if loc['bin_file'] != stem + '.bin' or loc['bin_byte_length'] != info['byte_length']:
                    raise ValueError('Wrong BIN filename or length metadata')
                one_files[kind + '.bin'] = files[loc['bin_file']]
                expected_files.add(loc['bin_file'])
            # Reconstruct the un-reversed padded stream from TXT using explicit BIN-only zeros.
            # The existing verifier checks the full binary, padding, independent layout and QAT integers.
            one_files[kind + '.txt'] = raw_text + (b'0' * (row_bytes * 2) + b'\n') * (pad // row_bytes)
            expected_files.add(loc['txt_file'])
            info['txt_line_count'] += pad // row_bytes
            for region in info['transfer_padding_regions']:
                if not region['bin_only'] or region['txt_start_line'] is not None or region['txt_line_count'] != 0:
                    raise ValueError('Transfer padding must be BIN-only')
                region['txt_start_line'] = region['logical_byte_offset'] // row_bytes
                region['txt_line_count'] = region['byte_length'] // row_bytes
            one['streams'][kind] = info
        report = verify_data(one_files, one, [source], quant)
        for check in report['streams']:
            check['layer'] = layer['name']
            check['txt_rows'] = layer[check['stream']]['txt_line_count']
            checks.append(check)
    data_files = {k for k in files if k.endswith(('.txt', '.bin'))}
    if data_files != expected_files:
        raise ValueError('Missing or unexpected layer data files')
    return dict(passed=True, file_organization='per_layer', streams=checks, layer_count=len(layers),
                quantization_record_count=len(quant['records']), state_unchanged=quant['provenance']['state_unchanged'])
