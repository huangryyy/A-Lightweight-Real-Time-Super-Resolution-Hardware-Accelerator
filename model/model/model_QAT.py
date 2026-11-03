import torch
import torch.nn as nn
import torch.nn.functional as F

import math
import torch
import torch.nn as nn
import torch.nn.functional as F

from brevitas.nn import QuantConv2d
from brevitas.nn import QuantIdentity
from brevitas.quant import Int8ActPerTensorFloat, Uint8ActPerTensorFloat, Int8WeightPerTensorFloat, Int16Bias


def make_activation(activation, alpha, inplace=False):
    if activation == "relu":
        return nn.ReLU(inplace=inplace)
    if activation == "leaky_relu":
        return nn.LeakyReLU(negative_slope=alpha, inplace=inplace)
    raise ValueError("activation must be 'relu' or 'leaky_relu'.")


def qat_checkpoint_configs(checkpoint):
    """Resolve saved semantics; checkpoints without new fields used LeakyReLU/int8."""
    model_config = dict(checkpoint["model_config"])
    quant_config = dict(checkpoint["quant_config"])
    model_config.setdefault("activation", "leaky_relu")
    quant_config.setdefault("act_signed", True)
    # Both historical variants used the ordinary activation sign for residuals.
    quant_config.setdefault("residual_signed", quant_config["act_signed"])
    # Earlier checkpoints tied model input/output signs to the hidden activations.
    quant_config.setdefault("io_signed", quant_config["act_signed"])
    quant_config.setdefault("bias_bit_width", None)
    quant_config.setdefault("quantize_residual", False)
    return model_config, quant_config


