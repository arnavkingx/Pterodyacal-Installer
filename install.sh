#!/usr/bin/env bash

# ============================================================
#        PTERODACTYL WINGS INSTALLER
#             MADE BY ARNAV SHARMA
# ============================================================

set -u

VERSION="2.0.0"
AUTHOR="ARNAV SHARMA"

# ---------------- COLORS ----------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
RESET='\033[0m'

# ---------------- BASIC FUNCTIONS ----------------

clear_screen() {
    clear 2>/dev/null || true
}

line() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

small_line() {
    echo -e "${GRAY}──────────────────────────────────────────────────${RESET}"
}

pause_screen() {
    echo
    read -rp "Press Enter to continue..." _
}

banner() {
    clear_screen

    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${WHITE}          PTERODACTYL INSTALLER                 ${CYAN}║${RESET}"
    echo -e "${CYAN}║${MAGENTA}             MADE BY ARNAV SHARMA              ${CYAN}║${RESET}"
    echo -e "${CYAN}║${GRAY}                  Version ${VERSION}                 ${CYAN}║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
    echo
}

loading() {
    local text="${1:-Loading}"
    local i

    echo -ne "${CYAN}${text}${RESET} "

    for i in 1 2 3; do
        echo -ne "${YELLOW}.${RESET}"
        sleep 0.25
    done

    echo
}

spinner_start() {
    local message="$1"

    (
        while true; do
            for s in '|' '/' '-' '\'; do
                printf "\r${CYAN}%s ${YELLOW}%s${RESET}" "$message" "$s"
                sleep 0.12
            done
        done
    ) &

    SPINNER_PID=$!
}

spinner_stop() {
    if [[ -n "${SPINNER_PID:-}" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        printf "\r\033[K"
    fi
}

success() {
    echo -e "${GREEN}✓${RESET} $1"
}

warning() {
    echo -e "${YELLOW}!${RESET} $1"
}

error() {
    echo -e "${RED}✗${RESET} $1"
}

info() {
    echo -e "${BLUE}➜${RESET} $1"
}

step() {
    echo
    echo -e "${CYAN}[$1]${RESET} ${WHITE}$2${RESET}"
}

# ---------------- ROOT CHECK ----------------

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error "Please run this installer as root."
        echo
        echo "Example:"
        echo "  sudo bash install.sh"
        exit 1
    fi
}

# ---------------- OS CHECK ----------------

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect operating system."
        exit 1
    fi

    source /etc/os-release

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
            exit 1
            ;;
    esac
}

# ---------------- ARCHITECTURE ----------------

get_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            WINGS_ARCH="amd64"
            ;;
        aarch64|arm64)
            WINGS_ARCH="arm64"
            ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
}

# ---------------- APT UPDATE ----------------

apt_update() {
    step "01/07" "Updating system packages..."

    if apt-get update; then
        success "Package lists updated"
    else
        warning "APT reported repository warnings/errors."
        warning "Continuing with available package indexes."
    fi
}

# ---------------- DEPENDENCIES ----------------

install_dependencies() {
    step "02/07" "Installing dependencies..."

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
        systemd \
        openssl

    success "Dependencies installed"
}

# ---------------- DOCKER ----------------

