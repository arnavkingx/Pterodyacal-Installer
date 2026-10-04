#!/usr/bin/env bash

# ============================================================
#                    # FASTER INSTALLER
#                 PTERODACTYL INSTALLER
#                 MADE BY ARNAV SHARMA
# ============================================================

set -u

VERSION="3.0.0"
AUTHOR="ARNAV SHARMA"

# ========================= COLORS ============================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
RESET='\033[0m'

# ========================= GLOBAL ============================

SPINNER_PID=""

# ========================= UI ================================

clear_screen() {
    clear 2>/dev/null || true
}

line() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

banner() {
    clear_screen

    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${WHITE}                    APNELY                      ${CYAN}║${RESET}"
    echo -e "${CYAN}║${MAGENTA}            PTERODACTYL INSTALLER              ${CYAN}║${RESET}"
    echo -e "${CYAN}║${GRAY}             MADE BY ARNAV SHARMA              ${CYAN}║${RESET}"
    echo -e "${CYAN}║${GRAY}                  Version ${VERSION}               ${CYAN}║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
    echo
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
    read -rp "Press Enter to continue..." _
}

loading() {
    local message="$1"

    echo -ne "${CYAN}${message}${RESET} "

    for _ in 1 2 3; do
        echo -ne "${YELLOW}.${RESET}"
        sleep 0.25
    done

    echo
}

startup_animation() {
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

    loading "Initializing installer"
    loading "Checking system"
    loading "Loading modules"

    sleep 0.5
}

# ========================= ROOT ===============================

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error "Root privileges are required."
        echo
        echo "Run:"
        echo "  sudo bash install.sh"
        exit 1
    fi
}

# ========================= OS =================================

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        error "Unable to detect operating system."
        return 1
    fi

    source /etc/os-release

    case "${ID}" in
        ubuntu|debian)
            success "${PRETTY_NAME} detected"
            ;;
        *)
            error "Unsupported OS: ${PRETTY_NAME}"
            echo
            echo "Supported systems:"
            echo "  Ubuntu"
            echo "  Debian"
            return 1
            ;;
    esac
}

# ========================= ARCH ===============================

get_wings_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            WINGS_ARCH="amd64"
            ;;
        aarch64|arm64)
            WINGS_ARCH="arm64"
            ;;
        *)
            error "Unsupported CPU architecture: $(uname -m)"
            return 1
            ;;
    esac
}

# ========================= APT ================================

apt_update() {
    info "Updating package lists..."

    if apt-get update; then
        success "Package lists updated"
    else
        warning "APT reported repository problems."
        warning "Continuing with available repositories."
    fi
}

# ========================= DEPENDENCIES =======================

install_base_dependencies() {

    info "Installing required packages..."

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https \
        jq \
        unzip \
        wget \
        tar \
        sudo \
        openssl

    success "Dependencies ready"
}

# ========================= DOCKER =============================

install_docker() {

    if command -v docker >/dev/null 2>&1; then
        success "Docker already installed"

        systemctl enable --now docker 2>/dev/null || true

        if systemctl is-active --quiet docker; then
            success "Docker is running"
        else
            warning "Docker is installed but not running."
        fi

        return 0
    fi

    info "Docker not found. Installing Docker..."

    install -m 0755 -d /etc/apt/keyrings

    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
        curl -fsSL \
            https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc

        chmod a+r /etc/apt/keyrings/docker.asc
    fi

    source /etc/os-release

    local docker_os="ubuntu"

    if [[ "${ID}" == "debian" ]]; then
        docker_os="debian"
    fi

    local arch
    arch="$(dpkg --print-architecture)"

    cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${docker_os} ${VERSION_CODENAME} stable
EOF

    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable --now docker

    success "Docker installed and running"
}

# ========================= WINGS ==============================

