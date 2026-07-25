#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.1.1"
QBT_USER="qbt"
QBT_GROUP="qbt"
QBT_HOME="/var/lib/qbittorrent"
DOWNLOAD_DIR="/srv/qbt/downloads"
INCOMPLETE_DIR="/srv/qbt/incomplete"
WEBUI_PORT="8080"
PEER_PORT="49160"
DOMAIN=""
SSH_PORT=""
SWAP_MB="auto"
ASSUME_YES="false"
CADDY_WAS_INSTALLED="false"
SERVICE_NAME="qbittorrent-pt.service"

log() {
  printf '\n\033[1;32m[信息]\033[0m %s\n' "$*"
}

warn() {
  printf '\n\033[1;33m[提醒]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\n\033[1;31m[错误]\033[0m %s\n' "$*" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  printf '\n\033[1;31m[失败]\033[0m 第 %s 行执行失败（退出码 %s）。\n' "${BASH_LINENO[0]:-未知}" "$exit_code" >&2
  printf '请不要反复重装。运行：journalctl -u %s -n 80 --no-pager\n' "$SERVICE_NAME" >&2
  exit "$exit_code"
}
trap on_error ERR

usage() {
  cat <<'EOF'
Debian 13 qBittorrent PT 基础环境安装脚本

用法：
  bash install.sh --domain qbt2.example.com [选项]

必填：
  --domain 域名          qBittorrent WebUI 使用的独立子域名

可选：
  --ssh-port 端口        SSH 端口；默认从当前 SSH 会话自动识别，失败时使用 22
  --peer-port 端口       BT 监听端口，默认 49160
  --swap-mb 数量         没有 Swap 时创建的大小；默认 auto，0 表示不创建
  --yes                  跳过最终确认
  -h, --help             显示帮助

示例：
  bash install.sh --domain qbt2.example.com
  bash install.sh --domain qbt2.example.com --peer-port 49161 --swap-mb 1024 --yes
EOF
}

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

validate_port() {
  local name="$1"
  local value="$2"
  is_integer "$value" || die "$name 必须是数字：$value"
  (( value >= 1 && value <= 65535 )) || die "$name 必须在 1～65535 之间：$value"
}