install_docker() {
    step "03/07" "Checking Docker..."

    if command -v docker >/dev/null 2>&1; then
        success "Docker already installed"

        if systemctl is-active --quiet docker; then
            success "Docker service is running"
        else
            info "Starting Docker service..."
            systemctl enable --now docker
            success "Docker service started"
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

    . /etc/os-release

    if [[ "${ID}" == "ubuntu" ]]; then
        DOCKER_OS="ubuntu"
    else
        DOCKER_OS="debian"
    fi

    ARCH="$(dpkg --print-architecture)"

    echo \
      "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_OS} \
      ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list

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

# ---------------- WINGS DOWNLOAD ----------------

download_wings() {
    local tmp_file

    get_arch

    mkdir -p /etc/pterodactyl

    tmp_file="$(mktemp /tmp/wings.XXXXXX)"

    info "Downloading Wings for ${WINGS_ARCH}..."

    if ! curl -fL \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 15 \
        -o "${tmp_file}" \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"; then

        rm -f "${tmp_file}"
        error "Failed to download Wings."
        return 1
    fi

    chmod 0755 "${tmp_file}"

    echo "${tmp_file}"
}

# ---------------- INSTALL WINGS ----------------

install_wings() {
    banner

    echo -e "${WHITE}                 WINGS INSTALLATION${RESET}"
    line

    check_os

    # 1
    step "01/07" "Detecting system..."
    get_arch
    success "Architecture: ${WINGS_ARCH}"

    # 2
    apt_update

    # 3
    install_dependencies

    # 4
    install_docker

    # 5
    step "05/07" "Installing Wings..."

    local tmp_wings
    tmp_wings="$(download_wings)" || {
        error "Wings installation failed."
        pause_screen
        return 1
    }

    # Stop old Wings before replacing binary
    if systemctl list-unit-files | grep -q '^wings.service'; then
        info "Stopping existing Wings service..."
        systemctl stop wings 2>/dev/null || true
    fi

    # Kill any leftover Wings process
    pkill -x wings 2>/dev/null || true
    sleep 1

    # Safe replacement
    if install -m 0755 "${tmp_wings}" /usr/local/bin/wings; then
        success "Wings installed successfully"
    else
        rm -f "${tmp_wings}"
        error "Could not install Wings binary."
        return 1
    fi

    rm -f "${tmp_wings}"

    # 6
    step "06/07" "Configuring Wings systemd service..."

    cat > /etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wings

    success "Wings service configured"

    # 7
    step "07/07" "Starting Wings..."

    if [[ -f /etc/pterodactyl/config.yml ]]; then

        systemctl restart wings

        sleep 2

        if systemctl is-active --quiet wings; then
            success "Wings is running"
        else
            warning "Wings could not start."
            warning "Check: journalctl -u wings -n 50 --no-pager"
        fi

    else

        warning "Wings config.yml was not found."
        echo
        echo -e "${YELLOW}Expected:${RESET}"
        echo "  /etc/pterodactyl/config.yml"
        echo
        info "Wings binary and service are installed."
        info "Generate the node configuration from your Pterodactyl Panel."
    fi

    echo
    line
    echo -e "${GREEN}          WINGS INSTALLATION COMPLETE${RESET}"
    line
    echo
    echo -e "${MAGENTA}        MADE BY ARNAV SHARMA${RESET}"
    echo

    pause_screen
}

# ---------------- UNINSTALL WINGS ----------------

uninstall_wings() {
    banner

    echo -e "${WHITE}                 WINGS UNINSTALLER${RESET}"
    line

    warning "This will remove the Wings daemon."
    echo
    echo "The following will be removed:"
    echo "  • Wings systemd service"
    echo "  • Wings binary"
    echo
    echo "The following will NOT be removed:"
    echo "  • Docker"
    echo "  • Docker containers"
    echo "  • /etc/pterodactyl/config.yml"
    echo "  • Panel"
    echo

    read -rp "Continue with uninstall? [y/N]: " confirm

    case "${confirm}" in
        y|Y|yes|YES)
            ;;
        *)
            info "Uninstall cancelled."
            sleep 1
            return
            ;;
    esac

    echo

    info "Stopping Wings..."
    systemctl stop wings 2>/dev/null || true

    info "Disabling Wings..."
    systemctl disable wings 2>/dev/null || true

    info "Stopping leftover Wings processes..."
    pkill -x wings 2>/dev/null || true

    sleep 1

    info "Removing systemd service..."
    rm -f /etc/systemd/system/wings.service

    systemctl daemon-reload
    systemctl reset-failed wings 2>/dev/null || true

    info "Removing Wings binary..."
    rm -f /usr/local/bin/wings

    success "Wings removed"

    echo
    warning "Docker and Pterodactyl configuration were preserved."
    echo

    pause_screen
}

