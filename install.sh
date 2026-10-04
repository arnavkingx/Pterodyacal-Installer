#!/usr/bin/env bash
set -u
VERSION="3.1.0"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; M='\033[0;35m'; W='\033[1;37m'; N='\033[0m'

banner(){ clear 2>/dev/null || true; echo; echo -e "${C}╔══════════════════════════════════════════════════╗${N}"; echo -e "${C}║${W}                     APNELY                     ${C}║${N}"; echo -e "${C}║${M}             PTERODACTYL INSTALLER             ${C}║${N}"; echo -e "${C}║${W}              MADE BY ARNAV SHARMA             ${C}║${N}"; echo -e "${C}║${W}                 Version ${VERSION}                ${C}║${N}"; echo -e "${C}╚══════════════════════════════════════════════════╝${N}"; echo; }
line(){ echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; }
ok(){ echo -e "${G}✓${N} $1"; }; bad(){ echo -e "${R}✗${N} $1"; }; warn(){ echo -e "${Y}!${N} $1"; }; info(){ echo -e "${B}➜${N} $1"; }
pause(){ echo; read -r -p 'Press Enter to continue...' _; }
load(){ echo -ne "${C}$1${N}"; for _ in 1 2 3; do echo -ne "${Y}.${N}"; sleep .2; done; echo; }

root_check(){ [ "$(id -u)" -eq 0 ] || { bad 'Run this installer as root.'; exit 1; }; }
os_check(){ [ -r /etc/os-release ] || return 1; . /etc/os-release; case "$ID" in ubuntu|debian) ok "$PRETTY_NAME detected";; *) bad 'Only Ubuntu/Debian are supported.'; return 1;; esac; }
apt_update(){ info 'Updating APT...'; apt-get update || warn 'APT reported an error; continuing.'; }
base_deps(){ DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget ca-certificates gnupg lsb-release apt-transport-https jq unzip tar sudo openssl git >/dev/null || return 1; ok 'Dependencies ready'; }

docker_install(){
  if command -v docker >/dev/null 2>&1; then systemctl enable --now docker 2>/dev/null || true; systemctl is-active --quiet docker && ok 'Docker is running' || warn 'Docker is not running'; return; fi
  info 'Installing Docker...'; install -d -m 0755 /etc/apt/keyrings
  . /etc/os-release; local os=ubuntu; [ "$ID" = debian ] && os=debian
  curl -fsSL "https://download.docker.com/linux/$os/gpg" -o /etc/apt/keyrings/docker.asc || return 1
  chmod a+r /etc/apt/keyrings/docker.asc; local arch; arch=$(dpkg --print-architecture)
  echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$os $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
  apt-get update || return 1
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
  systemctl enable --now docker; systemctl is-active --quiet docker && ok 'Docker installed' || bad 'Docker failed to start'
}

wings_service(){ cat > /etc/systemd/system/wings.service <<'EOF2'
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
EOF2
}

