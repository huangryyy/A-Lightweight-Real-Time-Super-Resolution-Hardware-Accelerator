# Linux 独立迁移运行目录

整个linux文件夹可单独复制到Linux，不再依赖上一级工程、/home/FSRCNN或任何旧调试目录。

## 文件

- Top.bit、Top.ltx：当前已验证的八层X4/全局残差比特流与探针。
- host/：唯一C++主机源码、STB头文件及流水线验收脚本。
- host/FSRCNN_X4_video：匹配当前源码的Ubuntu24.04 x86-64预编译程序；其他系统/ABI可用build.sh重编译。run.sh会恢复可执行权限并在源码更新时重新编译。
- driver/：XDMA源码、头文件和许可证，按本机内核重新编译。
- model/X4/：8层权重、16位偏置、manifest及独立整帧golden。
- data/lr/：100张320×180测试输入。
- reference_results/2026-10-29/：历史实板、质量和性能参考。参考视频如已取回放在其videos/中；未提供的视频不会用新生成文件冒充。
- SHA256SUMS：本目录独立校验清单；首次构建/运行前使用。

## 首次准备

已验证硬件XCZU19EG-FFVC1760-2-I，主机Ubuntu24.04.2 x86-64、内核6.11.0-17-generic。不同内核必须重新构建驱动。复制目录不等于系统已安装驱动、内核头文件或Vivado。

```bash
cd /path/to/linux
bash verify.sh files
bash setup.sh --install-deps
```

setup.sh安装编译器、Python、FFmpeg、pciutils和匹配内核头文件，然后编译主机及驱动；已有依赖可用bash setup.sh。系统依赖安装需要sudo及网络。
FFmpeg默认使用PATH；可用FFMPEG=/path/to/ffmpeg和FFMPEG_TOOLS=/path/to/directory指定版本，后者需同时包含ffmpeg/ffprobe。历史测速使用7.0.2，系统包版本可能影响性能。

## 配置板卡和运行

板卡接PCIe和USB/JTAG、保持正确供电。停止其他推理后：

```bash
sudo bash scripts/prepare_programming.sh
# source 本机Vivado的settings64.sh后再执行；Vivado软件及线缆驱动不随包提供
vivado -mode batch -source scripts/program_fpga.tcl
sudo bash scripts/load_driver.sh
bash verify.sh board
bash run.sh --repeat 10 --pace
```

必须看到PROGRAM_AND_DDR_PASS后才加载驱动。多个JTAG目标可用-tclargs '*线缆序列号*'指定。
设备不能枚举时，保持独立电源开启并重启主机后再加载。Secure Boot模块签名按主机已有MOK管理方式处理；脚本不更改启动安全设置。

run.sh自动检查/编译缺失或过旧的主机程序；默认流水线3槽、4个OpenMP线程/CPU阶段、100帧、60FPS视频时间戳。--pace才按输入节拍等待；--repeat 10循环至1000帧；--mode serial用于串行对照。输出写入本目录results/的新子目录，原参考结果不被覆盖。

```bash
bash verify.sh pipeline   # 300帧一致性/异常取消及串行、流水线、60FPS三组1000帧测试
```

当前只是文件序列流水线，不包含摄像头采集/显示。frame_ms是驻留延迟，输出节拍看output_interval，不能把frames_over_budget当丢帧数。

## 参考视频

reference_results/2026-10-29/videos/包含30FPS、60FPS及双三次插值对比的原编码MP4。直接保留Linux历史原片编码，不进行低码率预览转码。详见对应README及videos/manifest.json。

## 历史参考

2026-10-29：完整921600字节零差异；串行50.57FPS、流水线66.69FPS，60FPS节拍1000帧无持续积压；单样本PSNR-Y从27.3034提升至27.8943dB。
全部1000帧均为100张REDS输入循环10次，不能当成1000张独立场景；也不是在当前迁移主机上重新测量的结果。
STB许可证在头文件末尾，XDMA许可证在driver/。测试图像属于REDS，提交时注明第三方数据来源。
