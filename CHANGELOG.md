# 更新记录

## v1.1.1

- 修复 ShellCheck 对未使用版本变量和 Unicode 引号的警告；
- 安装前摘要现在会明确显示脚本版本；
- 一行安装入口更新到通过完整 CI 的补丁版本。

## v1.1.0

- 增加真正可复制一次执行的“一行安装”入口；
- 安装入口固定到 Release 版本，不直接执行会变化的 `main`；
- Bootstrap 下载后校验 `install.sh` 的 SHA-256；
- 增加自动生成 GitHub Release、压缩包和校验文件的工作流；
- 明确 Cloudflare 小黄云只保护 WebUI，不代理 BT TCP/UDP 端口；
- 增加上传速度诊断表，区分“没有需求”和“网络/端口故障”。

## v1.0.0

- Debian 13 amd64 初始版本；
- 安装 qBittorrent-nox、Caddy、UFW 和 Swap；
- 提供中文设置清单、操作手册和故障排查。
