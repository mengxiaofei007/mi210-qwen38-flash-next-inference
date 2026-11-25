# 硬件信息（实测）

> 本文所有数据来自 2026-11-25 在本机 `lucas-gpu-server` 上的实际采集。
> 采集命令见 [`scripts/collect-info.sh`](../scripts/collect-info.sh)。换机器时请重新采集，不要直接套用。

## 1. 总览

| 部件 | 型号 / 规格 | 备注 |
|---|---|---|
| 主机 | `lucas-gpu-server` | 单 GPU 工作站 |
| CPU | AMD EPYC 7452（32 核 / 64 线程） | Zen 2，4 个 NUMA 节点 |
| 内存 | 62 GiB RAM + 64 GiB Swap | MoE CPU 卸载 + engram 按需读盘的主战场 |
| GPU | AMD Instinct MI210（Aldebaran / gfx90a） | 1 张，65,520 MiB HBM2e VRAM |
| 存储 | NVMe `/dev/nvme1n1p2`，3.7 TB（已用 1.5 TB / 可用 2.3 TB） | 模型约 200 GB 放这里；DirectIO 顺序读盘 |
| 网卡 | `network-online.target` 后启动 | Studio 仅绑定 `127.0.0.1:8888` |

## 2. GPU 细节

从 llama.cpp 启动日志（`llama-1795171415-port-42707-try0.log`）中提取的权威信息：

```
ggml_cuda_init: found 1 ROCm devices (Total VRAM: 65520 MiB):
  Device 0: AMD Instinct MI210, gfx90a:sramecc+:xnack- (0x90a), VMM: no, Wave Size: 64, VRAM: 65520 MiB
```

| 项 | 值 |
|---|---|
| 架构 | gfx90a（Aldebaran / CDNA2） |
| 计算能力标识 | `gfx90a:sramecc+:xnack-` |
| VRAM | 65,520 MiB（≈ 64 GiB）HBM2e |
| Wave Size | 64 |
| VMM | no |
| 设备节点 | `/dev/kfd`（crw-rw-rw-, render 组）+ `/dev/dri/card0`、`card1`、`renderD128` |
| 驱动 | `rocm-gfx90a-bin` 10.2.0-1（pacman 包）；`linux-firmware-amdgpu` 20261019-1 |

> **权限**：普通用户需要能读写 `/dev/kfd` 与 `/dev/dri/renderD*`（通常在 `render`/`video` 组）。
> `torch.cuda.is_available()` 为 False 时先查这里。

## 3. CPU / NUMA

```
Architecture:        x86_64
CPU(s):              64
On-line CPU(s):      0-63
Model name:          AMD EPYC 7452 32-Core Processor
NUMA node0 CPU(s):   0-7,32-39
NUMA node1 CPU(s):   8-15,40-47
NUMA node2 CPU(s):   16-23,48-55
NUMA node3 CPU(s):   24-31,56-63
```

- 4 个 NUMA 节点，每节点 8 物理核 / 16 逻辑线程。
- MoE 专家权重留 CPU 内存（`-ncmoe 12`）时，CPU 内存带宽与 NUMA 局部性会影响 cache miss 延迟。
  本配置未做 `numactl` 绑核，属于「先跑通」状态；有进一步优化空间（见 [limits.md](limits.md)）。

## 4. 内存预算（关键）

整机 **62 GiB RAM** 是这套配置最紧的资源。systemd 单元设了 `MemoryMax=50G`，
给系统预留约 12 GiB。为什么需要这个护栏，见 [troubleshooting.md](troubleshooting.md) 的 OOM 复盘。

llama.cpp 模型加载日志中的实际 buffer 分布（主模型）：

```
load_tensors: offloaded 49/49 layers to GPU
load_tensors:        ROCm0 model buffer size = 48359.45 MiB   (~47.2 GiB，显存)
load_tensors:    ROCm_Host model buffer size = 13497.07 MiB   (~13.2 GiB，主机内存但 GPU 可访问)
load_tensors:   CPU_Mapped model buffer size = 97656.72 MiB   (~95.4 GiB，mmap 映射，按需读盘)
sched_reserve:      ROCm0 compute buffer size =  3673.27 MiB   (~3.6 GiB，计算缓冲)
sched_reserve:  ROCm_Host compute buffer size =   814.84 MiB
```

MTP draft 模型另占约 2.6 GiB 显存（`ROCm0 model buffer size = 2647.04 MiB`）。

要点：
- **显存**：~47.2 GiB 主模型 + ~3.6 GiB 计算 + ~2.6 GiB MTP ≈ 53.4 GiB，接近 64 GiB 上限但仍有余量给 KV。
- **主机内存**：`ROCm_Host` ~13.2 GiB + `CPU_Mapped` ~95.4 GiB（mmap，**不实际占满 RAM**，按需从磁盘读页）。
- 这就是为什么 `MemoryMax=50G` 够用：真正常驻 RAM 的是 ROCm_Host + 进程开销，mmap 部分由内核按需回收。

## 5. 磁盘 I/O

- engram 外挂文件 `Qwen3.8-Flash-Next-engram-BF16.gguf_file` ≈ 102 GB，用 `--load-mode dio`
  （Direct IO，绕过页缓存）+ `--lazy-mode auto`（按行按需读）加载。
- 因此**磁盘顺序读吞吐直接决定长 prompt 的 token 处理速度**（见 [benchmarks.md](benchmarks.md)）。
- 模型及缓存总占用约 200 GB，建议放在 NVMe 上并预留 ≥ 250 GB 可用空间。

## 6. 复现采集命令

```bash
# CPU / 内存 / 内核
lscpu
free -h
uname -a
cat /etc/os-release

# GPU 设备节点
ls -l /dev/kfd /dev/dri

# GPU 型号与 VRAM（从 llama-server 日志）
grep 'ggml_cuda_init' ~/.unsloth/studio/logs/llama-server/*.log | head

# 磁盘
df -h ~/AI ~/.unsloth
du -sh ~/AI/models/Qwen3.8-Flash-Next-GGUF
```