install_wings() {

    banner

    echo -e "${WHITE}                  WINGS INSTALLATION${RESET}"
    line
    echo

    echo -e "${CYAN}[01/07]${RESET} Detecting operating system..."

    if ! check_os; then
        pause_screen
        return
    fi

    get_wings_arch || {
        pause_screen
        return
    }

    success "Architecture: ${WINGS_ARCH}"

    echo
    echo -e "${CYAN}[02/07]${RESET} Updating packages..."
    apt_update

    echo
    echo -e "${CYAN}[03/07]${RESET} Installing dependencies..."
    install_base_dependencies

    echo
    echo -e "${CYAN}[04/07]${RESET} Checking Docker..."
    install_docker

    echo
    echo -e "${CYAN}[05/07]${RESET} Installing Wings..."

    mkdir -p /etc/pterodactyl

    local tmp_wings
    tmp_wings="$(mktemp /tmp/apnely-wings.XXXXXX)"

    if curl -fL \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 15 \
        -o "${tmp_wings}" \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"; then

        chmod 0755 "${tmp_wings}"

        # Stop old Wings before replacement
        systemctl stop wings 2>/dev/null || true
        pkill -x wings 2>/dev/null || true

        sleep 1

        if install -m 0755 "${tmp_wings}" /usr/local/bin/wings; then
            success "Wings binary installed"
        else
            rm -f "${tmp_wings}"
            error "Failed to install Wings binary."
            pause_screen
            return
        fi

    else
        rm -f "${tmp_wings}"
        error "Failed to download Wings."
        pause_screen
        return
    fi

    rm -f "${tmp_wings}"

    echo
    echo -e "${CYAN}[06/07]${RESET} Configuring systemd..."

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

    success "Wings service configured"

    echo
    echo -e "${CYAN}[07/07]${RESET} Starting Wings..."

    if [[ -f /etc/pterodactyl/config.yml ]]; then

        systemctl restart wings
        sleep 2

        if systemctl is-active --quiet wings; then
            success "Wings is running"
        else
            warning "Wings did not start."
            echo
            echo "Check logs:"
            echo "  journalctl -u wings -n 50 --no-pager"
        fi

    else

        warning "Wings configuration not found."
        echo
        echo -e "${YELLOW}Missing:${RESET}"
        echo "  /etc/pterodactyl/config.yml"
        echo
        info "Wings has been installed."
        info "Create the node in your Panel and place its configuration here."

    fi

    echo
    line
    echo -e "${GREEN}              WINGS COMPLETE${RESET}"
    echo -e "${MAGENTA}           MADE BY ARNAV SHARMA${RESET}"
    line

    pause_screen
}

# ========================= WINGS UNINSTALL ====================

uninstall_wings() {

    banner

    echo -e "${WHITE}                   WINGS UNINSTALL${RESET}"
    line
    echo

    warning "This removes Wings only."
    echo
    echo "Will remove:"
    echo "  • /usr/local/bin/wings"
    echo "  • wings.service"
    echo
    echo "Will KEEP:"
    echo "  • Docker"
    echo "  • Docker containers"
    echo "  • /etc/pterodactyl/config.yml"
    echo "  • Panel"
    echo

    read -rp "Continue? [y/N]: " answer

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

    rm -f /etc/systemd/system/wings.service
    rm -f /usr/local/bin/wings

    systemctl daemon-reload
    systemctl reset-failed wings 2>/dev/null || true

    success "Wings removed"
    warning "Docker and Pterodactyl configuration were preserved."

    pause_screen
}

# ========================= WINGS STATUS =======================

wings_status() {

    banner

    echo -e "${WHITE}                    WINGS STATUS${RESET}"
    line
    echo

    if systemctl list-unit-files 2>/dev/null | grep -q '^wings.service'; then

        systemctl status wings --no-pager

        echo

        if systemctl is-active --quiet wings; then
            success "Wings is ACTIVE"
        else
            warning "Wings is NOT running"
        fi

    else
        warning "Wings service is not installed."
    fi

    pause_screen
}

# ========================= WINGS RESTART ======================

restart_wings() {

    banner

    echo -e "${WHITE}                   RESTART WINGS${RESET}"
    line
    echo

    if ! systemctl list-unit-files 2>/dev/null | grep -q '^wings.service'; then
        error "Wings service is not installed."
        pause_screen
        return
    fi

    systemctl restart wings
    sleep 2

    if systemctl is-active --quiet wings; then
        success "Wings restarted successfully"
    else
        error "Wings failed to start."
        echo
        echo "Logs:"
        echo "  journalctl -u wings -n 50 --no-pager"
    fi

    pause_screen
}

# ========================= WINGS REPAIR =======================

repair_wings() {

    banner

    echo -e "${WHITE}                    REPAIR WINGS${RESET}"
    line
    echo

    if [[ ! -f /usr/local/bin/wings ]]; then
        warning "Wings binary is missing."
        install_wings
        return
    fi

    info "Checking Wings service..."

    systemctl daemon-reload

    if [[ ! -f /etc/systemd/system/wings.service ]]; then

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

        success "Wings service repaired"

    else
        success "Wings service file exists"
    fi

    if [[ -f /etc/pterodactyl/config.yml ]]; then
        systemctl restart wings
        sleep 2

        if systemctl is-active --quiet wings; then
            success "Wings is running"
        else
            warning "Wings still failed to start."
            echo
            echo "Run:"
            echo "  journalctl -u wings -n 100 --no-pager"
        fi
    else
        warning "config.yml not found."
    fi

    pause_screen
}

# ========================= NGINX ==============================

install_nginx() {

    banner

    echo -e "${WHITE}                    NGINX${RESET}"
    line
    echo

    apt_update

    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx

    systemctl enable --now nginx

    success "Nginx installed and running"

    pause_screen
}

