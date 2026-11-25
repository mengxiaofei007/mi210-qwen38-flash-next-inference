# 部署手册

从零到「开机自启 + 可调用 API」的完整步骤。每一步都有对应脚本，按顺序执行即可。
**前提**：Arch Linux + 单张 MI210（gfx90a）+ 62 GiB 内存 + NVMe ≥250 GB 可用空间。

> **已经装好 Unsloth Studio，或想自己手动安装 / 下载模型？** 不用照本文从头走，
> 直接看 [bring-your-own.md](bring-your-own.md)：它说明如何只调整参数与环境，
> 达到与本仓库脚本部署完全一致的效果。

## 0. 部署前体检（只读）

```bash
scripts/preflight.sh
```

会检查：OS/内核、GPU 设备节点、`rocm-gfx90a-bin`、可用内存、磁盘空间、`hf` 命令。
任何一项不达标都会明确报出并给出建议。**此步不修改任何东西。**

## 1. 安装 Unsloth Studio + gfx90a torch

```bash
scripts/install.sh
```

做了两件事：

1. 用官方安装器装 Studio + ROCm 预编译 llama.cpp/whisper.cpp/audio.cpp，
   并设 `UNSLOTH_INSTALL_SYSTEMD=1`、`UNSLOTH_SKIP_AUTOSTART=1`、`UNSLOTH_INSTALL_NO_ROLLBACK=1`；
2. 从 AMD 官方 wheel 源覆盖安装 `torch[device-gfx90a]==2.15.0+rocm10.2.0` 等，并验证 `torch.cuda.is_available()`。

## 2. 下载模型（约 200 GB）

```bash
pip install -U huggingface_hub         # 提供 hf 命令（本机 2.4.0）
export HF_TOKEN=hf_xxx                 # 如仓库需要登录；不要写进任何文件
scripts/download-models.sh
```

只下载必需文件：`UD-IQ4_XS/*`、`engram/…gguf_file`、`MTP/…shared-Q8_0.gguf`、`mmproj-BF16.gguf`。
默认下到 `~/AI/models/Qwen3.8-Flash-Next-GGUF`，可用 `MODEL_DIR` 覆盖。

## 3. 安装 systemd 单元 + linger

```bash
scripts/install-service.sh
```

会：复制单元到 `~/.config/systemd/user/` → `daemon-reload` → `enable` 服务 →
`loginctl enable-linger "$USER"`（没登录也常驻）。**不会立即启动**（启动留给第 4 步，便于先校验）。

> 单元的 `WorkingDirectory=%h/AI` 必须含 `models/`；`MemoryMax=50G` 按 62 GiB 整机换算。
> 内存不同的机器见 [limits.md](limits.md)。

## 4. 校验

```bash
scripts/verify.sh
```

检查：Studio venv / torch gfx90a / llama-server 二进制 / 4 类模型文件是否齐全且非空 /
systemd 单元是否已安装 / 端口是否被占用。全部通过才建议启动。

## 5. 启动与访问

```bash
systemctl --user enable --now unsloth-studio
journalctl --user -u unsloth-studio -f
# 浏览器打开 http://127.0.0.1:8888
```

在 Studio UI 里加载模型后，它会 fork 一个 llama-server 子进程（默认 `:42707`）。
参数解读见 [inference-flags.md](inference-flags.md)。

## 6. 脱离 Studio 直接启动（可选）

```bash
scripts/launch-llama-server.sh
# 自定义： CTX=65536 PORT=8080 API_KEY=xxx scripts/launch-llama-server.sh
```

参数与 Studio 下发的一致（已去重）。路径可用环境变量覆盖：`MODEL_DIR`、`MAIN_GGUF`、
`PLE_ENGRAM`、`MTP_DRAFT`、`LLAMA_SERVER`。额外参数直接追加，原样透传。

## 7. 基准测试

```bash
scripts/benchmark.sh
```

通过 OpenAI 兼容 API 发固定请求，输出 prompt/gen tok/s。基线数据见 [benchmarks.md](benchmarks.md)。

## 8. 自动更新（Arch Linux，可选）

AUR 包 `unsloth-studio-rocm-gfx90a-updater`：

```bash
yay -S unsloth-studio-rocm-gfx90a-updater
systemctl --user enable --now unsloth-updater.timer
journalctl --user -u unsloth-updater -f
```

它用 nvchecker 跟踪 PyPI（unsloth）与 AMD wheel 索引（torch/torchvision/torchaudio），
每天 05:00（随机延迟 30 分钟）检查，有新版本就重跑官方安装器并重新 pin gfx90a torch。
设计取舍与 dry-run 用法见 README 第 5 节。

## 卸载

```bash
systemctl --user disable --now unsloth-studio
systemctl --user disable --now unsloth-updater.timer
rm ~/.config/systemd/user/unsloth-studio.service
systemctl --user daemon-reload
# 模型文件与 ~/.unsloth 按需手动删除（注意约 200 GB）
```
