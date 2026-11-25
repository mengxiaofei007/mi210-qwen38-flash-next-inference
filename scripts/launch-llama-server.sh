#!/usr/bin/env bash
# 独立启动 llama-server 跑 Qwen3.8-Flash-Next（UD-IQ4_XS + engram PLE + MTP 投机解码）
#
# 参数与 Unsloth Studio 实际下发的命令行一致（已去重，同名参数取生效值）。
# 逐项解读见 docs/inference-flags.md；Studio 原始 87 参命令行在该文档附录。
#
# 用法：
#   scripts/launch-llama-server.sh                  # 用默认路径
#   API_KEY=xxx scripts/launch-llama-server.sh      # 带鉴权启动
#   CTX=65536 PORT=8080 scripts/launch-llama-server.sh
#   额外参数直接追加在命令行尾部，会原样透传给 llama-server。
set -euo pipefail

UNSLOTH_HOME="${UNSLOTH_HOME:-$HOME/.unsloth}"
LLAMA_SERVER="${LLAMA_SERVER:-$UNSLOTH_HOME/llama.cpp/llama-server}"

MODEL_DIR="${MODEL_DIR:-$HOME/AI/models/Qwen3.8-Flash-Next-GGUF}"
MAIN_GGUF="${MAIN_GGUF:-$MODEL_DIR/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf}"
PLE_ENGRAM="${PLE_ENGRAM:-$MODEL_DIR/engram/Qwen3.8-Flash-Next-engram-BF16.gguf_file}"
MTP_DRAFT="${MTP_DRAFT:-$MODEL_DIR/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf}"

PORT="${PORT:-42707}"
CTX="${CTX:-180000}"
PARALLEL="${PARALLEL:-4}"

# 鉴权：API_KEY / API_KEY_FILE 二选一；都不设则无鉴权，仅限可信网络！
API_KEY="${API_KEY:-}"
API_KEY_FILE="${API_KEY_FILE:-}"

for f in "$LLAMA_SERVER" "$MAIN_GGUF" "$PLE_ENGRAM" "$MTP_DRAFT"; do
    [ -e "$f" ] || { echo "缺少文件: $f （安装/下载步骤见 README）" >&2; exit 1; }
done

AUTH_ARGS=()
[ -n "$API_KEY" ]      && AUTH_ARGS+=(--api-key "$API_KEY")
[ -n "$API_KEY_FILE" ] && AUTH_ARGS+=(--api-key-file "$API_KEY_FILE")

exec "$LLAMA_SERVER" \
    -m "$MAIN_GGUF" \
    --ple "$PLE_ENGRAM" \
    --alias "unsloth/Qwen3.8-Flash-Next-GGUF" \
    --port "$PORT" \
    --parallel "$PARALLEL" \
    -c "$CTX" \
    --flash-attn on \
    --no-context-shift \
    --batch-size 4096 \
    --ubatch-size 2048 \
    --ctx-checkpoints 8 \
    --kv-unified \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    --load-mode dio \
    --lazy-mode auto \
    -ncmoe 12 \
    --moe-cache-mib 4096 \
    --fit off \
    -md "$MTP_DRAFT" \
    --spec-type ngram-mod,draft-mtp \
    --spec-draft-n-max 2 \
    --spec-ngram-mod-n-min 48 \
    --spec-ngram-mod-n-max 64 \
    --spec-ngram-mod-n-match 24 \
    --reasoning on \
    --jinja \
    --chat-template-kwargs '{"preserve_thinking": true}' \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    --presence-penalty 0.0 \
    --repeat-penalty 1.0 \
    --metrics \
    "${AUTH_ARGS[@]}" \
    "$@"
