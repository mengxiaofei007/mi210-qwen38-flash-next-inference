# 软件版本清单（实测）

> 采集时间：2026-11-25。所有版本均来自本机实际运行环境的 `pip`/`pacman`/`--version` 输出。
> **升级任何一项后请重跑 `scripts/preflight.sh` 与 `scripts/verify.sh`。**

## 1. 操作系统与驱动

| 组件 | 版本 | 来源 / 说明 |
|---|---|---|
| OS | Arch Linux（rolling） | `cat /etc/os-release`，`BUILD_ID=rolling` |
| 内核 | `7.3.5-arch1-1` | `uname -a`（2026-11-17 构建） |
| ROCm | `rocm-gfx90a-bin 10.2.0-1` | pacman；**pin gfx90a 目标** |
| linux-firmware-amdgpu | `20261019-1` | pacman |
| Mesa | `1:26.3.1-3` | pacman |
| glibc / 工具链 | 系统 rolling 最新 | Arch 滚动更新 |

## 2. Python 与推理栈（Studio venv）

Python 解释器位于 `~/.unsloth/studio/unsloth_studio/bin/python`。

| 包 | 版本 | 说明 |
|---|---|---|
| Python | 3.13.17 | Studio 自带 venv |
| torch | `2.15.0+rocm10.2.0` | **AMD 官方 wheel 源** `https://stable.repo.amd.com/rocm/whl-next/`，pin `device-gfx90a` |
| torchvision | `0.29.2+rocm10.2.0` | 同上，pin gfx90a |
| torchaudio | `2.11.1+rocm10.2.0` | AMD wheel 源 |
| triton | `3.9.0+git0a6e13e6.rocm10.2.0` | 随 ROCm torch 安装 |
| unsloth | `2026.11.11` | 官方安装器 |
| transformers | `5.5.4` | — |
| datasets | `4.3.0` | — |
| accelerate | `1.16.0` | — |
| peft | `0.18.1` | — |
| bitsandbytes | `0.50.3.dev0` | — |
| huggingface_hub (`hf`) | `2.4.0` | 提供 `hf download` 命令 |

> `torch.cuda.is_available() == True` 是本栈的最低验证条件；False 时见 [troubleshooting.md](troubleshooting.md)。

## 3. llama.cpp（Unsloth fork）

```
$ ~/.unsloth/llama.cpp/build/bin/llama-server --version
version: 1.0.0-dev (build 12675, commit add07b393)
built with Clang 24.0.0 for Linux x86_64 (Compiled by the Unsloth team)
```

| 项 | 值 |
|---|---|
| 构建号 | b12675（README 基线曾记 b12540，实际已更新，以本表为准） |
| commit | `add07b393` |
| 编译器 | Clang 24.0.0 |
| 目标 | Linux x86_64 / ROCm gfx90a 预编译 |
| 二进制 | `~/.unsloth/llama.cpp/llama-server` → `build/bin/llama-server`（符号链接） |

## 4. 服务组件

| 项 | 值 |
|---|---|
| Unsloth Studio | `:8888`（Web UI + OpenAI 兼容 API；绑定 `127.0.0.1`） |
| llama-server | Studio 拉起的子进程，`:42707` |
| systemd | 用户级单元 `unsloth-studio.service`，`Restart=on-failure`，`MemoryMax=50G` |
| 自动更新器 | `unsloth-studio-rocm-gfx90a-updater 1.0.0-8`（AUR / pacman） |

## 5. 模型文件

仓库 `unsloth/Qwen3.8-Flash-Next-GGUF`，下载到 `~/AI/models/Qwen3.8-Flash-Next-GGUF`：

| 文件 | 用途 | 实际大小 |
|---|---|---|
| `UD-IQ4_XS/…00001-of-00004.gguf` | 主模型分片 1（传给 `-m`） | 10.9 MB |
| `UD-IQ4_XS/…00002-of-00004.gguf` | 主模型分片 2 | 49.6 GB |
| `UD-IQ4_XS/…00003-of-00004.gguf` | 主模型分片 3 | 15.3 GB |
| `UD-IQ4_XS/…00004-of-00004.gguf` | 主模型分片 4 | 28.8 GB |
| **主模型合计** | UD-IQ4_XS 4 片 | **≈ 93.7 GB** |
| `engram/Qwen3.8-Flash-Next-engram-BF16.gguf_file` | PLE 外挂（`--ple`） | ≈ 102 GB（本地缓存实测约 102.4 GB） |
| `MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf` | MTP draft（`-md`，生效值） | 2.8 GB |
| `MTP/mtp-Qwen3.8-Flash-Next-Q4KM-q8emb.gguf` | 备用 MTP draft | 3.3 GB |
| `mmproj-BF16.gguf` | 视觉投影（**当前未加载**） | 0.9 GB |

> 磁盘总占用约 200 GB。

## 6. pin 版本的原因（不要随意升级）

1. **torch 必须 pin 到 gfx90a**：Unsloth 官方安装器默认装的 torch 不是 ROCm/gfx90a 构建，
   会从 AMD wheel 源覆盖安装 `torch[device-gfx90a]==2.15.0+rocm10.2.0`。
2. **ROCm 10.2 + 内核 7.3**：`rocm-gfx90a-bin` 10.2.0 是与 MI210 验证过的组合，跨大版本升级需重测。
3. **llama.cpp 预编译**：Unsloth fork 的 ROCm/gfx90a 预编译 tarball 布局特殊（build/bin overlay、
   顶层符号链接、install-record json、whisper 的 libggml 硬链接），与覆盖式重装不完全兼容，
   因此 AUR 更新器**故意不自动更新** llama.cpp / whisper.cpp / audio.cpp，留给人工确认。
4. **87 参命令行**：Studio 每次拉起 llama-server 的参数以 `.scratch/live-llama-server-cmdline.txt`
   记录的为准，重复参数取最后一次生效（`--fit on` 被 `--fit off` 覆盖等）。

## 7. 复现采集命令

```bash
PY=~/.unsloth/studio/unsloth_studio/bin/python
$PY --version
$PY -c "import importlib.metadata as m; [print(p, m.version(p)) for p in ['torch','triton','unsloth','transformers']]"
$PY -c "import torch; print(torch.__version__, torch.version.hip, torch.cuda.is_available())"
~/.unsloth/llama.cpp/build/bin/llama-server --version
pacman -Q | grep -E 'rocm-gfx90a-bin|unsloth-studio-rocm-gfx90a-updater'
hf --version
```
