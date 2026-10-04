#!/usr/bin/env bash
set -u

VERSION="4.0.0"
AUTHOR="ARNAV SHARMA"
PANEL_DIR="/var/www/pterodactyl"
PTERO_ENV_BACKUP="/root/apnely-pterodactyl-db.txt"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; GRAY='\033[0;90m'; RESET='\033[0m'

banner() {
  clear 2>/dev/null || true
  echo
  echo -e "${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}║${WHITE}                     APNELY                     ${CYAN}║${RESET}"
  echo -e "${CYAN}║${MAGENTA}             PTERODACTYL INSTALLER             ${CYAN}║${RESET}"
  echo -e "${CYAN}║${WHITE}              MADE BY ARNAV SHARMA             ${CYAN}║${RESET}"
  echo -e "${CYAN}║${GRAY}                 Version ${VERSION}                ${CYAN}║${RESET}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
  echo
}
line(){ echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
ok(){ echo -e "${GREEN}✓${RESET} $1"; }
bad(){ echo -e "${RED}✗${RESET} $1"; }
warn(){ echo -e "${YELLOW}!${RESET} $1"; }
info(){ echo -e "${BLUE}➜${RESET} $1"; }
pause(){ echo; read -r -p "Press Enter to continue..." _; }

root_check() {
  [ "$(id -u)" -eq 0 ] || { bad "Run as root."; exit 1; }
}
os_check() {
  . /etc/os-release
  case "$ID" in
    ubuntu)
      case "$VERSION_ID" in 22.04|24.04) ok "$PRETTY_NAME detected";; *) warn "Ubuntu $VERSION_ID is not the primary tested release.";; esac ;;
    debian) ok "$PRETTY_NAME detected";;
    *) bad "Only Ubuntu/Debian are supported."; return 1;;
  esac
}
apt_base() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update || warn "APT update reported errors."
  apt-get install -y curl wget ca-certificates gnupg lsb-release \
    software-properties-common git unzip tar sudo openssl jq mariadb-client
}

install_php83() {
  info "Installing PHP 8.3..."
  add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true
  apt-get update
  apt-get install -y php8.3 php8.3-cli php8.3-common php8.3-gd php8.3-mysql \
    php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl \
    php8.3-zip php8.3-opcache php8.3-tokenizer
  update-alternatives --set php /usr/bin/php8.3 2>/dev/null || true
  systemctl enable --now php8.3-fpm
  php -v | head -1
}

install_database() {
  info "Installing MariaDB..."
  apt-get install -y mariadb-server
  systemctl enable --now mariadb
  systemctl is-active --quiet mariadb && ok "MariaDB is running" || { bad "MariaDB failed"; return 1; }
}

install_redis() {
  info "Installing Redis..."
  apt-get install -y redis-server
  systemctl enable --now redis-server 2>/dev/null || systemctl enable --now redis
  if systemctl is-active --quiet redis-server || systemctl is-active --quiet redis; then
    ok "Redis is running"
  else
    bad "Redis failed to start"; return 1
  fi
}

install_composer() {
  if command -v composer >/dev/null 2>&1; then
    composer self-update --2 >/dev/null 2>&1 || true
    ok "Composer already installed"
    return
  fi
  info "Installing Composer 2..."
  curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
  php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
  rm -f /tmp/composer-setup.php
  composer --version
}

install_nginx_pkg() {
  apt-get install -y nginx
  systemctl enable --now nginx
}

create_panel_database() {
  DB_PASS="$(openssl rand -hex 20)"
  DB_NAME="panel"
  DB_USER="pterodactyl"

  mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

  cat > "$PTERO_ENV_BACKUP" <<EOF
APNELY Pterodactyl database credentials
=======================================
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}

KEEP THIS FILE PRIVATE.
EOF
  chmod 600 "$PTERO_ENV_BACKUP"
  ok "Panel database created"
  info "Database credentials saved to ${PTERO_ENV_BACKUP}"
}