class ECB(nn.Module):
    def __init__(self, channels, alpha=0.0625, deploy=False, use_edge=True, edge_scale=0.0625,
                 activation="relu"):
        super().__init__()
        self.channels = channels
        self.alpha = alpha
        self.activation = activation
        self.activation_fn = make_activation(activation, alpha)
        self.deploy = deploy
        self.use_edge = use_edge
        self.qat = False

        if deploy:
            self.reparam_conv = nn.Conv2d(channels, channels, kernel_size=3, padding=1, bias=True)
        else:
            self.conv3x3 = nn.Conv2d(channels, channels, kernel_size=3, padding=1, bias=True)
            self.conv1x1 = nn.Conv2d(channels, channels, kernel_size=1, padding=0, bias=False)
            self.conv1x1_3x3 = nn.Conv2d(channels, channels, kernel_size=3, padding=1, bias=True)

            if use_edge:
                # 2个方向的 Scharr 算子
                self.edge_conv = nn.Conv2d(channels, channels * 2, kernel_size=3, padding=1, groups=channels, bias=False)
                # 通道级可学习缩放因子
                self.edge_scale = nn.Parameter(torch.full((1, channels, 1, 1), edge_scale, dtype=torch.float32))
                self._initialize_edge_kernels()
            else:
                self.edge_conv = None

    def _initialize_edge_kernels(self):
        # 1. Scharr X & Y (水平/垂直)
        scharr_x = torch.tensor([[-3.0, 0.0, 3.0], [-10.0, 0.0, 10.0], [-3.0, 0.0, 3.0]])
        scharr_y = torch.tensor([[-3.0, -10.0, -3.0], [0.0, 0.0, 0.0], [3.0, 10.0, 3.0]])

        # 拼接 2 个算子 -> 形状 (2, 1, 3, 3)
        kernels = torch.stack([scharr_x, scharr_y], dim=0).unsqueeze(1)
        # 重复至 (channels * 2, 1, 3, 3) 适应 Group Convolution
        kernels = kernels.repeat(self.channels, 1, 1, 1)

        with torch.no_grad():
            self.edge_conv.weight.copy_(kernels)
        self.edge_conv.weight.requires_grad = False  # 冻结算子权重

    def forward(self, x):
        if self.deploy:
            if self.qat:
                x = self.input_quant(x)
                x = self.reparam_conv(x)
                x = self.activation_fn(x)
                return self.output_quant(x)
            return self.activation_fn(self.reparam_conv(x))

        y = self.conv3x3(x) + self.conv1x1_3x3(self.conv1x1(x))
        
        if self.use_edge:
            edge_out = self.edge_conv(x)
            # 将 2 个算子的输出按通道分组相加
            edge_out = edge_out.view(x.size(0), self.channels, 2, x.size(2), x.size(3)).sum(dim=2)
            y = y + self.edge_scale * edge_out

        return self.activation_fn(y)

    def enable_qat(self, weight_bit_width=8, act_bit_width=8, bias_bit_width=16, act_signed=False):
        if not self.deploy:
            raise RuntimeError("Call switch_to_deploy() before enabling QAT.")
        if self.qat:
            if (weight_bit_width, act_bit_width, bias_bit_width, act_signed) != self.quant_config:
                raise ValueError("QAT is already enabled with different bit widths.")
            return
        if bias_bit_width is not None and (type(bias_bit_width) is not int or bias_bit_width != 16):
            raise ValueError("bias_bit_width must be 16, or None for legacy FP32 bias.")
        for bit_width in (weight_bit_width, act_bit_width):
            if isinstance(bit_width, bool) or not isinstance(bit_width, int) or bit_width < 2:
                raise ValueError("QAT bit widths must be integers greater than or equal to 2.")
        if not isinstance(act_signed, bool):
            raise ValueError("act_signed must be a boolean.")
        if not act_signed and act_bit_width != 8:
            raise ValueError("Unsigned activation mode requires act_bit_width=8 (range 0..255).")
        act_quant = Int8ActPerTensorFloat if act_signed else Uint8ActPerTensorFloat

        source_conv = self.reparam_conv
        quant_conv = QuantConv2d(
            self.channels, self.channels, kernel_size=3, padding=1, bias=True,
            weight_quant=Int8WeightPerTensorFloat,
            weight_bit_width=weight_bit_width,
            bias_quant=Int16Bias if bias_bit_width is not None else None,
            return_quant_tensor=False,
        ).to(device=source_conv.weight.device, dtype=source_conv.weight.dtype)
        with torch.no_grad():
            quant_conv.weight.copy_(source_conv.weight)
            quant_conv.bias.copy_(source_conv.bias)

        self.input_quant = QuantIdentity(
            act_quant=act_quant,
            bit_width=act_bit_width,
            return_quant_tensor=bias_bit_width is not None,
        ).to(device=source_conv.weight.device, dtype=source_conv.weight.dtype)
        self.output_quant = QuantIdentity(
            act_quant=act_quant,
            bit_width=act_bit_width,
            return_quant_tensor=bias_bit_width is not None,
        ).to(device=source_conv.weight.device, dtype=source_conv.weight.dtype)
        self.reparam_conv = quant_conv
        self.quant_config = (weight_bit_width, act_bit_width, bias_bit_width, act_signed)
        self.qat = True
        self.train(self.training)

    @staticmethod
    def _fuse_conv1x1_3x3(conv1, conv3):
        W1 = conv1.weight[:, :, 0, 0]  # (C, C)
        W3 = conv3.weight              # (C, C, 3, 3)
        b3 = conv3.bias
        W_fused = torch.einsum('oihw,ic->ochw', W3, W1)
        return W_fused, b3.clone()

    def switch_to_deploy(self):
        if self.deploy:
            return

        # 1. 融合 1x1 -> 3x3 级联
        W_13, b_13 = self._fuse_conv1x1_3x3(self.conv1x1, self.conv1x1_3x3)
        W_total = self.conv3x3.weight.detach().clone() + W_13
        b_total = self.conv3x3.bias.detach().clone() + b_13

        # 2. 融合边缘算子分支
        if self.use_edge:
            edge_w = self.edge_conv.weight.detach().view(self.channels, 2, 3, 3).sum(dim=1)  # (C, 3, 3)
            # 转为稠密 DW 矩阵 (C, C, 3, 3)
            dense_edge_w = torch.zeros(self.channels, self.channels, 3, 3, device=W_total.device, dtype=W_total.dtype)
            idx = torch.arange(self.channels)
            dense_edge_w[idx, idx] = edge_w
            
            # 乘以通道缩放权重
            scale = self.edge_scale.detach().view(self.channels, 1, 1, 1)
            W_total += dense_edge_w * scale

        # 3. 创建部署卷机构造
        deploy_conv = nn.Conv2d(self.channels, self.channels, kernel_size=3, padding=1, bias=True).to(device=W_total.device, dtype=W_total.dtype)
        with torch.no_grad():
            deploy_conv.weight.copy_(W_total)
            deploy_conv.bias.copy_(b_total)

        self.reparam_conv = deploy_conv
        self.deploy = True

        # 清理内存
        del self.conv3x3, self.conv1x1, self.conv1x1_3x3
        if self.use_edge:
            del self.edge_conv, self.edge_scale


