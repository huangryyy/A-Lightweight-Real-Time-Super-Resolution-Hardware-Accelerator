"""硬件整数计算、reference 导出、超分辨率图像还原和 Y 通道 PSNR。
不模拟 DMA、SRAM 和时钟流水线；硬件输出仅用于计算完成后的比对。
"""

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image


SIM_DATA_DIR = Path(__file__).resolve().parent / "data_txt"
BASE_DIR = Path(__file__).resolve().parent
SCALE = 4
LR_IMAGE_PATH = BASE_DIR / "dataset" / "val_sharp_bicubic" / f"X{SCALE}" / "00000000.png"
if not LR_IMAGE_PATH.exists():
    LR_IMAGE_PATH = BASE_DIR / "dataset" / "val_sharp_bicubic" / "00000000.png"
GT_IMAGE_PATH = BASE_DIR / "dataset" / "val_sharp" / "00000000.png"
OUTPUT_SR_IMAGE = BASE_DIR / "results" / f"sr_result_x{SCALE}_sim.png"
CHANNELS = 16
PIXELS_PER_WORD = 4
BYTES_PER_WORD = CHANNELS * PIXELS_PER_WORD

# (文件名前缀, 卷积核大小, Q0.16 乘数)
LAYERS_CONFIG = (
    ("first_part.0", 5, 0x04A7),
    ("shrink.0", 1, 0x076E),
    ("ecb_blocks.0.reparam_conv", 3, 0x0591),
    ("ecb_blocks.1.reparam_conv", 3, 0x03F7),
    ("ecb_blocks.2.reparam_conv", 3, 0x0729),
    ("ecb_blocks.3.reparam_conv", 3, 0x06D7),
    ("expand.0", 1, 0x048C),
    ("last_part", 3, 0x0055),
)


def load_hex_file(filepath):
    return np.frombuffer(bytes.fromhex(Path(filepath).read_text(encoding="ascii")),
                         dtype=np.uint8)


def load_input_feature_hex(filepath, width, height):
    raw = load_hex_file(filepath)
    expected = width * height * CHANNELS
    if raw.size != expected:
        raise ValueError(f"{filepath}: 需要 {expected} 字节，实际 {raw.size} 字节")
    return raw.reshape(width, height, CHANNELS).astype(np.int32)


def load_weight_hex(filepath, kernel):
    raw = load_hex_file(filepath)
    expected = kernel * kernel * CHANNELS * CHANNELS
    if raw.size != expected:
        raise ValueError(f"{filepath}: 需要 {expected} 字节，实际 {raw.size} 字节")
    return raw.view(np.int8).reshape(kernel, kernel, CHANNELS, CHANNELS).astype(np.int32)


def load_bias_hex(filepath):
    raw = load_hex_file(filepath)
    if raw.size != CHANNELS * 2:
        raise ValueError(f"{filepath}: 需要 {CHANNELS * 2} 字节，实际 {raw.size} 字节")
    return raw.view(">i2").astype(np.int32)


def conv2d_int(x, weight, bias):
    width, height, _ = x.shape
    kernel = weight.shape[0]
    pad = kernel // 2
    padded = np.pad(x, ((pad, pad), (pad, pad), (0, 0)))
    acc = np.zeros_like(x, dtype=np.int32)
    for kw in range(kernel):
        for kh in range(kernel):
            acc += padded[kw:kw + width, kh:kh + height] @ weight[kw, kh].T
    return np.clip(acc + bias, -(1 << 17), (1 << 17) - 1)


def quantize_rtl(acc, scale):
    if not 0 <= scale <= 0xFFFF:
        raise ValueError("量化乘数必须是 16-bit")
    signed_scale = scale if scale < 0x8000 else scale - 0x10000
    product = acc.astype(np.int64) * signed_scale
    base = product >> 16
    fraction = product & 0xFFFF
    carry = np.where(
        product < 0,
        fraction > 0x8000,
        (fraction > 0x8000) | ((fraction == 0x8000) & ((base & 1) != 0)),
    )
    return (base + carry).astype(np.int32)