download_panel() {
  if [ -f "$PANEL_DIR/artisan" ]; then
    warn "Pterodactyl Panel already exists at $PANEL_DIR"
    read -r -p "Continue without replacing existing files? [Y/n]: " a
    case "$a" in n|N) return 1;; esac
    return 0
  fi

  mkdir -p "$PANEL_DIR"
  cd "$PANEL_DIR"
  info "Downloading latest Pterodactyl Panel..."
  curl -fL --retry 3 -o panel.tar.gz \
    https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
  tar -xzf panel.tar.gz
  rm -f panel.tar.gz
  chmod -R 755 storage bootstrap/cache
  ok "Panel files downloaded"
}

composer_install() {
  cd "$PANEL_DIR"
  cp -n .env.example .env
  info "Installing PHP dependencies..."
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  php artisan key:generate --force
}

configure_panel_interactive() {
  cd "$PANEL_DIR"
  echo
  line
  echo -e "${WHITE}PTERODACTYL ENVIRONMENT SETUP${RESET}"
  line
  echo
  info "Pterodactyl will now ask for the Panel URL, timezone, cache, session, queue and Redis settings."
  info "For the database prompts use:"
  echo "  Host: 127.0.0.1"
  echo "  Port: 3306"
  echo "  Database: panel"
  echo "  Username: pterodactyl"
  echo "  Password: see ${PTERO_ENV_BACKUP}"
  echo
  php artisan p:environment:setup
  php artisan p:environment:database
}

migrate_panel() {
  cd "$PANEL_DIR"
  php artisan migrate --seed --force
}

create_nginx_config() {
  local server_name="$1"
  cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${server_name};

    root ${PANEL_DIR}/public;
    index index.php;

    client_max_body_size 100m;

    access_log /var/log/nginx/pterodactyl-access.log;
    error_log /var/log/nginx/pterodactyl-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
  ln -sfn /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t || return 1
  systemctl reload nginx
}

permissions() {
  chown -R www-data:www-data "$PANEL_DIR"
  chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
}

queue_service() {
  cat > /etc/systemd/system/pteroq.service <<'EOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now pteroq.service
}

cron_setup() {
  local cron_line="* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1"
  (crontab -l 2>/dev/null | grep -Fv "${PANEL_DIR}/artisan schedule:run" || true; echo "$cron_line") | crontab -
}

panel_install() {
  banner
  echo -e "${WHITE}PTERODACTYL PANEL INSTALLATION${RESET}"
  line
  echo

  [ -f "$PANEL_DIR/artisan" ] && {
    warn "A Panel installation already exists."
    echo "Use Panel Repair/Status instead of reinstalling over it."
    pause
    return
  }

  os_check || { pause; return; }
  apt_base || { bad "Base packages failed"; pause; return; }
  install_php83 || { bad "PHP installation failed"; pause; return; }
  install_database || { pause; return; }
  install_redis || { pause; return; }
  install_composer || { pause; return; }
  install_nginx_pkg || { pause; return; }

  create_panel_database || { bad "Database setup failed"; pause; return; }
  download_panel || { pause; return; }
  composer_install || { bad "Composer install failed"; pause; return; }

  configure_panel_interactive || { bad "Environment setup failed"; pause; return; }
  migrate_panel || { bad "Database migration failed"; pause; return; }

  echo
  line
  echo -e "${WHITE}CREATE ADMIN USER${RESET}"
  line
  cd "$PANEL_DIR"
  php artisan p:user:make || { bad "Admin user creation failed"; pause; return; }

  echo
  read -r -p "Enter Panel domain or IP for Nginx [default: _]: " SERVER_NAME
  SERVER_NAME="${SERVER_NAME:-_}"
  create_nginx_config "$SERVER_NAME" || { bad "Nginx configuration failed"; pause; return; }

  permissions
  queue_service
  cron_setup

  echo
  line
  ok "PTERODACTYL PANEL INSTALLATION COMPLETE"
  ok "Queue worker enabled"
  ok "Cron configured"
  ok "Nginx configured"
  echo
  warn "Database credentials are stored in: $PTERO_ENV_BACKUP"
  info "Now open your Panel URL and log in with the admin account you created."
  info "For HTTPS, use Certbot / SSL from the APNELY menu."
  line
  pause
}

