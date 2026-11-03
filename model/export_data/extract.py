"""Audited adapter for this project's FSRCNN_ECB and Brevitas 0.13.2."""
import hashlib
import sys
from collections import defaultdict
from pathlib import Path

import brevitas
import numpy as np
import torch
from brevitas.nn import QuantConv2d, QuantIdentity
from brevitas.quant_tensor import IntQuantTensor

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.model_QAT import FSRCNN_ECB, qat_checkpoint_configs
from export_data.layout import checked_int


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def full_type(obj):
    return type(obj).__module__ + '.' + type(obj).__name__


def parameter(tensor):
    a = tensor.detach().cpu()
    if not torch.isfinite(a).all():
        raise ValueError('Nonfinite quantization parameter')
    return {'shape': list(a.shape), 'values': a.tolist()}


def quant_metadata(q, name, role, call, owner, proxy):
    if not isinstance(q, IntQuantTensor):
        raise ValueError(f'{name}: expected actual IntQuantTensor, got {type(q)}')
    if torch.any(q.scale <= 0):
        raise ValueError(f'{name}: nonpositive quantization scale')
    bits = float(q.bit_width.item())
    if not bits.is_integer():
        raise ValueError('Nonintegral bit width')
    axis = None
    for p in (q.scale, q.zero_point):
        if p.numel() > 1:
            # Broadcasting semantics, never reduce per-channel arrays to a scalar.
            shape = (1,) * (q.value.ndim - p.ndim) + tuple(p.shape)
            axes = [i for i, n in enumerate(shape) if n > 1]
            if len(axes) != 1 or shape[axes[0]] != q.value.shape[axes[0]]:
                raise ValueError(f'{name}: unsupported non-channel quantizer shape {shape}')
            if axis is not None and axis != axes[0]:
                raise ValueError('Scale and zero-point axes differ')
            axis = axes[0]
    signed = bool(q.signed)
    narrow = bool(proxy.is_narrow_range)
    code_min = -(1 << (int(bits) - 1)) + int(narrow) if signed else 0
    code_max = (1 << (int(bits) - int(signed))) - 1
    return dict(id=f'{name}#{call}', module_name=name, module_type=full_type(proxy),
                associated_module=owner, role=role, call_index=call, bit_width=int(bits),
                signed=signed, granularity='per_tensor' if axis is None else 'per_channel',
                axis=axis, channel_mapping=None if axis is None else
                f'parameter index j corresponds to original tensor axis {axis}, channel j; no padded channels',
                scale=parameter(q.scale), zero_point=parameter(q.zero_point),
                source='actual eval forward quantizer output IntQuantTensor metadata',
                integer_encoding='real = (integer - zero_point) * scale',
                narrow_range=narrow, quantizer_integer_range=[code_min, code_max],
                rounding='Brevitas RoundSte (torch.round, nearest, ties to even)',
                saturation='Brevitas tensor clamp before dequantization')


def quant_integers(q, bits):
    if not isinstance(q, IntQuantTensor) or int(q.bit_width.item()) != bits or not q.signed:
        raise ValueError(f'Requires a signed int{bits} quantizer; conversion is not implicit')
    # Ask Brevitas for the actual integer grid. Validate BEFORE any narrow cast.
    values = q.int(float_datatype=True).detach().cpu().numpy()
    result = checked_int(values, bits)
    np.testing.assert_array_equal(result, q.int(float_datatype=False).detach().cpu().numpy())
    return result


def activation_links(model):
    """Explicit dataflow of FSRCNN_ECB.forward, checked against observed calls."""
    links = {'input_quant': ['first_part.0', 'residual_repeat'],
             'first_part.output_quant': ['shrink.0'],
             'shrink.output_quant': ['ecb_blocks.0.input_quant'] if model.m else ['expand.0'],
             'expand.output_quant': ['last_part'],
             'output_quant': ['pixel_shuffle']}
    for i in range(model.m):
        prefix = f'ecb_blocks.{i}'
        links[prefix + '.input_quant'] = [prefix + '.reparam_conv']
        links[prefix + '.output_quant'] = [f'ecb_blocks.{i + 1}.input_quant' if i + 1 < model.m else 'expand.0']
    if model.quantize_residual:
        links['residual_quant'] = ['residual_add.main', 'residual_add.skip']
    return links


