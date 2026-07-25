#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.1.0"
REPOSITORY="elonjack/debian-pt-seedbox"
INSTALL_SHA256="f6cfb423cf098464c2eff17f99ab095b5665f6f27266aee9a05ef82be79c1b09"
BASE_URL="https://github.com/${REPOSITORY}/releases/download/v${VERSION}"

die() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || die "请切换到 root 后再执行一行安装命令"
command -v sha256sum >/dev/null 2>&1 || die "系统缺少 sha256sum"

temp_dir="$(mktemp -d /tmp/debian-pt-seedbox.XXXXXX)"
trap 'rm -rf -- "$temp_dir"' EXIT
installer="${temp_dir}/install.sh"

printf '下载固定版本 v%s 安装脚本...\n' "$VERSION"
if command -v curl >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -fsSLo "$installer" "${BASE_URL}/install.sh"
elif command -v wget >/dev/null 2>&1; then
  wget --https-only -qO "$installer" "${BASE_URL}/install.sh"
else
  die "系统没有 curl 或 wget。请先执行：apt-get update && apt-get install -y curl ca-certificates"
fi

printf '%s  %s\n' "$INSTALL_SHA256" "$installer" | sha256sum --check --status - \
  || die "安装脚本 SHA-256 校验失败，已停止执行"

printf 'SHA-256 校验通过，开始安装。\n'
bash "$installer" "$@"
