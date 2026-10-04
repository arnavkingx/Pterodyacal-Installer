#!/usr/bin/env bash

# ============================================================
#                    APNELY INSTALLER
#                 PTERODACTYL INSTALLER
#                 MADE BY ARNAV SHARMA
# ============================================================

set -u

VERSION="3.0.0"
AUTHOR="ARNAV SHARMA"

# -------------------- COLORS --------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
RESET='\033[0m'

# -------------------- UI ------------------------

clear_screen() {
    clear 2>/dev/null || true
}

line() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

success() {
    echo -e "${GREEN}✓${RESET} $1"
}

error() {
    echo -e "${RED}✗${RESET} $1"
}

warning() {
    echo -e "${YELLOW}!${RESET} $1"
}

info() {
    echo -e "${BLUE}➜${RESET} $1"
}

pause_screen() {
    echo
    read -r -p "Press Enter to continue..." _
}

banner() {
    clear_screen

    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${WHITE}                     APNELY                     ${CYAN}║${RESET}"
    echo -e "${CYAN}║${MAGENTA}             PTERODACTYL INSTALLER             ${CYAN}║${RESET}"
    echo -e "${CYAN}║${GRAY}              MADE BY ARNAV SHARMA             ${CYAN}║${RESET}"
    echo -e "${CYAN}║${GRAY}                 Version ${VERSION}                ${CYAN}║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
    echo
}

loading() {
    local message="$1"

    echo -ne "${CYAN}${message}${RESET}"

    for _ in 1 2 3; do
        echo -ne "${YELLOW}.${RESET}"
        sleep 0.25
    done

    echo
}

startup() {
    clear_screen

    echo
    echo -e "${MAGENTA}"
    echo "              ███████████████████"
    echo "              █     APNELY      █"
    echo "              ███████████████████"
    echo -e "${RESET}"

    echo
    echo -e "${WHITE}          PTERODACTYL INSTALLER${RESET}"
    echo -e "${MAGENTA}           MADE BY ARNAV SHARMA${RESET}"
    echo

    loading "Starting installer"
    loading "Checking environment"
    loading "Loading modules"

    sleep 0.5
}

# -------------------- ROOT ----------------------

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This installer must be run as root."
        echo
        echo "Use:"
        echo "  sudo bash install.sh"
        exit 1
    fi
}

# -------------------- OS ------------------------

check_os() {
    if [ ! -f /etc/os-release ]; then
        error "Cannot detect operating system."
        return 1
    fi

    . /etc/os-release

    case "${ID}" in
        ubuntu|debian)
            success "${PRETTY_NAME} detected"
            ;;
        *)
            error "Unsupported operating system: ${PRETTY_NAME}"
            echo
            echo "Supported:"
            echo "  Ubuntu"
            echo "  Debian"
            return 1
            ;;
    esac
}

# -------------------- APT -----------------------

apt_update() {
    info "Updating APT repositories..."

    if apt-get update; then
        success "APT update completed"
    else
        warning "APT reported a repository error."
        warning "Continuing with available repositories."
    fi
}

# -------------------- DEPENDENCIES ---------------

install_dependencies() {
    info "Installing basic dependencies..."

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        jq \
        unzip \
        tar \
        sudo \
        openssl \
        git

    success "Basic dependencies installed"
}

# -------------------- DOCKER ---------------------

install_docker() {
    echo
    info "Checking Docker..."

    if command -v docker >/dev/null 2>&1; then
        success "Docker is already installed"

        systemctl enable --now docker 2>/dev/null || true

        if systemctl is-active --quiet docker; then
            success "Docker service is running"
        else
            warning "Docker is installed but not running"
        fi

        return 0
    fi

    info "Docker not found. Installing Docker..."

    install -m 0755 -d /etc/apt/keyrings

    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
        curl -fsSL \
            https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc

        chmod a+r /etc/apt/keyrings/docker.asc
    fi

    . /etc/os-release

    DOCKER_OS="ubuntu"

    if [ "${ID}" = "debian" ]; then
        DOCKER_OS="debian"
    fi

    ARCH="$(dpkg --print-architecture)"

    cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_OS} ${VERSION_CODENAME} stable
