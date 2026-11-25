# 自带环境 / 手动安装：如何调整参数达到本仓库的效果

> 本仓库的 `scripts/install.sh`、`scripts/download-models.sh`、`scripts/install-service.sh`
> 面向「从零开始、照单全收」的用户。如果你**已经装好了 Unsloth Studio**，或希望**自己手动装**
> Unsloth / 下载模型，本文告诉你：**哪些东西是“效果”的关键、哪些可以照自己的习惯来、
> 以及怎么把参数调成和本仓库一致**。

先明确一点：本仓库所谓的「效果」= 在单卡 MI210 上，用 Qwen3.8-Flash-Next 跑出
**180k 上下文 / 4 并发 / 常驻服务 / 与 DSH 实测一致的 tok/s**。它由三类东西共同决定：

1. **模型文件选对**（UD-IQ4_XS + engram 外挂 + MTP draft）；
2. **llama-server 启动参数**（显存/内存分层、KV、投机解码那一整套）；
3. **运行环境**（gfx90a 版 torch、HF_HOME、WorkingDirectory、内存护栏）。

脚本只是把这三件事自动化。**你完全可以不用脚本，只要把这三件事做到位，效果一样。**

---

## 1. 三种使用姿势，选一种

| 你的情况 | 推荐做法 | 需要读的章节 |
|---|---|---|
| 已有可用的 Unsloth Studio，只是想让推理达到本仓库效果 | **场景 A**：在 Studio 里改加载参数 + 设置环境变量 | 第 2、3、4、6 节 |
| 想自己手动装 Unsloth / torch / 下载模型，不用本仓库脚本 | **场景 B**：手工做安装 + 用 `launch-llama-server.sh` 或自己的命令启动 | 第 3、4、5、6 节 |
| 完全按仓库脚本从零部署 | 走 [deployment.md](deployment.md) | 不用读本文 |

---

## 2. 场景 A：已有 Studio，只调参数

### 2.1 先确认你的 Studio 是「可用状态」

```
~/.unsloth/studio/unsloth_studio/bin/python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
```

- 若输出含 `+rocm` 且 `True`：直接进入 2.2。
- 若 torch 不是 gfx90a/ROCm 构建：按 [software-versions.md](software-versions.md) 第 2 节
  用 AMD wheel 源覆盖安装（这是唯一强烈建议照抄的步骤，否则 MI210 上跑不起来）。

### 2.2 在 Studio 里加载模型时，设置关键参数

Studio 的 Web UI 里加载模型时会有「高级参数 / Advanced parameters」入口（不同版本位置略有不同），
把下面这些**关键项**填进去。**完整命令行见 [inference-flags.md](inference-flags.md) 附录**；
如果你能直接编辑 Studio 传给 llama-server 的参数，优先用第 3 节的表格逐项对齐。

必须设置的关键项（缺一个效果就打折）：

| 参数 | 值 | 为什么关键 |
|---|---|---|
| `-m` / model | `UD-IQ4_XS/…-00001-of-00004.gguf` | 主模型，只传第 1 分片 |
| `--ple` / shard | `engram/…-engram-BF16.gguf_file` | PLE 外挂，不加载就没有完整能力 |
| `-md` / model-draft | `MTP/mtp-…-shared-Q8_0.gguf` | MTP 投机解码 draft |
| `-c` / ctx-size | `180000` | 180k 上下文 |
| `--parallel` | `4` | 4 并发槽位 |
| `-ncmoe` | `12` | 前 12 层 MoE 留 CPU（显存装不下的核心） |
| `--moe-cache-mib` | `4096` | CPU 专家的 4 GiB 显存热缓存 |
| `--load-mode` | `dio` | DirectIO 读 engram，绕过页缓存 |
| `--lazy-mode` | `auto` | engram 按行按需读 |
| `--cache-type-k/-v` | `q8_0` / `q8_0` | KV 量化，180k×4 的关键 |
| `--kv-unified` | 开 | 多槽位共享 KV |
| `--spec-type` | `ngram-mod,draft-mtp` | 双引擎投机解码 |
| `--spec-draft-n-max` | `2` | 每步最多草拟 2 token |
| `--fit` | `off` | 关闭自动调参（Studio 探测完会自己关） |
| `--flash-attn` | `on` | ROCm 上开 FA |

可选但影响体感（采样/模板）：

```
--jinja
--reasoning on
--chat-template-kwargs {"preserve_thinking": true}
--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0
--presence-penalty 0.0 --repeat-penalty 1.0
```

> **注意**：Studio 会在你点“加载模型”后自己拼出一条很长的命令行（本机实测 87 个参数），
> 其中可能有重复参数，**生效的是最后一次**。最容易踩的坑是 `--fit on` 被后面的 `--fit off`
> 覆盖、`--model-draft <HF blob>` 被 `-md <本地路径>` 覆盖。若 UI 无法精确控制，
> 直接用第 3 节的启动脚本更稳妥。

### 2.3 设置 Studio 的运行环境

无论 Studio 是自己装的还是用本仓库脚本装的，下面这些环境变量都要对，否则扫不到模型或起不来：

