#!/usr/bin/env bash
set -Eeuo pipefail

[[ -f /.dockerenv ]] || {
  echo "此测试只能在一次性 Docker 容器中运行。" >&2
  exit 1
}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  qbittorrent-nox \
  caddy \
  ufw \
  curl \
  ca-certificates \
  iproute2

test_user="qbt-test"
test_home="/tmp/qbt-test-home"
webui_port="18080"
peer_port="49161"
cookie_file="/tmp/qbt-test-cookie"
log_file="/tmp/qbt-test.log"

useradd --system --user-group --home-dir "$test_home" "$test_user"
install -d -o "$test_user" -g "$test_user" -m 0750 \
  "$test_home/.config/qBittorrent"
cat > "$test_home/.config/qBittorrent/qBittorrent.conf" <<EOF
[Preferences]
Connection\\PortRangeMin=${peer_port}
WebUI\\Address=127.0.0.1
WebUI\\Port=${webui_port}
WebUI\\UPnP=false
EOF
chown -R "$test_user:$test_user" "$test_home"
chmod 0600 "$test_home/.config/qBittorrent/qBittorrent.conf"

setsid runuser -u "$test_user" -- \
  env HOME="$test_home" LANG=C.UTF-8 \
  qbittorrent-nox --confirm-legal-notice --webui-port="$webui_port" \
  >"$log_file" 2>&1 &
process_group="$!"

cleanup() {
  kill -- "-${process_group}" >/dev/null 2>&1 || true
  wait "$process_group" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ready="false"
for _ in {1..30}; do
  if curl -fsS --max-time 2 "http://127.0.0.1:${webui_port}/" >/dev/null 2>&1; then
    ready="true"
    break
  fi
  sleep 1
done
[[ "$ready" == "true" ]] || {
  cat "$log_file"
  echo "qBittorrent WebUI 未启动" >&2
  exit 1
}

listeners="$(ss -H -lnt | awk -v suffix=":${webui_port}" '$4 ~ suffix"$" {print $4}')"
[[ -n "$listeners" ]]
if printf '%s\n' "$listeners" \
    | grep -qvE "^(127\\.0\\.0\\.1|\\[::1\\]):${webui_port}$"; then
  printf 'WebUI 监听地址不安全：\n%s\n' "$listeners" >&2
  exit 1
fi

temporary_password="$(sed -nE \
  's/.*temporary password[^:]*:[[:space:]]*(.+)$/\1/p' \
  "$log_file" | tail -n 1)"
referer="http://127.0.0.1:${webui_port}"
authenticated="false"

for candidate in "$temporary_password" "adminadmin"; do
  [[ -n "$candidate" ]] || continue
  result="$(printf '%s' "$candidate" \
    | curl -sS -c "$cookie_file" \
      -H "Referer: ${referer}" \
      --data-urlencode "username=admin" \
      --data-urlencode "password@-" \
      "${referer}/api/v2/auth/login" || true)"
  if [[ "$result" == "Ok." ]]; then
    authenticated="true"
    break
  fi
done
[[ "$authenticated" == "true" ]]

test_password="compatibility-test-password-2026"
preferences="$(printf \
  '{"listen_port":%s,"random_port":false,"upnp":false,"dht":false,"pex":false,"lsd":false,"add_trackers_enabled":false,"web_ui_upnp":false,"bypass_local_auth":false,"bypass_auth_subnet_whitelist_enabled":false,"web_ui_csrf_protection_enabled":true,"web_ui_clickjacking_protection_enabled":true,"web_ui_host_header_validation_enabled":true,"web_ui_secure_cookie_enabled":true,"web_ui_domain_list":"qbt.example.com;127.0.0.1","use_https":false,"web_ui_username":"admin","web_ui_password":"%s"}' \
  "$peer_port" "$test_password")"
printf '%s' "$preferences" \
  | curl -fsS -b "$cookie_file" \
    -H "Referer: ${referer}" \
    --data-urlencode "json@-" \
    "${referer}/api/v2/app/setPreferences" >/dev/null

rm -f -- "$cookie_file"
result="$(printf '%s' "$test_password" \
  | curl -sS -c "$cookie_file" \
    -H "Referer: ${referer}" \
    --data-urlencode "username=admin" \
    --data-urlencode "password@-" \
    "${referer}/api/v2/auth/login" || true)"
[[ "$result" == "Ok." ]]

peer_ready="false"
for _ in {1..10}; do
  if ss -H -lntup | grep -Eq ":${peer_port}[[:space:]]"; then
    peer_ready="true"
    break
  fi
  sleep 1
done
[[ "$peer_ready" == "true" ]]

qbittorrent-nox --version
caddy version
echo "Debian qBittorrent/Caddy 兼容性测试通过。"
