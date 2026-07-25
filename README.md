# Debian PT Seedbox 一键部署

面向新手的 Debian 12/13（amd64）qBittorrent-nox 部署脚本。它负责系统安装、安全基线、HTTPS 和首次强密码；PT 站点相关设置仍需按中文清单逐项确认。

> 仅下载和分享你有权获取、保存与传播的内容。使用前必须同时遵守当地法律、VPS 服务商条款和 PT 站点规则。

## 支持范围

| 系统 | Debian 官方 qBittorrent | 支持状态 |
|---|---:|---|
| Debian 12 bookworm | 4.5.2 系列 | 自动测试 |
| Debian 13 trixie | 5.1.0 系列 | 自动测试 |

- 架构：amd64
- 推荐：1～2 GB 内存、独立公网 IP、全新或专用 VPS
- 必需：一个指向 VPS 的独立子域名
- 客户端版本最终是否可用，以目标 PT 站点的客户端白名单为准

脚本不会安装 Vertex/Docker，不会添加种子，也不会保存 PT 账号、Cookie、Tracker URL 或 passkey。

## 脚本会做什么

- 从 Debian 官方仓库安装 qBittorrent-nox、Caddy、UFW、curl；
- 创建低权限 `qbt` 系统用户，qBittorrent 不以 root 运行；
- 首次启动前把 WebUI 固定到 `127.0.0.1:8080`；
- 为 Debian 12/13 自动生成随机首次登录密码，避免 Debian 12 的默认 `adminadmin` 暴露；
- 使用 Caddy 提供自动 HTTPS；
- 只开放 SSH、80、443 和指定 BT TCP/UDP 端口，不开放 8080；
- 为小内存 VPS 按需创建 Swap；
- 安装 systemd 开机自启服务；
- 自动执行端口、服务和 HTTPS 基础检查。

## 安装前准备

1. 使用全新的 Debian 12 或 Debian 13 amd64 VPS，并以 root 登录。
2. 在 Cloudflare 创建独立 A 记录，例如 `qbt2.example.com`，指向该 VPS 的 IPv4。
3. 首次签发证书时先设为“仅 DNS/灰云”。HTTPS 正常后再切“小黄云”。
4. Cloudflare SSL/TLS 模式最终使用 **Full (strict)**。
5. 确认 VPS 商家的安全组也放行 SSH、80、443 和准备使用的 BT 端口。
6. 确认 PT 站允许你的 Debian 官方 qBittorrent 版本；使用第二台 VPS 前，还要确认是否允许同账号多 IP。

## 一行安装

当前稳定版：**v1.2.1**。

在全新的 Debian 12/13 VPS 上，以 root 身份把下面整行复制一次：

```bash
apt-get update -qq && apt-get install -y -qq curl ca-certificates && curl --proto '=https' --tlsv1.2 -fsSLo /tmp/pt-bootstrap.sh https://github.com/elonjack/debian-pt-seedbox/releases/download/v1.2.1/bootstrap.sh && bash /tmp/pt-bootstrap.sh
```

脚本会询问完整子域名。这里必须输入你自己的域名，例如：

```text
qbt2.qgv.de5.net
```

不要原样输入文档中的 `qbt2.example.com`。

非交互安装可以把自己的域名写在同一行末尾：

```bash
apt-get update -qq && apt-get install -y -qq curl ca-certificates && curl --proto '=https' --tlsv1.2 -fsSLo /tmp/pt-bootstrap.sh https://github.com/elonjack/debian-pt-seedbox/releases/download/v1.2.1/bootstrap.sh && bash /tmp/pt-bootstrap.sh --domain qbt2.example.com --yes
```

上面第二条命令中的 `qbt2.example.com` 必须替换为你自己的完整子域名。

安装器下载固定版本的 `install.sh`，并在执行前核验仓库发布时固定的 SHA-256。Release 页面也提供 `SHA256SUMS` 和完整压缩包。

## Swap 行为

默认 `--swap-mb auto`：

