import math
import torch
import torch.nn as nn
import torch.nn.functional as F

class ECB(nn.Module):
    def __init__(self, channels, deploy=False, use_edge=True, edge_scale=0.0625):
        super().__init__()
        self.channels = channels
        self.deploy = deploy
        self.use_edge = use_edge

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
            return F.relu(self.reparam_conv(x))

        y = self.conv3x3(x) + self.conv1x1_3x3(self.conv1x1(x))
        
        if self.use_edge:
            edge_out = self.edge_conv(x)
            # 将 2 个算子的输出按通道分组相加
            edge_out = edge_out.view(x.size(0), self.channels, 2, x.size(2), x.size(3)).sum(dim=2)
            y = y + self.edge_scale * edge_out

        return F.relu(y)

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
    def __init__(self, scale_factor, num_channels=1, d=16, s=16, m=4, deploy=False):
        super(FSRCNN_ECB, self).__init__()
        self.scale_factor = scale_factor
        self.num_channels = num_channels
        self.d = d
        self.s = s
        self.m = m
        self.deploy = deploy

        self.first_part = nn.Sequential(
            nn.Conv2d(num_channels, d, kernel_size=5, padding=2),
            nn.ReLU(inplace=True)
        )
        self.shrink = nn.Sequential(
            nn.Conv2d(d, s, kernel_size=1),
            nn.ReLU(inplace=True)
        )
        self.ecb_blocks = nn.ModuleList()
        for _ in range(m):
            self.ecb_blocks.append(ECB(channels=s, deploy=deploy, use_edge=True, edge_scale=0.0625))

        self.expand = nn.Sequential(
            nn.Conv2d(s, d, kernel_size=1),
            nn.ReLU(inplace=True)
        )
        out_channels = num_channels * scale_factor * scale_factor
        self.last_part = nn.Conv2d(d, out_channels, kernel_size=3, padding=1)
        self.pixel_shuffle = nn.PixelShuffle(scale_factor)

        if not deploy:
            self._initialize_weights()

    def _initialize_weights(self):
        for module in self.first_part:
            if isinstance(module, nn.Conv2d):
                nn.init.kaiming_normal_(module.weight, mode='fan_out', nonlinearity='relu')
                if module.bias is not None:
                    nn.init.zeros_(module.bias)
        for module in self.shrink:
            if isinstance(module, nn.Conv2d):
                nn.init.kaiming_normal_(module.weight, mode='fan_out', nonlinearity='relu')
                if module.bias is not None:
                    nn.init.zeros_(module.bias)
        for ecb in self.ecb_blocks:
            nn.init.kaiming_normal_(ecb.conv3x3.weight, mode='fan_out', nonlinearity='relu')
            nn.init.zeros_(ecb.conv3x3.bias)
            nn.init.kaiming_normal_(ecb.conv1x1.weight, mode='fan_out', nonlinearity='relu')
            if ecb.conv1x1.bias is not None:
                nn.init.zeros_(ecb.conv1x1.bias)
            nn.init.kaiming_normal_(ecb.conv1x1_3x3.weight, mode='fan_out', nonlinearity='relu')
            nn.init.zeros_(ecb.conv1x1_3x3.bias)
        for module in self.expand:
            if isinstance(module, nn.Conv2d):
                nn.init.kaiming_normal_(module.weight, mode='fan_out', nonlinearity='relu')
                if module.bias is not None:
                    nn.init.zeros_(module.bias)
        nn.init.normal_(self.last_part.weight, mean=0.0, std=0.001)
        if self.last_part.bias is not None:
            nn.init.zeros_(self.last_part.bias)

    def forward(self, x):
        x_repeat = x.repeat(1, self.scale_factor * self.scale_factor, 1, 1)
        x = self.first_part(x)
        x = self.shrink(x)
        for ecb in self.ecb_blocks:
            x = ecb(x)
        x = self.expand(x)
        x = self.last_part(x)
        x = self.pixel_shuffle(x + x_repeat)
        return x

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
        print("FSRCNN + Lightweight ECB (ReLU)")
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
    with torch.no_grad():
        out_deploy = model(dummy_input)

    print("Forward pass successful. Difference between train and deploy modes:", torch.max(torch.abs(out_train - out_deploy)).item())