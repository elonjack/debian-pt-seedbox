# Debian 13 PT Seedbox 安全部署

面向新手的 Debian 13（amd64）qBittorrent-nox 部署仓库。脚本负责系统层安装和安全基线，WebUI 内的站点相关设置按中文手册逐项确认。

## 适用范围

- Debian 13（trixie）amd64
- 1～2 GB 内存的小型 VPS
- 独立公网 IPv4/IPv6
- 一个已经解析到 VPS 的独立子域名
- 使用站点明确允许的 qBittorrent 版本

脚本不会安装 Vertex，不会添加种子，也不会保存 PT 账号、Cookie、Tracker URL 或 passkey。

> 仅分享你有权获取和传播的内容。使用前同时确认 VPS 服务商条款、当地法律和 PT 站点规则。

## 安装前必须完成

1. 在 Cloudflare 添加一个新的 A 记录，例如 `qbt2.example.com`。
2. A 记录指向新 VPS 的 IPv4。
3. 首次安装时 Cloudflare 代理状态先选择 **仅 DNS（灰云）**，TTL 自动，让 Caddy 签发源站证书。
4. 确认安全组/云防火墙没有拦截 SSH、80、443 和准备使用的 BT 端口。
5. 如果同一 PT 账号准备在多台 VPS 使用，先向站点管理组确认是否允许多公网 IP、多客户端。不要凭“连接数无限”自行推断。

每台 VPS 必须使用不同子域名，例如：

- 第一台：`qbt.example.com`
- 第二台：`qbt2.example.com`
- 第三台：`qbt3.example.com`

## 真正的一行安装（推荐）

当前稳定版为 **v1.1.1**。先登录全新的 Debian 13 VPS，以 `root` 身份把下面整行复制一次：

```bash
apt-get update -qq && apt-get install -y -qq curl ca-certificates && curl --proto '=https' --tlsv1.2 -fsSLo /tmp/pt-bootstrap.sh https://github.com/elonjack/debian-pt-seedbox/releases/download/v1.1.1/bootstrap.sh && bash /tmp/pt-bootstrap.sh --domain qbt2.example.com
```

这是一条命令：它安装下载工具、获取固定 Release 的 Bootstrap、下载 `install.sh`、校验 SHA-256，再开始交互式安装。脚本会自动识别当前 SSH 会话使用的端口。

你的第二台 VPS 示例：

```bash
apt-get update -qq && apt-get install -y -qq curl ca-certificates && curl --proto '=https' --tlsv1.2 -fsSLo /tmp/pt-bootstrap.sh https://github.com/elonjack/debian-pt-seedbox/releases/download/v1.1.1/bootstrap.sh && bash /tmp/pt-bootstrap.sh --domain qbt2.qgv.de5.net
```

若 SSH 不是 22 或需要自定义参数，仍然只复制一行：

```bash
apt-get update -qq && apt-get install -y -qq curl ca-certificates && curl --proto '=https' --tlsv1.2 -fsSLo /tmp/pt-bootstrap.sh https://github.com/elonjack/debian-pt-seedbox/releases/download/v1.1.1/bootstrap.sh && bash /tmp/pt-bootstrap.sh --domain qbt2.example.com --ssh-port 你的SSH端口 --peer-port 49160 --swap-mb 1024
```

这里没有使用 `curl | bash`，下载失败时不会执行残缺脚本。Bootstrap 还会核对安装脚本的固定 SHA-256。

### 想先审查再安装

如果你希望逐个文件查看，再使用 Git：

```bash
apt-get update
apt-get install -y git
git clone --branch v1.1.1 --depth 1 https://github.com/elonjack/debian-pt-seedbox.git
cd debian-pt-seedbox
less install.sh
bash install.sh --domain qbt2.example.com
```