- 内存不超过 2 GiB 时，计划创建 1024 MiB Swap；
- 内存大于 2 GiB 时，不自动创建；
- 已有任何正在使用的 Swap：保持现状，不重复创建；
- `/etc/fstab` 已有 Swap 条目但暂未启用：保持现状，不重复创建；
- 已存在未启用的 `/swapfile`：不覆盖；
- 磁盘空间不足以创建 Swap 并保留 512 MiB：跳过并警告；
- `--swap-mb 0`：明确不创建。

所以，你的 VPS 已经有正常启用的 Swap 时，脚本不会再添加一份。

## 安装完成后的第一步

安装结束会显示：

```bash
cat /root/qbittorrent-webui-credentials.txt
```

运行它查看首次登录地址、用户名和随机密码。登录后：

1. 立即改成你自己的强密码；
2. 完成 [qBittorrent 设置清单](docs/qBittorrent设置清单.md)；
3. 确认新密码可登录后删除凭据文件：

```bash
rm -f /root/qbittorrent-webui-credentials.txt
```

4. HTTPS 正常后，把 Cloudflare A 记录切换为“已代理/小黄云”，并使用 Full (strict)；
5. BT 监听端口不能走 Cloudflare，必须直接连接 VPS 公网 IP。

## 常用参数

```text
--domain qbt.example.com   必填，完整 WebUI 子域名
--ssh-port 22              自定义 SSH 端口
--peer-port 49160          自定义 BT TCP/UDP 端口
--swap-mb auto             auto、0 或整数 MiB
--check-only               只做兼容性预检查，不修改系统
--yes                      跳过确认
```

只检查 Debian 和参数是否受支持：

```bash
bash install.sh --domain qbt.example.com --check-only --yes
```

同样要把示例域名替换成自己的域名；`--check-only` 不会安装软件或修改系统。

## 安装后检查

```bash
systemctl status qbittorrent-pt.service --no-pager
systemctl status caddy --no-pager
ufw status verbose
ss -lntup | grep -E '8080|49160'
```

正确结果：

- WebUI 只监听 `127.0.0.1:8080`；
- BT 端口在公网网卡监听 TCP 和 UDP；
- UFW 没有放行 8080；
- 80/443 由 Caddy 监听；
- `https://你的域名` 可以打开。

完整诊断：

```bash
curl --proto '=https' --tlsv1.2 -fsSLo /root/qbt-check.sh https://github.com/elonjack/debian-pt-seedbox/releases/download/v1.2.1/check.sh && bash /root/qbt-check.sh
```

## 文档

- [小白操作手册](docs/小白操作手册.md)：从 DNS、安装、登录到加种、H&R 和日常维护。
- [qBittorrent 设置清单](docs/qBittorrent设置清单.md)：Debian 12/13 对应界面设置。
- [故障排查](docs/故障排查.md)：HTTPS、密码、端口、Tracker、磁盘和内存问题。
- [安全说明](SECURITY.md)：威胁边界、敏感信息和漏洞报告。
- [更新记录](CHANGELOG.md)：每个版本的改动。

## 重要限制

- 这是专用新 VPS 安装器，不会覆盖已有 `/etc/qbt-seedbox.conf`；
- 检测到已有非本项目 Caddy 配置时会在修改系统前停止；
- 不会替你判断某个 PT 站是否允许多 IP、盒子或具体客户端版本；
- 端口已开放不代表一定有高速上传。上传速度还取决于是否有人下载、对方线路、种子竞争、硬盘和站点限速；
- 不要把 `.torrent`、Tracker URL、Cookie、passkey、WebUI 密码或凭据文件提交到 GitHub。

## 卸载

为避免误删做种数据，项目不提供“一键卸载”。需要卸载时先确认全部 H&R 已达标并备份：

- `/var/lib/qbittorrent`
- `/srv/qbt`
- `/etc/qbt-seedbox.conf`
- `/etc/caddy/Caddyfile`
- `/etc/systemd/system/qbittorrent-pt.service`

不要在没确认路径和 H&R 状态时运行批量删除命令。
