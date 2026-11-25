#!/usr/bin/env bash
# 安装后完整性校验：Studio venv / torch gfx90a / llama-server / 模型文件 / 服务单元 / 端口
# 用法: scripts/verify.sh
set -uo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'
ok()   { printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*"; RC=1; }
RC=0

echo "=== 安装后校验 ($(date '+%F %T')) ==="
echo

UNSLOTH_HOME="${UNSLOTH_HOME:-$HOME/.unsloth}"
PY="$UNSLOTH_HOME/studio/unsloth_studio/bin/python"
LLAMA_SERVER="$UNSLOTH_HOME/llama.cpp/llama-server"
MODEL_DIR="${MODEL_DIR:-$HOME/AI/models/Qwen3.8-Flash-Next-GGUF}"

echo "-- Studio venv --"
if [ -x "$PY" ]; then
    ok "Python: $PY ($($PY --version 2>&1))"
else
    fail "缺少 Studio venv: $PY"
fi

echo; echo "-- torch (gfx90a) --"
if [ -x "$PY" ]; then
    TORCH_V=$($PY -c 'import torch; print(torch.__version__)' 2>/dev/null || true)
    CUDA_OK=$($PY -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || true)
    echo "torch: ${TORCH_V:-<未安装>}  cuda.is_available: ${CUDA_OK:-<未知>}"
    case "$TORCH_V" in
        *rocm*) ok "torch 为 ROCm 构建" ;;
        *) warn "torch 不是 ROCm 构建，请重跑 install.sh 第二步" ;;
    esac
    [ "$CUDA_OK" = "True" ] && ok "CUDA/ROCm 可用" || fail "torch.cuda.is_available() != True"
fi

echo; echo "-- llama-server --"
if [ -e "$LLAMA_SERVER" ]; then
    ok "llama-server: $LLAMA_SERVER"
    "$LLAMA_SERVER" --version 2>/dev/null | head -2 || true
else
    fail "缺少 llama-server: $LLAMA_SERVER"
fi

echo; echo "-- 模型文件 --"
MAIN_GGUF="${MAIN_GGUF:-$MODEL_DIR/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf}"
PLE_ENGRAM="${PLE_ENGRAM:-$MODEL_DIR/engram/Qwen3.8-Flash-Next-engram-BF16.gguf_file}"
MTP_DRAFT="${MTP_DRAFT:-$MODEL_DIR/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf}"
for f in "$MAIN_GGUF" "$PLE_ENGRAM" "$MTP_DRAFT"; do
    if [ -e "$f" ]; then
        ok "$(du -h "$f" 2>/dev/null | cut -f1) $(basename "$f")"
    else
        fail "缺少模型文件: $f"
    fi
done

echo; echo "-- 主模型全部分片（4 片） --"
SHARDS=$(find "$MODEL_DIR/UD-IQ4_XS" -name '*.gguf' -type f 2>/dev/null | wc -l)
echo "UD-IQ4_XS 分片数: $SHARDS"
[ "$SHARDS" -ge 4 ] && ok "4 个主分片齐全" || fail "主分片不足 4 个（当前 $SHARDS）"

echo; echo "-- systemd 单元 --"
UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/unsloth-studio.service"
if [ -f "$UNIT" ]; then
    ok "单元已安装: $UNIT"
    systemctl --user is-enabled unsloth-studio 2>/dev/null | sed 's/^/  enabled: /' || true
else
    warn "单元未安装：运行 scripts/install-service.sh"
fi

echo; echo "-- 端口 --"
for p in 8888 42707; do
    if command -v ss >/dev/null 2>&1; then
        if ss -ltn 2>/dev/null | grep -q ":$p "; then
            ok "端口 $p 正在监听"
        else
            echo "  端口 $p 未监听（未启动或未加载模型时属正常）"
        fi
    fi
done

echo
if [ "$RC" -eq 0 ]; then
    ok "校验通过，可以启动服务"
else
    printf "${RED}[FAIL]${NC} 存在未通过项，请先解决\n"
fi
exit "$RC"
