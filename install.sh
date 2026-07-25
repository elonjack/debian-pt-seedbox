#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.2.0"
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
CHECK_ONLY="false"
SERVICE_NAME="qbittorrent-pt.service"
CONFIG_FILE="/etc/qbt-seedbox.conf"
CREDENTIAL_FILE="/root/qbittorrent-webui-credentials.txt"

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
  printf '\n\033[1;31m[失败]\033[0m 第 %s 行执行失败（退出码 %s）。\n' \
    "${BASH_LINENO[0]:-未知}" "$exit_code" >&2
  printf '请先查看日志，不要反复重装：journalctl -u %s -n 100 --no-pager\n' \
    "$SERVICE_NAME" >&2
  exit "$exit_code"
}
trap on_error ERR

usage() {
  cat <<'EOF'
Debian 12/13 qBittorrent PT 基础环境安装脚本

用法：
  bash install.sh --domain qbt.example.com [选项]

必填：
  --domain 域名          qBittorrent WebUI 使用的完整独立子域名

可选：
  --ssh-port 端口        SSH 端口；默认从当前 SSH 会话识别，失败时使用 22
  --peer-port 端口       BT 监听端口，默认 49160
  --swap-mb 数量         没有 Swap 时创建的大小；默认 auto，0 表示不创建
  --check-only           只检查系统、参数和兼容性，不安装或修改任何内容
  --yes                  跳过最终确认
  -h, --help             显示帮助

示例：
  bash install.sh --domain qbt2.example.com
  bash install.sh --domain qbt2.example.com --peer-port 49161 --swap-mb 1024 --yes

注意：示例域名必须替换成你自己已在 DNS 中创建的完整子域名。
EOF
}

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

validate_port() {
  local name="$1"
  local value="$2"
  is_integer "$value" || die "${name}必须是数字：${value}"
  (( value >= 1 && value <= 65535 )) || die "${name}必须在 1～65535 之间：${value}"
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
    --check-only)
      CHECK_ONLY="true"
      shift
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

[[ "${EUID}" -eq 0 ]] || die "请使用 root 执行"
[[ -r /etc/os-release ]] || die "无法识别操作系统"
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "debian" ]] || die "仅支持 Debian 12/13；当前是 ${PRETTY_NAME:-未知}"
case "${VERSION_ID:-}" in
  12|13) ;;
  *) die "仅验证 Debian 12/13；当前 VERSION_ID=${VERSION_ID:-未知}" ;;
esac
[[ "$(dpkg --print-architecture)" == "amd64" ]] || die "当前仅验证 amd64 架构"

