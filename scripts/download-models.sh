#!/usr/bin/env bash
# 下载 Qwen3.8-Flash-Next GGUF 所需文件（约 200 GB，注意磁盘空间）
# 依赖：pip install -U huggingface_hub   （提供 hf 命令）
# 若仓库需要登录：export HF_TOKEN=hf_xxx（不要把 token 写进任何配置文件）
#
# 下载内容：
#   UD-IQ4_XS/*                          主模型 4 分片 ≈ 93.7 GB
#   engram/…-engram-BF16.gguf_file       PLE 外挂分片 ≈ 102.4 GB
#   MTP/mtp-…-shared-Q8_0.gguf           MTP draft ≈ 2.8 GB
#   mmproj-BF16.gguf                     视觉投影（备用）≈ 0.9 GB
set -euo pipefail

REPO="unsloth/Qwen3.8-Flash-Next-GGUF"
DEST="${MODEL_DIR:-$HOME/AI/models/Qwen3.8-Flash-Next-GGUF}"

hf download "$REPO" \
    --local-dir "$DEST" \
    --include \
    "UD-IQ4_XS/*" \
    "engram/Qwen3.8-Flash-Next-engram-BF16.gguf_file" \
    "MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf" \
    "mmproj-BF16.gguf"

echo
echo "完成。模型文件："
find "$DEST" \( -name '*.gguf' -o -name '*.gguf_file' \) -print | sort
echo
echo "总占用：$(du -sh "$DEST" | cut -f1)"
