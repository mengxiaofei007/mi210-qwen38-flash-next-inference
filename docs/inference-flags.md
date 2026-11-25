# llama-server 推理参数逐项解读（Qwen3.8-Flash-Next @ MI210）

本文解释 Studio 实际下发、并被 [`scripts/launch-llama-server.sh`](../scripts/launch-llama-server.sh)
复刻的参数组合。测试环境：MI210 64 GiB VRAM / 整机 62 GiB RAM / llama.cpp b12540（unsloth fork ROCm 预编译）。

一句话总纲：**主权重 93.7 GB + PLE 外挂 102.4 GB 都远大于显存，整套参数就是在
"CPU 内存驻留 + 磁盘按需读 + 显存缓存热点" 之间做分层。**

## 模型与文件布局

| 参数 | 值 | 说明 |
|---|---|---|
| `-m` | `UD-IQ4_XS/…-00001-of-00004.gguf` | 只传第 1 分片，llama.cpp 按命名规则自动加载全部 4 片（≈93.7 GB） |
| `--ple` | `engram/…-engram-BF16.gguf_file`（≈102.4 GB） | PLE（per-layer embedding）外挂分片，可放任意路径/任意盘 |
| `-md` | `MTP/mtp-…-shared-Q8_0.gguf`（≈2.8 GB） | MTP 投机解码的 draft 权重（shared 版） |
| `--alias` | `unsloth/Qwen3.8-Flash-Next-GGUF` | API 里 `/v1/models` 显示的模型名，Studio 靠它对接 |

## 显存/内存分层策略（本配置的核心）

| 参数 | 值 | 语义（摘自 llama.cpp --help） |
|---|---|---|
| `-ncmoe, --n-cpu-moe` | `12` | 前 12 层的 MoE 专家权重留在 CPU 内存，不进显存 |
| `--moe-cache-mib` | `4096` | 给 CPU 驻留的专家在 **显存** 里留 4 GiB 缓存（默认 0=关闭；`auto`=按 fit 后剩余显存自动定） |
| `--load-mode` | `dio` | Direct IO 读权重，绕过页缓存。`auto/none/mmap/mlock/mmap+mlock/dio` 可选 |
| `--lazy-mode` | `auto` | 特定张量（如每层 embedding）**按需从磁盘读行**而非常驻内存；需要 mmap 类加载配合 |
| `--fit` | `off` | 关闭 "自动调参塞满显存"（Studio 先 `--fit on` 探测再显式关掉，见附录） |

要点：`dio + lazy` 让 102 GB 的 engram 既不占显存也不吃页缓存，靠顺序读盘扛住；
`-ncmoe 12` + `--moe-cache-mib 4096` 是专家路由的 "CPU 主存 + GPU 热缓存" 组合。
（还有 `--moe-cache-cpu-share` 可让 CPU 参与 cache miss 的计算，本机未启用。）

## KV 缓存与上下文

| 参数 | 值 | 说明 |
|---|---|---|
| `-c, --ctx-size` | `180000` | 上下文长度 |
| `--parallel` | `4` | 并发槽位数（共享统一 KV） |
| `--kv-unified` | — | 所有序列共用一块统一 KV 缓冲（多槽位时默认开，显式声明） |
| `--cache-type-k/-v` | `q8_0` / `q8_0` | KV 量化到 8 bit，180k×4 并发下显著省显存，质量损失可接受 |
| `--ctx-checkpoints` | `8` | 上下文检查点个数（默认 32）；配合 slot 保存/恢复降低重算成本 |
| `--no-context-shift` | — | 关闭上下文滑动窗口（超长直接按槽位处理） |
| `--slot-save-path` | `~/.unsloth/studio/cache/llama-slots` | Studio 用它持久化槽位 KV，重启后热恢复 |

## 投机解码

| 参数 | 值 | 说明 |
|---|---|---|
| `--spec-type` | `ngram-mod,draft-mtp` | 双引擎：改进版 n-gram 草拟 + 模型自带 MTP 头（可选值含 draft-eagle3/draft-mtp/ngram-* 系列） |
| `-md` | shared-Q8_0 | MTP draft 文件（见上表） |
| `--spec-draft-n-max` | `2` | 每步最多草拟 2 个 token（默认 3，保守值防回滚浪费） |
| `--spec-ngram-mod-n-min` | `48` | n-gram 最小匹配长度（默认 48） |
| `--spec-ngram-mod-n-max` | `64` | n-gram 最大窗口（默认 64） |
| `--spec-ngram-mod-n-match` | `24` | 触发草拟所需命中数（默认 24） |

