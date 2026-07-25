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
3. Cloudflare 代理状态选择 **仅 DNS（灰云）**，TTL 自动。
4. 确认安全组/云防火墙没有拦截 SSH、80、443 和准备使用的 BT 端口。
5. 如果同一 PT 账号准备在多台 VPS 使用，先向站点管理组确认是否允许多公网 IP、多客户端。不要凭“连接数无限”自行推断。

每台 VPS 必须使用不同子域名，例如：

- 第一台：`qbt.example.com`
- 第二台：`qbt2.example.com`
- 第三台：`qbt3.example.com`

## 快速安装

先登录 VPS，再执行：

```bash
apt-get update
apt-get install -y git
git clone https://github.com/elonjack/debian-pt-seedbox.git
cd debian-pt-seedbox
bash install.sh --domain qbt2.example.com
```

脚本会自动识别当前 SSH 会话使用的端口。若识别失败或使用特殊端口，明确指定：

```bash
bash install.sh \
  --domain qbt2.example.com \
  --ssh-port 22 \
  --peer-port 49160 \
  --swap-mb 1024
```

不建议使用未经检查的 `curl | bash`。先下载仓库、查看 `install.sh`，再以 root 执行。

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

当前版本按照 Debian 13、qBittorrent 5.1.x 和 Caddy 的组合编写。站点规则可能随时变化，速度、H&R 和客户端白名单以站点当日规则为准。
