#!/usr/bin/env bash
# 生成脱敏的本机环境报告（提 Issue 时附上其输出）
# 用法: scripts/collect-info.sh > environment.txt
# 注意：不采集任何 API key / token / 鉴权文件内容
set -uo pipefail

echo "==================== MI210 推理栈环境报告 ===================="
echo "生成时间: $(date -Is)"
echo "主机:     $(hostname)"
echo "=============================================================="
echo

echo "--- 操作系统 ---"
cat /etc/os-release 2>/dev/null | grep -E '^(NAME|PRETTY_NAME|BUILD_ID)=' || echo "(不可读)"
echo "内核: $(uname -a)"
echo

echo "--- CPU / 内存 ---"
lscpu 2>/dev/null | grep -E '^(Architecture|CPU\(s\)|Model name|Thread|Core|Socket|NUMA node)' | head -20 || echo "(lscpu 不可用)"
echo
free -h 2>/dev/null || echo "(free 不可用)"
echo

echo "--- GPU / ROCm 设备节点 ---"
ls -l /dev/kfd /dev/dri 2>/dev/null || echo "(无 GPU 设备节点)"
echo
if grep -rh 'ggml_cuda_init' ~/.unsloth/studio/logs/llama-server/*.log 2>/dev/null | head -2; then :; else
    echo "(未找到 llama-server 日志中的 GPU 信息)"
fi
echo

echo "--- 磁盘 ---"
df -h "$HOME" 2>/dev/null || echo "(df 不可用)"
echo

echo "--- 软件版本 ---"
PY="${UNSLOTH_HOME:-$HOME/.unsloth}/studio/unsloth_studio/bin/python"
if [ -x "$PY" ]; then
    echo "Python: $($PY --version 2>&1)"
    $PY -c "import torch; print('torch:', torch.__version__, '| hip:', torch.version.hip, '| cuda.is_available:', torch.cuda.is_available())" 2>/dev/null || echo "torch: <不可用>"
    $PY -c "import importlib.metadata as m; [print(p+':', m.version(p)) for p in ['triton','unsloth','transformers']]" 2>/dev/null || true
else
    echo "Studio venv: <未安装>"
fi
LLAMA="${UNSLOTH_HOME:-$HOME/.unsloth}/llama.cpp/build/bin/llama-server"
[ -x "$LLAMA" ] && "$LLAMA" --version 2>/dev/null | head -3 || echo "llama-server: <不可用>"
echo "hf: $(hf --version 2>/dev/null || echo '<不可用>')"
if command -v pacman >/dev/null 2>&1; then
    pacman -Q 2>/dev/null | grep -E 'rocm-gfx90a-bin|unsloth-studio-rocm-gfx90a-updater|linux-firmware-amdgpu|mesa ' || true
fi
echo

echo "--- 模型文件 ---"
MD="${MODEL_DIR:-$HOME/AI/models/Qwen3.8-Flash-Next-GGUF}"
if [ -d "$MD" ]; then
    du -sh "$MD" 2>/dev/null
    find "$MD" -maxdepth 2 -type f \( -name '*.gguf' -o -name '*.gguf_file' \) -printf '%s %p\n' 2>/dev/null | sort -n
else
    echo "模型目录不存在: $MD"
fi
echo

echo "--- 服务单元状态 ---"
UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/unsloth-studio.service"
if [ -f "$UNIT" ]; then
    echo "单元已安装"
    systemctl --user is-active unsloth-studio 2>/dev/null || true
    systemctl --user show -p MemoryMax --value unsloth-studio 2>/dev/null | sed 's/^/MemoryMax=/' || true
    grep -E 'WorkingDirectory|MemoryMax|ExecStart' "$UNIT" | sed 's/^/  /'
else
    echo "单元未安装"
fi
echo

echo "--- 近期性能样本（若有 llama-server 日志） ---"
LOGDIR="${UNSLOTH_HOME:-$HOME/.unsloth}/studio/logs/llama-server"
if compgen -G "$LOGDIR/*.log" >/dev/null 2>&1; then
    grep -h -oE 'eval time = +[0-9.]+ ms / +[0-9]+ tokens \( +[0-9.]+ ms per token, +[0-9.]+ tokens per second\)' "$LOGDIR"/*.log 2>/dev/null \
        | grep -oE '[0-9.]+ tokens per second' | grep -oE '[0-9.]+' | sort -n \
        | awk 'NR==1{m=$1}{a[NR]=$1;s+=$1}END{if(NR>0)printf "decode tok/s: n=%d p50=%s avg=%.1f max=%s\n",NR,a[int(NR/2)],s/NR,a[NR]}'
else
    echo "(无日志)"
fi
echo
echo "============================= 报告结束 ========================="