## 采样与模板

| 参数 | 值 | 说明 |
|---|---|---|
| `--jinja` | — | 使用模型内嵌 Jinja chat template |
| `--reasoning on` | — | 解析思考链（thinking）内容 |
| `--chat-template-kwargs` | `{"preserve_thinking": true}` | 多轮对话保留历史思考内容 |
| `--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0` | — | 模型官方推荐采样 |
| `--presence-penalty 0.0 --repeat-penalty 1.0` | — | 不加任何重复惩罚（官方推荐） |

## 服务与其他

| 参数 | 值 | 说明 |
|---|---|---|
| `--port` | `42707` | llama-server 端口（Studio 分配） |
| `--api-key-file` | `~/.unsloth/studio/auth/llama_api_key_*` | 每行一个 key；**内容勿外传** |
| `--metrics` | — | 暴露 /metrics 供监控 |
| `--flash-attn on` | — | ROCm 上开启 FA |
| `--batch-size 4096 / --ubatch-size 2048` | — | 提示/分块批大小 |
| `--verbosity 4` | — | 日志级别（Studio 调试用，可降 3） |
| `--mmproj-offload` + `--no-mmproj-auto` | — | 只影响视觉投影：当前 **没有** 传 `--mmproj` 文件 → 本实例无视觉能力；`--no-mmproj-auto` 禁止自动探测 mmproj 文件 |
| `--video-fps 1 --video-timestamp-interval 2000` | — | 视频输入相关，无视觉时不生效 |

## 附录：Studio 原始命令行（87 参，原样）

两点注意：
1. **重复参数取最后一次**：`--fit on`（前段）被后面的 `--fit off` 覆盖；
   `--model-draft <HF blob>` 被后面的 `-md …/shared-Q8_0.gguf` 覆盖。
2. HF 缓存里的 snapshot 路径与 `hf download --local-dir` 的目录树不同，但文件内容一致，
   启动脚本用后者。

```
~/.unsloth/llama.cpp/llama-server
-m ~/AI/huggingface/hub/models--unsloth--Qwen3.8-Flash-Next-GGUF/snapshots/b630fe39…/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf
--port 42707
--parallel 4
--ple ~/AI/huggingface/hub/models--unsloth--Qwen3.8-Flash-Next-GGUF/snapshots/f5d175de…/engram/Qwen3.8-Flash-Next-engram-BF16.gguf_file
--flash-attn on
--no-context-shift
-c 180000
--batch-size 4096
--ubatch-size 2048
--ctx-checkpoints 8
--video-fps 1
--video-timestamp-interval 2000
--alias unsloth/Qwen3.8-Flash-Next-GGUF
--fit on
--metrics
--slot-save-path ~/.unsloth/studio/cache/llama-slots
--kv-unified
--fit-ctx 180000
--fit-target 512
--jinja
--verbosity 4
--cache-type-k q8_0
--cache-type-v q8_0
--model-draft ~/AI/huggingface/hub/…/blobs/58a47d6a…          # 被后面的 -md 覆盖
--spec-type ngram-mod,draft-mtp
--spec-draft-n-max 2
--spec-ngram-mod-n-match 24
--spec-ngram-mod-n-min 48
--spec-ngram-mod-n-max 64
--reasoning on
--chat-template-kwargs {"preserve_thinking": true}
--api-key-file ~/.unsloth/studio/auth/llama_api_key_********   # key 内容已脱敏
--load-mode dio
--lazy-mode auto
-ncmoe 12
--moe-cache-mib 4096
--fit off                                                        # 生效值
-md ~/AI/models/Qwen3.8-Flash-Next-GGUF/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf   # 生效值
--mmproj-offload
--temp 1.0
--top-p 0.95
--top-k 20
--min-p 0.0
--presence-penalty 0.0
--repeat-penalty 1.0
--no-mmproj-auto
```
