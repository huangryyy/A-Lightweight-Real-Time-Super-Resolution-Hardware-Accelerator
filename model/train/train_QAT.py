import sys
import os
parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)
import glob
import os
import random
import torch
import torch.backends.cudnn as cudnn
import torch.optim as optim
import torchvision.transforms.functional as TF
from PIL import Image
from torch import nn
from torch.utils.data import DataLoader, Dataset
from tqdm import tqdm

from datasets import EvalDataset
from utils import AverageMeter, calc_psnr
from model.model_QAT import FSRCNN_ECB, qat_checkpoint_configs


class Config:
    # 数据集路径设置
    train_hr_dir = "dataset/div2k/DIV2K_train_HR"
    train_lr_dir = "dataset/div2k/DIV2K_train_LR_bicubic/X4"
    eval_file = "dataset/Set5_x4.h5"
    outputs_dir = "model_data/QAT"
    weights_file = "model_data/best_deploy.pth"
    resume_file = None
    weight_bit_width = 8
    act_bit_width = 8
    act_signed = False
    residual_signed = True
    io_signed = True
    bias_bit_width = 16
    quantize_residual = True

    scale = 4
    num_channels = 1
    d = 16
    s = 16
    m = 4
    alpha = 0.0625
    activation = "relu"

    hr_crop_size = 192
    iterations_per_epoch = 1000
    batch_size = 64
    num_epochs = 30

    lr = 1e-4
    min_lr = 1e-6

    num_workers = 4
    seed = 123
    grad_clip = 1.0
    test_every = 1
    save_every = 20  


class DIV2KTrainDataset(Dataset):
    """DIV2K 在线动态裁剪与增强 Dataset"""
    def __init__(self, hr_dir, lr_dir, scale, hr_crop_size, num_channels=1, epoch_samples=32000):
        super().__init__()
        self.scale = scale
        self.hr_crop_size = hr_crop_size
        self.lr_crop_size = hr_crop_size // scale
        self.num_channels = num_channels
        self.epoch_samples = epoch_samples

        hr_paths = sorted(glob.glob(os.path.join(hr_dir, "*.png")))
        lr_paths = sorted(glob.glob(os.path.join(lr_dir, "*.png")))
        assert len(hr_paths) == len(lr_paths) and len(hr_paths) > 0, "请确保 DIV2K 的 HR 与 LR 路径正确且包含 PNG 图片！"

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

        lr_crop = lr_img.crop((x_lr, y_lr, x_lr + self.lr_crop_size, y_lr + self.lr_crop_size))
        hr_crop = hr_img.crop((x_hr, y_hr, x_hr + self.hr_crop_size, y_hr + self.hr_crop_size))

        if self.num_channels == 1:
            lr_crop = lr_crop.convert("L")
            hr_crop = hr_crop.convert("L")

        lr_tensor = TF.to_tensor(lr_crop)
        hr_tensor = TF.to_tensor(hr_crop)

        # [修改 3] 单样本级别的数据增强（翻转/旋转）
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


def evaluate(model, dataloader, device):
    model.eval()
    psnr_meter = AverageMeter()
    with torch.no_grad():
        for inputs, labels in dataloader:
            inputs = inputs.to(device=device, dtype=torch.float32, non_blocking=True)
            labels = labels.to(device=device, dtype=torch.float32, non_blocking=True)
            predictions = model(inputs).clamp(0.0, 1.0)
            psnr_meter.update(calc_psnr(predictions, labels).item(), inputs.size(0))
    return psnr_meter.avg


