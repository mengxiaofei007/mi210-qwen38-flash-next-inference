#!/usr/bin/env bash
# 可复现的基准测试：通过 OpenAI 兼容 API 发固定请求，输出 prompt/gen tok/s
# 用法:
#   scripts/benchmark.sh
#   scripts/benchmark.sh --url http://127.0.0.1:8888/v1 --model unsloth/Qwen3.8-Flash-Next-GGUF
#   scripts/benchmark.sh --prompt-tokens 4096 --max-tokens 256 --runs 3
# 依赖: curl, python3
set -euo pipefail

URL="${BENCH_URL:-http://127.0.0.1:8888/v1}"
MODEL="${BENCH_MODEL:-unsloth/Qwen3.8-Flash-Next-GGUF}"
PROMPT_TOKENS=512
MAX_TOKENS=256
RUNS=3
API_KEY="${BENCH_API_KEY:-${API_KEY:-}}"

while [ $# -gt 0 ]; do
    case "$1" in
        --url)            URL="$2"; shift 2 ;;
        --model)          MODEL="$2"; shift 2 ;;
        --prompt-tokens)  PROMPT_TOKENS="$2"; shift 2 ;;
        --max-tokens)     MAX_TOKENS="$2"; shift 2 ;;
        --runs)           RUNS="$2"; shift 2 ;;
        --api-key)        API_KEY="$2"; shift 2 ;;
        -h|--help)        sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

command -v curl >/dev/null 2>&1 || { echo "缺少 curl" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "缺少 python3" >&2; exit 1; }

# 构造近似指定 token 数的 prompt（中文/英文混合，约 4 字符≈1 token 的粗略估计）
PROMPT=$(python3 - "$PROMPT_TOKENS" <<'PY'
import sys
n = int(sys.argv[1])
unit = ("The quick brown fox jumps over the lazy dog. " * 12)  # ~ 24 tokens/unit approx
s = unit * max(1, n // 24)
sys.stdout.write(s[: max(1, n * 4)])
PY
)

echo "=== MI210 推理栈基准测试 ==="
echo "端点: $URL/chat/completions"
echo "模型: $MODEL"
echo "prompt tokens ≈ $PROMPT_TOKENS | max_tokens=$MAX_TOKENS | runs=$RUNS"
echo

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

for i in $(seq 1 "$RUNS"); do
    echo "--- run $i/$RUNS ---"
    AUTH=()
    [ -n "$API_KEY" ] && AUTH=(-H "Authorization: Bearer $API_KEY")
    curl -sS --fail --max-time 600 "${AUTH[@]}" \
        -H 'Content-Type: application/json' \
        -d "$(python3 - "$PROMPT" "$MODEL" "$MAX_TOKENS" <<'PY'
import json, sys
prompt, model, max_tokens = sys.argv[1], sys.argv[2], int(sys.argv[3])
print(json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": max_tokens,
    "temperature": 1.0,
    "top_p": 0.95,
    "stream": False,
}, ensure_ascii=False))
PY
)" "$URL/chat/completions" > "$TMP" || { echo "请求失败，响应:" >&2; cat "$TMP" >&2; exit 1; }

    python3 - "$TMP" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
u = d.get("usage", {})
pe = u.get("prompt_eval_duration", 0) or u.get("prompt_eval_time", 0)
ed = u.get("eval_duration", 0) or u.get("eval_time", 0)
pc = u.get("prompt_eval_count", 0) or u.get("prompt_tokens", 0)
ec = u.get("completion_tokens", 0) or u.get("eval_count", 0)
# llama.cpp 暴露纳秒；兼容秒/毫秒
def to_s(x):
    if x > 1e12: return x/1e9
    if x > 1e9:  return x/1e3
    return x
prompt_s, eval_s = to_s(pe), to_s(ed)
print(f"  prompt: {pc} tok / {prompt_s:.3f}s" + (f" = {pc/prompt_s:.1f} tok/s" if prompt_s>0 else ""))
print(f"  gen:    {ec} tok / {eval_s:.3f}s" + (f" = {ec/eval_s:.1f} tok/s" if eval_s>0 else ""))
if "choices" in d and d["choices"]:
    text = d["choices"][0].get("message", {}).get("content", "")
    print(f"  输出片段: {text[:80].replace(chr(10),' ')}...")
PY
done

echo
echo "提示：以上为单次请求样本。完整统计见 docs/benchmarks.md。"
