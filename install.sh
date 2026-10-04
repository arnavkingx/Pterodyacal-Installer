#!/bin/bash

set -e

# ==========================================
# PTERODACTYL INSTALLER
# MADE BY ARNAV SHARMA
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear

echo -e "${CYAN}"
echo "=========================================="
echo "          PTERODACTYL INSTALLER"
echo "           MADE BY ARNAV SHARMA"
echo "=========================================="
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this installer as root.${NC}"
    exit 1
fi

echo ""
echo "1) Panel Installation"
echo "2) Wings Installation"
echo "3) Exit"
echo ""

read -rp "Select an option [1-3]: " OPTION

# ==========================================
# WINGS
# ==========================================

install_wings() {

    clear

    echo -e "${CYAN}"
    echo "=========================================="
    echo "           WINGS INSTALLATION"
    echo "=========================================="
    echo -e "${NC}"

    echo -e "${YELLOW}[1/7] Detecting system...${NC}"

    if [ ! -f /etc/os-release ]; then
        echo -e "${RED}Unsupported operating system.${NC}"
        exit 1
    fi

    . /etc/os-release

    case "$ID" in
        ubuntu|debian)
            echo -e "${GREEN}✓ $PRETTY_NAME detected${NC}"
            ;;
        *)
            echo -e "${RED}This first version supports Ubuntu/Debian only.${NC}"
            exit 1
            ;;
    esac

    echo ""
    echo -e "${YELLOW}[2/7] Updating packages...${NC}"

    apt-get update -y

    echo -e "${GREEN}✓ Packages updated${NC}"

    echo ""
    echo -e "${YELLOW}[3/7] Installing dependencies...${NC}"

    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https

    echo -e "${GREEN}✓ Dependencies installed${NC}"

    echo ""
    echo -e "${YELLOW}[4/7] Installing Docker...${NC}"

    if command -v docker >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker already installed${NC}"
    else
        install -m 0755 -d /etc/apt/keyrings

        curl -fsSL https://download.docker.com/linux/${ID}/gpg \
            -o /etc/apt/keyrings/docker.asc

        chmod a+r /etc/apt/keyrings/docker.asc

        ARCH=$(dpkg --print-architecture)

        echo \
          "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} \
          ${VERSION_CODENAME} stable" \
          > /etc/apt/sources.list.d/docker.list

        apt-get update -y

        apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin

        systemctl enable --now docker
    fi

    echo -e "${GREEN}✓ Docker ready${NC}"

    echo ""
    echo -e "${YELLOW}[5/7] Installing Wings...${NC}"

    mkdir -p /etc/pterodactyl

    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64)
            WINGS_ARCH="amd64"
            ;;
        aarch64|arm64)
            WINGS_ARCH="arm64"
            ;;
        *)
            echo -e "${RED}Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac

    curl -L \
        -o /usr/local/bin/wings \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"

    chmod +x /usr/local/bin/wings

    echo -e "${GREEN}✓ Wings installed${NC}"

    echo ""
    echo -e "${YELLOW}[6/7] Installing Wings service...${NC}"

    cat > /etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wings

    echo -e "${GREEN}✓ Wings service created${NC}"

    echo ""
    echo -e "${YELLOW}[7/7] Checking configuration...${NC}"

    if [ ! -f /etc/pterodactyl/config.yml ]; then

        echo ""
        echo -e "${YELLOW}Wings is installed, but Panel configuration is missing.${NC}"
        echo ""
        echo "Create your Node in:"
        echo "Admin → Nodes → Configuration"
        echo ""
        echo "Then save the generated configuration as:"
        echo ""
        echo "/etc/pterodactyl/config.yml"
        echo ""

        echo -e "${GREEN}✓ Wings installation completed${NC}"
        echo -e "${CYAN}Run 'systemctl start wings' after adding config.yml.${NC}"

        return
    fi

    systemctl enable --now wings

    echo -e "${GREEN}✓ Wings started successfully${NC}"

    echo ""
    echo "=========================================="
    echo -e "${GREEN}       WINGS INSTALLATION COMPLETE${NC}"
    echo "=========================================="
}

# ==========================================
# PANEL
# ==========================================

install_panel() {

    clear

    echo -e "${CYAN}"
    echo "=========================================="
    echo "           PANEL INSTALLATION"
    echo "=========================================="
    echo -e "${NC}"

    echo ""
    echo "Panel installer will be added next."
    echo ""
    echo -e "${YELLOW}For now, choose Wings to test the installer.${NC}"
}

# ==========================================
# MENU
# ==========================================

case "$OPTION" in

    1)
        install_panel
        ;;

    2)
        install_wings
        ;;

    3)
        echo "Goodbye."
        exit 0
        ;;

    *)
        echo -e "${RED}Invalid option.${NC}"
        exit 1
        ;;

esac