def simulate(data_dir, width=320, height=180):
    """仅由输入、权重、偏置计算八层网络，返回 (W, H, Co) 整数结果。"""
    data_dir = Path(data_dir)
    x = load_input_feature_hex(data_dir / "input_data.txt", width, height)
    residual_byte = x[:, :, 0]
    residual = np.where(residual_byte >= 128, residual_byte - 256, residual_byte)
    for index, (name, kernel, scale) in enumerate(LAYERS_CONFIG):
        weight = load_weight_hex(data_dir / f"{name}.weight.txt", kernel)
        bias = load_bias_hex(data_dir / f"{name}.bias.txt")
        acc = conv2d_int(x, weight, bias)
        last_layer = index == len(LAYERS_CONFIG) - 1
        if not last_layer:
            acc = np.maximum(acc, 0)
        x = quantize_rtl(acc, scale)
        if last_layer:
            x = np.clip(x + residual[:, :, None], -128, 127)
        else:
            x = np.clip(x, 0, 255)
        print(f"[{index + 1}/8] {name:28s} range=[{x.min():4d}, {x.max():4d}] "
              f"scale=0x{scale:04X}", flush=True)
    return x


def save_output_feature_hex(filepath, x):
    data = (x & 0xFF).astype(np.uint8).tobytes()
    if len(data) % BYTES_PER_WORD:
        raise ValueError("输出字节数必须是 64 的整数倍")
    filepath = Path(filepath)
    filepath.parent.mkdir(parents=True, exist_ok=True)
    with filepath.open("w", encoding="ascii", newline="\r\n") as output:
        for offset in range(0, len(data), BYTES_PER_WORD):
            output.write(data[offset:offset + BYTES_PER_WORD].hex() + "\n")
    print(f"Output: {filepath} ({len(data) // BYTES_PER_WORD} words, {len(data)} bytes)")


def compare_outputs(reference_path, hardware_path):
    """逐行比较完整 512-bit 数据，包含长度检查；不影响参考计算。"""
    reference = Path(reference_path).read_text(encoding="ascii").splitlines()
    hardware = Path(hardware_path).read_text(encoding="ascii").splitlines()
    mismatches = 0
    for index in range(max(len(reference), len(hardware))):
        expected = reference[index].strip().lower() if index < len(reference) else "<missing>"
        actual = hardware[index].strip().lower() if index < len(hardware) else "<missing>"
        if expected != actual:
            if mismatches < 5:
                print(f"Mismatch line {index + 1}:\n  reference: {expected}\n  hardware:  {actual}")
            mismatches += 1
    print(f"Compare: reference={len(reference)} words, hardware={len(hardware)} words, "
          f"mismatches={mismatches}")
    return mismatches


def calculate_psnr(img1, img2):
    mse = np.mean((img1.astype(np.float64) - img2.astype(np.float64)) ** 2)
    if mse == 0:
        return float("inf")
    return 10 * math.log10(255.0 ** 2 / mse)


def calculate_psnr_y(sr_image_path, gt_image_path):
    """保留原代码的 Y 通道 PSNR：RGB 图像转 YCbCr 后比较 Y，不裁边。"""
    if not Path(sr_image_path).exists():
        print(f"[PSNR] 找不到 SR 图像: {sr_image_path}")
        return None
    if not Path(gt_image_path).exists():
        print(f"[PSNR] 找不到 GT 图像: {gt_image_path}")
        return None
    with Image.open(gt_image_path) as image:
        gt_y = image.convert("YCbCr").getchannel("Y")
    with Image.open(sr_image_path) as image:
        sr_y = image.convert("YCbCr").getchannel("Y")
    if sr_y.size != gt_y.size:
        print(f"[PSNR] 警告: SR 尺寸 {sr_y.size} 与 GT 尺寸 {gt_y.size} 不符，执行裁剪对齐。")
        width = min(sr_y.width, gt_y.width)
        height = min(sr_y.height, gt_y.height)
        gt_y_np = np.array(gt_y)[:height, :width]
        sr_y_np = np.array(sr_y)[:height, :width]
    else:
        gt_y_np = np.array(gt_y)
        sr_y_np = np.array(sr_y)
    psnr_val = calculate_psnr(sr_y_np, gt_y_np)
    print(f"[PSNR] Y 通道 PSNR = {psnr_val:.4f} dB")
    return psnr_val


