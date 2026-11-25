# MI210 上的 Qwen3.8-Flash-Next 推理栈

> 在 **单张 AMD Instinct MI210（gfx90a，64 GiB HBM2e）** 上，用 Unsloth Studio + ROCm 版 llama.cpp，
> 跑 `unsloth/Qwen3.8-Flash-Next-GGUF`（UD-IQ4_XS + engram PLE 外挂 + MTP 投机解码 + MoE CPU 卸载），
> 在 **180k 上下文 / 4 并发** 下稳定常驻服务的一套**可复现、开箱即用**的部署配置。

本项目把「个人机器上能跑」整理成「别人照着也能跑」：所有脚本可单独执行，所有数字来自真实机器采集，
并明确写出**上限与下限**（能做什么、不能做什么、什么条件下会崩）。

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-ROCm%2Fgfx90a-darkred.svg)](docs/hardware.md)
[![Status](https://img.shields.io/badge/Status-tested%20on%20MI210-green.svg)](docs/benchmarks.md)

---

## 目录

- [一句话结论 / 能力边界](#一句话结论--能力边界)
- [快速开始（开箱即用路径）](#快速开始开箱即用路径)
- [环境基线](#环境基线)
- [上限与下限](#上限与下限)
- [仓库结构](#仓库结构)
- [文档索引](#文档索引)
- [免责声明](#免责声明)

---

## 一句话结论 / 能力边界

| 问题 | 回答 |
|---|---|
| 这套配置是干什么的 | 在一张 MI210 上，以 Web UI + OpenAI 兼容 API 的形式，提供 Qwen3.8-Flash-Next 的 180k 长上下文推理 |
| 显存放不下 200 GB 模型怎么办 | 主权重 MoE 前 12 层留 CPU + 4 GiB 显存热缓存；102 GB 的 engram 外挂用 DirectIO + lazy 按需读盘 |
| 实测生成速度 | DSH 真实会话中交互生成 **中位 ~25 tok/s**（p10–p90 为 19–41 tok/s）；长 prompt 处理中位 ~210 tok/s。见 [benchmarks.md](docs/benchmarks.md) |
| 上限 | 180k 上下文、4 并发槽位、~200 GB 模型文件常驻磁盘、整机 62 GiB 内存 |
| 下限 / 硬约束 | 必须 gfx90a + ROCm 10.2；整机内存 < 62 GiB 需重算 `MemoryMax`；**没有视觉能力**；单卡，不支持多卡并行 |
| 不适合谁 | 没有 MI210/gfx90a 的用户、想开箱跑多模态的用户、内存 < 48 GiB 的机器 |

> **性能数据出处**：本文及 [benchmarks.md](docs/benchmarks.md) 中的 tok/s 数字，全部来自
> **DeepSeek Harness（DSH）编码智能体的实际使用过程**——作者把这套服务作为 DSH 后端，
> 在真实的代码编写、文件读写、多轮对话与工具调用任务中产生的 llama-server 日志，经聚合统计得出；
> 不是压测脚本的合成数据。

> 详细的上限/下限与「什么时候会出问题」见 [docs/limits.md](docs/limits.md)。

---

## 快速开始（开箱即用路径）

按顺序执行，每一步都有对应的独立脚本，**任何一步失败都不会污染后续步骤**。

```bash
# 0) 环境体检：确认 GPU / ROCm / 内存 / 磁盘都达标（只读，不改任何东西）
scripts/preflight.sh

# 1) 安装 Unsloth Studio + 覆盖安装 gfx90a 版 torch
scripts/install.sh

# 2) 下载模型（约 200 GB，请确保磁盘空间与 HF_TOKEN）
export HF_TOKEN=hf_xxx                 # 如仓库需要登录；不要写进任何文件
scripts/download-models.sh

# 3) 安装开机自启 + 内存护栏（用户级 systemd）
scripts/install-service.sh

# 4) 校验安装与模型完整性
scripts/verify.sh

# 5) 启动服务并访问
systemctl --user enable --now unsloth-studio
loginctl enable-linger "$USER"         # 没登录也要常驻
# 浏览器打开 http://127.0.0.1:8888
```

脱离 Studio 直接跑 llama-server（等价参数）：

```bash
scripts/launch-llama-server.sh
# 或自定义： CTX=65536 PORT=8080 API_KEY=xxx scripts/launch-llama-server.sh
```

跑一次可复现的基准测试：

```bash
scripts/benchmark.sh                   # 通过 Studio 的 :8888 OpenAI 兼容 API 打一轮
scripts/benchmark.sh --url http://127.0.0.1:8888/v1 --model unsloth/Qwen3.8-Flash-Next-GGUF
```

生成一份本机环境报告（提 Issue 时附上它）：

```bash
scripts/collect-info.sh > environment.txt
```

---

## 环境基线

数据于 **2026-11-25** 在本机实测采集（原始方法见 [collect-info.sh](scripts/collect-info.sh)）。

| 类别 | 值 |
|---|---|
| 主机 | `lucas-gpu-server`，Arch Linux（rolling） |
| 内核 | `7.3.5-arch1-1` |
| CPU | AMD EPYC 7452（32 核 / 64 线程，4 NUMA 节点） |
| 内存 | 62 GiB RAM + 64 GiB Swap |
| GPU | AMD Instinct MI210（gfx90a:sramecc+:xnack-），65,520 MiB VRAM |
| ROCm | `rocm-gfx90a-bin` 10.2.0-1（pacman） |
| Python | 3.13.17（Studio venv） |
| torch | 2.15.0+rocm10.2.0 |
| llama.cpp | build 12675 / commit add07b393（Unsloth fork，ROCm/gfx90a 预编译） |
| Studio 模型 | UD-IQ4_XS 4 分片 ≈ 93.7 GB + engram 外挂 ≈ 102.4 GB + MTP ≈ 2.8 GB |
| 服务端口 | Studio `:8888`（Web + OpenAI API），llama-server 子进程 `:42707` |

完整版本清单见 [docs/software-versions.md](docs/software-versions.md)，硬件细节见 [docs/hardware.md](docs/hardware.md)。

---

## 上限与下限

**上限（这套配置能稳定做到）**

- 180,000 token 上下文（llama.cpp 实际 `n_ctx_slot = 180224`），4 并发槽位共享统一 KV。
- 主权重 MoE 卸载到 CPU 后，可在 64 GiB 显存里跑 93.7 GB 模型 + 102 GB PLE 外挂。
- 常驻服务，崩溃由 systemd `Restart=on-failure` 自愈；内存越界只杀本单元，不拖垮整机。

**下限 / 硬限制（这些是边界，越过去就会出问题）**

- **硬件**：MI210 / gfx90a 专属；ROCm 10.2 + gfx90a 预编译 llama.cpp 是已验证组合。
- **内存**：整机 62 GiB 时 `MemoryMax=50G`；内存更小必须等比下调并把更多 MoE 层留 CPU。
- **无视觉**：当前实例没加载 `--mmproj`，`--no-mmproj-auto` 显式关闭；`mmproj-BF16.gguf` 只是备用。
- **不支持多卡**：配置面向单卡；`--main-gpu/--tensor-split` 未调优，多卡需自行重测。

完整矩阵（含显存/内存预算表、故障阈值）见 [docs/limits.md](docs/limits.md)。

---

## 仓库结构

```
mi210-qwen38-flash-next-inference/
├── README.md                        # 本文（入口）
├── LICENSE                          # Apache License 2.0
├── NOTICE                           # 第三方组件归属说明
├── CONTRIBUTING.md                  # 贡献 / 提 Issue 规范
├── Makefile                         # 常用命令的 make 封装
├── .gitignore                       # 排除密钥/缓存/模型
├── docs/
│   ├── hardware.md                  # 硬件信息、拓扑、NUMA、驱动
│   ├── software-versions.md         # 软件版本清单与来源
│   ├── deployment.md                # 分步部署手册（含 AUR 自动更新器）
│   ├── bring-your-own.md            # 已有 Studio / 手动安装者的参数对齐指南
│   ├── benchmarks.md                # 真实性能数据与测量方法
│   ├── limits.md                    # 上限/下限/边界条件
│   ├── inference-flags.md           # llama-server 参数逐项解读
│   └── troubleshooting.md           # 故障排查（含 OOM 事故复盘）
├── scripts/
│   ├── preflight.sh                 # 部署前环境体检（只读）
│   ├── install.sh                   # Studio + gfx90a torch 安装
│   ├── download-models.sh           # 仅下载所需 GGUF 文件
│   ├── install-service.sh           # 安装 systemd 单元 + linger
│   ├── verify.sh                    # 安装后完整性校验
│   ├── launch-llama-server.sh       # 独立启动（Studio 等效参数）
│   ├── benchmark.sh                 # 可复现的基准测试
│   └── collect-info.sh              # 生成环境报告（提 Issue 用）
└── systemd/
    └── unsloth-studio.service       # 用户级自启单元（含内存护栏）
```

---

## 文档索引

| 文档 | 用途 |
|---|---|
| [docs/hardware.md](docs/hardware.md) | CPU / GPU / 内存 / NUMA / 驱动 / 磁盘 |
| [docs/software-versions.md](docs/software-versions.md) | 所有软件版本、来源、pin 原因 |
| [docs/deployment.md](docs/deployment.md) | 从零部署到常驻服务的完整步骤 |
| [docs/bring-your-own.md](docs/bring-your-own.md) | 已有 Studio / 手动安装者如何调参达到本仓库效果 |
| [docs/benchmarks.md](docs/benchmarks.md) | DSH 真实会话中采集的 tok/s、上下文、显存占用与测量脚本 |
| [docs/limits.md](docs/limits.md) | 能力上限、硬下限、边界条件 |
| [docs/inference-flags.md](docs/inference-flags.md) | 87 参原始命令行与逐项解读 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | OOM / 500 / 无视觉 / 版本回退等问题 |

---

## 开源许可

本项目配置与脚本采用 [Apache License 2.0](LICENSE)，第三方组件归属见 [NOTICE](NOTICE)。

## 免责声明

所有配置按「在作者机器上实测可跑」整理。升级 ROCm / torch / llama.cpp 后请重新执行
`scripts/preflight.sh` 与 `scripts/verify.sh` 验证。**本项目不包含任何鉴权 token / API key**，
任何实际 key 都只存在于本机 `~/.unsloth/studio/auth/` 中，切勿外传。

欢迎提 Issue，请附上 `scripts/collect-info.sh` 的输出与硬件/版本信息。