# ---------------- WINGS STATUS ----------------

wings_status() {
    banner

    echo -e "${WHITE}                    WINGS STATUS${RESET}"
    line
    echo

    if systemctl list-unit-files | grep -q '^wings.service'; then

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

    echo
    pause_screen
}

# ---------------- RESTART WINGS ----------------

restart_wings() {
    banner

    echo -e "${WHITE}                  RESTARTING WINGS${RESET}"
    line
    echo

    if ! systemctl list-unit-files | grep -q '^wings.service'; then
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
        echo "journalctl -u wings -n 50 --no-pager"
    fi

    echo
    pause_screen
}

# ---------------- CERTBOT ----------------

install_certbot() {
    banner

    echo -e "${WHITE}                 CERTBOT / SSL TOOLS${RESET}"
    line
    echo

    apt_update

    info "Installing Certbot..."

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        certbot \
        python3-certbot-nginx

    success "Certbot installed"

    echo
    echo -e "${YELLOW}Certbot does NOT automatically issue a certificate here.${RESET}"
    echo
    echo "A real domain and DNS pointing to this server are required."
    echo
    echo "For Nginx:"
    echo
    echo "  certbot --nginx"
    echo

    pause_screen
}

# ---------------- NGINX + CERTBOT ----------------

install_nginx_certbot() {
    banner

    echo -e "${WHITE}              NGINX + CERTBOT INSTALLER${RESET}"
    line
    echo

    apt_update

    info "Installing Nginx and Certbot..."

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        nginx \
        certbot \
        python3-certbot-nginx

    systemctl enable --now nginx

    success "Nginx installed"
    success "Certbot installed"

    echo
    echo "To request an SSL certificate:"
    echo
    echo "  certbot --nginx"
    echo

    pause_screen
}

# ---------------- STARTUP ----------------

startup_animation() {
    banner

    echo -e "${CYAN}Initializing installer${RESET}"

    for i in 1 2 3 4 5; do
        echo -ne "${MAGENTA}█${RESET}"
        sleep 0.12
    done

    echo
    echo

    success "Installer loaded"
    success "Author: ${AUTHOR}"

    sleep 0.7
}

# ---------------- MAIN MENU ----------------

main_menu() {

    while true; do

        banner

        echo -e "${WHITE}                 MAIN MENU${RESET}"
        line
        echo

        echo -e "  ${GREEN}[1]${RESET} Install Wings"
        echo -e "  ${RED}[2]${RESET} Uninstall Wings"
        echo -e "  ${BLUE}[3]${RESET} Install Certbot"
        echo -e "  ${CYAN}[4]${RESET} Nginx + Certbot"
        echo -e "  ${YELLOW}[5]${RESET} Wings Status"
        echo -e "  ${MAGENTA}[6]${RESET} Restart Wings"
        echo -e "  ${WHITE}[7]${RESET} Exit"

        echo
        line
        echo

        read -rp "Select an option [1-7]: " choice

        case "${choice}" in

            1)
                install_wings
                ;;

            2)
                uninstall_wings
                ;;

            3)
                install_certbot
                ;;

            4)
                install_nginx_certbot
                ;;

            5)
                wings_status
                ;;

            6)
                restart_wings
                ;;

            7)
                clear_screen
                echo
                echo -e "${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
                echo -e "${CYAN}║${WHITE}        THANK YOU FOR USING THE INSTALLER       ${CYAN}║${RESET}"
                echo -e "${CYAN}║${MAGENTA}             MADE BY ARNAV SHARMA              ${CYAN}║${RESET}"
                echo -e "${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                echo
                exit 0
                ;;

            *)
                error "Invalid option."
                sleep 1
                ;;

        esac

    done
}

# ---------------- START ----------------

check_root
startup_animation
main_menu
