"""Pure layout/serialization functions; no quantization or model inference here."""
import numpy as np


def checked_int(values, bits):
    a = np.asarray(values)
    if a.dtype.kind not in 'iuf' or not np.all(np.isfinite(a)):
        raise ValueError('Expected finite numeric integers')
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if np.any(a < lo) or np.any(a > hi) or np.any(a != np.rint(a)):
        raise ValueError(f'Nonintegral value or signed int{bits} overflow')
    return a.astype(np.int8 if bits == 8 else np.int16)


def ceil16(n):
    if n <= 0:
        raise ValueError('Channel count must be positive')
    return (n + 15) // 16 * 16


def weight_layout(values):
    w = checked_int(values, 8)
    if w.ndim != 4 or min(w.shape) <= 0:
        raise ValueError('Only ordinary Conv2d [Co,Ci,Kh,Kw] is supported')
    co, ci, kh, kw = w.shape
    padded = np.zeros((ceil16(co), ceil16(ci), kh, kw), dtype=np.int8)
    padded[:co, :ci] = w
    grouped = padded.reshape(ceil16(co) // 16, 16, ceil16(ci) // 16, 16, kh, kw)
    return grouped.transpose(0, 5, 4, 2, 1, 3).copy()


def reference_weight_layout(values):
    """Independent index loops; deliberately does not use reshape/transpose."""
    co, ci, kh, kw = values.shape
    result = []
    for og in range(ceil16(co) // 16):
        for x in range(kw):
            for y in range(kh):
                for ig in range(ceil16(ci) // 16):
                    for o in range(16):
                        for i in range(16):
                            oc, ic = 16 * og + o, 16 * ig + i
                            result.append(int(values[oc, ic, y, x]) if oc < co and ic < ci else 0)
    return np.asarray(result, dtype=np.int8)


def inverse_weight_layout(values, original_shape):
    co, ci, kh, kw = original_shape
    layout = np.asarray(values).reshape(ceil16(co) // 16, kw, kh, ceil16(ci) // 16, 16, 16)
    padded = layout.transpose(0, 4, 3, 5, 2, 1).reshape(ceil16(co), ceil16(ci), kh, kw)
    return padded[:co, :ci].copy()


def bias_layout(values, co):
    b = checked_int(values, 16)
    if b.shape != (co,):
        raise ValueError('Bias shape must be [Co]')
    out = np.zeros(ceil16(co), dtype=np.int16)
    out[:co] = b
    return out.reshape(-1, 16)


def reverse64(data):
    if len(data) % 64:
        raise ValueError('Refusing to reverse an incomplete 64-byte block')
    return b''.join(data[i:i + 64][::-1] for i in range(0, len(data), 64))


def serialize(values, bits, endian):
    a = checked_int(values, bits)
    if bits == 8:
        return a.tobytes(order='C')
    if endian not in ('little', 'big'):
        raise ValueError('An explicit int16 endianness is required')
    return a.astype('<i2' if endian == 'little' else '>i2').tobytes(order='C')


def make_text(values, bits):
    a = checked_int(values, bits).reshape(-1)
    row = 256 if bits == 8 else 16
    if a.size % row:
        raise ValueError('Incomplete logical TXT row')
    mask = (1 << bits) - 1
    return ''.join(''.join(f'{int(v) & mask:0{bits // 4}X}' for v in a[i:i + row]) + '\n'
                   for i in range(0, a.size, row))


def parse_text(text, bits):
    row, width = (256, 2) if bits == 8 else (16, 4)
    lines = text.splitlines()
    if text and not text.endswith('\n'):
        raise ValueError('Missing final newline')
    values = []
    for line in lines:
        if len(line) != row * width or any(c not in '0123456789ABCDEF' for c in line):
            raise ValueError('Invalid TXT line width or characters')
        for i in range(0, len(line), width):
            n = int(line[i:i + width], 16)
            values.append(n - (1 << bits) if n >= (1 << (bits - 1)) else n)
    return checked_int(values, bits)


def validate_hardware(config):
    if config is None:
        return
    required = {'bias_endian', 'block_scope', 'tail_policy', 'padding_consumes_addresses',
                'txt_leftmost', 'missing_bias', 'nonzero_zero_point_padding'}
    if set(config) != required:
        raise ValueError(f'Hardware config must contain exactly {sorted(required)}')
    choices = {'bias_endian': ('little', 'big'), 'block_scope': ('combined', 'per_layer'),
               'tail_policy': ('error', 'zero_pad'), 'txt_leftmost': ('msb',),
               'missing_bias': ('error', 'omit', 'zeros'),
               'nonzero_zero_point_padding': ('reject', 'masked')}
    for key, allowed in choices.items():
        if config[key] not in allowed:
            raise ValueError(f'{key} must be one of {allowed}')
    if type(config['padding_consumes_addresses']) is not bool:
        raise ValueError('padding_consumes_addresses must be a boolean')
    if config['tail_policy'] == 'zero_pad' and not config['padding_consumes_addresses']:
        raise ValueError('This exporter supports padding as stored hardware addresses only')


def pack_stream(arrays, bits, hardware):
    """Offsets include prior transfer padding; payload offsets exclude it."""
    validate_hardware(hardware)
    row_elements = 256 if bits == 8 else 16
    item_bytes = bits // 8
    chunks, entries, padding = [], [], []
    offset = payload = 0
    for index, values in enumerate(arrays):
        a = checked_int(values, bits).reshape(-1)
        if a.size % row_elements:
            raise ValueError('Layer has an incomplete logical storage row')
        entry = dict(logical_byte_offset=offset, logical_element_offset=offset // item_bytes,
                     payload_byte_offset=payload, element_count=int(a.size), byte_length=int(a.nbytes),
                     txt_start_line=offset // (row_elements * item_bytes),
                     txt_line_count=int(a.size // row_elements), transfer_padding_bytes_after=0)
        entries.append(entry)
        chunks.append(a)
        offset += a.nbytes
        payload += a.nbytes
        if hardware and hardware['block_scope'] == 'per_layer':
            extra = (-a.nbytes) % 64
            if extra:
                if hardware['tail_policy'] == 'error':
                    raise ValueError(f'Layer {index} requires {extra} transfer-padding bytes')
                padding.append(dict(logical_byte_offset=offset, byte_length=extra, after_layer=index,
                                    txt_start_line=offset // (row_elements * item_bytes),
                                    txt_line_count=extra // (row_elements * item_bytes), value=0))
                chunks.append(np.zeros(extra // item_bytes, dtype=a.dtype))
                entry['transfer_padding_bytes_after'] = extra
                offset += extra
    if hardware and hardware['block_scope'] == 'combined' and offset % 64:
        extra = (-offset) % 64
        if hardware['tail_policy'] == 'error':
            raise ValueError(f'Final stream requires {extra} transfer-padding bytes')
        padding.append(dict(logical_byte_offset=offset, byte_length=extra, after_layer='file_tail',
                            txt_start_line=offset // (row_elements * item_bytes),
                            txt_line_count=extra // (row_elements * item_bytes), value=0))
        chunks.append(np.zeros(extra // item_bytes, dtype=np.int8 if bits == 8 else np.int16))
        offset += extra
    flat = np.concatenate(chunks) if chunks else checked_int([], bits)
    txt = make_text(flat, bits)
    binary = reverse64(serialize(flat, bits, hardware['bias_endian'])) if hardware else None
    info = dict(dtype=f'int{bits}', row_elements=row_elements, row_bytes=row_elements * item_bytes,
                txt_line_count=len(txt.splitlines()), byte_length=offset, payload_bytes=payload,
                transfer_padding_bytes=offset - payload, transfer_padding_regions=padding,
                bin_byte_mapping='physical_byte = 64 * (logical_byte // 64) + 63 - logical_byte % 64'
                if hardware else None)
    return txt, binary, entries, info
