# 性能测试数据（实测）

> 本文数据全部来自本机 llama-server 运行日志中 `slot print_timing` 的**真实记录**，
> 不是合成基准。采集时间跨度 2026-11-20 ~ 2026-11-24，共 20 个会话日志、
> 2,116 条生成（decode）与 2,116 条 prompt 计时样本。
> 日志位置：`~/.unsloth/studio/logs/llama-server/*.log`；统计方法见文末。

## 1. 结论速览

| 指标 | 中位数 | p10 | p90 | 观测最大 | 说明 |
|---|---|---|---|---|---|
| **生成速度（decode）** | **~25 tok/s** | ~19 tok/s | ~41 tok/s | ~54 tok/s | 常规交互生成（接受长度几十~数千 token） |
| **Prompt 处理** | **~210 tok/s** | ~58 tok/s | ~580 tok/s | ~1,038 tok/s | 随 prompt 长度与投机命中波动很大 |
| 长 prompt 分块进度 | 628–971 tok/s | — | — | — | 10k–13k token 大 prompt 的分块处理日志 |

> **重要**：这些数字来自真实用户请求（含思考链、工具调用、长短混杂），**不是**标准化 benchmark。
> 它们反映的是「这一套配置在实际负载下是什么体感」，而不是理论峰值。想要可复现的基线，用
> [`scripts/benchmark.sh`](../scripts/benchmark.sh)。

## 2. 生成速度（decode / eval）

llama.cpp 日志中 `eval time = … / N tokens ( … ms per token, … tokens per second)` 的统计：

```
n = 2116   min = 0.00   p10 = 18.84   p50 = 25.26   p90 = 40.63   p99 = 49.45   max = 54.51   avg = 27.58   (tok/s)
```

- 中位 **~25 tok/s**，平均 **~27.6 tok/s**。
- p10–p90 区间 **19–41 tok/s**：低值多为短输出（启动/拒绝/工具调用）或长上下文下的重载；高值多为投机解码命中时的连续生成。
- 剔除明显异常的极短输出后（n=2062），中位数 25.5、平均 28.2 tok/s，结论不变。

**按会话分组的中位生成速度**（体现不同负载/参数状态下的一致性）：

| 会话日志 | 样本数 | 中位 tok/s | 中位 prompt tok/s |
|---|---|---|---|
| `llama-1795171415-port-42707` | 248 | 39.1 | 308 |
| `llama-1795186444-port-47561` | 266 | 35.7 | 180 |
| `llama-1795237262-port-40047` | 235 | 36.0 | 305 |
| `llama-1795252488-retry-port-51117` | 74 | 25.3 | 316 |
| `llama-1795287432-retry-port-49097` | 56 | 26.4 | 225 |
| `llama-1795344251-retry-port-55089` | 26 | 26.6 | 230 |
| `llama-1795353115-retry-port-55153` | 621 | 23.4 | 172 |
| `llama-1795407547-retry-port-37669` | 484 | 23.6 | 206 |
| `llama-1795449534-port-59559` | 24 | 36.7 | 196 |

可以看到会话间中位值落在 **23–39 tok/s**，差异主要来自负载形态（长思考链 vs 短问答）与是否命中投机解码。

## 3. Prompt 处理（prompt eval）

```
n = 2116   min = 1.54   p10 = 58.08   p50 = 210.41   p90 = 579.92   max = 1037.94   (tok/s)
```

- 中位 **~210 tok/s**，p90 接近 **580 tok/s**。
- 大 prompt 的分块进度日志（同一请求内）：

```
prompt processing, n_tokens =   4096, t =  4.22 s / 970.75 tokens per second
prompt processing, n_tokens =   8192, t = 10.75 s / 761.76 tokens per second
prompt processing, n_tokens =  10826, t = 17.24 s / 627.91 tokens per second
prompt processing, n_tokens =  12874, t = 19.50 s / 660.11 tokens per second
prompt eval time = 21558.99 ms / 12878 tokens (597.34 tokens per second)
```

