#!/usr/bin/env bash
# 部署前环境体检 —— 只读，不修改任何东西
# 用法: scripts/preflight.sh
# 检查 OS / 内核 / GPU 设备节点 / ROCm 包 / 内存 / 磁盘 / hf 命令
set -uo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'
ok()   { printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*"; RC=1; }
RC=0

echo "=== MI210 推理栈部署前体检 ($(date '+%F %T')) ==="
echo

# --- OS / 内核 ---
echo "-- 系统 --"
if [ -r /etc/os-release ]; then
    OS=$(. /etc/os-release; echo "$PRETTY_NAME")
    echo "OS: $OS"
    case "$OS" in
        *Arch*) ok "Arch Linux (已验证平台)" ;;
        *) warn "非 Arch Linux：ROCm 包管理方式不同，需自行适配 install.sh" ;;
    esac
else
    warn "无法读取 /etc/os-release"
fi
KVER=$(uname -r 2>/dev/null || echo unknown)
echo "内核: $KVER"

# --- GPU 设备节点 ---
echo; echo "-- GPU / ROCm 设备 --"
if [ -e /dev/kfd ]; then
    ok "/dev/kfd 存在 ($(stat -c '%A %G' /dev/kfd 2>/dev/null))"
else
    fail "/dev/kfd 不存在：确认 AMD GPU 驱动已加载"
fi
if [ -e /dev/dri/renderD128 ]; then
    ok "/dev/dri/renderD128 存在 ($(stat -c '%A %G' /dev/dri/renderD128 2>/dev/null))"
else
    fail "/dev/dri/renderD128 不存在"
fi

# --- ROCm 包 ---
if command -v pacman >/dev/null 2>&1; then
    ROCM_PKG=$(pacman -Q rocm-gfx90a-bin 2>/dev/null || true)
    if [ -n "$ROCM_PKG" ]; then
        ok "ROCm 包: $ROCM_PKG"
    else
        warn "未安装 rocm-gfx90a-bin（当前基线 10.2.0-1）"
    fi
else
    warn "无 pacman，跳过 ROCm 包检查"
fi

# --- 内存 ---
echo; echo "-- 内存 --"
MEM_TOTAL=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
echo "物理内存: ${MEM_TOTAL} GiB"
if [ "$MEM_TOTAL" -ge 60 ]; then
    ok "内存 >= 60 GiB（可用 MemoryMax=50G 基线）"
elif [ "$MEM_TOTAL" -ge 40 ]; then
    warn "内存 40-60 GiB：需下调 MemoryMax 并增大 -ncmoe"
else
    fail "内存 < 40 GiB：本配置（62 GiB 基线）大概率不适用"
fi

# --- 磁盘 ---
echo; echo "-- 磁盘 --"
MODEL_PARENT="${MODEL_DIR:-$HOME/AI}"
if [ -d "$MODEL_PARENT" ]; then
    AVAIL=$(df -BG --output=avail "$MODEL_PARENT" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
    echo "$MODEL_PARENT 可用: ${AVAIL} GiB"
    if [ "${AVAIL:-0}" -ge 250 ]; then
        ok "可用空间 >= 250 GiB"
    else
        fail "可用空间 < 250 GiB：模型约需 200 GiB，请先清理"
    fi
else
    warn "$MODEL_PARENT 不存在，跳过磁盘检查（脚本会用到它）"
fi

# --- 工具 ---
echo; echo "-- 工具 --"
command -v curl >/dev/null 2>&1 && ok "curl" || fail "缺少 curl"
command -v hf >/dev/null 2>&1 && ok "hf ($(hf --version 2>/dev/null || echo '?'))" \
    || warn "缺少 hf 命令：pip install -U huggingface_hub"

# --- 结论 ---
echo
if [ "$RC" -eq 0 ]; then
    ok "体检通过，可以继续 scripts/install.sh"
else
    printf "${RED}[FAIL]${NC} 存在问题，请先解决上面标记为 FAIL 的项\n"
fi
exit "$RC"