panel_status() {
  banner
  echo -e "${WHITE}PTERODACTYL PANEL STATUS${RESET}"
  line
  echo
  [ -f "$PANEL_DIR/artisan" ] && ok "Panel files: installed" || warn "Panel files: missing"
  command -v php >/dev/null && php -v | head -1
  systemctl is-active --quiet php8.3-fpm && ok "PHP-FPM: active" || warn "PHP-FPM: inactive"
  systemctl is-active --quiet mariadb && ok "MariaDB: active" || warn "MariaDB: inactive"
  systemctl is-active --quiet redis-server && ok "Redis: active" || warn "Redis: inactive"
  systemctl is-active --quiet nginx && ok "Nginx: active" || warn "Nginx: inactive"
  systemctl is-active --quiet pteroq && ok "Queue worker: active" || warn "Queue worker: inactive"
  pause
}

panel_repair() {
  banner
  echo -e "${WHITE}PTERODACTYL PANEL REPAIR${RESET}"
  line
  echo
  [ -f "$PANEL_DIR/artisan" ] || { bad "Panel is not installed."; pause; return; }
  cd "$PANEL_DIR"
  composer install --no-dev --optimize-autoloader || true
  php artisan optimize:clear || true
  chown -R www-data:www-data "$PANEL_DIR"
  chmod -R 755 storage bootstrap/cache
  systemctl restart php8.3-fpm nginx pteroq 2>/dev/null || true
  cron_setup
  ok "Panel repair tasks completed"
  pause
}

panel_uninstall() {
  banner
  echo -e "${WHITE}PANEL UNINSTALL${RESET}"
  line
  echo
  warn "This removes the Panel files and Nginx/queue configuration."
  warn "The MariaDB database is NOT automatically deleted."
  read -r -p "Type DELETE to continue: " a
  [ "$a" = "DELETE" ] || { info "Cancelled."; return; }
  systemctl disable --now pteroq 2>/dev/null || true
  rm -f /etc/systemd/system/pteroq.service
  rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
  systemctl daemon-reload
  systemctl reload nginx 2>/dev/null || true
  rm -rf "$PANEL_DIR"
  ok "Panel files removed; database was kept"
  pause
}

wings_status(){ banner; systemctl status wings --no-pager || true; pause; }
nginx_status(){ banner; systemctl status nginx --no-pager || true; pause; }
ssl_generate(){ banner; command -v certbot >/dev/null || apt-get install -y certbot python3-certbot-nginx; read -r -p "Enter domain: " d; [ -n "$d" ] && certbot --nginx -d "$d"; pause; }
ssl_install(){ banner; apt-get update; apt-get install -y certbot python3-certbot-nginx; ok "Certbot installed"; pause; }
ssl_renew(){ banner; certbot renew; pause; }

wings_install() {
  banner
  echo -e "${WHITE}WINGS INSTALLATION${RESET}"
  line
  echo
  os_check || { pause; return; }
  apt_base
  apt-get install -y docker.io
  systemctl enable --now docker
  mkdir -p /etc/pterodactyl
  local arch tmp
  case "$(uname -m)" in x86_64|amd64) arch=amd64;; aarch64|arm64) arch=arm64;; *) bad "Unsupported architecture"; pause; return;; esac
  tmp="$(mktemp /tmp/apnely-wings.XXXXXX)"
  curl -fL --retry 3 -o "$tmp" "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${arch}" || { rm -f "$tmp"; bad "Wings download failed"; pause; return; }
  chmod 755 "$tmp"
  systemctl stop wings 2>/dev/null || true
  install -m 0755 "$tmp" /usr/local/bin/wings
  rm -f "$tmp"
  cat > /etc/systemd/system/wings.service <<'EOF'
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
EOF
  systemctl daemon-reload
  systemctl enable wings
  ok "Wings installed"
  if [ -f /etc/pterodactyl/config.yml ]; then systemctl restart wings; else warn "config.yml missing; create the node in Panel first."; fi
  pause
}