长 prompt 的处理速度受两个因素影响：
1. **engram 外挂的磁盘按需读**（`--load-mode dio` + `--lazy-mode auto`）——这是主要瓶颈；
2. 投机解码对 prompt 阶段帮助有限（MTP 主要作用于生成阶段）。

## 4. 上下文长度实测

- 配置 `-c 180000`，llama.cpp 实际 `n_ctx_slot = 180224`。
- 日志中观测到的单请求最大 prompt 长度 `n_tokens ≈ 83,275`，说明**至少 83k 上下文已在真实负载中跑过**。
- 更长上下文会显著增加 KV 与 engram 读盘压力；180k 是配置上限，但不是「任意 180k 都快」的保证。

## 5. 显存与内存占用（加载阶段实测）

```
load_tensors: offloaded 49/49 layers to GPU
load_tensors:        ROCm0 model buffer size = 48359.45 MiB   (~47.2 GiB)
load_tensors:    ROCm_Host model buffer size = 13497.07 MiB   (~13.2 GiB)
load_tensors:   CPU_Mapped model buffer size = 97656.72 MiB   (~95.4 GiB, mmap)
sched_reserve:      ROCm0 compute buffer size =  3673.27 MiB   (~3.6 GiB)
sched_reserve:  ROCm_Host compute buffer size =   814.84 MiB

# MTP draft 模型
load_tensors:        ROCm0 model buffer size =  2647.04 MiB   (~2.6 GiB)
sched_reserve:      ROCm0 compute buffer size =  1076.06 MiB
```

- 显存峰值构成 ≈ 47.2（主模型）+ 3.6（计算）+ 2.6（MTP）≈ **53.4 GiB / 64 GiB**，留有余量给 KV。
- CPU_Mapped 是 mmap 映射，不实际占满 RAM；常驻 RAM 主要是 ROCm_Host（~13.2 GiB）+ 进程开销。
- systemd `MemoryMax=50G` 把整机 OOM 限制在单元内部——事故复盘见 [troubleshooting.md](troubleshooting.md)。

## 6. 可复现基准测试

仓库提供 [`scripts/benchmark.sh`](../scripts/benchmark.sh)，通过 Studio 的 OpenAI 兼容 API
发固定请求，输出 tok/s 与延迟。用法：

```bash
# 默认打本机 Studio :8888
scripts/benchmark.sh

# 指定端点与模型
scripts/benchmark.sh --url http://127.0.0.1:8888/v1 --model unsloth/Qwen3.8-Flash-Next-GGUF

# 指定 prompt token 数与生成上限
scripts/benchmark.sh --prompt-tokens 4096 --max-tokens 256 --runs 3
```

脚本输出示例（字段）：`prompt_eval_count` / `prompt_eval_duration` / `eval_count` /
`eval_duration` → 换算 `prompt tok/s` 与 `gen tok/s`。建议至少跑 3 次取中位数。

## 7. 统计方法

```bash
# 生成速度（eval time）
grep -h -oE 'eval time = +[0-9.]+ ms / +[0-9]+ tokens \( +[0-9.]+ ms per token, +[0-9.]+ tokens per second\)' \
  ~/.unsloth/studio/logs/llama-server/*.log \
  | grep -oE '[0-9.]+ tokens per second' | grep -oE '[0-9.]+' | sort -n \
  | awk '{a[NR]=$1;s+=$1} END{print "n="NR, "p10="a[int(NR*.1)], "p50="a[int(NR*.5)], "p90="a[int(NR*.9)], "avg="s/NR}'

# Prompt 速度：把上面 grep 的模式换成 'prompt eval time = …'
```

> **免责声明**：以上为单卡 MI210 上的观测值。换 GPU、换量化、改 `-ncmoe`/`--moe-cache-mib`/
> KV 量化后性能会变化；请以 `scripts/benchmark.sh` 在自己机器上的结果为准。
