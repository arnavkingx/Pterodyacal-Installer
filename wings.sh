#!/usr/bin/env bash
set -u
VERSION="1.0.0"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; M='\033[0;35m'; W='\033[1;37m'; N='\033[0m'
banner(){ clear 2>/dev/null || true; echo -e "${C}╔══════════════════════════════════════════════════╗${N}"; echo -e "${C}║${W}                     APNELY                     ${C}║${N}"; echo -e "${C}║${M}                    WINGS                        ${C}║${N}"; echo -e "${C}║${W}              MADE BY ARNAV SHARMA             ${C}║${N}"; echo -e "${C}╚══════════════════════════════════════════════════╝${N}"; echo; }
ok(){  echo -e "${G}✓${N} $1"; }; bad(){  echo -e "${R}✗${N} $1"; }; warn(){  echo -e "${Y}!${N} $1"; }; pause(){  read -r -p 'Press Enter to continue...' _; }
root(){  [ "$(id -u)" -eq 0 ] || { bad 'Run as root.'; exit 1; }; }
install(){  banner; echo 'Wings installation'; echo; . /etc/os-release 2>/dev/null || true; case "${ID:-}" in ubuntu|debian) ;; *) bad 'Ubuntu/Debian required'; pause; return;; esac
case "$(uname -m)" in x86_64|amd64) arch=amd64;; aarch64|arm64) arch=arm64;; *) bad 'Unsupported architecture'; pause; return;; esac
export DEBIAN_FRONTEND=noninteractive; apt-get update || true; apt-get install -y curl ca-certificates gnupg jq >/dev/null || { bad 'Dependencies failed'; pause; return; }
if ! command -v docker >/dev/null 2>&1; then curl -fsSL https://get.docker.com | sh || { bad 'Docker install failed'; pause; return; }; fi
systemctl enable --now docker
mkdir -p /etc/pterodactyl
local_tmp=$(mktemp /tmp/apnely-wings.XXXXXX)
if ! curl -fL --retry 3 -o "$local_tmp" "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${arch}"; then rm -f "$local_tmp"; bad 'Wings download failed'; pause; return; fi
chmod 755 "$local_tmp"; systemctl stop wings 2>/dev/null || true; pkill -x wings 2>/dev/null || true
install -m 0755 "$local_tmp" /usr/local/bin/wings; rm -f "$local_tmp"
cat > /etc/systemd/system/wings.service <<'UNIT'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable wings; if [ -f /etc/pterodactyl/config.yml ]; then systemctl restart wings; else warn 'config.yml not found; add the node config from your Panel before starting Wings.'; fi
ok 'Wings installed'; pause; }
uninstall(){   banner; read -r -p 'Remove Wings binary/service? [y/N]: ' a; case "$a" in y|Y) systemctl stop wings 2>/dev/null || true; systemctl disable wings 2>/dev/null || true; rm -f /usr/local/bin/wings /etc/systemd/system/wings.service; systemctl daemon-reload; ok 'Wings removed';; esac; pause; }
status(){  banner; systemctl status wings --no-pager || true; pause; }; restart(){  banner; systemctl restart wings && ok 'Wings restarted' || bad 'Wings failed'; pause; }
menu(){  root; while true; do banner; echo '[1] Install Wings'; echo '[2] Uninstall Wings'; echo '[3] Restart Wings'; echo '[4] Wings Status'; echo '[5] Back'; read -r -p 'Select: ' c; case "$c" in 1) install;;2) uninstall;;3) restart;;4) status;;5) return;;*) bad 'Invalid option';;esac; done; }; menu