wings_menu(){
  while true; do
    banner; echo -e "${WHITE}WINGS${RESET}"; line; echo
    echo "  [1] Install Wings"; echo "  [2] Restart Wings"; echo "  [3] Wings Status"; echo "  [4] Back"; echo
    read -r -p "Select [1-4]: " c
    case "$c" in 1) wings_install;; 2) systemctl restart wings; pause;; 3) wings_status;; 4) return;; *) bad "Invalid option";; esac
  done
}

nginx_menu(){
  while true; do
    banner; echo -e "${WHITE}NGINX${RESET}"; line; echo
    echo "  [1] Install Nginx"; echo "  [2] Restart Nginx"; echo "  [3] Nginx Status"; echo "  [4] Back"; echo
    read -r -p "Select [1-4]: " c
    case "$c" in 1) apt-get update; apt-get install -y nginx; systemctl enable --now nginx; pause;; 2) systemctl restart nginx; pause;; 3) nginx_status;; 4) return;; *) bad "Invalid option";; esac
  done
}

ssl_menu(){
  while true; do
    banner; echo -e "${WHITE}CERTBOT / SSL${RESET}"; line; echo
    echo "  [1] Install Certbot"; echo "  [2] Generate SSL"; echo "  [3] Renew SSL"; echo "  [4] Back"; echo
    read -r -p "Select [1-4]: " c
    case "$c" in 1) ssl_install;; 2) ssl_generate;; 3) ssl_renew;; 4) return;; *) bad "Invalid option";; esac
  done
}

panel_menu(){
  while true; do
    banner; echo -e "${WHITE}PTERODACTYL PANEL${RESET}"; line; echo
    echo "  [1] Install Panel"; echo "  [2] Uninstall Panel"; echo "  [3] Repair Panel"; echo "  [4] Panel Status"; echo "  [5] Back"; echo
    read -r -p "Select [1-5]: " c
    case "$c" in 1) panel_install;; 2) panel_uninstall;; 3) panel_repair;; 4) panel_status;; 5) return;; *) bad "Invalid option";; esac
  done
}

system_menu(){
  while true; do
    banner; echo -e "${WHITE}SYSTEM TOOLS${RESET}"; line; echo
    echo "  [1] System Information"; echo "  [2] Docker Status"; echo "  [3] Disk Usage"; echo "  [4] Memory Usage"; echo "  [5] Back"; echo
    read -r -p "Select [1-5]: " c
    case "$c" in
      1) banner; . /etc/os-release; echo "OS: $PRETTY_NAME"; echo "Kernel: $(uname -r)"; echo "Arch: $(uname -m)"; pause;;
      2) banner; systemctl status docker --no-pager || true; pause;;
      3) banner; df -h; pause;;
      4) banner; free -h; pause;;
      5) return;;
      *) bad "Invalid option";;
    esac
  done
}

main(){
  root_check
  os_check || exit 1
  while true; do
    banner; echo -e "${WHITE}MAIN MENU${RESET}"; line; echo
    echo "  [1] Pterodactyl Panel"
    echo "  [2] Wings"
    echo "  [3] Nginx"
    echo "  [4] Certbot / SSL"
    echo "  [5] System Tools"
    echo "  [6] Exit"
    echo; line
    read -r -p "Select option [1-6]: " c
    case "$c" in 1) panel_menu;; 2) wings_menu;; 3) nginx_menu;; 4) ssl_menu;; 5) system_menu;; 6) clear; exit 0;; *) bad "Invalid option";; esac
  done
}
main
