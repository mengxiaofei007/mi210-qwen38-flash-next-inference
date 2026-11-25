# 贡献指南

感谢改进这套配置！为了让 Issue / PR 高效，请遵守以下约定。

## 提 Issue

1. **先附环境报告**：运行 `scripts/collect-info.sh > environment.txt`，把输出贴上来（脚本已脱敏，不含 key）。
2. **说明硬件与版本**：GPU 型号、ROCm/torch/llama.cpp 版本、内存大小。
3. **复现步骤**：哪条脚本、什么参数、完整报错（日志用 `journalctl --user -u unsloth-studio -n 200`
   或 `~/.unsloth/studio/logs/llama-server/*.log`）。
4. **不要贴任何 token / API key**（`~/.unsloth/studio/auth/` 下的内容、HF_TOKEN 等）。

## 提 PR

- 脚本改动请说明影响的安装/运行阶段，并在本机验证 `bash -n scripts/*.sh`。
- 文档中的数字须来自真实采集，注明采集时间与来源命令；不要编造性能数据。
- 新脚本放到 `scripts/`，并在 README 的仓库结构与文档索引中登记。
- 保持「开箱即用」：脚本要能单独执行、有清晰的用法注释、失败有明确报错。

## 运行环境

本项目的基线是：单卡 AMD MI210（gfx90a）+ Arch Linux + ROCm 10.2 + 62 GiB 内存。
其他硬件的 PR 欢迎，但请注明验证平台，不要假定与基线一致。

## 许可

贡献默认按 [Apache License 2.0](LICENSE) 授权。
