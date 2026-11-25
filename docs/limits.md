# 上限与下限（能力边界）

> 这套配置是**针对单卡 MI210 + 62 GiB 内存 + ROCm 10.2 的一套特定解**，不是通用推理方案。
> 本文明确写出「能做什么」「不能做什么」「什么条件下会崩」，避免使用者误判。

## 1. 已验证上限（做了就能稳定跑）

| 维度 | 上限 | 证据 / 条件 |
|---|---|---|
| 上下文长度 | **180,000 token**（实际 `n_ctx_slot = 180224`） | `-c 180000`，日志实测；真实负载跑到 ~83k |
| 并发 | **4 槽位**（`--parallel 4` + `--kv-unified`） | 统一 KV 共享，4 路并发已验证 |
| 模型规模 | 主权重 ~93.7 GB + PLE 外挂 ~102 GB ≈ **200 GB** | 显存 64 GiB 装不下，靠 CPU 卸载 + 磁盘按需读 |
| 服务可用性 | 常驻 + 崩溃自愈 | `Restart=on-failure`，`RestartSec=10`，`MemoryMax=50G` |
| 生成速度 | 中位 ~25 tok/s（见 [benchmarks.md](benchmarks.md)） | 交互体感，非峰值 |
| 磁盘 | 模型约 200 GB（预留 ≥250 GB） | NVMe 顺序读，engram 用 DirectIO + lazy |

## 2. 硬下限（低于这些不行）

| 维度 | 下限 / 要求 | 不满足的后果 |
|---|---|---|
| GPU 架构 | **gfx90a（MI210/MI250）**，ROCm 预编译 | 其他 GPU 无对应预编译 llama.cpp；需自行编译并调参 |
| ROCm 版本 | 10.2.0（`rocm-gfx90a-bin`） | 跨大版本需重测 torch 与 llama.cpp 兼容性 |
| 整机内存 | **≥ 62 GiB**（本配置按此设定 `MemoryMax=50G`） | 内存更小必须下调 `MemoryMax`、增加 `-ncmoe`、减小 `-c` |
| 显存 | **64 GiB**（MI210 满血） | 显存不足需增加 `-ncmoe`（更多 MoE 留 CPU）、减小 `--moe-cache-mib` |
| 磁盘 | NVMe，≥250 GB 可用 | HDD 上 engram 按需读会极慢，`--load-mode dio` 收益骤降 |
| 权限 | `/dev/kfd`、`/dev/dri/renderD*` 可读写 | `torch.cuda.is_available()` = False |

## 3. 明确不支持 / 当前关闭的能力

| 能力 | 状态 | 说明 |
|---|---|---|
| **视觉 / 多模态** | ❌ 当前关闭 | 未传 `--mmproj`，且显式 `--no-mmproj-auto`；`mmproj-BF16.gguf` 只是备用文件 |
| **多 GPU 并行** | ❌ 未配置 | 面向单卡；`--main-gpu`/`--tensor-split` 未调优，多卡需重测 |
| **上下文滑动窗口** | ❌ 关闭 | `--no-context-shift`，超长直接按槽位处理，不做窗口滚动 |
| **KV 高精度** | ❌ 已量化 | `--cache-type-k/-v q8_0`，换 fp16 会显著增加 KV 占用 |
| **自动调参填满显存** | ❌ 关闭 | `--fit off`（Studio 先 `--fit on` 探测再显式关掉） |
| **MoE CPU 参与计算** | ❌ 未启用 | `--moe-cache-cpu-share` 默认 0，可尝试但需重测延迟 |

## 4. 边界条件：什么时候会出问题

| 场景 | 现象 | 应对 |
|---|---|---|
| 整机内存 < 62 GiB 却沿用 `MemoryMax=50G` | 整机 OOM / 僵死 | 按「总内存 − 系统预留(≥12 GiB)」重算 `MemoryMax` |
| 显存被其他进程占用 | llama-server 加载失败 / 上下文被 `--fit` 砍小 | 关闭占用进程，或减小 `-c`、增大 `-ncmoe` |
| engram 放 HDD 或网络盘 | prompt 处理极慢（秒级/token） | 移到 NVMe，保持 `--load-mode dio` |
| 从 HF 缓存直接启动（snapshot 路径） | 路径与 `hf download --local-dir` 不同 | 启动脚本用 `--local-dir` 布局（见 [inference-flags.md](inference-flags.md) 附录） |
| 升级 llama.cpp 后参数变化 | 启动失败 / 参数告警 | 对照 `--help` 重测，记录新的生效命令行 |
| 打开视觉（加载 mmproj） | 显存不足 | 预留 mmproj 显存，必要时增大 `-ncmoe`、减小 `-c` |

## 5. 调参杠杆（在边界内取舍）

| 想优化什么 | 调哪个参数 | 代价 |
|---|---|---|
| 显存不够 | 增大 `-ncmoe`（更多 MoE 留 CPU） | 生成变慢（CPU↔GPU 传输增加） |
| 想提速 | 减小 `-ncmoe` / 增大 `--moe-cache-mib` | 显存占用上升 |
| 内存不够 | 减小 `--moe-cache-mib`、增大 `-ncmoe` | 生成变慢 |
| 长上下文不够 | 增大 `-c` | KV 显存上升，可能触发 `--fit` 自动降 ctx |
| 想开视觉 | 加 `--mmproj mmproj-BF16.gguf` | 显存 +~0.9 GB，需重测 |
| prompt 太慢 | 换更快 NVMe / 减少 engram 读盘 | 硬件约束 |

> 调整任一项后，务必跑 `scripts/verify.sh` 和 `scripts/benchmark.sh` 重新确认边界。
