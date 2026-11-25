# 常用命令封装 —— make <target>
.PHONY: help preflight install download service verify bench info launch check

help:
	@echo "目标:"
	@echo "  make preflight  部署前环境体检（只读）"
	@echo "  make install    安装 Studio + gfx90a torch"
	@echo "  make download   下载模型（约 200 GB）"
	@echo "  make service    安装 systemd 单元 + linger"
	@echo "  make verify     安装后完整性校验"
	@echo "  make launch     直接启动 llama-server"
	@echo "  make bench      跑一次基准测试"
	@echo "  make info       生成环境报告"
	@echo "  make check      校验所有脚本语法"

preflight:
	bash scripts/preflight.sh

install:
	bash scripts/install.sh

download:
	bash scripts/download-models.sh

service:
	bash scripts/install-service.sh

verify:
	bash scripts/verify.sh

launch:
	bash scripts/launch-llama-server.sh

bench:
	bash scripts/benchmark.sh

info:
	bash scripts/collect-info.sh

check:
	@bash -n scripts/*.sh && echo "所有脚本语法通过"
