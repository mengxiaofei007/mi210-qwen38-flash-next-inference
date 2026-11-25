#!/usr/bin/env bash
# Unsloth Studio + ROCm(gfx90a) torch 安装
# 适用：AMD MI210 / gfx90a，Linux。详见 README.md 第 1 节。
set -euo pipefail

echo "== 第 1/3 步：环境体检（只读） =="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/preflight.sh" || echo "[WARN] 体检有 FAIL 项，仍继续安装（请自行确认）"

echo
echo "== 第 2/3 步：安装 Unsloth Studio + gfx90a torch =="

export UNSLOTH_INSTALL_SYSTEMD=1      # 安装 systemd 单元
export UNSLOTH_SKIP_AUTOSTART=1       # 安装后不自动启动
export UNSLOTH_INSTALL_NO_ROLLBACK=1  # 禁用回滚

# 1) 官方安装器（Studio + ROCm 预编译 llama.cpp/whisper.cpp/audio.cpp）
curl -fsSL https://unsloth.ai/install.sh | sh

# 2) 覆盖安装 AMD 官方 wheel 源的 torch，pin 到 gfx90a
#    （安装器默认装的 torch 不是 ROCm/gfx90a 构建，必须换掉）
~/.unsloth/studio/unsloth_studio/bin/python -m pip install --index-url https://stable.repo.amd.com/rocm/whl-next/ \
    "torch[device-gfx90a]==2.15.0+rocm10.2.0" \
    "torchvision[device-gfx90a]==0.29.2+rocm10.2.0" \
    "torchaudio==2.11.1+rocm10.2.0"

# 3) 验证
echo
echo "== 第 3/3 步：验证 =="
~/.unsloth/studio/unsloth_studio/bin/python -c "import torch; print('torch:', torch.__version__); print('cuda.is_available:', torch.cuda.is_available())"
# 期望输出 True；若为 False，见 docs/troubleshooting.md（/dev/kfd 权限、ROCm 包、torch 构建）
echo
echo "安装完成。下一步: scripts/download-models.sh"