install_wings(){
  banner; echo -e "${W}WINGS INSTALLATION${N}"; line; echo
  echo -e "${C}[1/7]${N} System"; os_check || { pause; return; }
  case "$(uname -m)" in x86_64|amd64) arch=amd64;; aarch64|arm64) arch=arm64;; *) bad 'Unsupported architecture'; pause; return;; esac; ok "Architecture: $arch"
  echo -e "${C}[2/7]${N} APT"; apt_update
  echo -e "${C}[3/7]${N} Dependencies"; base_deps || { bad 'Dependency installation failed'; pause; return; }
  echo -e "${C}[4/7]${N} Docker"; docker_install || { bad 'Docker installation failed'; pause; return; }
  echo -e "${C}[5/7]${N} Wings binary"; mkdir -p /etc/pterodactyl
  tmp=$(mktemp /tmp/apnely-wings.XXXXXX)
  if ! curl -fL --retry 3 --connect-timeout 20 -o "$tmp" "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$arch"; then rm -f "$tmp"; bad 'Wings download failed'; pause; return; fi
  chmod 755 "$tmp"; systemctl stop wings 2>/dev/null || true; systemctl disable wings 2>/dev/null || true; pkill -x wings 2>/dev/null || true
  install -m 0755 "$tmp" /usr/local/bin/wings || { rm -f "$tmp"; bad 'Wings install failed'; pause; return; }; rm -f "$tmp"; ok 'Wings installed'
  echo -e "${C}[6/7]${N} systemd"; wings_service; systemctl daemon-reload; systemctl enable wings; ok 'Service configured'
  echo -e "${C}[7/7]${N} Configuration"
  if [ -f /etc/pterodactyl/config.yml ]; then systemctl restart wings; sleep 2; systemctl is-active --quiet wings && ok 'Wings is running' || warn 'Wings failed; run journalctl -u wings -n 50 --no-pager'; else warn 'Missing /etc/pterodactyl/config.yml'; info 'Wings is installed. Add the node config from your Panel.'; fi
  line; echo -e "${G}WINGS INSTALL COMPLETE${N}"; echo -e "${M}MADE BY ARNAV SHARMA${N}"; line; pause
}
uninstall_wings(){ banner; echo -e "${W}UNINSTALL WINGS${N}"; line; echo; warn 'Wings binary and service will be removed; Docker/config stay.'; read -r -p 'Continue? [y/N]: ' a; case "$a" in y|Y|yes|YES) ;; *) return;; esac; systemctl stop wings 2>/dev/null || true; systemctl disable wings 2>/dev/null || true; pkill -x wings 2>/dev/null || true; rm -f /usr/local/bin/wings /etc/systemd/system/wings.service; systemctl daemon-reload; ok 'Wings removed'; pause; }
wings_status(){ banner; echo -e "${W}WINGS STATUS${N}"; line; echo; systemctl status wings --no-pager || true; pause; }
wings_restart(){ banner; echo -e "${W}RESTART WINGS${N}"; line; echo; systemctl restart wings; systemctl is-active --quiet wings && ok 'Wings restarted' || bad 'Wings failed'; pause; }
wings_repair(){ banner; echo -e "${W}REPAIR WINGS${N}"; line; echo; [ -x /usr/local/bin/wings ] || { warn 'Wings binary missing'; install_wings; return; }; [ -f /etc/systemd/system/wings.service ] || { wings_service; systemctl daemon-reload; systemctl enable wings; }; [ -f /etc/pterodactyl/config.yml ] && systemctl restart wings || warn 'config.yml missing'; pause; }

nginx_install(){ banner; echo -e "${W}NGINX INSTALL${N}"; line; apt_update; DEBIAN_FRONTEND=noninteractive apt-get install -y nginx; systemctl enable --now nginx; systemctl is-active --quiet nginx && ok 'Nginx is running' || bad 'Nginx failed'; pause; }
nginx_remove(){ banner; echo -e "${W}NGINX UNINSTALL${N}"; line; read -r -p 'Remove Nginx? [y/N]: ' a; case "$a" in y|Y|yes|YES) ;; *) return;; esac; systemctl stop nginx 2>/dev/null || true; DEBIAN_FRONTEND=noninteractive apt-get remove -y nginx nginx-common || true; ok 'Nginx removed'; pause; }
nginx_status(){ banner; systemctl status nginx --no-pager || true; pause; }
nginx_restart(){ banner; systemctl restart nginx; systemctl is-active --quiet nginx && ok 'Nginx restarted' || bad 'Nginx failed'; pause; }

certbot_install(){ banner; echo -e "${W}CERTBOT INSTALL${N}"; line; apt_update; DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-nginx; command -v certbot >/dev/null && ok 'Certbot installed' || bad 'Certbot failed'; pause; }
ssl_generate(){ banner; echo -e "${W}GENERATE SSL${N}"; line; command -v certbot >/dev/null || { certbot_install; }; command -v certbot >/dev/null || return; read -r -p 'Enter domain: ' d; [ -n "$d" ] || { bad 'Domain cannot be empty'; pause; return; }; certbot --nginx -d "$d"; pause; }
ssl_renew(){ banner; certbot renew; pause; }
ssl_status(){ banner; command -v certbot >/dev/null && certbot certificates || warn 'Certbot not installed'; pause; }

