#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.2.0"
REPOSITORY="elonjack/debian-pt-seedbox"
INSTALL_SHA256="1645b9af1e9669d5bbe43d59250dab4dd8346b036f01e0e146db2fccf57cdd5b"
BASE_URL="https://github.com/${REPOSITORY}/releases/download/v${VERSION}"

die() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || die "请切换到 root 后再执行一行安装命令"
command -v sha256sum >/dev/null 2>&1 || die "系统缺少 sha256sum"

has_domain="false"
for argument in "$@"; do
  if [[ "$argument" == "--domain" ]]; then
    has_domain="true"
    break
  fi
done

if [[ "$has_domain" != "true" ]]; then
  [[ -t 0 ]] || die "非交互运行必须明确指定：--domain 你的完整子域名"
  printf '请输入这台 VPS 使用的完整 WebUI 子域名（例如 qbt2.example.com）：'
  if ! read -r domain; then
    die "没有读到域名"
  fi
  [[ -n "$domain" ]] || die "域名不能为空"
  set -- --domain "$domain" "$@"
fi

temp_dir="$(mktemp -d /tmp/debian-pt-seedbox.XXXXXX)"
trap 'rm -rf -- "$temp_dir"' EXIT
installer="${temp_dir}/install.sh"

printf '下载固定版本 v%s 安装脚本...\n' "$VERSION"
if command -v curl >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -fsSLo "$installer" "${BASE_URL}/install.sh"
elif command -v wget >/dev/null 2>&1; then
  wget --https-only -qO "$installer" "${BASE_URL}/install.sh"
else
  die "系统没有 curl 或 wget；请先安装 curl 和 ca-certificates"
fi

printf '%s  %s\n' "$INSTALL_SHA256" "$installer" | sha256sum --check --status - \
  || die "安装脚本 SHA-256 校验失败，已停止执行"

printf 'SHA-256 校验通过，开始安装。\n'
bash "$installer" "$@"
