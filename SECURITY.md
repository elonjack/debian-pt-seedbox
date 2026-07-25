# 安全说明

## 支持版本

安全修复只发布到最新 GitHub Release。当前支持 Debian 12/13 amd64，软件来自 Debian 官方仓库。

## 安全边界

安装器负责：

- qBittorrent 使用独立低权限账户；
- WebUI 首次启动前仅绑定 `127.0.0.1`；
- Debian 12/13 首次凭据自动替换为随机强密码；
- 首次凭据文件权限为 `0600`；
- Caddy 提供 HTTPS；
- UFW 不开放 8080；
- systemd 使用基础沙箱限制；
- 固定版本安装器执行前核验 SHA-256；
- 不保存 PT Cookie、Tracker URL 或 passkey。

用户仍需负责：

- 修改首次密码并删除 `/root/qbittorrent-webui-credentials.txt`；
- 完成 WebUI CSRF、Host Header、Secure Cookie 和反向代理设置；
- 维护系统安全更新；
- 确认 PT 客户端白名单和多 IP 规则；
- 保护 `.torrent`、passkey 和站点 Cookie；
- 配置 VPS 商家安全组和 Cloudflare 账户安全。

## 敏感信息

不要提交、截图或粘贴：

- `.torrent` 文件；
- Tracker 完整 URL；
- passkey、authkey、torrent_pass；
- PT Cookie；
- WebUI 密码或首次凭据文件；
- Cloudflare API Token；
- VPS root 密码或 SSH 私钥。

仓库 `.gitignore` 只能降低误提交风险，不能撤销已经推送的秘密。若已泄露，应立即在对应服务中轮换。

## 供应链

- 一行命令从固定版本 Release 下载 bootstrap；
- bootstrap 从同一固定 Release 下载 installer；
- bootstrap 内置 installer 的 SHA-256；
- Release 提供独立 `SHA256SUMS`；
- GitHub Actions 第三方 action 使用完整提交 SHA 固定。

通过 HTTPS 获取 bootstrap 仍依赖 GitHub、TLS 和本机 CA 信任链。高安全要求用户应手动下载 Release、核对 `SHA256SUMS` 后离线审阅再执行。

## 报告漏洞

不要在公开 Issue 中附带真实域名、IP、密码、passkey、Cookie 或 `.torrent`。请先提交不含敏感信息的最小描述，包含：

- 受影响版本；
- Debian 版本；
- 可复现步骤；
- 预期与实际结果；
- 已脱敏日志。

确认需要私下交换细节后，再使用仓库所有者指定的私密渠道。