panel_menu(){ while true; do banner; echo -e "${W}PTERODACTYL PANEL${N}"; line; echo; echo '  [1] Install Panel'; echo '  [2] Uninstall Panel'; echo '  [3] Repair Panel'; echo '  [4] Panel Status'; echo '  [5] Back'; echo; line; read -r -p 'Select [1-5]: ' c; case "$c" in 1) banner; warn 'Panel installer is not enabled yet. No changes made.'; pause;; 2) banner; warn 'Panel uninstall disabled for safety.'; pause;; 3) banner; warn 'Panel repair not enabled yet.'; pause;; 4) banner; [ -d /var/www/pterodactyl ] && ok 'Panel directory exists' || warn 'Panel directory not found'; pause;; 5) return;; *) bad 'Invalid option';; esac; done; }
wings_menu(){ while true; do banner; echo -e "${W}WINGS${N}"; line; echo; echo '  [1] Install Wings'; echo '  [2] Uninstall Wings'; echo '  [3] Restart Wings'; echo '  [4] Wings Status'; echo '  [5] Repair Wings'; echo '  [6] Back'; echo; line; read -r -p 'Select [1-6]: ' c; case "$c" in 1) install_wings;; 2) uninstall_wings;; 3) wings_restart;; 4) wings_status;; 5) wings_repair;; 6) return;; *) bad 'Invalid option';; esac; done; }
nginx_menu(){ while true; do banner; echo -e "${W}NGINX${N}"; line; echo; echo '  [1] Install Nginx'; echo '  [2] Uninstall Nginx'; echo '  [3] Restart Nginx'; echo '  [4] Nginx Status'; echo '  [5] Back'; echo; line; read -r -p 'Select [1-5]: ' c; case "$c" in 1) nginx_install;; 2) nginx_remove;; 3) nginx_restart;; 4) nginx_status;; 5) return;; *) bad 'Invalid option';; esac; done; }
ssl_menu(){ while true; do banner; echo -e "${W}CERTBOT / SSL${N}"; line; echo; echo '  [1] Install Certbot'; echo '  [2] Generate SSL'; echo '  [3] Renew SSL'; echo '  [4] Certificate Status'; echo '  [5] Back'; echo; line; read -r -p 'Select [1-5]: ' c; case "$c" in 1) certbot_install;; 2) ssl_generate;; 3) ssl_renew;; 4) ssl_status;; 5) return;; *) bad 'Invalid option';; esac; done; }
system_menu(){ while true; do banner; echo -e "${W}SYSTEM TOOLS${N}"; line; echo; echo '  [1] System Information'; echo '  [2] Docker Status'; echo '  [3] Disk Usage'; echo '  [4] Memory Usage'; echo '  [5] Back'; echo; line; read -r -p 'Select [1-5]: ' c; case "$c" in 1) banner; . /etc/os-release; echo "OS: $PRETTY_NAME"; echo "Kernel: $(uname -r)"; echo "Arch: $(uname -m)"; pause;; 2) banner; systemctl status docker --no-pager || true; pause;; 3) banner; df -h; pause;; 4) banner; free -h; pause;; 5) return;; *) bad 'Invalid option';; esac; done; }
main(){ while true; do banner; echo -e "${W}MAIN MENU${N}"; line; echo; echo '  [1] Pterodactyl Panel'; echo '  [2] Wings'; echo '  [3] Nginx'; echo '  [4] Certbot / SSL'; echo '  [5] System Tools'; echo '  [6] Exit'; echo; line; read -r -p 'Select option [1-6]: ' c; case "$c" in 1) panel_menu;; 2) wings_menu;; 3) nginx_menu;; 4) ssl_menu;; 5) system_menu;; 6) clear; echo; echo -e "${M}APNELY - MADE BY ARNAV SHARMA${N}"; exit 0;; *) bad 'Invalid option';; esac; done; }

root_check; load 'Starting APNELY'; load 'Checking environment'; load 'Loading modules'; main
