import copy
import glob
import os
import random
import sys

# 将父目录加入 Python 搜索路径
parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

import torch
import torch.backends.cudnn as cudnn
import torch.optim as optim
import torchvision.transforms.functional as TF
from PIL import Image
from torch import nn
from torch.utils.data import DataLoader, Dataset
from tqdm import tqdm

from datasets import EvalDataset
from model.model_float import FSRCNN_ECB
from utils import AverageMeter, calc_psnr


class Config:
    # 数据集路径设置
    train_hr_dir = "dataset/div2k/DIV2K_train_HR"
    train_lr_dir = "dataset/div2k/DIV2K_train_LR_bicubic/X4"
    eval_file = "dataset/Set5_x4.h5"
    outputs_dir = "model_data"
    weights_file = None

    scale = 4
    num_channels = 1
    d = 16
    s = 16
    m = 4

    hr_crop_size = 192
    iterations_per_epoch = 1000
    batch_size = 64
    num_epochs = 500

    lr = 1e-3
    min_lr = 5e-5

    num_workers = 4
    seed = 123
    grad_clip = 1.0
    test_every = 1
    save_every = 20


class DIV2KTrainDataset(Dataset):
    """DIV2K 在线动态裁剪与增强 Dataset"""

    def __init__(
        self,
        hr_dir,
        lr_dir,
        scale,
        hr_crop_size,
        num_channels=1,
        epoch_samples=32000,
    ):
        super().__init__()
        self.scale = scale
        self.hr_crop_size = hr_crop_size
        self.lr_crop_size = hr_crop_size // scale
        self.num_channels = num_channels
        self.epoch_samples = epoch_samples

        hr_paths = sorted(glob.glob(os.path.join(hr_dir, "*.png")))
        lr_paths = sorted(glob.glob(os.path.join(lr_dir, "*.png")))
        assert (
            len(hr_paths) == len(lr_paths) and len(hr_paths) > 0
        ), "请确保 DIV2K 的 HR 与 LR 路径正确且包含 PNG 图片！"

        print(f"\n正在将 {len(hr_paths)} 张 DIV2K 图像预加载至内存...")
        self.hr_images = [Image.open(p).convert("RGB") for p in hr_paths]
        self.lr_images = [Image.open(p).convert("RGB") for p in lr_paths]
        print("内存预加载完成！")

    def __len__(self):
        return self.epoch_samples

    def __getitem__(self, idx):
        img_idx = random.randint(0, len(self.hr_images) - 1)
        hr_img = self.hr_images[img_idx]
        lr_img = self.lr_images[img_idx]

        w_lr, h_lr = lr_img.size
        x_lr = random.randint(0, w_lr - self.lr_crop_size)
        y_lr = random.randint(0, h_lr - self.lr_crop_size)

        x_hr = x_lr * self.scale
        y_hr = y_lr * self.scale

        lr_crop = lr_img.crop(
            (x_lr, y_lr, x_lr + self.lr_crop_size, y_lr + self.lr_crop_size)
        )
        hr_crop = hr_img.crop(
            (x_hr, y_hr, x_hr + self.hr_crop_size, y_hr + self.hr_crop_size)
        )

        if self.num_channels == 1:
            lr_crop = lr_crop.convert("L")
            hr_crop = hr_crop.convert("L")

        lr_tensor = TF.to_tensor(lr_crop)
        hr_tensor = TF.to_tensor(hr_crop)

        # 单样本级别的数据增强（翻转/旋转）
        if random.random() < 0.5:
            lr_tensor = torch.flip(lr_tensor, dims=[2])
            hr_tensor = torch.flip(hr_tensor, dims=[2])
        if random.random() < 0.5:
            lr_tensor = torch.flip(lr_tensor, dims=[1])
            hr_tensor = torch.flip(hr_tensor, dims=[1])
        if random.random() < 0.5:
            lr_tensor = lr_tensor.transpose(1, 2)
            hr_tensor = hr_tensor.transpose(1, 2)

        return lr_tensor, hr_tensor


