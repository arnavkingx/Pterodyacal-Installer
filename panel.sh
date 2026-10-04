#!/usr/bin/env bash
set -u
VERSION="1.0.0"
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; M='\033[0;35m'; W='\033[1;37m'; N='\033[0m'
APP="/var/www/pterodactyl"
DB_NAME="panel"
DB_USER="pterodactyl"
DB_PASS_FILE="/root/apnely-pterodactyl-db.txt"

banner(){ clear 2>/dev/null || true; echo; echo -e "${C}╔══════════════════════════════════════════════════╗${N}"; echo -e "${C}║${W}                     APNELY                     ${C}║${N}"; echo -e "${C}║${M}                PTERODACTYL PANEL               ${C}║${N}"; echo -e "${C}║${W}              MADE BY ARNAV SHARMA             ${C}║${N}"; echo -e "${C}║${W}                 Version ${VERSION}                ${C}║${N}"; echo -e "${C}╚══════════════════════════════════════════════════╝${N}"; echo; }
ok(){ echo -e "${G}✓${N} $1"; }; bad(){ echo -e "${R}✗${N} $1"; }; warn(){ echo -e "${Y}!${N} $1"; }; info(){ echo -e "${C}➜${N} $1"; }
pause(){ echo; read -r -p "Press Enter to continue..." _; }
die(){ bad "$1"; exit 1; }

