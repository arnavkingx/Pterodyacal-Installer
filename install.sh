#!/usr/bin/env bash

set -u

# ============================================================
#              PTERODACTYL INSTALLER
#                 MADE BY ARNAV SHARMA
# ============================================================

VERSION="1.0.0"
AUTHOR="ARNAV SHARMA"

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# ---------- Helpers ----------

line() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                                                  ║"
    echo "║          PTERODACTYL INSTALLER                  ║"
    echo "║                                                  ║"
    echo "║             MADE BY ARNAV SHARMA                ║"
    echo "║                                                  ║"
    echo "║                 v${VERSION}                         ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

loading() {
    local text="$1"

    echo -ne "${CYAN}${text}${NC} "

    for i in 1 2 3 4 5; do
        echo -ne "▓"
        sleep 0.12
    done

    echo -e " ${GREEN}✓${NC}"
}

step() {
    local number="$1"
    local total="$2"
    local text="$3"

    echo -e ""
    echo -e "${CYAN}[${number}/${total}]${NC} ${WHITE}${text}${NC}"
}

success() {
    echo -e "      ${GREEN}✓${NC} $1"
}

warning() {
    echo -e "      ${YELLOW}!${NC} $1"
}

error() {
    echo -e "      ${RED}✗${NC} $1"
}

pause_screen() {
    echo ""
    echo -e "${GRAY}Press ENTER to continue...${NC}"
    read -r
}

# ---------- Root Check ----------

root_check() {
    if [ "$(id -u)" -ne 0 ]; then
        banner
        error "This installer must be run as root."
        echo ""
        echo -e "${YELLOW}Example:${NC}"
        echo "sudo -i"
        echo "bash <(curl -fsSL https://raw.githubusercontent.com/arnavkingx/Pterodyacal-Installer/main/install.sh)"
        echo ""
        exit 1
    fi
}

# ---------- OS Check ----------

os_check() {
    if [ ! -f /etc/os-release ]; then
        error "Unable to detect operating system."
        return 1
    fi

    . /etc/os-release

    case "${ID:-}" in
        ubuntu|debian)
            success "${PRETTY_NAME}"
            ;;
        *)
            error "Unsupported operating system: ${ID:-unknown}"
            echo ""
            echo "Supported:"
            echo "  Ubuntu"
            echo "  Debian"
            return 1
            ;;
    esac
}

# ---------- Startup ----------

startup() {
    banner

    echo ""
    echo -e "${WHITE}Initializing installer...${NC}"
    echo ""

    loading "Loading installer"
    loading "Checking environment"
    loading "Loading modules"
    loading "Preparing interface"

    echo ""
    echo -e "${GREEN}✓ Installer ready${NC}"

    sleep 0.5
}

# ============================================================
#                    WINGS INSTALLER
# ============================================================

install_wings() {

    banner

    echo -e "${WHITE}WINGS INSTALLATION${NC}"
    echo -e "${GRAY}MADE BY ARNAV SHARMA${NC}"
    line

    echo ""

    # ---------------- STEP 1 ----------------

    step "01" "07" "Detecting system"

    if ! os_check; then
        pause_screen
        return
    fi

    # ---------------- STEP 2 ----------------

    step "02" "07" "Updating package lists"

    if apt-get update -y; then
        success "Package lists updated"
    else
        error "apt update failed"
        pause_screen
        return
    fi

    # ---------------- STEP 3 ----------------

    step "03" "07" "Installing dependencies"

    if apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https \
        jq; then

        success "Dependencies installed"

    else

        error "Dependency installation failed"
        pause_screen
        return

    fi

    # ---------------- STEP 4 ----------------

    step "04" "07" "Checking Docker"

    if command -v docker >/dev/null 2>&1; then

        success "Docker already installed"

    else

        echo "      Installing Docker..."

        install -m 0755 -d /etc/apt/keyrings

        if [ "${ID}" = "ubuntu" ]; then
            DOCKER_OS="ubuntu"
        else
            DOCKER_OS="debian"
        fi

        if ! curl -fsSL \
            "https://download.docker.com/linux/${DOCKER_OS}/gpg" \
            -o /etc/apt/keyrings/docker.asc; then

            error "Failed to download Docker GPG key"
            pause_screen
            return

        fi

        chmod a+r /etc/apt/keyrings/docker.asc

        ARCH="$(dpkg --print-architecture)"

        cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_OS} ${VERSION_CODENAME} stable