[[ -n "$DOMAIN" ]] || die "必须指定域名，例如：--domain qbt2.example.com"
DOMAIN="${DOMAIN,,}"
[[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] \
  || die "域名格式不正确：${DOMAIN}"

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

cat <<EOF

预检查结果：
  脚本版本：     ${VERSION}
  系统：         ${PRETTY_NAME}
  WebUI 域名：   ${DOMAIN}
  SSH 端口：     ${SSH_PORT}/tcp
  BT 端口：      ${PEER_PORT}/tcp + udp
  WebUI 上游：   127.0.0.1:${WEBUI_PORT}
  下载目录：     ${DOWNLOAD_DIR}
  未完成目录：   ${INCOMPLETE_DIR}
  Swap 计划：    ${SWAP_MB} MiB（检测到已有 Swap 时保持现状）
EOF

if [[ "$CHECK_ONLY" == "true" ]]; then
  log "预检查通过；未安装软件，也未修改系统。"
  exit 0
fi

[[ ! -e "$CONFIG_FILE" ]] \
  || die "检测到 ${CONFIG_FILE}，说明本脚本已安装过。为保护现有任务，本次拒绝覆盖；请运行 check.sh 排查。"
[[ ! -e "${QBT_HOME}/.config/qBittorrent/qBittorrent.conf" ]] \
  || die "检测到已有 qBittorrent 配置。为保护现有任务和密码，本次拒绝覆盖。"

if [[ -s /etc/caddy/Caddyfile ]] \
   && ! grep -qxF '# Managed by debian-pt-seedbox' /etc/caddy/Caddyfile; then
  die "检测到已有 Caddy 配置。为避免覆盖其他网站，本次未修改系统；请按文档手动合并。"
fi

if [[ "$ASSUME_YES" != "true" ]]; then
  read -r -p "确认以上信息正确并继续？输入 yes：" answer
  [[ "$answer" == "yes" ]] || die "用户取消"
fi

log "更新软件索引并安装 Debian 官方软件包"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  qbittorrent-nox \
  ufw \
  caddy \
  curl \
  ca-certificates

log "创建低权限 qBittorrent 服务账户和目录"
if ! id "$QBT_USER" >/dev/null 2>&1; then
  adduser --system --group --home "$QBT_HOME" "$QBT_USER"
fi
install -d -o "$QBT_USER" -g "$QBT_GROUP" -m 0750 "$QBT_HOME"
install -d -o "$QBT_USER" -g "$QBT_GROUP" -m 0750 "$DOWNLOAD_DIR"
install -d -o "$QBT_USER" -g "$QBT_GROUP" -m 0750 "$INCOMPLETE_DIR"

active_swap="$(swapon --show --noheadings 2>/dev/null || true)"
configured_swap="$(awk '
  $0 !~ /^[[:space:]]*#/ && NF >= 3 && $3 == "swap" { print; exit }
' /etc/fstab)"

if [[ -n "$active_swap" ]]; then
  log "检测到正在使用的 Swap，保持现状，不重复创建。"
elif [[ -n "$configured_swap" ]]; then
  warn "检测到 /etc/fstab 已配置 Swap，但当前未启用；为避免重复创建，脚本保持现状。"
elif [[ "$SWAP_MB" == "0" ]]; then
  log "按参数不创建 Swap。"
elif [[ -e /swapfile ]]; then
  warn "/swapfile 已存在但未启用；为避免覆盖数据，脚本保持现状。"
else
  available_mb="$(df --output=avail -BM / | awk 'NR == 2 {gsub(/M/, "", $1); print $1}')"
  required_mb=$((SWAP_MB + 512))
  if (( available_mb < required_mb )); then
    warn "磁盘空间不足以安全创建 ${SWAP_MB} MiB Swap（还需保留 512 MiB），本次跳过。"
  else
    log "创建 ${SWAP_MB} MiB Swap"
    if ! fallocate -l "${SWAP_MB}M" /swapfile; then
      rm -f -- /swapfile
      dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_MB" status=progress
    fi
    chmod 0600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    cp -a /etc/fstab "/etc/fstab.qbt-backup.$(date +%Y%m%d-%H%M%S)"
    printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
  fi
fi

log "配置 UFW；先放行 SSH，再启用防火墙"
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment "SSH"
ufw allow "${PEER_PORT}/tcp" comment "qBittorrent peer TCP"
ufw allow "${PEER_PORT}/udp" comment "qBittorrent peer UDP"
ufw allow 80/tcp comment "Caddy HTTP"
ufw allow 443/tcp comment "Caddy HTTPS"
ufw --force enable

log "首次启动前把 WebUI 固定到本机回环地址"
qbt_config_dir="${QBT_HOME}/.config/qBittorrent"
qbt_config="${qbt_config_dir}/qBittorrent.conf"
install -d -o "$QBT_USER" -g "$QBT_GROUP" -m 0750 "$qbt_config_dir"
if [[ ! -e "$qbt_config" ]]; then
  cat > "$qbt_config" <<EOF
[Preferences]
Connection\\PortRangeMin=${PEER_PORT}
WebUI\\Address=127.0.0.1
WebUI\\Port=${WEBUI_PORT}
WebUI\\UPnP=false
EOF
  chown "$QBT_USER:$QBT_GROUP" "$qbt_config"
  chmod 0600 "$qbt_config"
fi

log "创建独立 systemd 服务（qBittorrent 不以 root 运行）"
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
ExecStart=/usr/bin/qbittorrent-nox --confirm-legal-notice --webui-port=${WEBUI_PORT}
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
ReadWritePaths=${QBT_HOME} /srv/qbt

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

log "等待本机 WebUI 启动"
webui_ready="false"
for _ in {1..20}; do
  if curl -fsS --max-time 2 "http://127.0.0.1:${WEBUI_PORT}/" >/dev/null 2>&1; then
    webui_ready="true"
    break
  fi
  sleep 1
done
[[ "$webui_ready" == "true" ]] || die "WebUI 未在 20 秒内启动"

log "生成首次登录强密码并设置 BT 监听端口"
initial_password="$(od -An -N18 -tx1 /dev/urandom | tr -d ' \n')"
cookie_file="$(mktemp /tmp/qbt-cookie.XXXXXX)"
referer="http://127.0.0.1:${WEBUI_PORT}"

temporary_password="$(journalctl -u "$SERVICE_NAME" -o cat --no-pager 2>/dev/null \
  | sed -nE 's/.*temporary password[^:]*:[[:space:]]*(.+)$/\1/p' \
  | tail -n 1)"

login_password=""
for candidate in "$temporary_password" "adminadmin"; do
  [[ -n "$candidate" ]] || continue
  login_result="$(printf '%s' "$candidate" \
    | curl -sS -c "$cookie_file" \
      -H "Referer: ${referer}" \
      --data-urlencode "username=admin" \
      --data-urlencode "password@-" \
      "${referer}/api/v2/auth/login" || true)"
  if [[ "$login_result" == "Ok." ]]; then
    login_password="$candidate"
    break
  fi
done
[[ -n "$login_password" ]] \
  || die "无法使用 qBittorrent 首次凭据登录本机 WebAPI；Caddy 尚未开放 WebUI"

preferences_json="$(printf \
  '{"listen_port":%s,"random_port":false,"upnp":false,"dht":false,"pex":false,"lsd":false,"add_trackers_enabled":false,"save_path":"%s","temp_path_enabled":true,"temp_path":"%s","web_ui_upnp":false,"bypass_local_auth":false,"bypass_auth_subnet_whitelist_enabled":false,"web_ui_csrf_protection_enabled":true,"web_ui_clickjacking_protection_enabled":true,"web_ui_host_header_validation_enabled":true,"web_ui_secure_cookie_enabled":true,"web_ui_domain_list":"%s;127.0.0.1","use_https":false,"web_ui_username":"admin","web_ui_password":"%s"}' \
  "$PEER_PORT" "$DOWNLOAD_DIR" "$INCOMPLETE_DIR" "$DOMAIN" "$initial_password")"
printf '%s' "$preferences_json" \
  | curl -fsS -b "$cookie_file" \
    -H "Referer: ${referer}" \
    --data-urlencode "json@-" \
    "${referer}/api/v2/app/setPreferences" >/dev/null

rm -f -- "$cookie_file"
cookie_file="$(mktemp /tmp/qbt-cookie.XXXXXX)"
login_result="$(printf '%s' "$initial_password" \
  | curl -sS -c "$cookie_file" \
    -H "Referer: ${referer}" \
    --data-urlencode "username=admin" \
    --data-urlencode "password@-" \
    "${referer}/api/v2/auth/login" || true)"
rm -f -- "$cookie_file"
[[ "$login_result" == "Ok." ]] || die "首次强密码设置后验证失败"

install -m 0600 /dev/null "$CREDENTIAL_FILE"
cat > "$CREDENTIAL_FILE" <<EOF
qBittorrent WebUI 首次登录凭据
地址：https://${DOMAIN}
用户名：admin
密码：${initial_password}

首次登录后请立即修改用户名和密码，然后删除本文件：
rm -f ${CREDENTIAL_FILE}
EOF

log "配置 Caddy 自动 HTTPS 反向代理"
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

log "保存非敏感安装参数"
cat > "$CONFIG_FILE" <<EOF
DOMAIN=${DOMAIN}
SSH_PORT=${SSH_PORT}
PEER_PORT=${PEER_PORT}
WEBUI_PORT=${WEBUI_PORT}
DOWNLOAD_DIR=${DOWNLOAD_DIR}
INCOMPLETE_DIR=${INCOMPLETE_DIR}
EOF
chmod 0644 "$CONFIG_FILE"

log "执行安装后检查"
systemctl is-active --quiet "$SERVICE_NAME" || die "qBittorrent 服务未运行"
systemctl is-active --quiet caddy || die "Caddy 服务未运行"
ss -lntup | grep -Eq ":${PEER_PORT}[[:space:]]" || die "未发现 BT 监听端口 ${PEER_PORT}"

webui_listeners="$(ss -H -lntp | awk -v suffix=":${WEBUI_PORT}" '$4 ~ suffix"$" {print $4}')"
[[ -n "$webui_listeners" ]] || die "未发现 WebUI 监听端口 ${WEBUI_PORT}"
if printf '%s\n' "$webui_listeners" \
    | grep -qvE "^(127\\.0\\.0\\.1|\\[::1\\]):${WEBUI_PORT}$"; then
  die "WebUI 不仅监听回环地址，已停止后续操作"
fi

printf '\n\033[1;32m安装完成。\033[0m\n'
cat <<EOF

首次登录：
  地址：https://${DOMAIN}
  凭据：cat ${CREDENTIAL_FILE}

必须继续完成：
  1. 用上面的随机密码登录，并立即改成你自己的强密码。
  2. 按 README 和 qBittorrent 设置清单完成 PT 安全设置。
  3. HTTPS 正常后，可把 Cloudflare 切换成“已代理/小黄云”，SSL/TLS 使用 Full (strict)。
  4. BT 端口 ${PEER_PORT} 不能走 Cloudflare，必须直接连接 VPS 公网 IP。

检查命令：
  systemctl status ${SERVICE_NAME} --no-pager
  systemctl status caddy --no-pager
  ufw status verbose
  ss -lntup | grep -E '${WEBUI_PORT}|${PEER_PORT}'

重要：
  - 不要开放 ${WEBUI_PORT}/tcp 到公网。
  - 不要泄露 .torrent、Tracker URL、Cookie 或 passkey。
  - 第二台 VPS 添加同一 PT 站种子前，先确认站点是否允许多 IP/多客户端。
EOF

if ! getent ahostsv4 "$DOMAIN" >/dev/null 2>&1; then
  warn "当前查不到 ${DOMAIN} 的 IPv4 解析。Caddy 会自动重试证书申请，请先完成 DNS。"
elif ! curl -fsSI --max-time 10 "https://${DOMAIN}" >/dev/null 2>&1; then
  warn "HTTPS 暂不可达，常见原因是 DNS 尚未生效；完成 DNS 后运行 systemctl restart caddy。"
else
  log "HTTPS 检查通过：https://${DOMAIN}"
fi