root_check(){ [ "$(id -u)" -eq 0 ] || die "Run as root."; }
os_check(){ . /etc/os-release; [ "$ID" = ubuntu ] && [ "$VERSION_ID" = "22.04" ] || warn "This script is designed for Ubuntu 22.04. Detected: $PRETTY_NAME"; }
apt_base(){ export DEBIAN_FRONTEND=noninteractive; apt-get update || die "APT update failed."; apt-get install -y software-properties-common curl ca-certificates gnupg sudo tar unzip git mariadb-server nginx redis-server; }
php_install(){
  info "Installing PHP 8.3..."
  add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true
  apt-get update || die "APT update failed after PHP repository."
  apt-get install -y php8.3 php8.3-{cli,common,gd,mysql,mbstring,tokenizer,bcmath,xml,fpm,curl,zip,opcache} || die "PHP 8.3 installation failed."
  systemctl enable --now php8.3-fpm
  php -v | head -1
}
composer_install(){
  if command -v composer >/dev/null 2>&1; then composer self-update --2 >/dev/null 2>&1 || true; else
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php || die "Composer download failed."
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer || die "Composer installation failed."
    rm -f /tmp/composer-setup.php
  fi
  composer --version | head -1
}
db_setup(){
  systemctl enable --now mariadb redis-server
  if [ -f "$DB_PASS_FILE" ]; then DB_PASS=$(awk -F= '/^DB_PASSWORD=/{print substr($0,index($0,"=")+1)}' "$DB_PASS_FILE"); fi
  if [ -z "${DB_PASS:-}" ]; then DB_PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24); fi
  mariadb -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  mariadb -e "CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';"
  mariadb -e "ALTER USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';"
  mariadb -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1'; FLUSH PRIVILEGES;"
  umask 077; printf 'DB_NAME=%s\nDB_USER=%s\nDB_PASSWORD=%s\n' "$DB_NAME" "$DB_USER" "$DB_PASS" > "$DB_PASS_FILE"
  ok "Database ready. Credentials saved to $DB_PASS_FILE"
}
download_panel(){
  mkdir -p "$APP"
  if [ -f "$APP/artisan" ]; then die "Pterodactyl Panel already exists at $APP. Refusing to overwrite."; fi
  info "Downloading latest Pterodactyl Panel..."
  tmp=$(mktemp /tmp/pterodactyl.XXXXXX.tar.gz)
  curl -fL --retry 3 -o "$tmp" https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz || { rm -f "$tmp"; die "Panel download failed."; }
  tar -xzf "$tmp" -C "$APP" || { rm -f "$tmp"; die "Panel extraction failed."; }
  rm -f "$tmp"
  cd "$APP"
  cp .env.example .env
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction || die "Composer dependencies failed."
  php artisan key:generate --force || die "App key generation failed."
}
env_setup(){
  cd "$APP"
  php artisan p:environment:setup --url="${PANEL_URL}" --timezone="${PANEL_TZ}" --author="${PANEL_EMAIL}" --telemetry="${PANEL_TELEMETRY}" || die "Environment setup failed."
  php artisan p:environment:database --host=127.0.0.1 --port=3306 --database="$DB_NAME" --username="$DB_USER" --password="$DB_PASS" || die "Database environment setup failed."
}
migrate(){ cd "$APP"; php artisan migrate --seed --force || die "Database migration failed."; }
permissions(){ chown -R www-data:www-data "$APP"; chmod -R 755 "$APP/storage" "$APP/bootstrap/cache"; }
nginx_config(){
  cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${PANEL_DOMAIN};
    root ${APP}/public;
    index index.html index.htm index.php;
    charset utf-8;
    client_max_body_size 100m;
    add_header X-Content-Type-Options nosniff;
    add_header X-Robots-Tag none;
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }
    location ~ /\.ht { deny all; }
}
EOF
  rm -f /etc/nginx/sites-enabled/default
  ln -sfn /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
  nginx -t || die "Nginx configuration test failed."
  systemctl enable --now nginx
  systemctl reload nginx
}
queue_setup(){
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
  systemctl enable --now pteroq
  (crontab -u www-data -l 2>/dev/null | grep -v 'pterodactyl/artisan schedule:run' ; echo '* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1') | crontab -u www-data -
}
install_panel(){
  banner; root_check; os_check
  [ -f "$APP/artisan" ] && { bad "Panel already installed at $APP"; pause; return; }
  echo -e "${W}APNELY PTERODACTYL PANEL INSTALLER${N}"; echo
  read -r -p "Panel domain (e.g. panel.example.com): " PANEL_DOMAIN
  [ -n "$PANEL_DOMAIN" ] || { bad "Domain required."; pause; return; }
  read -r -p "Panel URL [http://$PANEL_DOMAIN]: " PANEL_URL
  PANEL_URL=${PANEL_URL:-http://$PANEL_DOMAIN}
  read -r -p "Timezone [UTC]: " PANEL_TZ; PANEL_TZ=${PANEL_TZ:-UTC}
  read -r -p "Admin email: " PANEL_EMAIL
  [ -n "$PANEL_EMAIL" ] || { bad "Admin email required."; pause; return; }
  read -r -p "Enable anonymous telemetry? [Y/n]: " PANEL_TELEMETRY; PANEL_TELEMETRY=${PANEL_TELEMETRY:-y}
  case "$PANEL_TELEMETRY" in n|N) PANEL_TELEMETRY=0;; *) PANEL_TELEMETRY=1;; esac
  apt_base; php_install; composer_install; db_setup; download_panel; env_setup; migrate
  permissions; nginx_config; queue_setup
  echo
  ok "Pterodactyl Panel installation completed."
  info "Panel URL: $PANEL_URL"
  info "Database credentials: $DB_PASS_FILE"
  info "Create the first admin with: cd $APP && php artisan p:user:make"
  warn "Run Certbot from your APNELY SSL menu after DNS points to this server."
  pause
}
panel_status(){ banner; [ -f "$APP/artisan" ] && ok "Panel files present" || warn "Panel not installed"; systemctl is-active --quiet nginx && ok "Nginx: running" || warn "Nginx: stopped"; systemctl is-active --quiet mariadb && ok "MariaDB: running" || warn "MariaDB: stopped"; systemctl is-active --quiet redis-server && ok "Redis: running" || warn "Redis: stopped"; systemctl is-active --quiet pteroq && ok "Queue: running" || warn "Queue: stopped"; pause; }
panel_repair(){ banner; [ -f "$APP/artisan" ] || { bad "Panel not installed."; pause; return; }; cd "$APP"; COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction; php artisan optimize:clear; permissions; nginx_config; queue_setup; ok "Panel repaired."; pause; }
panel_uninstall(){ banner; warn "This removes Panel files/config and queue service, but keeps MariaDB database."; read -r -p "Type REMOVE to continue: " x; [ "$x" = REMOVE ] || return; systemctl disable --now pteroq 2>/dev/null || true; rm -f /etc/systemd/system/pteroq.service /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf; systemctl daemon-reload; rm -rf "$APP"; ok "Panel files removed. Database was kept."; pause; }
menu(){
 while true; do banner; echo -e "${W}PTERODACTYL PANEL${N}"; echo; echo "  [1] Install Panel"; echo "  [2] Uninstall Panel"; echo "  [3] Repair Panel"; echo "  [4] Panel Status"; echo "  [5] Back"; echo; read -r -p "Select [1-5]: " c; case "$c" in 1) install_panel;; 2) panel_uninstall;; 3) panel_repair;; 4) panel_status;; 5) exit 0;; *) bad "Invalid option";; esac; done
}
root_check; menu