EOF

        if ! apt-get update -y; then
            error "Docker repository update failed"
            pause_screen
            return
        fi

        if ! apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin; then

            error "Docker installation failed"
            pause_screen
            return

        fi

        systemctl enable --now docker

        success "Docker installed"

    fi

    # ---------------- STEP 5 ----------------

    step "05" "07" "Installing Wings"

    mkdir -p /etc/pterodactyl

    ARCH="$(uname -m)"

    case "$ARCH" in
        x86_64)
            WINGS_ARCH="amd64"
            ;;
        aarch64|arm64)
            WINGS_ARCH="arm64"
            ;;
        *)
            error "Unsupported CPU architecture: $ARCH"
            pause_screen
            return
            ;;
    esac

    TEMP_WINGS="$(mktemp)"

    echo "      Downloading Wings (${WINGS_ARCH})..."

    if ! curl -fL \
        --retry 3 \
        --connect-timeout 15 \
        -o "$TEMP_WINGS" \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"; then

        rm -f "$TEMP_WINGS"

        error "Wings download failed"
        pause_screen
        return

    fi

    chmod +x "$TEMP_WINGS"

    # Stop old Wings before replacing binary.
    systemctl stop wings 2>/dev/null || true

    # Safe replacement.
    if ! install -m 0755 "$TEMP_WINGS" /usr/local/bin/wings; then

        rm -f "$TEMP_WINGS"

        error "Failed to install Wings binary"
        pause_screen
        return

    fi

    rm -f "$TEMP_WINGS"

    success "Wings binary installed"

    # ---------------- STEP 6 ----------------

    step "06" "07" "Configuring Wings service"

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

    # ---------------- STEP 7 ----------------

    step "07" "07" "Checking Wings configuration"

    if [ -f /etc/pterodactyl/config.yml ]; then

        success "config.yml detected"

        if systemctl start wings; then
            success "Wings service started"
        else
            warning "Wings could not be started"
            warning "Check: journalctl -u wings -n 50"
        fi

    else

        warning "Panel node configuration not found"
        echo ""
        echo -e "${WHITE}Wings is installed successfully.${NC}"
        echo ""
        echo "The Panel-generated node configuration is still required:"
        echo ""
        echo "  /etc/pterodactyl/config.yml"
        echo ""
        echo "After placing the configuration, run:"
        echo ""
        echo "  systemctl enable --now wings"

    fi

    echo ""
    line
    echo -e "${GREEN}             WINGS INSTALLATION COMPLETE${NC}"
    line

    echo ""
    echo -e "${GRAY}MADE BY ARNAV SHARMA${NC}"

    pause_screen
}

# ============================================================
#                    PANEL INSTALLER
# ============================================================

install_panel() {

    banner

    echo -e "${WHITE}PANEL INSTALLATION${NC}"
    echo -e "${GRAY}MADE BY ARNAV SHARMA${NC}"
    line

    echo ""

    warning "Panel installer module is not enabled yet."
    echo ""
    echo "We will add the Panel installation flow separately"
    echo "using the current official Pterodactyl requirements."
    echo ""

    pause_screen
}

# ============================================================
#                       MAIN MENU
# ============================================================

main_menu() {

    while true; do

        banner

        echo -e "${WHITE}MAIN MENU${NC}"
        line

        echo ""
        echo -e "   ${CYAN}[1]${NC}  Panel Installation"
        echo -e "   ${CYAN}[2]${NC}  Wings Installation"
        echo -e "   ${RED}[3]${NC}  Exit"
        echo ""

        read -rp "   Select an option [1-3]: " OPTION

        case "$OPTION" in

            1)
                install_panel
                ;;

            2)
                install_wings
                ;;

            3)
                clear
                echo ""
                echo -e "${GREEN}Thanks for using Pterodactyl Installer.${NC}"
                echo -e "${GRAY}MADE BY ARNAV SHARMA${NC}"
                echo ""
                exit 0
                ;;

            *)
                error "Invalid option."
                sleep 1
                ;;

        esac

    done
}

# ============================================================
#                         START
# ============================================================

root_check
startup
main_menu