class FSRCNN_ECB(nn.Module):
    def __init__(self, scale_factor, num_channels=1, d=16, s=16, m=3, alpha=0.0625, deploy=False,
                 activation="relu"):
        super(FSRCNN_ECB, self).__init__()
        self.scale_factor = scale_factor
        self.num_channels = num_channels
        self.d = d
        self.s = s
        self.m = m
        self.alpha = alpha
        self.activation = activation
        self.deploy = deploy
        self.qat = False

        self.first_part = nn.Sequential(
            nn.Conv2d(num_channels, d, kernel_size=5, padding=2),
            make_activation(activation, alpha, inplace=True)
        )
        self.shrink = nn.Sequential(
            nn.Conv2d(d, s, kernel_size=1),
            make_activation(activation, alpha, inplace=True)
        )
        self.ecb_blocks = nn.ModuleList()
        for _ in range(m):
            self.ecb_blocks.append(ECB(channels=s, alpha=alpha, deploy=deploy,use_edge=True, edge_scale=0.0625,
                                       activation=activation))

        self.expand = nn.Sequential(
            nn.Conv2d(s, d, kernel_size=1),
            make_activation(activation, alpha, inplace=True)
        )
        out_channels = num_channels * scale_factor * scale_factor
        self.last_part = nn.Conv2d(d, out_channels, kernel_size=3, padding=1)
        self.pixel_shuffle = nn.PixelShuffle(scale_factor)

        if not deploy:
            self._initialize_weights()

    def _initialize_weights(self):
        slope = self.alpha if self.activation == "leaky_relu" else 0.0
        for module in self.first_part:
            if isinstance(module, nn.Conv2d):
                nn.init.kaiming_normal_(module.weight, a=slope, mode='fan_out', nonlinearity=self.activation)
                if module.bias is not None:
                    nn.init.zeros_(module.bias)
        for module in self.shrink:
            if isinstance(module, nn.Conv2d):
                nn.init.kaiming_normal_(module.weight, a=slope, mode='fan_out', nonlinearity=self.activation)
                if module.bias is not None:
                    nn.init.zeros_(module.bias)
        for ecb in self.ecb_blocks:
            nn.init.kaiming_normal_(ecb.conv3x3.weight, a=slope, mode='fan_out', nonlinearity=self.activation)
            nn.init.zeros_(ecb.conv3x3.bias)
            nn.init.kaiming_normal_(ecb.conv1x1.weight, a=slope, mode='fan_out', nonlinearity=self.activation)
            if ecb.conv1x1.bias is not None:
                nn.init.zeros_(ecb.conv1x1.bias)
            nn.init.kaiming_normal_(ecb.conv1x1_3x3.weight, a=slope, mode='fan_out', nonlinearity=self.activation)
            nn.init.zeros_(ecb.conv1x1_3x3.bias)
        for module in self.expand:
            if isinstance(module, nn.Conv2d):
                nn.init.kaiming_normal_(module.weight, a=slope, mode='fan_out', nonlinearity=self.activation)
                if module.bias is not None:
                    nn.init.zeros_(module.bias)
        nn.init.normal_(self.last_part.weight, mean=0.0, std=0.001)
        if self.last_part.bias is not None:
            nn.init.zeros_(self.last_part.bias)

    def forward(self, x):
        if self.qat:
            x = self.input_quant(x)
        residual = x.value if self.qat and self.bias_bit_width is not None else x
        x_repeat = residual.repeat(1, self.scale_factor * self.scale_factor, 1, 1)
        x = self.first_part(x)
        x = self.shrink(x)
        for ecb in self.ecb_blocks:
            x = ecb(x)
        x = self.expand(x)
        x = self.last_part(x)
        if self.qat and self.quantize_residual:
            branches = self.residual_quant(torch.cat((x, x_repeat), dim=1))
            x, x_repeat = branches.value.chunk(2, dim=1)
        x = x + x_repeat
        if self.qat:
            x = self.output_quant(x)
        x = self.pixel_shuffle(x)
        return x

    def enable_qat(self, weight_bit_width=8, act_bit_width=8, bias_bit_width=16, quantize_residual=True,
                   act_signed=False, residual_signed=True, io_signed=True):
        """Enable fake quantization after FP32 fusion and weight loading.

        Bias uses the input-scale times weight-scale grid. Residual operands
        share a signed int8 grid by default, preserving negative corrections.
        Only ReLU features use uint8 by default. Model input/output retain signed
        quantization: neither location has an activation in the FP32 model.
        Create the optimizer afterwards. This is not an integer-only export.
        """
        if not self.deploy:
            raise RuntimeError("Call switch_to_deploy() before enabling QAT.")
        if self.qat:
            if (weight_bit_width, act_bit_width, bias_bit_width, quantize_residual, act_signed, residual_signed, io_signed) != (
                self.weight_bit_width, self.act_bit_width, self.bias_bit_width, self.quantize_residual,
                self.act_signed, self.residual_signed, self.io_signed
            ):
                raise ValueError("QAT is already enabled with a different configuration.")
            return
        if bias_bit_width is not None and (type(bias_bit_width) is not int or bias_bit_width != 16):
            raise ValueError("bias_bit_width must be 16, or None for legacy FP32 bias.")
        if not isinstance(quantize_residual, bool):
            raise ValueError("quantize_residual must be a boolean.")
        if not isinstance(residual_signed, bool):
            raise ValueError("residual_signed must be a boolean.")
        if not isinstance(io_signed, bool):
            raise ValueError("io_signed must be a boolean.")
        if quantize_residual and act_bit_width != 8:
            raise ValueError("Quantized residual operands require act_bit_width=8.")
        for bit_width in (weight_bit_width, act_bit_width):
            if isinstance(bit_width, bool) or not isinstance(bit_width, int) or bit_width < 2:
                raise ValueError("QAT bit widths must be integers greater than or equal to 2.")
        if not isinstance(act_signed, bool):
            raise ValueError("act_signed must be a boolean.")
        if not act_signed and act_bit_width != 8:
            raise ValueError("Unsigned activation mode requires act_bit_width=8 (range 0..255).")
        if any(block.qat for block in self.ecb_blocks):
            raise RuntimeError("Enable QAT on the whole model before enabling individual ECB blocks.")

        reference_weight = self.first_part[0].weight
        act_quant = Int8ActPerTensorFloat if act_signed else Uint8ActPerTensorFloat

        def make_activation_quant(return_quant_tensor=False, quantizer=act_quant):
            return QuantIdentity(
                act_quant=quantizer,
                bit_width=act_bit_width,
                return_quant_tensor=return_quant_tensor,
            ).to(device=reference_weight.device, dtype=reference_weight.dtype)

        def quantize_conv(source_conv):
            quant_conv = QuantConv2d(
                source_conv.in_channels, source_conv.out_channels,
                kernel_size=source_conv.kernel_size, stride=source_conv.stride,
                padding=source_conv.padding, dilation=source_conv.dilation,
                groups=source_conv.groups, bias=source_conv.bias is not None,
                padding_mode=source_conv.padding_mode,
                weight_quant=Int8WeightPerTensorFloat,
                weight_bit_width=weight_bit_width,
                bias_quant=Int16Bias if bias_bit_width is not None else None,
                return_quant_tensor=False,
            ).to(device=source_conv.weight.device, dtype=source_conv.weight.dtype)
            with torch.no_grad():
                quant_conv.weight.copy_(source_conv.weight)
                if source_conv.bias is not None:
                    quant_conv.bias.copy_(source_conv.bias)
            return quant_conv

        io_quantizer = Int8ActPerTensorFloat if io_signed else Uint8ActPerTensorFloat
        self.input_quant = make_activation_quant(
            return_quant_tensor=bias_bit_width is not None, quantizer=io_quantizer)
        self.output_quant = make_activation_quant(quantizer=io_quantizer)
        if quantize_residual:
            residual_quantizer = Int8ActPerTensorFloat if residual_signed else Uint8ActPerTensorFloat
            self.residual_quant = make_activation_quant(return_quant_tensor=True, quantizer=residual_quantizer)
        for part in (self.first_part, self.shrink, self.expand):
            part[0] = quantize_conv(part[0])
            part.add_module("output_quant", make_activation_quant(return_quant_tensor=bias_bit_width is not None))
        self.last_part = quantize_conv(self.last_part)
        for block in self.ecb_blocks:
            block.enable_qat(weight_bit_width, act_bit_width, bias_bit_width, act_signed)
        self.weight_bit_width = weight_bit_width
        self.act_bit_width = act_bit_width
        self.act_signed = act_signed
        self.residual_signed = residual_signed
        self.io_signed = io_signed
        self.bias_bit_width = bias_bit_width
        self.quantize_residual = quantize_residual
        self.qat = True
        self.train(self.training)

    def num_parameters(self):
        return sum(p.numel() for p in self.parameters())
    
    def switch_to_deploy(self):
        if self.deploy:
            return
        print("Converting FSRCNN + Lightweight ECB to deployment mode...")
        for ecb in self.ecb_blocks:
            ecb.switch_to_deploy()
        self.deploy = True
        print("Deployment conversion completed.")
        print(f"Deployment model parameters: {self.num_parameters()}")

    def print_structure(self):
        print("=" * 70)
        print("FSRCNN + Lightweight ECB")
        print("=" * 70)
        print(self)
        print("=" * 70)
        print("Parameters:", self.num_parameters())
        print("=" * 70)

if __name__ == "__main__":
    # 实例化模型（以 4 倍超分，单通道为例）
    model = FSRCNN_ECB(scale_factor=4, num_channels=1, d=16, s=16, m=4)
    model.eval()

    # 模拟输入张量：(batch_size=1, channels=1, H=48, W=48)
    dummy_input = torch.randn(1, 1, 48, 48)

    with torch.no_grad():
        out_train = model(dummy_input)
    model.switch_to_deploy()
