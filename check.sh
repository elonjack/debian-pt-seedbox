#!/usr/bin/env bash
set -u

SERVICE_NAME="qbittorrent-pt.service"
CONFIG_FILE="/etc/qbt-seedbox.conf"

if [[ "${EUID}" -ne 0 ]]; then
  echo "请使用 root 运行：sudo bash check.sh"
  exit 1
fi

if [[ -r "$CONFIG_FILE" ]]; then
  # 文件仅由本仓库安装脚本生成，只包含非敏感的端口和路径。
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
else
  DOMAIN="未记录"
  WEBUI_PORT="8080"
  PEER_PORT="49160"
fi

echo "=== 系统 ==="
sed -n 's/^PRETTY_NAME=//p' /etc/os-release
uname -m
free -h
df -h /
swapon --show

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
echo "=== 最近日志（不会显示 Tracker/passkey）==="
journalctl -u "$SERVICE_NAME" -n 15 --no-pager \
  | sed -E \
      -e 's#(passkey|authkey|torrent_pass)=[^&[:space:]]+#\1=REDACTED#gI' \
      -e 's#(temporary password[^:]*:)[[:space:]]*.*#\1 REDACTED#I'