def main(cfg=None):
    cfg = Config() if cfg is None else cfg
    if cfg.num_epochs < 1 or cfg.test_every < 1 or cfg.save_every < 1:
        raise ValueError("num_epochs, test_every and save_every must be positive.")

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

    print("\nCreating FSRCNN + Lightweight ECB...")
    model = FSRCNN_ECB(
        scale_factor=cfg.scale,
        num_channels=cfg.num_channels,
        d=cfg.d,
        s=cfg.s,
        m=cfg.m,
        alpha=cfg.alpha,
        deploy=True,
        activation=cfg.activation
    )
    model_config = dict(scale_factor=cfg.scale, num_channels=cfg.num_channels,
                        d=cfg.d, s=cfg.s, m=cfg.m, alpha=cfg.alpha, deploy=True, activation=cfg.activation)
    quant_config = dict(weight_bit_width=cfg.weight_bit_width, act_bit_width=cfg.act_bit_width,
                        bias_bit_width=cfg.bias_bit_width, quantize_residual=cfg.quantize_residual,
                        act_signed=cfg.act_signed, residual_signed=cfg.residual_signed,
                        io_signed=cfg.io_signed)
    checkpoint = None
    if cfg.resume_file is not None:
        checkpoint = torch.load(cfg.resume_file, map_location="cpu", weights_only=True)
        saved_model_config, saved_quant_config = qat_checkpoint_configs(checkpoint)
        if saved_model_config != model_config or saved_quant_config != quant_config:
            raise ValueError("Resume checkpoint architecture or quantization configuration does not match. "
                             "Start a new QAT run from fused FP32 weights for the new quantization scheme.")
        if checkpoint["num_epochs"] != cfg.num_epochs:
            raise ValueError("Keep num_epochs unchanged when resuming the cosine schedule.")
        model.enable_qat(**quant_config)
        model.load_state_dict(checkpoint["model_state_dict"], strict=True)
    else:
        if cfg.weights_file is None or not os.path.isfile(cfg.weights_file):
            raise FileNotFoundError("QAT requires a fused FP32 weights_file or a QAT resume_file.")
        print("\nLoading fused FP32 weights:", cfg.weights_file)
        model.load_state_dict(torch.load(cfg.weights_file, map_location="cpu", weights_only=True), strict=True)
        model.enable_qat(**quant_config)
    model = model.to(device)
    print("\nQAT parameters:", model.num_parameters())
    print("Activation:", cfg.activation, "Quantization:", quant_config)

    criterion = nn.L1Loss()
    optimizer = optim.Adam(model.parameters(), lr=cfg.lr)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=cfg.num_epochs, eta_min=cfg.min_lr)
    start_epoch = 0
    best_epoch = -1
    best_psnr = -float("inf")
    if checkpoint is not None:
        optimizer.load_state_dict(checkpoint["optimizer_state_dict"])
        scheduler.load_state_dict(checkpoint["scheduler_state_dict"])
        start_epoch = checkpoint["epoch"] + 1
        best_epoch = checkpoint["best_epoch"]
        best_psnr = checkpoint["best_psnr"]
        print("Resuming QAT at epoch:", start_epoch + 1)

    def save_checkpoint(path, epoch):
        torch.save({
            "model_state_dict": model.state_dict(),
            "optimizer_state_dict": optimizer.state_dict(),
            "scheduler_state_dict": scheduler.state_dict(),
            "model_config": model_config,
            "quant_config": quant_config,
            "epoch": epoch,
            "num_epochs": cfg.num_epochs,
            "best_epoch": best_epoch,
            "best_psnr": best_psnr,
        }, path)

    print("\nLoading DIV2K training dataset...")
    epoch_samples = cfg.iterations_per_epoch * cfg.batch_size
    train_dataset = DIV2KTrainDataset(
        hr_dir=cfg.train_hr_dir,
        lr_dir=cfg.train_lr_dir,
        scale=cfg.scale,
        hr_crop_size=cfg.hr_crop_size,
        num_channels=cfg.num_channels,
        epoch_samples=epoch_samples
    )
    train_dataloader = DataLoader(
        dataset=train_dataset,
        batch_size=cfg.batch_size,
        shuffle=True,
        num_workers=cfg.num_workers,
        pin_memory=True,
        drop_last=True
    )

    print("\nLoading validation dataset (Set5)...")
    eval_dataset = EvalDataset(cfg.eval_file)
    eval_dataloader = DataLoader(dataset=eval_dataset, batch_size=1, shuffle=False, num_workers=0)

    print("\n" + "=" * 80)
    print("Start QAT fine-tuning on DIV2K")
    print("=" * 80)

    for epoch in range(start_epoch, cfg.num_epochs):
        model.train()
        epoch_losses = AverageMeter()
        current_lr = optimizer.param_groups[0]["lr"]

        print("\nEpoch [{}/{}]  LR = {:.8f}".format(epoch + 1, cfg.num_epochs, current_lr))
        progress = tqdm(train_dataloader, total=len(train_dataloader), ncols=100)

        for inputs, labels in progress:
            inputs = inputs.to(device=device, dtype=torch.float32, non_blocking=True)
            labels = labels.to(device=device, dtype=torch.float32, non_blocking=True)

            preds = model(inputs)
            loss = criterion(preds, labels)

            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=cfg.grad_clip)
            optimizer.step()

            epoch_losses.update(loss.item(), inputs.size(0))
            progress.set_postfix(loss="{:.6f}".format(epoch_losses.avg))

        scheduler.step()
        print("Epoch [{}/{}] - Loss: {:.6f}".format(epoch + 1, cfg.num_epochs, epoch_losses.avg))

        if (epoch + 1) % cfg.test_every == 0 or epoch + 1 == cfg.num_epochs:
            epoch_psnr = evaluate(model, eval_dataloader, device)
            print("QAT validation PSNR (Set5): {:.4f} dB".format(epoch_psnr))
            if epoch_psnr > best_psnr:
                best_psnr = epoch_psnr
                best_epoch = epoch
                best_path = os.path.join(cfg.outputs_dir, "best_qat.pth")
                save_checkpoint(best_path, epoch)
                print("New best model! PSNR: {:.4f} dB".format(best_psnr))

        save_checkpoint(os.path.join(cfg.outputs_dir, "last_qat.pth"), epoch)
        if (epoch + 1) % cfg.save_every == 0:
            checkpoint_path = os.path.join(cfg.outputs_dir, "epoch_{}.pth".format(epoch + 1))
            save_checkpoint(checkpoint_path, epoch)
            print("Saved:", checkpoint_path)

    print("\n" + "=" * 80)
    print("Training finished")
    print("=" * 80)
    print("Best epoch:", best_epoch + 1)
    print("Best PSNR:", best_psnr)

    print("QAT checkpoints saved to:", cfg.outputs_dir)
    print("QAT checkpoints require enable_qat() before loading model_state_dict.")

if __name__ == "__main__":
    main()