def load_model(checkpoint_path):
    if brevitas.__version__ != '0.13.2':
        raise ValueError('This adapter is audited for Brevitas 0.13.2; audit before using another version')
    ckpt = torch.load(checkpoint_path, map_location='cpu', weights_only=True)
    if not isinstance(ckpt, dict) or not {'model_config', 'quant_config', 'model_state_dict'} <= ckpt.keys():
        raise ValueError('Expected structured QAT checkpoint; raw FP32 state_dict is unsupported')
    model_config, qc = qat_checkpoint_configs(ckpt)
    if qc.get('weight_bit_width') != 8 or qc.get('bias_bit_width') != 16:
        raise ValueError('Requires trained int8 weight / Int16Bias configuration. '
                         'FP32 or other-bit bias needs a separately agreed scale/round/clamp conversion')
    if ckpt['model_config'].get('deploy') is not True:
        raise ValueError('Checkpoint must already contain fused deploy convolutions')
    model = FSRCNN_ECB(**model_config)
    model.enable_qat(**qc)
    model.load_state_dict(ckpt['model_state_dict'], strict=True)
    model.cpu().eval()
    return model, ckpt, qc


def audit_fixed_quantizers(model, state):
    """Only accept known input-independent eval quantizers, before any probe forward."""
    audits = []
    for name, module in model.named_modules():
        if isinstance(module, (torch.nn.ConvTranspose1d, torch.nn.ConvTranspose2d,
                               torch.nn.ConvTranspose3d, torch.nn.Linear)):
            raise ValueError(f'{name}: special weight layout requires a hardware-specific adapter')
        if isinstance(module, torch.nn.Conv2d):
            if not isinstance(module, QuantConv2d) or module.groups != 1:
                raise ValueError(f'{name}: unquantized/grouped/depthwise convolution is unsupported')
        if 'weight' in module._parameters and not isinstance(module, QuantConv2d):
            raise ValueError(f'{name}: unhandled parameter-bearing layer {full_type(module)}')
        if isinstance(module, QuantConv2d):
            if module.input_quant.is_quant_enabled or module.output_quant.is_quant_enabled:
                raise ValueError(f'{name}: adapter expects explicit QuantIdentity activation sites')
            tq = module.weight_quant.tensor_quant
            if type(tq.scaling_impl).__name__ != 'StatsFromParameterScaling':
                raise ValueError(f'{name}: unknown/dynamic weight scale; adapter audit required')
            if module.bias is not None:
                bq = module.bias_quant
                if not bq.is_quant_enabled or not bq.requires_input_scale:
                    raise ValueError(f'{name}: expected configured Int16Bias with input scale')
        if isinstance(module, QuantIdentity):
            aq = module.act_quant
            sq = aq.fused_activation_quant_proxy.tensor_quant.scaling_impl
            key = name + '.act_quant.fused_activation_quant_proxy.tensor_quant.scaling_impl.value'
            if type(sq).__name__ != 'ParameterFromRuntimeStatsScaling' or key not in state:
                raise ValueError(f'{name}: unknown/dynamic activation quantizer; '
                                 'real inputs and a deployment policy are required')
            if sq.counter <= sq.collect_stats_steps or sq.training:
                raise ValueError(f'{name}: activation statistics are not frozen for evaluation')
            audits.append(dict(module_name=name, checkpoint_scale_key=key,
                               scaling_impl=full_type(sq), input_independent_in_eval=True,
                               evidence='loaded value disables collection; eval forward reads value, not input statistics'))
    return audits