EOF

    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable --now docker

    if systemctl is-active --quiet docker; then
        success "Docker installed and running"
    else
        warning "Docker installation completed but service is not active"
    fi
}

# ============================================================
#                         WINGS
# ============================================================

get_wings_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            WINGS_ARCH="amd64"
            ;;
        aarch64|arm64)
            WINGS_ARCH="arm64"
            ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac
}

install_wings() {
    banner

    echo -e "${WHITE}                    WINGS INSTALLATION${RESET}"
    line
    echo

    echo -e "${CYAN}[1/7]${RESET} Detecting system..."
    check_os || {
        pause_screen
        return
    }

    get_wings_arch || {
        pause_screen
        return
    }

    success "Architecture: ${WINGS_ARCH}"

    echo
    echo -e "${CYAN}[2/7]${RESET} Updating repositories..."
    apt_update

    echo
    echo -e "${CYAN}[3/7]${RESET} Installing dependencies..."
    install_dependencies

    echo
    echo -e "${CYAN}[4/7]${RESET} Installing/checking Docker..."
    install_docker

    echo
    echo -e "${CYAN}[5/7]${RESET} Downloading Wings..."

    mkdir -p /etc/pterodactyl

    TMP_WINGS="$(mktemp /tmp/apnely-wings.XXXXXX)"

    if curl -fL \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 20 \
        -o "${TMP_WINGS}" \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"; then

        chmod 0755 "${TMP_WINGS}"

        success "Wings downloaded"

    else

        rm -f "${TMP_WINGS}"

        error "Wings download failed"
        pause_screen
        return

    fi

    echo
    info "Stopping old Wings process if present..."

    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true
    pkill -x wings 2>/dev/null || true

    sleep 1

    if install -m 0755 "${TMP_WINGS}" /usr/local/bin/wings; then
        success "Wings binary installed"
    else
        rm -f "${TMP_WINGS}"
        error "Could not install Wings binary"
        pause_screen
        return
    fi

    rm -f "${TMP_WINGS}"

    echo
    echo -e "${CYAN}[6/7]${RESET} Creating Wings service..."

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

    success "Wings systemd service created"

    echo
    echo -e "${CYAN}[7/7]${RESET} Checking configuration..."

    if [ -f /etc/pterodactyl/config.yml ]; then

        info "config.yml found"

        systemctl restart wings
        sleep 2

        if systemctl is-active --quiet wings; then
            success "Wings is running"
        else
            warning "Wings failed to start"
            echo
            echo "Check logs with:"
            echo "  journalctl -u wings -n 50 --no-pager"
        fi

    else

        warning "Wings configuration was not found."
        echo
        echo "Expected:"
        echo "  /etc/pterodactyl/config.yml"
        echo
        info "Wings binary and service are installed."
        info "Create a node in your Pterodactyl Panel and place the generated"
        info "configuration at /etc/pterodactyl/config.yml"

    fi

    echo
    line
    echo -e "${GREEN}                 WINGS INSTALL COMPLETE${RESET}"
    echo -e "${MAGENTA}                  MADE BY ARNAV SHARMA${RESET}"
    line

    pause_screen
}

uninstall_wings() {
    banner

    echo -e "${WHITE}                    UNINSTALL WINGS${RESET}"
    line
    echo

    warning "This removes the Wings binary and service."
    echo
    echo "It will NOT remove:"
    echo "  - Docker"
    echo "  - Docker containers"
    echo "  - /etc/pterodactyl/config.yml"
    echo "  - Pterodactyl Panel"
    echo

    read -r -p "Continue? [y/N]: " answer

    case "${answer}" in
        y|Y|yes|YES)
            ;;
        *)
            info "Cancelled."
            sleep 1
            return
            ;;
    esac

    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true

    pkill -x wings 2>/dev/null || true

    rm -f /usr/local/bin/wings
    rm -f /etc/systemd/system/wings.service

    systemctl daemon-reload
    systemctl reset-failed wings 2>/dev/null || true

    success "Wings removed"

    pause_screen
}