uninstall_nginx() {

    banner

    echo -e "${WHITE}                  NGINX UNINSTALL${RESET}"
    line
    echo

    warning "This removes Nginx packages and service."
    echo

    read -rp "Continue? [y/N]: " answer

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

    DEBIAN_FRONTEND=noninteractive apt-get remove -y nginx nginx-common 2>/dev/null || true

    success "Nginx removed"

    pause_screen
}

nginx_status() {

    banner

    echo -e "${WHITE}                   NGINX STATUS${RESET}"
    line
    echo

    systemctl status nginx --no-pager 2>/dev/null || true

    pause_screen
}

restart_nginx() {

    banner

    echo -e "${WHITE}                  RESTART NGINX${RESET}"
    line
    echo

    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        success "Nginx restarted"
    else
        error "Nginx failed to restart."
    fi

    pause_screen
}

# ========================= CERTBOT ============================

install_certbot() {

    banner

    echo -e "${WHITE}                  CERTBOT / SSL${RESET}"
    line
    echo

    apt_update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        certbot \
        python3-certbot-nginx

    success "Certbot installed"

    echo
    echo "To issue an Nginx certificate:"
    echo
    echo "  certbot --nginx"
    echo

    warning "A valid domain pointing to this server is required."

    pause_screen
}

generate_ssl() {

    banner

    echo -e "${WHITE}                  GENERATE SSL${RESET}"
    line
    echo

    if ! command -v certbot >/dev/null 2>&1; then
        warning "Certbot is not installed."
        echo
        read -rp "Install Certbot now? [y/N]: " answer

        case "${answer}" in
            y|Y|yes|YES)
                install_certbot
                ;;
            *)
                return
                ;;
        esac
    fi

    read -rp "Enter domain: " domain

    if [[ -z "${domain}" ]]; then
        error "Domain cannot be empty."
        pause_screen
        return
    fi

    info "Requesting certificate for ${domain}..."

    certbot --nginx -d "${domain}"

    pause_screen
}

certificate_status() {

    banner

    echo -e "${WHITE}                CERTIFICATE STATUS${RESET}"
    line
    echo

    if command -v certbot >/dev/null 2>&1; then
        certbot certificates
    else
        warning "Certbot is not installed."
    fi

    pause_screen
}

renew_ssl() {

    banner

    echo -e "${WHITE}                   RENEW SSL${RESET}"
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

# ========================= PANEL ==============================

panel_menu() {

    while true; do

        banner

        echo -e "${WHITE}                 PTERODACTYL PANEL${RESET}"
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

        read -rp "Select [1-5]: " choice

        case "${choice}" in

            1)
                banner
                echo -e "${WHITE}                 PANEL INSTALLER${RESET}"
                line
                echo
                warning "Panel installer module is prepared for the next release."
                echo
                info "This module will configure PHP, MariaDB, Redis, Composer,"
                info "Node.js, Panel files, Nginx and queue workers."
                pause_screen
                ;;

            2)
                banner
                echo -e "${WHITE}                 PANEL UNINSTALLER${RESET}"
                line
                echo
                warning "Panel uninstall is intentionally disabled in this release."
                warning "This prevents accidental database/data deletion."
                pause_screen
                ;;

            3)
                banner
                echo -e "${WHITE}                  PANEL REPAIR${RESET}"
                line
                echo
                warning "Panel repair module is prepared for the next release."
                pause_screen
                ;;

            4)
                banner
                echo -e "${WHITE}                  PANEL STATUS${RESET}"
                line
                echo
                warning "Panel status module is prepared for the next release."
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

# ========================= WINGS MENU =========================

wings_menu() {

    while true; do

        banner

        echo -e "${WHITE}                      WINGS${RESET}"
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

        read -rp "Select [1-6]: " choice

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

# ========================= NGINX MENU =========================

nginx_menu() {

    while true; do

        banner

        echo -e "${WHITE}                     NGINX${RESET}"
        line
        echo

        echo -e "  ${GREEN}[1]${RESET} Install Nginx"
        echo -e "  ${RED}[2]${RESET} Uninstall Nginx"
        echo -e "  ${CYAN}[3]${RESET} Restart Nginx"
        echo -e "  ${BLUE}[4]${RESET} Nginx Status"
        echo -e "  ${WHITE}[5]${RESET} Back"

        echo
        line
        echo

        read -rp "Select [1-5]: " choice

        case "${choice}" in
            1) install_nginx ;;
            2) uninstall_nginx ;;
            3) restart_nginx ;;
            4) nginx_status ;;
            5) return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac

    done
}

# ========================= SSL MENU ===========================

ssl_menu() {

    while true; do

        banner

        echo -e "${WHITE}                  CERTBOT / SSL${RESET}"
        line
        echo

        echo -e "  ${GREEN}[1]${RESET} Install Certbot"
        echo -e "  ${CYAN}[2]${RESET} Generate SSL"
        echo -e "  ${YELLOW}[3]${RESET}