def main():
    cfg = Config()
    random.seed(cfg.seed)
    torch.manual_seed(cfg.seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(cfg.seed)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    os.makedirs(cfg.outputs_dir, exist_ok=True)
    
    print("=" * 80)
    print("Using device:", device)
    if torch.cuda.is_available():
        cudnn.benchmark = True

    print("\nCreating FSRCNN_ECB (Scharr + ReLU)...")
    model = FSRCNN_ECB(
        scale_factor=cfg.scale,
        num_channels=cfg.num_channels,
        d=cfg.d,
        s=cfg.s,
        m=cfg.m,
        deploy=False,
    ).to(device)

    num_params = sum(p.numel() for p in model.parameters() if p.requires_grad)
    print(f"\nTraining parameters: {num_params}")

    if cfg.weights_file is not None and os.path.exists(cfg.weights_file):
        print("\nLoading pretrained weights:", cfg.weights_file)
        checkpoint = torch.load(cfg.weights_file, map_location=device)
        model.load_state_dict(checkpoint)
    else:
        print("\nTraining from scratch.")

    criterion = nn.L1Loss()
    optimizer = optim.Adam(model.parameters(), lr=cfg.lr)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(
        optimizer, T_max=cfg.num_epochs, eta_min=cfg.min_lr
    )

    print("\nLoading DIV2K training dataset...")
    epoch_samples = cfg.iterations_per_epoch * cfg.batch_size
    train_dataset = DIV2KTrainDataset(
        hr_dir=cfg.train_hr_dir,
        lr_dir=cfg.train_lr_dir,
        scale=cfg.scale,
        hr_crop_size=cfg.hr_crop_size,
        num_channels=cfg.num_channels,
        epoch_samples=epoch_samples,
    )
    train_dataloader = DataLoader(
        dataset=train_dataset,
        batch_size=cfg.batch_size,
        shuffle=True,
        num_workers=cfg.num_workers,
        pin_memory=True,
        drop_last=True,
    )

    print("\nLoading validation dataset (Set5)...")
    eval_dataset = EvalDataset(cfg.eval_file)
    eval_dataloader = DataLoader(
        dataset=eval_dataset, batch_size=1, shuffle=False, num_workers=0
    )

    best_weights = copy.deepcopy(model.state_dict())
    best_epoch = 0
    best_psnr = -float("inf")

    print("\n" + "=" * 80)
    print("Start training on DIV2K")
    print("=" * 80)

    for epoch in range(cfg.num_epochs):
        model.train()
        epoch_losses = AverageMeter()
        current_lr = optimizer.param_groups[0]["lr"]

        print(
            "\nEpoch [{}/{}]  LR = {:.8f}".format(
                epoch + 1, cfg.num_epochs, current_lr
            )
        )
        progress = tqdm(
            train_dataloader, total=len(train_dataloader), ncols=100
        )

        for inputs, labels in progress:
            inputs = inputs.to(device, non_blocking=True)
            labels = labels.to(device, non_blocking=True)

            preds = model(inputs)
            loss = criterion(preds, labels)

            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(
                model.parameters(), max_norm=cfg.grad_clip
            )
            optimizer.step()

            epoch_losses.update(loss.item(), inputs.size(0))
            progress.set_postfix(loss="{:.6f}".format(epoch_losses.avg))

        scheduler.step()
        print(
            "Epoch [{}/{}] - Loss: {:.6f}".format(
                epoch + 1, cfg.num_epochs, epoch_losses.avg
            )
        )

        if (epoch + 1) % cfg.save_every == 0:
            checkpoint_path = os.path.join(
                cfg.outputs_dir, "epoch_{}.pth".format(epoch + 1)
            )
            torch.save(model.state_dict(), checkpoint_path)
            print("Saved:", checkpoint_path)

        if (epoch + 1) % cfg.test_every == 0:
            model.eval()
            epoch_psnr = AverageMeter()
            shave = cfg.scale 

            with torch.no_grad():
                for inputs, labels in eval_dataloader:
                    inputs = inputs.to(device, non_blocking=True)
                    labels = labels.to(device, non_blocking=True)

                    preds = model(inputs)
                    preds = preds.clamp(0.0, 1.0)

                    # 裁边计算 PSNR
                    if (
                        preds.shape[2] > 2 * shave
                        and preds.shape[3] > 2 * shave
                    ):
                        preds_c = preds[..., shave:-shave, shave:-shave]
                        labels_c = labels[..., shave:-shave, shave:-shave]
                    else:
                        preds_c, labels_c = preds, labels

                    psnr = calc_psnr(preds_c, labels_c)
                    epoch_psnr.update(psnr, inputs.size(0))

            print(
                "Validation PSNR (Set5, shaved): {:.4f} dB".format(
                    epoch_psnr.avg
                )
            )

            if epoch_psnr.avg > best_psnr:
                best_psnr = epoch_psnr.avg
                best_epoch = epoch
                best_weights = copy.deepcopy(model.state_dict())
                best_path = os.path.join(cfg.outputs_dir, "best_train.pth")
                torch.save(best_weights, best_path)
                print("New best model! PSNR: {:.4f} dB".format(best_psnr))

    print("\n" + "=" * 80)
    print("Training finished")
    print("=" * 80)
    print("Best epoch:", best_epoch + 1)
    print("Best PSNR:", best_psnr)

    # 部署转换验证与精度评估
    model.load_state_dict(best_weights)
    model.eval()

    print("\n" + "=" * 80)
    print("Testing structural re-parameterization & Deployment Accuracy")
    print("=" * 80)

    # 1. 哑输入数值等价性校验
    test_input = torch.randn(1, cfg.num_channels, 32, 32).to(device)

    with torch.no_grad():
        y_train = model(test_input)

    if hasattr(model, "switch_to_deploy"):
        model.switch_to_deploy()
        model.eval()

        with torch.no_grad():
            y_deploy = model(test_input)

        max_diff = torch.max(torch.abs(y_train - y_deploy)).item()
        print(f"\nMaximum absolute difference on dummy input: {max_diff:.8f}")

        if max_diff < 1e-5:
            print("Re-parameterization verification: PASS")
        else:
            print(
                "Re-parameterization verification: WARNING (Please check fusion logic)"
            )
    else:
        print(
            "\n[Notice] Model has no 'switch_to_deploy' method, skipping re-parameterization check."
        )

    # 2. 使用部署模型在验证集进行测试
    print("\nRunning evaluation with DEPLOY model on validation set...")
    deploy_psnr = AverageMeter()
    shave = cfg.scale

    with torch.no_grad():
        for lr, hr in eval_dataloader:
            lr = lr.to(device, non_blocking=True)
            hr = hr.to(device, non_blocking=True)

            preds = model(lr)
            preds = torch.clamp(preds, 0.0, 1.0)

            if preds.shape[2] > 2 * shave and preds.shape[3] > 2 * shave:
                preds_c = preds[..., shave:-shave, shave:-shave]
                hr_c = hr[..., shave:-shave, shave:-shave]
            else:
                preds_c, hr_c = preds, hr

            psnr = calc_psnr(preds_c, hr_c)
            deploy_psnr.update(psnr, lr.size(0))

    print(f"Deploy Model Test PSNR (Set5, shaved): {deploy_psnr.avg:.4f} dB")

    # 3. 保存部署模型参数
    deploy_path = os.path.join(cfg.outputs_dir, "best_deploy.pth")
    torch.save(model.state_dict(), deploy_path)
    print("\nDeployment model saved to:", deploy_path)


if __name__ == "__main__":
    main()