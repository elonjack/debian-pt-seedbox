# 更新记录

## 1.2.1 - 2026-07-25

### 兼容性修复

- 修复 Debian 12 的 qBittorrent 4.5.2 不支持 `--confirm-legal-notice`，导致服务无法启动的问题。
- 在受保护的初始配置中记录法律提示确认，Debian 12/13 使用同一套无交互启动流程。
- 修复 ShellCheck 对安装结束提示中 Unicode 弯引号的告警。

### 发布与测试

- Release 只会在完整 Validate 工作流通过后运行，不再出现“测试失败但版本已发布”的竞态。
- 升级并固定 `actions/checkout` v7.0.1 的完整提交 SHA。
- 兼容测试失败时输出失败命令和 qBittorrent 日志，便于定位回归。

## 1.2.0 - 2026-07-25

### 新增

- 正式支持 Debian 12 bookworm 与 Debian 13 trixie（amd64）。
- 增加 Debian 12/13 容器矩阵预检查与真实软件包/WebAPI 兼容测试。
- 增加 `--check-only` 非破坏性兼容检查。
- 自动生成并验证首次 WebUI 强密码。
- 自动写入 PT 基础安全项：关闭 DHT/PeX/LSD/公共 Tracker、随机端口与 UPnP，并启用 WebUI 防护。

### 安全修复

- 首次启动前将 WebUI 绑定到 `127.0.0.1`，消除短暂公网监听窗口。
- Debian 12 不再保留公开默认密码 `adminadmin`。
- 在修改系统前检测并拒绝覆盖已有 Caddy 配置。
- 拒绝覆盖已安装实例，保护现有 qBittorrent 任务。
- 固定 GitHub Actions checkout 到完整提交 SHA。
- `check.sh` 不再 `source` 配置文件，避免把配置内容当 shell 代码执行。

### 可靠性

- 不再依赖 Debian 12 不支持的 `--torrenting-port` 命令行参数，改由配置和 WebAPI 设置监听端口。
- Swap 检测同时覆盖活动 Swap、fstab 条目和已有 `/swapfile`。
- 创建 Swap 前检查磁盘余量，失败回退时先清理本次创建的空文件。
- Release 同时打包 `SECURITY.md` 和可执行 `check.sh`。

### 文档

- 重排 README，明确一行安装、域名替换、Cloudflare、Swap 和安装后步骤。
- 重写 Debian 12/13 小白手册、设置清单和故障排查。

## 1.1.2 - 2026-07-25

- 一行 bootstrap 安装时交互询问域名。
- 清理 README 中与通用部署无关的临时速度诊断内容。
- 改进 Release 校验与固定版本下载。

## 1.1.1 - 2026-07-25

- 修复 Release 工作流验证逻辑。
- 发布固定版本安装资源与 SHA256SUMS。

## 1.1.0 - 2026-07-25

- 增加固定 Release 的一行安装入口。
- 增加自动 Release 工作流。

## 1.0.0 - 2026-07-25

- 首个 Debian 13 安全部署版本。
- 提供 qBittorrent、Caddy、UFW、systemd、Swap 与中文文档。