restart_wings() {
    banner

    echo -e "${WHITE}                     RESTART WINGS${RESET}"
    line
    echo

    if [ ! -f /etc/systemd/system/wings.service ]; then
        error "Wings service is not installed."
        pause_screen
        return
    fi

    systemctl restart wings
    sleep 2

    if systemctl is-active --quiet wings; then
        success "Wings restarted successfully"
    else
        error "Wings failed to start"
        echo
        echo "Logs:"
        echo "  journalctl -u wings -n 50 --no-pager"
    fi

    pause_screen
}

wings_status() {
    banner

    echo -e "${WHITE}                      WINGS STATUS${RESET}"
    line
    echo

    if [ ! -f /etc/systemd/system/wings.service ]; then
        warning "Wings service is not installed."
        pause_screen
        return
    fi

    systemctl status wings --no-pager || true

    echo

    if systemctl is-active --quiet wings; then
        success "Wings is ACTIVE"
    else
        warning "Wings is NOT running"
    fi

    pause_screen
}

repair_wings() {
    banner

    echo -e "${WHITE}                      REPAIR WINGS${RESET}"
    line
    echo

    if [ ! -x /usr/local/bin/wings ]; then
        warning "Wings binary is missing."
        echo
        info "Running Wings installation..."
        sleep 1
        install_wings
        return
    fi

    if [ ! -f /etc/systemd/system/wings.service ]; then

        warning "Wings service file is missing."

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

        success "Wings service recreated"

    else
        success "Wings service exists"
    fi

    if [ -f /etc/pterodactyl/config.yml ]; then

        systemctl restart wings
        sleep 2

        if systemctl is-active --quiet wings; then
            success "Wings is running"
        else
            warning "Wings is still not running"
        fi

    else
        warning "config.yml is missing"
    fi

    pause_screen
}

# ============================================================
#                         NGINX
# ============================================================

install_nginx() {
    banner

    echo -e "${WHITE}                     INSTALL NGINX${RESET}"
    line
    echo

    apt_update

    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx

    systemctl enable --now nginx

    if systemctl is-active --quiet nginx; then
        success "Nginx installed and running"
    else
        warning "Nginx installed but is not running"
    fi

    pause_screen
}

uninstall_nginx() {
    banner

    echo -e "${WHITE}                    UNINSTALL NGINX${RESET}"
    line
    echo

    warning "Nginx packages will be removed."
    echo

    read -r -p "Continue? [y/N]: " answer

    case "${answer}" in
        y|Y|yes|YES)
            ;;
        *)
            info "Cancelled."
            sleep 1
            return
            ;;
    esac

    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true

    DEBIAN_FRONTEND=noninteractive apt-get remove -y \
        nginx \
        nginx-common 2>/dev/null || true

    success "Nginx removed"

    pause_screen
}

restart_nginx() {
    banner

    echo -e "${WHITE}                    RESTART NGINX${RESET}"
    line
    echo

    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        success "Nginx restarted"
    else
        error "Nginx failed to restart"
    fi

    pause_screen
}

nginx_status() {
    banner

    echo -e "${WHITE}                     NGINX STATUS${RESET}"
    line
    echo

    systemctl status nginx --no-pager || true

    pause_screen
}

# ============================================================
#                         CERTBOT
# ============================================================

install_certbot() {
    banner

    echo -e "${WHITE}                   INSTALL CERTBOT${RESET}"
    line
    echo

    apt_update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        certbot \
        python3-certbot-nginx

    if command -v certbot >/dev/null 2>&1; then
        success "Certbot installed"
    else
        error "Certbot installation failed"
    fi

    echo
    info "A domain pointing to this server is required to issue SSL."

    pause_screen
}

generate_ssl() {
    banner

    echo -e "${WHITE}                    GENERATE SSL${RESET}"
    line
    echo

    if ! command -v certbot >/dev/null 2>&1; then
        warning "Certbot is not installed."
        echo
        read -r -p "Install Certbot now? [y/N]: " answer

        case "${answer}" in
            y|Y|yes|YES)
                install_certbot
                ;;
            *)
                return
                ;;
        esac
    fi

    echo
    read -r -p "Enter domain: " DOMAIN

    if [ -z "${DOMAIN}" ]; then
        error "Domain cannot be empty."
        pause_screen
        return
    fi

    echo
    info "Requesting SSL certificate for ${DOMAIN}..."
    echo

    certbot --nginx -d "${DOMAIN}"

    pause_screen
}