def reconstruct_image(x, lr_image_path, output_path):
    width, height, channels = x.shape
    if channels != SCALE * SCALE:
        raise ValueError(f"PixelShuffle X{SCALE} 需要 {SCALE * SCALE} 个通道")
    with Image.open(lr_image_path) as image:
        lr_img = image.convert("YCbCr")
    if lr_img.size != (width, height):
        raise ValueError(f"LR 图像尺寸 {lr_img.size} 与计算尺寸 {(width, height)} 不一致")
    _, lr_cb, lr_cr = lr_img.split()
    print("开始进行反量化与 PixelShuffle 图像重建...")
    dequant_out = x.transpose(1, 0, 2).astype(np.float32) * np.float32(1.0 / 127)
    sr_y = dequant_out.reshape(height, width, SCALE, SCALE)
    sr_y = sr_y.transpose(0, 2, 1, 3).reshape(height * SCALE, width * SCALE)
    sr_y_np = np.clip(sr_y * np.float32(255.0), 0.0, 255.0).astype(np.uint8)
    sr_y_img = Image.fromarray(sr_y_np)
    hr_size = (width * SCALE, height * SCALE)
    cb_hr = lr_cb.resize(hr_size, Image.Resampling.BICUBIC)
    cr_hr = lr_cr.resize(hr_size, Image.Resampling.BICUBIC)
    sr_rgb_img = Image.merge("YCbCr", (sr_y_img, cb_hr, cr_hr)).convert("RGB")
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sr_rgb_img.save(output_path)
    print(f"超分辨率重建图像已保存至: {output_path}")
    print(f"输出图像分辨率: {sr_rgb_img.size}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=SIM_DATA_DIR)
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=180)
    parser.add_argument("--output", type=Path, help="默认 data-dir/output_data_reference.txt")
    parser.add_argument("--compare", type=Path, help="默认比对 data-dir/output_data_configurable.txt（若存在）")
    parser.add_argument("--no-compare", action="store_true", help="仅计算生成参考文件")
    parser.add_argument("--lr-image", type=Path, default=LR_IMAGE_PATH)
    parser.add_argument("--gt-image", type=Path, default=GT_IMAGE_PATH)
    parser.add_argument("--sr-image", type=Path, default=OUTPUT_SR_IMAGE)
    args = parser.parse_args()
    if args.width <= 0 or args.height <= 0 or args.height % PIXELS_PER_WORD:
        parser.error("width/height 必须为正数，height 必须是 4 的整数倍（每字四像素）")
    output = args.output or args.data_dir / "output_data_reference.txt"
    hardware = args.compare or args.data_dir / "output_data_configurable.txt"
    protected = [args.data_dir / "input_data.txt", hardware]
    protected.extend(args.data_dir / f"{name}.{kind}.txt"
                     for name, _, _ in LAYERS_CONFIG for kind in ("weight", "bias"))
    if output.resolve() in {path.resolve() for path in protected}:
        parser.error("output 不能覆盖输入、权重、偏置或硬件输出文件")
    x = simulate(args.data_dir, args.width, args.height)
    save_output_feature_hex(output, x)
    reconstruct_image(x, args.lr_image, args.sr_image)
    calculate_psnr_y(args.sr_image, args.gt_image)
    if not args.no_compare:
        if hardware.exists() or args.compare is not None:
            if compare_outputs(output, hardware):
                raise SystemExit(1)
        else:
            print(f"Compare skipped: {hardware} does not exist")


if __name__ == "__main__":
    main()