def extract(checkpoint_path, input_npy=None):
    model, ckpt, qc = load_model(checkpoint_path)
    audits = audit_fixed_quantizers(model, ckpt['model_state_dict'])
    links = activation_links(model)
    conv_names = ['first_part.0', 'shrink.0'] + [f'ecb_blocks.{i}.reparam_conv' for i in range(model.m)] + ['expand.0', 'last_part']
    if input_npy is None:
        x = torch.zeros(1, model.num_channels, 8, 8)
        input_info = dict(kind='deterministic_zero_shape_probe', shape=list(x.shape),
                          purpose='exercise actual forward call order; no calibration or statistics updates',
                          fixed_scale_evidence=audits)
    else:
        a = np.load(input_npy, allow_pickle=False)
        if a.ndim != 4 or a.shape[1] != model.num_channels or min(a.shape) < 1 or not np.isfinite(a).all():
            raise ValueError('Input .npy must be finite normalized NCHW with matching channels')
        x = torch.from_numpy(a.astype(np.float32))
        input_info = dict(kind='user_normalized_npy', path=str(Path(input_npy).resolve()),
                          sha256=sha256(input_npy), shape=list(x.shape), fixed_scale_evidence=audits)
    before = {k: v.detach().clone() for k, v in model.state_dict().items()}
    buffers = {k: v.detach().clone() for k, v in model.named_buffers()}
    counters = {a['module_name']: model.get_submodule(a['module_name']).act_quant.
                fused_activation_quant_proxy.tensor_quant.scaling_impl.counter for a in audits}
    aliases = defaultdict(list)
    for name, module in model.named_modules(remove_duplicate=False):
        aliases[id(module)].append(name)
    records, layers, events, handles, stack = [], [], [], [], []
    calls = defaultdict(int)
    layer_calls = defaultdict(int)
    input_ids = {'first_part.0': 'input_quant.act_quant#0', 'shrink.0': 'first_part.output_quant.act_quant#0',
                 'expand.0': (f'ecb_blocks.{model.m - 1}.output_quant.act_quant#0' if model.m else 'shrink.output_quant.act_quant#0'),
                 'last_part': 'expand.output_quant.act_quant#0'}
    input_ids.update({f'ecb_blocks.{i}.reparam_conv': f'ecb_blocks.{i}.input_quant.act_quant#0' for i in range(model.m)})

    def enter(name, module):
        def hook(_module, args):
            if isinstance(module, QuantConv2d):
                call = layer_calls[name]
                layer_calls[name] += 1
                layer = dict(index=len(layers), name=name, module_type=full_type(module), call_index=call,
                             original_weight_shape=list(module.weight.shape), bias_present=module.bias is not None,
                             stride=list(module.stride), padding=list(module.padding), dilation=list(module.dilation),
                             groups=module.groups, input_quant_id=input_ids[name])
                layers.append(layer)
                stack.append((name, layer))
            else:
                stack.append((name, None))
        return hook

    def leave(_module, _args, _output):
        stack.pop()

    def capture(proxy, args, q):
        owner, layer = stack[-1]
        role = 'weight' if proxy is getattr(model.get_submodule(owner), 'weight_quant', None) else 'bias' if proxy is getattr(model.get_submodule(owner), 'bias_quant', None) else 'input_activation' if owner == 'input_quant' or owner.endswith('.input_quant') else 'output_activation'
        suffix = 'weight_quant' if role == 'weight' else 'bias_quant' if role == 'bias' else 'act_quant'
        name = owner + '.' + suffix
        call = calls[name]
        calls[name] += 1
        rec = quant_metadata(q, name, role, call, owner, proxy)
        rec['module_aliases'] = aliases[id(proxy)]
        rec['shared_quantizer_id'] = aliases[id(proxy)][0]
        rec['execution_index'] = len(events)
        events.append(rec['id'])
        if role in ('weight', 'bias'):
            arr = quant_integers(q, 8 if role == 'weight' else 16)
            layer[role + '_integers'] = arr
            layer[role + '_quant_id'] = rec['id']
            rec['logical_tensor_shape'] = list(arr.shape)
            rec['integer_min'] = int(arr.min())
            rec['integer_max'] = int(arr.max())
            if role == 'bias':
                input_rec = next(r for r in records if r['id'] == layer['input_quant_id'])
                if (parameter(args[1].scale) != input_rec['scale'] or
                        parameter(args[1].zero_point) != input_rec['zero_point'] or
                        int(args[1].bit_width.item()) != input_rec['bit_width'] or
                        bool(args[1].signed) != input_rec['signed']):
                    raise ValueError('Actual convolution input quantization differs from its recorded producer')
                actual_scale = proxy.compute_bias_scale(args[1], args[2]).reshape(-1)
                torch.testing.assert_close(q.scale, actual_scale, rtol=0, atol=0)
                product = (args[1].scale * args[2].scale).reshape(-1)
                torch.testing.assert_close(q.scale, product, rtol=0, atol=0)
                rec['derivation'] = dict(operation='input_scale * weight_scale (verified against compute_bias_scale)',
                                         input_quant_id=layer['input_quant_id'], weight_quant_id=layer['weight_quant_id'],
                                         source='BiasQuantProxyFromInjector.compute_bias_scale / Int16Bias')
                preclamp = torch.round(args[0].detach() / q.scale + q.zero_point)
                rec['saturated_parameter_count'] = int(((preclamp < -32768) | (preclamp > 32767)).sum())
        else:
            rec['consumers'] = links[owner]
            rec['location'] = 'residual_operands_shared' if owner == 'residual_quant' else role
            if owner == 'residual_quant':
                c = model.num_channels * model.scale_factor ** 2
                rec['uses'] = [dict(branch='main', concatenated_channel_range=[0, c]),
                               dict(branch='skip_repeat', concatenated_channel_range=[c, 2 * c])]
                rec['range_convention'] = 'start inclusive, end exclusive'
            if owner == 'output_quant':
                rec['location'] = 'after wide residual addition, before PixelShuffle'
        records.append(rec)

    seen = set()
    for name, module in model.named_modules():
        if isinstance(module, (QuantConv2d, QuantIdentity)):
            handles.extend([module.register_forward_pre_hook(enter(name, module)),
                            module.register_forward_hook(leave)])
            proxies = [module.weight_quant, module.bias_quant] if isinstance(module, QuantConv2d) else [module.act_quant]
            for proxy in proxies:
                if proxy.is_quant_enabled and id(proxy) not in seen:
                    handles.append(proxy.register_forward_hook(capture))
                    seen.add(id(proxy))
    try:
        with torch.no_grad():
            model(x)
    finally:
        for handle in handles:
            handle.remove()
    for name, tensor in model.state_dict().items():
        torch.testing.assert_close(tensor, before[name], rtol=0, atol=0)
    for name, tensor in model.named_buffers():
        torch.testing.assert_close(tensor, buffers[name], rtol=0, atol=0)
    for name, counter in counters.items():
        if model.get_submodule(name).act_quant.fused_activation_quant_proxy.tensor_quant.scaling_impl.counter != counter:
            raise ValueError('Forward updated activation collection counter')
    if [layer['name'] for layer in layers] != conv_names:
        raise ValueError('Observed computation differs from audited architecture; update adapter explicitly')
    if set(links) != {r['associated_module'] for r in records if 'activation' in r['role']}:
        raise ValueError('Missing or unexpected activation quantization site')
    by_id = {r['id']: r for r in records}
    for layer in layers:
        if 'weight_integers' not in layer or (layer['bias_present'] and 'bias_integers' not in layer):
            raise ValueError('A required quantized parameter was not captured')
        b = by_id.get(layer.get('bias_quant_id'))
        if b:
            input_rec, weight_rec = by_id[layer['input_quant_id']], by_id[layer['weight_quant_id']]
            np.testing.assert_allclose(np.asarray(b['scale']['values']).reshape(-1),
                                       (np.asarray(input_rec['scale']['values'], dtype=np.float32) *
                                        np.asarray(weight_rec['scale']['values'], dtype=np.float32)).reshape(-1),
                                       rtol=0, atol=0)
    provenance = dict(checkpoint=str(Path(checkpoint_path).resolve()), checkpoint_sha256=sha256(checkpoint_path),
                      model_source_sha256=sha256(ROOT / 'model/model_QAT.py'),
                      model_config=qat_checkpoint_configs(ckpt)[0],
                      quant_config=qc, checkpoint_epoch_zero_based=ckpt.get('epoch'),
                      versions=dict(python=sys.version.split()[0], torch=torch.__version__, brevitas=brevitas.__version__, numpy=np.__version__),
                      extraction_device='cpu', eval=True, no_grad=True, state_unchanged=True, input=input_info)
    quant = dict(schema_version=1, provenance=provenance, records=records, execution_order=events,
                 unquantized_operations=['Conv2d accumulation/output before explicit activation quantization',
                                         f'{model.activation} before output QuantIdentity',
                                         'residual wide addition before output_quant', 'PixelShuffle (reorders quantized values)'],
                 notes=['No input/intermediate activation arrays exported.',
                        'Convolution input/output proxies are disabled; external QuantIdentity sites carry the activation grids.',
                        'No scale or zero point is fabricated for unquantized operations.'])
    return layers, quant