renew_ssl() {
    banner

    echo -e "${WHITE}                      RENEW SSL${RESET}"
    line
    echo

    if ! command -v certbot >/dev/null 2>&1; then
        error "Certbot is not installed."
        pause_screen
        return
    fi

    certbot renew

    pause_screen
}

certificate_status() {
    banner

    echo -e "${WHITE}                  CERTIFICATE STATUS${RESET}"
    line
    echo

    if ! command -v certbot >/dev/null 2>&1; then
        warning "Certbot is not installed."
    else
        certbot certificates
    fi

    pause_screen
}

# ============================================================
#                         PANEL
# ============================================================

panel_menu() {
    while true; do

        banner

        echo -e "${WHITE}                  PTERODACTYL PANEL${RESET}"
        line
        echo

        echo -e "  ${GREEN}[1]${RESET} Install Panel"
        echo -e "  ${RED}[2]${RESET} Uninstall Panel"
        echo -e "  ${YELLOW}[3]${RESET} Repair Panel"
        echo -e "  ${BLUE}[4]${RESET} Panel Status"
        echo -e "  ${WHITE}[5]${RESET} Back"

        echo
        line
        echo

        read -r -p "Select [1-5]: " choice

        case "${choice}" in

            1)
                banner
                echo -e "${WHITE}                    PANEL INSTALL${RESET}"
                line
                echo
                warning "Panel installer is not enabled in v3.0.0 yet."
                echo
                info "The Panel installer will configure:"
                echo "  PHP 8.2/8.3"
                echo "  MariaDB"
                echo "  Redis"
                echo "  Composer"
                echo "  Node.js"
                echo "  Pterodactyl Panel"
                echo "  Nginx"
                echo "  Queue worker"
                echo "  Cron"
                echo
                warning "No changes were made."
                pause_screen
                ;;

            2)
                banner
                echo -e "${WHITE}                   PANEL UNINSTALL${RESET}"
                line
                echo
                warning "Panel uninstall is disabled for safety."
                warning "This prevents accidental deletion of database data."
                pause_screen
                ;;

            3)
                banner
                echo -e "${WHITE}                    PANEL REPAIR${RESET}"
                line
                echo
                warning "Panel repair is not enabled in v3.0.0 yet."
                pause_screen
                ;;

            4)
                banner
                echo -e "${WHITE}                    PANEL STATUS${RESET}"
                line
                echo

                if [ -d /var/www/pterodactyl ]; then
                    success "Pterodactyl Panel directory exists"
                else
                    warning "Pterodactyl Panel directory not found"
                fi

                if systemctl is-active --quiet nginx; then
                    success "Nginx is running"
                else
                    warning "Nginx is not running"
                fi

                pause_screen
                ;;

            5)
                return
                ;;

            *)
                error "Invalid option."
                sleep 1
                ;;

        esac

    done
}

# ============================================================
#                         WINGS MENU
# ============================================================

wings_menu() {
    while true; do

        banner

        echo -e "${WHITE}                       WINGS${RESET}"
        line
        echo

        echo -e "  ${GREEN}[1]${RESET} Install Wings"
        echo -e "  ${RED}[2]${RESET} Uninstall Wings"
        echo -e "  ${CYAN}[3]${RESET} Restart Wings"
        echo -e "  ${BLUE}[4]${RESET} Wings Status"
        echo -e "  ${YELLOW}[5]${RESET} Repair Wings"
        echo -e "  ${WHITE}[6]${RESET} Back"

        echo
        line
        echo

        read -r -p "Select [1-6]: " choice

        case "${choice}" in
            1) install_wings ;;
            2) uninstall_wings ;;
            3) restart_wings ;;
            4) wings_status ;;
            5) repair_wings ;;
            6) return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac

    done
}

# ============================================================
#                         NGINX MENU
# ============================================================

nginx_menu() {
    while true; do

        banner

        echo -e "${WHITE}                       NGINX${RESET}"
        line
        echo

        echo -e "  ${GREEN}[1]${RESET}
