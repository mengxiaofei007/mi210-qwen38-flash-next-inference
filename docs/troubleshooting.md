# 故障排查

## 1. `torch.cuda.is_available()` 为 False

```
~/.unsloth/studio/unsloth_studio/bin/python -c "import torch; print(torch.cuda.is_available())"
```

按顺序检查：

1. **torch 是不是 gfx90a 构建**：`python -c "import torch; print(torch.__version__)"`
   应为 `2.15.0+rocm10.2.0`。若不是，重跑 `scripts/install.sh` 的第二步（AMD wheel 源 pin gfx90a）。
2. **设备节点权限**：`ls -l /dev/kfd /dev/dri`，当前用户需在 `render`/`video` 组，且 `/dev/kfd` 可写。
3. **ROCm 包**：`pacman -Q rocm-gfx90a-bin` 应为 `10.2.0-1`。
4. **内核版本**：本机验证于 `7.3.5-arch1-1`；跨大版本内核需重测。

## 2. 前端 "refresh local models" 报 500（FileNotFoundError）

**原因**：Studio 用相对路径 `./models` 扫描本地模型，工作目录下没有 `models/` 时会抛
`[Errno 2] No such file or directory`。

**修复**：systemd 单元的 `WorkingDirectory` 必须落在含 `models/` 的目录（本配置是 `%h/AI`）：

```ini
WorkingDirectory=%h/AI     # 确保 %h/AI/models 存在
```

改完 `systemctl --user daemon-reload && systemctl --user restart unsloth-studio`。

## 3. 整机 OOM / 僵死（事故复盘）

**现象（2026-11-17）**：llama-server 内存涨到 ~48 GB（anon 35 GB + shmem 13.7 GB），
触发全局 OOM：整机僵死约 20 秒，监控进程被饿住产生误报，llama-server 被内核杀了 3 次。

**根因**：用户级 systemd 单元没设内存上限，llama-server 的匿名映射 + 共享内存无节制增长。

**修复**：单元里加 `MemoryMax=50G`（整机 62 GiB，留 ~12 GiB 给系统）。
超限的 OOM 只发生在单元内部，`Restart=on-failure` 会把服务拉回来，不再拖垮整机。

> **换机器必须换算**：`MemoryMax = 总内存 − 系统预留(≥12 GiB)`。
> 内存更小还要配合增大 `-ncmoe`、减小 `-c`、`--moe-cache-mib`。

## 4. 模型加载报参数告警 / 启动失败

llama.cpp 升级后参数可能变化。日志里若出现 `DEPRECATED` 或未识别参数：

1. 对照当前 `--help` 检查每个参数（本机 help 节选见 `.scratch/help-part1.txt`）。
2. 重新抓取 Studio 实际下发的命令行（生效值取重复参数的最后一次）：
   Studio 拉起子进程后，从 `ps` 或 Studio 日志里记录完整命令行，与
   [`scripts/launch-llama-server.sh`](../scripts/launch-llama-server.sh) 对比。
3. 已知重复参数陷阱：`--fit on` 被后面的 `--fit off` 覆盖；
   `--model-draft <HF blob>` 被 `-md …/shared-Q8_0.gguf` 覆盖。

## 5. 从 HF 缓存启动时路径不对

HF 缓存的 snapshot 路径与 `hf download --local-dir` 的目录树不同：

```
# HF 缓存（Studio 默认用这个）
~/AI/huggingface/hub/models--unsloth--Qwen3.8-Flash-Next-GGUF/snapshots/<hash>/UD-IQ4_XS/…

# --local-dir（启动脚本用这个）
~/AI/models/Qwen3.8-Flash-Next-GGUF/UD-IQ4_XS/…
```

文件内容一致。独立启动脚本用后者；Studio 则由 `HF_HOME=%h/AI/huggingface` 指向缓存。

## 6. 没有视觉能力

当前实例**没有**加载 mmproj，且显式传了 `--no-mmproj-auto`。`mmproj-BF16.gguf` 只是备用文件。
要开启视觉：

1. 启动参数加 `--mmproj <path>/mmproj-BF16.gguf`；
2. 预留相应显存（~0.9 GB），必要时增大 `-ncmoe` 或减小 `-c`；
3. 重跑 `scripts/benchmark.sh` 确认性能可接受。

## 7. HF_TOKEN / 鉴权

- `HF_TOKEN` 放登录环境（如 `~/.zshenv`），**不要写进 systemd 单元**——单元文件常被截图外发。
- Studio 给 llama-server 传 `--api-key-file ~/.unsloth/studio/auth/llama_api_key_*`，key 内容勿外传。
- 本仓库所有文件**不含任何 token / key**。

## 8. 更新器没有更新 llama.cpp

AUR 包 `unsloth-studio-rocm-gfx90a-updater` 故意**不自动更新** llama.cpp / whisper.cpp / audio.cpp：
Unsloth 预编译 tarball 的布局（build/bin overlay、顶层符号链接、install-record json、whisper 的
libggml 硬链接）与覆盖式重装不完全兼容，留给人工确认。需要更新时：
`FORCE=1 unsloth-updater.sh` 强制应用；`UNSLOTH_UPDATER_DRY_RUN=1` 只看差异。

## 9. 提 Issue 前

请附上：

```bash
scripts/collect-info.sh > environment.txt
```

以及：相关日志（`journalctl --user -u unsloth-studio -n 200` 或
`~/.unsloth/studio/logs/llama-server/*.log`）、硬件/版本信息、复现步骤。
