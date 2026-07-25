#!/usr/bin/env bash
set -u

SERVICE_NAME="qbittorrent-pt.service"
CONFIG_FILE="/etc/qbt-seedbox.conf"
DOMAIN="未记录"
WEBUI_PORT="8080"
PEER_PORT="49160"

if [[ "${EUID}" -ne 0 ]]; then
  echo "请使用 root 运行：sudo bash check.sh"
  exit 1
fi

read_config_value() {
  local key="$1"
  local value
  [[ -r "$CONFIG_FILE" ]] || return 0
  value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$CONFIG_FILE")"
  printf '%s' "$value"
}

configured_domain="$(read_config_value DOMAIN)"
configured_webui_port="$(read_config_value WEBUI_PORT)"
configured_peer_port="$(read_config_value PEER_PORT)"
DOMAIN="${configured_domain:-$DOMAIN}"
WEBUI_PORT="${configured_webui_port:-$WEBUI_PORT}"
PEER_PORT="${configured_peer_port:-$PEER_PORT}"

echo "=== 系统 ==="
sed -n 's/^PRETTY_NAME=//p' /etc/os-release
uname -m
free -h
df -h /
swapon --show

echo
echo "=== 软件版本 ==="
qbittorrent-nox --version 2>/dev/null || true
caddy version 2>/dev/null || true

echo
echo "=== 服务 ==="
systemctl is-active "$SERVICE_NAME" 2>/dev/null || true
systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true
systemctl is-active caddy 2>/dev/null || true
systemctl is-enabled caddy 2>/dev/null || true

echo
echo "=== 监听端口 ==="
ss -lntup | grep -E ":(${WEBUI_PORT}|${PEER_PORT}|80|443)[[:space:]]" || true

echo
echo "=== 防火墙 ==="
ufw status verbose

echo
echo "=== DNS / HTTPS ==="
echo "域名：${DOMAIN}"
if [[ "$DOMAIN" != "未记录" ]]; then
  getent ahostsv4 "$DOMAIN" || true
  curl -fsSI --max-time 10 "https://${DOMAIN}" | sed -n '1,8p' || true
fi

echo
echo "=== 最近日志（隐藏密码和常见 passkey 参数）==="
journalctl -u "$SERVICE_NAME" -n 20 --no-pager \
  | sed -E \
      -e 's#(passkey|authkey|torrent_pass)=[^&[:space:]]+#\1=REDACTED#gI' \
      -e 's#(temporary password[^:]*:)[[:space:]]*.*#\1 REDACTED#I'