while (($#)); do
  case "$1" in
    --domain)
      (($# >= 2)) || die "--domain 后缺少值"
      DOMAIN="$2"
      shift 2
      ;;
    --ssh-port)
      (($# >= 2)) || die "--ssh-port 后缺少值"
      SSH_PORT="$2"
      shift 2
      ;;
    --peer-port)
      (($# >= 2)) || die "--peer-port 后缺少值"
      PEER_PORT="$2"
      shift 2
      ;;
    --swap-mb)
      (($# >= 2)) || die "--swap-mb 后缺少值"
      SWAP_MB="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数：$1（使用 --help 查看帮助）"
      ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || die "请使用 root 执行：sudo bash install.sh --domain qbt2.example.com"
[[ -r /etc/os-release ]] || die "无法识别操作系统"
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "debian" ]] || die "本脚本仅支持 Debian 13，目前是：${PRETTY_NAME:-未知}"
[[ "${VERSION_ID:-}" == "13" ]] || die "本脚本仅验证过 Debian 13，目前 VERSION_ID=${VERSION_ID:-未知}"
[[ "$(dpkg --print-architecture)" == "amd64" ]] || die "本脚本当前仅验证 amd64 架构"

[[ -n "$DOMAIN" ]] || die "必须指定域名，例如：--domain qbt2.example.com"
DOMAIN="${DOMAIN,,}"
[[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] \
  || die "域名格式不正确：$DOMAIN"

if [[ -z "$SSH_PORT" && -n "${SSH_CONNECTION:-}" ]]; then
  SSH_PORT="${SSH_CONNECTION##* }"
fi
SSH_PORT="${SSH_PORT:-22}"

validate_port "SSH 端口" "$SSH_PORT"
validate_port "BT 监听端口" "$PEER_PORT"
validate_port "WebUI 端口" "$WEBUI_PORT"
(( PEER_PORT >= 1024 )) || die "BT 监听端口建议使用 1024 以上"
[[ "$PEER_PORT" != "$SSH_PORT" ]] || die "BT 端口不能与 SSH 端口相同"
[[ "$PEER_PORT" != "80" && "$PEER_PORT" != "443" && "$PEER_PORT" != "$WEBUI_PORT" ]] \
  || die "BT 端口不能与 80、443 或 WebUI 端口冲突"

if [[ "$SWAP_MB" == "auto" ]]; then
  total_mem_mb="$(awk '/MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)"
  if (( total_mem_mb <= 2048 )); then
    SWAP_MB="1024"
  else
    SWAP_MB="0"
  fi
else
  is_integer "$SWAP_MB" || die "--swap-mb 必须是整数或 auto"
fi

if command -v caddy >/dev/null 2>&1; then
  CADDY_WAS_INSTALLED="true"
fi

cat <<EOF

即将安装：
  脚本版本：    ${VERSION}
  系统：        ${PRETTY_NAME}
  WebUI 域名： ${DOMAIN}
  SSH 端口：   ${SSH_PORT}/tcp（会先放行，防止 UFW 锁住 SSH）
  BT 端口：    ${PEER_PORT}/tcp + udp
  Caddy 上游： 127.0.0.1:${WEBUI_PORT}
  WebUI 绑定： 首次登录后按文档改为 127.0.0.1；此前由 UFW 阻止公网直连 ${WEBUI_PORT}
  下载目录：   ${DOWNLOAD_DIR}
  未完成目录： ${INCOMPLETE_DIR}
  Swap：       ${SWAP_MB} MiB（已有 Swap 时不修改）

脚本不会安装 Vertex，不会写入 PT passkey/Cookie，也不会添加任何种子。
EOF

if [[ "$ASSUME_YES" != "true" ]]; then
  read -r -p "确认以上信息正确并继续？输入 yes： " answer
  [[ "$answer" == "yes" ]] || die "用户取消"
fi

log "更新软件索引并安装官方 Debian 软件包"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  qbittorrent-nox \
  ufw \
  caddy \
  curl \
  ca-certificates

log "创建低权限 qBittorrent 服务账号和下载目录"
if ! id "$QBT_USER" >/dev/null 2>&1; then
  adduser --system --group --home "$QBT_HOME" "$QBT_USER"
fi
install -d -o "$QBT_USER" -g "$QBT_GROUP" -m 0750 "$QBT_HOME"
install -d -o "$QBT_USER" -g "$QBT_GROUP" -m 0750 "$DOWNLOAD_DIR"
install -d -o "$QBT_USER" -g "$QBT_GROUP" -m 0750 "$INCOMPLETE_DIR"

if [[ -z "$(swapon --show --noheadings 2>/dev/null)" && "$SWAP_MB" != "0" ]]; then
  if [[ -e /swapfile ]]; then
    warn "/swapfile 已存在但未启用；为避免覆盖用户数据，脚本不会修改它。请看文档手动检查。"
  else
    log "创建 ${SWAP_MB} MiB Swap"
    if ! fallocate -l "${SWAP_MB}M" /swapfile; then
      dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_MB" status=progress
    fi
    chmod 0600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -Eq '^[[:space:]]*/swapfile[[:space:]]+none[[:space:]]+swap[[:space:]]' /etc/fstab; then
      cp -a /etc/fstab "/etc/fstab.qbt-backup.$(date +%Y%m%d-%H%M%S)"
      printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
    fi
  fi
else
  log "已有 Swap，保持现状"
fi

log "配置 UFW；先放行当前 SSH 端口，再启用防火墙"
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment "SSH"
ufw allow "${PEER_PORT}/tcp" comment "qBittorrent peer TCP"
ufw allow "${PEER_PORT}/udp" comment "qBittorrent peer UDP"
ufw allow 80/tcp comment "Caddy HTTP"
ufw allow 443/tcp comment "Caddy HTTPS"
ufw --force enable

log "创建独立的 systemd 服务（qBittorrent 不以 root 运行）"
cat > "/etc/systemd/system/${SERVICE_NAME}" <<EOF
[Unit]
Description=qBittorrent-nox for private tracker use
Documentation=man:qbittorrent-nox(1)
Wants=network-online.target
After=network-online.target nss-lookup.target

[Service]
Type=exec
User=${QBT_USER}
Group=${QBT_GROUP}
Environment=HOME=${QBT_HOME}
Environment=LANG=C.UTF-8
UMask=0027
ExecStart=/usr/bin/qbittorrent-nox --confirm-legal-notice --webui-port=${WEBUI_PORT} --torrenting-port=${PEER_PORT}
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=${QBT_HOME} /srv/qbt

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

log "配置 Caddy 自动 HTTPS 反向代理"
if [[ "$CADDY_WAS_INSTALLED" == "true" && -s /etc/caddy/Caddyfile ]] \
   && ! grep -qxF '# Managed by debian-pt-seedbox' /etc/caddy/Caddyfile; then
  die "检测到服务器原先已有 Caddy 配置。为避免覆盖其他网站，脚本已停止。qBittorrent 服务已安装；请按文档手动合并 Caddy 配置。"
fi

if [[ -e /etc/caddy/Caddyfile ]]; then
  cp -a /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.qbt-backup.$(date +%Y%m%d-%H%M%S)"
fi

cat > /etc/caddy/Caddyfile <<EOF
# Managed by debian-pt-seedbox
${DOMAIN} {
	reverse_proxy 127.0.0.1:${WEBUI_PORT}
}
EOF

caddy fmt --overwrite /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile
systemctl enable caddy
systemctl restart caddy

log "保存无敏感信息的安装参数"
cat > /etc/qbt-seedbox.conf <<EOF
DOMAIN=${DOMAIN}
SSH_PORT=${SSH_PORT}
PEER_PORT=${PEER_PORT}
WEBUI_PORT=${WEBUI_PORT}
DOWNLOAD_DIR=${DOWNLOAD_DIR}
INCOMPLETE_DIR=${INCOMPLETE_DIR}
EOF
chmod 0644 /etc/qbt-seedbox.conf

log "执行安装后检查"
systemctl is-active --quiet "$SERVICE_NAME" || die "qBittorrent 服务未运行"
systemctl is-active --quiet caddy || die "Caddy 服务未运行"
ss -lntup | grep -Eq ":${PEER_PORT}[[:space:]]" || die "未发现 BT 监听端口 ${PEER_PORT}"
ss -lntp | grep -Eq ":${WEBUI_PORT}[[:space:]]" || die "未发现 WebUI 监听端口 ${WEBUI_PORT}"

printf '\n\033[1;32m安装完成。\033[0m\n'
cat <<EOF

下一步（必须完成）：
  1. 首次签发证书时先让 ${DOMAIN} 直接解析到这台 VPS（仅 DNS/灰云）。
  2. 查看首次登录临时密码：
       journalctl -u ${SERVICE_NAME} --no-pager | grep -i 'password'
  3. 浏览器打开：
       https://${DOMAIN}
  4. 立即修改 WebUI 用户名和强密码，并按中文操作手册完成全部设置。
  5. HTTPS 正常后，可按手册把该 WebUI 域名切换为 Cloudflare "已代理/小黄云"，
     SSL/TLS 模式使用 Full (strict)。BT 端口 ${PEER_PORT} 仍必须直连公网。

检查命令：
  systemctl status ${SERVICE_NAME} --no-pager
  systemctl status caddy --no-pager
  ufw status verbose
  ss -lntup | grep -E '${WEBUI_PORT}|${PEER_PORT}'

重要：
  - 不要开放 ${WEBUI_PORT}/tcp 到公网。
  - 不要泄露 .torrent、Tracker URL、Cookie 或 passkey。
  - 使用第二个公网 IP 前，先向 PT 站确认同一账号是否允许多 IP/多客户端。
  - 只下载和分享你有权获取的内容，并遵守 VPS 与站点规则。
EOF

if ! getent ahostsv4 "$DOMAIN" >/dev/null 2>&1; then
  warn "当前还查不到 ${DOMAIN} 的 IPv4 解析。Caddy 会自动重试证书申请，请先完成 DNS。"
fi

if ! curl -fsSI --max-time 10 "https://${DOMAIN}" >/dev/null 2>&1; then
  warn "HTTPS 暂时不可达，常见原因是 DNS 尚未生效。完成 DNS 后运行：systemctl restart caddy"
else
  log "HTTPS 检查通过：https://${DOMAIN}"
fi