所有固定版本和校验文件见 [Releases](https://github.com/elonjack/debian-pt-seedbox/releases)。

## 脚本会做什么

- 只使用 Debian 官方仓库安装 `qbittorrent-nox`、`ufw`、`caddy` 等软件；
- 创建无登录权限的 `qbt` 系统账号；
- 创建 `/srv/qbt/downloads` 和 `/srv/qbt/incomplete`；
- 小内存且没有 Swap 时创建 1 GiB `/swapfile`；
- UFW 默认拒绝入站，放行当前 SSH、BT TCP/UDP、80 和 443；
- 用独立 systemd 服务运行 qBittorrent，不使用 root；
- qBittorrent 崩溃时自动重启，并随系统启动；
- 用 Caddy 为 WebUI 提供自动 HTTPS；
- 不向公网开放 8080；
- 保留已有 Swap，不覆盖现存 `/swapfile`；
- 若发现原先已有自定义 Caddy 配置则停止，避免覆盖其他网站。

## 安装后

查看首次登录临时密码：

```bash
journalctl -u qbittorrent-pt.service --no-pager | grep -i password
```

浏览器打开：

```text
https://qbt2.example.com
```

立即修改 WebUI 用户名和强密码，然后完整阅读：

- [小白操作手册](docs/小白操作手册.md)
- [qBittorrent 设置清单](docs/qBittorrent设置清单.md)
- [故障排查](docs/故障排查.md)

确认直接访问 HTTPS 正常后，可以把 Cloudflare 中这个 **WebUI 域名**切换为“已代理（小黄云）”，并把 SSL/TLS 模式设置为 **Full (strict)**。小黄云只代理 443 上的 WebUI；BT 的 TCP/UDP `49160` 仍由 VPS 公网 IP 直连，不能交给普通 Cloudflare HTTP 代理。

## 为什么显示 KiB/s，而不是十几 MiB/s

截图中的速度并没有证明 VPS 端口故障：

- `用户 4(8)` 表示当前只连接 4 个下载者，不代表这 4 人会全速向你取数据；
- `种子 0(1)` 表示没有连接那个完整做种者；
- 完成种子的 `用户 0(5)` 表示当前没有下载者连接你，上传为 0 完全正常；
- 10 Gbps 是端口理论上限，不是每个种子保证带宽；
- 你的全局上传上限 `18000 KiB/s` 约为 17.6 MiB/s，它只规定最高速度，不会制造下载需求。

先确认站点显示“可连接：是”、TCP/UDP 监听端口正常，再用刚发布且确实有下载者的新种测试。完整判断表见 [故障排查：上传速度只有 KiB/s](docs/故障排查.md#7-上传速度只有-kibs)。

## 日常检查

```bash
cd ~/debian-pt-seedbox
bash check.sh
```

也可以单独执行：

```bash
systemctl status qbittorrent-pt.service --no-pager
systemctl status caddy --no-pager
ufw status verbose
df -h /
free -h
```

## 更新仓库

更新脚本前先看改动，不要在正在做种时盲目重装：

```bash
cd ~/debian-pt-seedbox
git pull --ff-only
git log -1 --oneline
```

`install.sh` 设计为可重复执行，但正常运行中的 VPS 没有必要反复执行安装脚本。

## 安全原则

- 不截图、发送或提交 `.torrent` 文件。
- 不公开含 `passkey=`、`authkey=` 或 `torrent_pass=` 的链接。
- 不把 WebUI 密码写进 GitHub、Shell 历史或聊天记录。
- 不关闭 CSRF、Host Header、Clickjacking 和登录验证。
- 不开放 8080 到公网。
- 不使用伪造上传、篡改客户端、重复汇报或其他作弊方式。
- 不在未经站点确认的情况下让同一账号跨多个公网 IP 同时连接 Tracker。

## 项目状态

当前稳定版为 `v1.1.1`，按照 Debian 13、qBittorrent 5.1.x 和 Caddy 的组合编写。站点规则可能随时变化，速度、H&R 和客户端白名单以站点当日规则为准。