```bash
# Studio 的 HF 缓存位置（必须与下载模型时的位置一致）
export HF_HOME="$HOME/AI/huggingface"

# 避免 Studio 自己再拉一份 torch（本机用预编译 llama.cpp 时设）
export UNSLOTH_NO_TORCH=1

# ROCm 目标
export VLLM_TARGET_DEVICE=rocm

# 工作目录必须含 models/，否则前端 “refresh local models” 报 500
cd "$HOME/AI"          # 确保 $HOME/AI/models 存在
unsloth studio --port 8888 --host 127.0.0.1
```

如果你用 systemd 管理 Studio，把这些写进单元的 `[Service]`（参考
[`systemd/unsloth-studio.service`](../systemd/unsloth-studio.service)），并保留 `MemoryMax=50G`
（或按你整机内存换算，见 [limits.md](limits.md)）。

---

## 3. 场景 B：手动装 + 手动下载，用脚本启动

### 3.1 手动安装（跳过 `install.sh`）

依次做这些事（等价于 `scripts/install.sh`）：

```bash
# 1) 用你自己习惯的方式装 Unsloth Studio（官方安装器 / pip / 已有环境均可）
curl -fsSL https://unsloth.ai/install.sh | sh

# 2) 关键：把 torch 换成 ROCm/gfx90a 构建（唯一强烈建议照抄的步骤）
~/.unsloth/studio/unsloth_studio/bin/python -m pip install \
  --index-url https://stable.repo.amd.com/rocm/whl-next/ \
  "torch[device-gfx90a]==2.15.0+rocm10.2.0" \
  "torchvision[device-gfx90a]==0.29.2+rocm10.2.0" \
  "torchaudio==2.11.1+rocm10.2.0"

# 3) 验证
~/.unsloth/studio/unsloth_studio/bin/python -c "import torch; print(torch.cuda.is_available())"  # True
```

> 版本可随升级变化，但**必须保持 `device-gfx90a` + ROCm 源**这一对；
> 具体版本基线见 [software-versions.md](software-versions.md)。

### 3.2 手动下载模型（跳过 `download-models.sh`）

等价命令（用 `hf` 或 `huggingface-cli`，随你的版本）：

```bash
hf download unsloth/Qwen3.8-Flash-Next-GGUF \
  --local-dir "$HOME/AI/models/Qwen3.8-Flash-Next-GGUF" \
  --include \
    "UD-IQ4_XS/*" \
    "engram/Qwen3.8-Flash-Next-engram-BF16.gguf_file" \
    "MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf" \
    "mmproj-BF16.gguf"
```

**必须有的 4 类文件**（少一个就达不到效果）：

| 文件 | 作用 | 缺了会怎样 |
|---|---|---|
| `UD-IQ4_XS/*`（4 片） | 主模型 | 完全跑不了 |
| `engram/…-engram-BF16.gguf_file` | PLE 外挂 | 能力不完整（本仓库效果的前提） |
| `MTP/mtp-…-shared-Q8_0.gguf` | MTP draft | 投机解码失效，生成速度明显下降 |
| `mmproj-BF16.gguf` | 视觉投影 | 当前配置本就不用（可选，备着） |

> 你完全可以用自己的缓存路径；只要把启动脚本里的 `MODEL_DIR` 指过去即可。

### 3.3 用脚本启动（推荐）

`scripts/launch-llama-server.sh` **不依赖安装脚本**，只要路径对就能用：

```bash
MODEL_DIR="/你的/模型目录/Qwen3.8-Flash-Next-GGUF" \
LLAMA_SERVER="/你的/unsloth/llama.cpp/llama-server" \
  scripts/launch-llama-server.sh
```

脚本里的参数就是本仓库效果的“标准答案”，逐项含义见 [inference-flags.md](inference-flags.md)。
支持覆盖的变量：`MODEL_DIR`、`MAIN_GGUF`、`PLE_ENGRAM`、`MTP_DRAFT`、`LLAMA_SERVER`、
`PORT`、`CTX`、`PARALLEL`、`API_KEY` / `API_KEY_FILE`。

### 3.4 或手写等价命令

如果你连脚本也不用，下面这条命令和脚本完全等价（把路径换成你的）：

```bash
"$LLAMA_SERVER" \
  -m "$MODEL_DIR/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf" \
  --ple "$MODEL_DIR/engram/Qwen3.8-Flash-Next-engram-BF16.gguf_file" \
  -md  "$MODEL_DIR/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf" \
  --alias unsloth/Qwen3.8-Flash-Next-GGUF \
  --port 42707 --parallel 4 -c 180000 \
  --flash-attn on --no-context-shift \
  --batch-size 4096 --ubatch-size 2048 --ctx-checkpoints 8 \
  --kv-unified --cache-type-k q8_0 --cache-type-v q8_0 \
  --load-mode dio --lazy-mode auto \
  -ncmoe 12 --moe-cache-mib 4096 --fit off \
  --spec-type ngram-mod,draft-mtp --spec-draft-n-max 2 \
  --spec-ngram-mod-n-min 48 --spec-ngram-mod-n-max 64 --spec-ngram-mod-n-match 24 \
  --reasoning on --jinja --chat-template-kwargs '{"preserve_thinking": true}' \
  --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 \
  --presence-penalty 0.0 --repeat-penalty 1.0 --metrics
```

