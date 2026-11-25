#!/usr/bin/env bash
# 安装用户级 systemd 单元（开机自启 + 内存护栏），但不立即启动
# 用法: scripts/install-service.sh
# 组件: systemd/unsloth-studio.service → ~/.config/systemd/user/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/../systemd/unsloth-studio.service"
DEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
DEST="$DEST_DIR/unsloth-studio.service"

[ -f "$SRC" ] || { echo "找不到单元文件: $SRC" >&2; exit 1; }

echo "== 安装 systemd 用户单元 =="
mkdir -p "$DEST_DIR"

if [ -e "$DEST" ]; then
    echo "已存在 $DEST，备份为 $DEST.bak"
    cp -a "$DEST" "$DEST.bak.$(date +%s)"
fi
cp "$SRC" "$DEST"
echo "已复制: $SRC -> $DEST"

echo
echo "== 校验 WorkingDirectory (%h/AI) =="
# 单元用 %h/AI；这里检查实际 home 下是否有 models/
if [ -d "$HOME/AI/models" ]; then
    echo "[ OK ] $HOME/AI/models 存在"
else
    echo "[WARN] $HOME/AI/models 不存在：Studio 刷新本地模型会 500，请创建或改单元 WorkingDirectory" >&2
fi

echo
echo "== daemon-reload + enable =="
systemctl --user daemon-reload
systemctl --user enable unsloth-studio

echo
echo "== 开启 linger（没登录也常驻） =="
if command -v loginctl >/dev/null 2>&1; then
    loginctl enable-linger "$USER"
    echo "Linger 状态: $(loginctl show-user "$USER" 2>/dev/null | grep -i '^Linger=' || echo '?')"
else
    echo "[WARN] 无 loginctl，跳过 linger" >&2
fi

echo
echo "完成。启动服务: systemctl --user start unsloth-studio"
echo "查看日志:     journalctl --user -u unsloth-studio -f"
echo "访问:         http://127.0.0.1:8888"