> 若你的 llama.cpp 版本和本仓库不同，先用 `--help` 核对参数名（见
> [troubleshooting.md](troubleshooting.md) 第 4 节）；旧版本可能没有 `--ple`、`--lazy-mode`、
> `--moe-cache-mib` 等较新的参数，那就需要升级 llama.cpp 才能对齐效果。

---

## 4. 「效果」参数速查对照表（脚本 ↔ 手动 ↔ 含义）

| 目标 | 本仓库脚本/参数 | 手动要做的 | 不改的后果 |
|---|---|---|---|
| 模型能装进 64 GiB 显存 | `-ncmoe 12 --moe-cache-mib 4096` | 启动参数里照抄 | 加载失败或被 `--fit` 砍上下文 |
| 102 GB engram 不吃内存 | `--load-mode dio --lazy-mode auto` | 启动参数里照抄 | 页缓存暴涨 / OOM |
| 180k×4 上下文可控 | `-c 180000 --parallel 4 --kv-unified --cache-type-k/-v q8_0` | 启动参数里照抄 | KV 显存爆 |
| 投机解码提速 | `-md …shared-Q8_0 --spec-type ngram-mod,draft-mtp --spec-draft-n-max 2` | 下载 MTP + 照抄参数 | 生成速度约减半 |
| 前端能刷出本地模型 | `WorkingDirectory=%h/AI`（含 `models/`） | 从含 `models/` 的目录启动 Studio | 前端 500 |
| HF 缓存路径一致 | `HF_HOME=%h/AI/huggingface` | 设置同名环境变量 | Studio 扫不到模型 |
| 整机不被 OOM 拖死 | `MemoryMax=50G` | systemd 单元里设置 | 全局 OOM / 僵死 |
| API 可用 | `--api-key-file` 或 `--api-key` | 用 `API_KEY` / `API_KEY_FILE` 环境变量 | 无鉴权（仅可信网络可用） |

---

## 5. 验证你手动调的参数是否到位

```bash
# 1) 环境体检（只读，不依赖安装脚本）
scripts/preflight.sh

# 2) 完整性校验（会按你的 MODEL_DIR / LLAMA_SERVER 检查）
MODEL_DIR="/你的/模型目录/Qwen3.8-Flash-Next-GGUF" \
LLAMA_SERVER="/你的/llama.cpp/llama-server" \
  scripts/verify.sh

# 3) 跑一次基准，和 docs/benchmarks.md 的数字对比
BENCH_URL=http://127.0.0.1:8888/v1 BENCH_MODEL=unsloth/Qwen3.8-Flash-Next-GGUF \
  scripts/benchmark.sh --runs 3
```

如果你的生成 tok/s 明显低于 [benchmarks.md](benchmarks.md) 的 p10（~19 tok/s），优先检查：

1. MTP draft 文件是否加载（日志里有没有 `load_tensors` 的第二段 ~2.6 GiB）；
2. `-ncmoe` 是否被别的参数覆盖、或 `--moe-cache-mib` 是否为 0；
3. engram 是否放在 NVMe 上（`--load-mode dio` 在机械盘上没有意义）；
4. torch 是否真的是 gfx90a 构建。

---

## 6. 常见「我照着做了但效果不一样」的原因

| 现象 | 最可能原因 | 解决 |
|---|---|---|
| 生成只有个位数 tok/s | 没加载 MTP draft，或 `--spec-type` 没设 | 补 `-md` 和 `--spec-type` |
| 加载时报显存不足 | `-ncmoe` 太小 / `--moe-cache-mib` 太大 / 上下文设太大 | 增大 `-ncmoe`、减小 `--moe-cache-mib -c` |
| prompt 处理极慢 | engram 在 HDD/网络盘，或没用 `dio` | 移到 NVMe，确认 `--load-mode dio` |
| Studio 前端刷不出模型 | 工作目录没有 `models/` / `HF_HOME` 不对 | 见第 2.3 节 |
| 升级后参数不认识 | llama.cpp 版本比本仓库旧 | 升级 llama.cpp，或对照 `--help` 裁剪 |
| 上下文被悄悄降低 | `--fit on` 生效了 | 确认最终生效的是 `--fit off` |

---

## 7. 小结

- **不用脚本也能达到同样效果**：关键是「选对文件 + 抄对参数 + 设对环境」三件事。
- **最不该省的两步**：torch 的 gfx90a pin（第 3.1 步）和 MTP/engram 的加载（第 2.2 / 3.2 节）。
- **最值得直接用的脚本**：`scripts/launch-llama-server.sh`（与安装方式无关，路径对就能跑）和
  `scripts/verify.sh`（按你的路径校验）。

有疑问请附 `scripts/collect-info.sh` 输出提 Issue，见 [CONTRIBUTING.md](../CONTRIBUTING.md)。
