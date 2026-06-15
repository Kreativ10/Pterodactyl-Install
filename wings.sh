#!/bin/bash
#
# Sundy.Systems — Pterodactyl Wings Installer v2.0
# Copyright (c) 2024-2026 Sundy.Systems
#
# This script installs and configures Pterodactyl Wings (the game-server daemon).
# It is fully self-contained and requires no external libraries.
#
# Supported Operating Systems:
#   Ubuntu 20.04 / 22.04 / 24.04
#   Debian 11 / 12
#   Rocky Linux 8 / 9
#   AlmaLinux 8 / 9
#
# Usage: sudo bash wings.sh
#

set -e

###############################################################################
# COLOR DEFINITIONS
###############################################################################

ORANGE='\033[38;5;208m'
DARK_ORANGE='\033[38;5;202m'
YELLOW='\033[38;5;220m'
GREEN='\033[38;5;82m'
RED='\033[38;5;196m'
WHITE='\033[38;5;255m'
BOLD='\033[1m'
RESET='\033[0m'

###############################################################################
# ASCII ART BANNER
###############################################################################

print_banner() {
    echo ""
    echo -e "${DARK_ORANGE} ███████╗██╗   ██╗███╗   ██╗██████╗ ██╗   ██╗${RESET}"
    echo -e "${DARK_ORANGE} ██╔════╝██║   ██║████╗  ██║██╔══██╗╚██╗ ██╔╝${RESET}"
    echo -e "${ORANGE} ███████╗██║   ██║██╔██╗ ██║██║  ██║ ╚████╔╝${RESET}"
    echo -e "${ORANGE} ╚════██║██║   ██║██║╚██╗██║██║  ██║  ╚██╔╝${RESET}"
    echo -e "${YELLOW} ███████║╚██████╔╝██║ ╚████║██████╔╝   ██║${RESET}"
    echo -e "${YELLOW} ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝    ╚═╝${RESET}"
    echo -e "${WHITE}        ┌─────────────────────────────┐${RESET}"
    echo -e "${WHITE}        │${ORANGE}   S U N D Y . S Y S T E M S ${WHITE}│${RESET}"
    echo -e "${WHITE}        │${YELLOW}    Wings Installer v2.0     ${WHITE}│${RESET}"
    echo -e "${WHITE}        └─────────────────────────────┘${RESET}"
    echo ""
}

###############################################################################
# HELPER FUNCTIONS
###############################################################################

output() {
    echo -e "${ORANGE}[*]${RESET} ${WHITE}$1${RESET}"
}

success() {
    echo -e "${GREEN}[✔]${RESET} ${WHITE}$1${RESET}"
}

error() {
    echo -e "${RED}[✘]${RESET} ${WHITE}$1${RESET}" >&2
}

warning() {
    echo -e "${YELLOW}[!]${RESET} ${WHITE}$1${RESET}"
}

print_brake() {
    local len="${1:-60}"
    local line=""
    for ((i = 0; i < len; i++)); do
        line="${line}─"
    done
    echo -e "${ORANGE}${line}${RESET}"
}

# Prompt for required input; loops until non-empty value is provided.
# Usage: required_input "Prompt text" VARIABLE_NAME
required_input() {
    local prompt="$1"
    local varname="$2"
    local value=""

    while true; do
        echo -en "${ORANGE}[?]${RESET} ${WHITE}${prompt}:${RESET} "
        read -r value
        if [[ -n "$value" ]]; then
            # Basic input sanitisation — reject shell metacharacters
            if [[ "$value" =~ [\;\|\&\$\(\)\`\\] ]]; then
                error "Input contains forbidden characters. Please try again."
                continue
            fi
            printf -v "$varname" '%s' "$value"
            return 0
        fi
        error "This field is required. Please provide a value."
    done
}

# Prompt with a default value; accepts empty input as default.
# Usage: input_with_default "Prompt text" DEFAULT_VALUE VARIABLE_NAME
input_with_default() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local value=""

    echo -en "${ORANGE}[?]${RESET} ${WHITE}${prompt} [${YELLOW}${default}${WHITE}]:${RESET} "
    read -r value
    if [[ -z "$value" ]]; then
        value="$default"
    fi
    # Basic input sanitisation
    if [[ "$value" =~ [\;\|\&\$\(\)\`\\] ]]; then
        error "Input contains forbidden characters. Using default."
        value="$default"
    fi
    printf -v "$varname" '%s' "$value"
}

# Yes/No prompt with a default.
# Usage: ask_yes_no "Prompt text" DEFAULT_VALUE(y/n) VARIABLE_NAME
ask_yes_no() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local yn_hint

    if [[ "$default" == "y" ]]; then
        yn_hint="Y/n"
    else
        yn_hint="y/N"
    fi

    while true; do
        echo -en "${ORANGE}[?]${RESET} ${WHITE}${prompt} [${YELLOW}${yn_hint}${WHITE}]:${RESET} "
        read -r answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            y|yes)
                printf -v "$varname" '%s' "true"
                return 0
                ;;
            n|no)
                printf -v "$varname" '%s' "false"
                return 0
                ;;
            *)
                error "Please answer y or n."
                ;;
        esac
    done
}

# Generate a random password of given length (default 32).
gen_passwd() {
    local length="${1:-32}"
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

###############################################################################
# OS DETECTION
###############################################################################

OS=""
OS_VERSION=""
OS_FAMILY=""   # debian or rhel

detect_os() {
    output "Detecting operating system..."

    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect OS: /etc/os-release not found."
        exit 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    OS="${ID}"
    OS_VERSION="${VERSION_ID}"

    case "$OS" in
        ubuntu)
            OS_FAMILY="debian"
            case "$OS_VERSION" in
                20.04|22.04|24.04) ;;
                *)
                    error "Unsupported Ubuntu version: $OS_VERSION"
                    error "Supported versions: 20.04, 22.04, 24.04"
                    exit 1
                    ;;
            esac
            ;;
        debian)
            OS_FAMILY="debian"
            case "$OS_VERSION" in
                11|12) ;;
                *)
                    error "Unsupported Debian version: $OS_VERSION"
                    error "Supported versions: 11, 12"
                    exit 1
                    ;;
            esac
            ;;
        rocky)
            OS_FAMILY="rhel"
            case "$OS_VERSION" in
                8*|9*)
                    # Normalise to major version
                    OS_VERSION="${OS_VERSION%%.*}"
                    ;;
                *)
                    error "Unsupported Rocky Linux version: $OS_VERSION"
                    error "Supported versions: 8, 9"
                    exit 1
                    ;;
            esac
            ;;
        almalinux)
            OS_FAMILY="rhel"
            case "$OS_VERSION" in
                8*|9*)
                    OS_VERSION="${OS_VERSION%%.*}"
                    ;;
                *)
                    error "Unsupported AlmaLinux version: $OS_VERSION"
                    error "Supported versions: 8, 9"
                    exit 1
                    ;;
            esac
            ;;
        *)
            error "Unsupported operating system: $OS"
            error "Supported: Ubuntu, Debian, Rocky Linux, AlmaLinux"
            exit 1
            ;;
    esac

    success "Detected: ${OS} ${OS_VERSION} (${OS_FAMILY})"
}

###############################################################################
# PACKAGE MANAGEMENT HELPERS
###############################################################################

update_repos() {
    output "Updating package repositories..."
    case "$OS_FAMILY" in
        debian)
            DEBIAN_FRONTEND=noninteractive apt-get update -yq >/dev/null 2>&1
            ;;
        rhel)
            dnf makecache -q >/dev/null 2>&1
            ;;
    esac
    success "Package repositories updated."
}

install_packages() {
    local packages=("$@")
    output "Installing packages: ${packages[*]}"
    case "$OS_FAMILY" in
        debian)
            DEBIAN_FRONTEND=noninteractive apt-get install -yq "${packages[@]}" >/dev/null 2>&1
            ;;
        rhel)
            dnf install -y -q "${packages[@]}" >/dev/null 2>&1
            ;;
    esac
    success "Packages installed: ${packages[*]}"
}

###############################################################################
# FIREWALL HELPERS
###############################################################################

install_firewall() {
    output "Installing and configuring firewall..."

    case "$OS_FAMILY" in
        debian)
            install_packages ufw
            # Make sure ufw is enabled (non-interactive)
            echo "y" | ufw enable >/dev/null 2>&1 || true
            success "UFW firewall enabled."
            ;;
        rhel)
            install_packages firewalld
            systemctl enable --now firewalld >/dev/null 2>&1
            success "firewalld enabled."
            ;;
    esac
}

firewall_allow_ports() {
    local ports=("$@")
    for port in "${ports[@]}"; do
        output "Opening port ${port}..."
        case "$OS_FAMILY" in
            debian)
                ufw allow "$port" >/dev/null 2>&1
                ;;
            rhel)
                firewall-cmd --add-port="${port}/tcp" --permanent >/dev/null 2>&1
                ;;
        esac
    done

    if [[ "$OS_FAMILY" == "rhel" ]]; then
        firewall-cmd --reload >/dev/null 2>&1
    fi

    success "Firewall ports opened: ${ports[*]}"
}

###############################################################################
# DATABASE HELPERS
###############################################################################

create_db_user() {
    local username="$1"
    local password="$2"
    local host="$3"

    output "Creating MariaDB user '${username}'@'${host}'..."

    # Escape single quotes in the password for SQL safety
    local safe_password="${password//\'/\\\'}"

    mariadb -u root -e "CREATE USER IF NOT EXISTS '${username}'@'${host}' IDENTIFIED BY '${safe_password}';" 2>/dev/null
    success "MariaDB user '${username}'@'${host}' created."
}

grant_all_privileges() {
    local username="$1"
    local host="$2"

    output "Granting all privileges to '${username}'@'${host}' on *.* ..."
    mariadb -u root -e "GRANT ALL PRIVILEGES ON *.* TO '${username}'@'${host}' WITH GRANT OPTION;" 2>/dev/null
    mariadb -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
    success "Privileges granted."
}

###############################################################################
# ROOT CHECK
###############################################################################

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[✘] This script must be run as root (use sudo).${RESET}" >&2
    exit 1
fi

###############################################################################
# MAIN FLOW
###############################################################################

print_banner
detect_os

print_brake 60
echo -e "${BOLD}${ORANGE}  WINGS INSTALLATION CONFIGURATION${RESET}"
print_brake 60
echo ""

# ── Firewall ─────────────────────────────────────────────────────────────────
CONFIGURE_FIREWALL="false"
ask_yes_no "Configure firewall (UFW/firewalld)?" "y" CONFIGURE_FIREWALL

# ── MariaDB ──────────────────────────────────────────────────────────────────
INSTALL_MARIADB="false"
ask_yes_no "Install MariaDB for database host?" "n" INSTALL_MARIADB

DB_USER=""
DB_PASSWORD=""
DB_HOST=""
CONFIGURE_DB_FIREWALL="false"

if [[ "$INSTALL_MARIADB" == "true" ]]; then
    echo ""
    output "MariaDB configuration:"
    input_with_default "Database host username" "pterodactyluser" DB_USER
    required_input "Database host password (required)" DB_PASSWORD
    input_with_default "Database host bind address" "127.0.0.1" DB_HOST
    echo ""
    ask_yes_no "Open port 3306 in firewall for remote DB access?" "n" CONFIGURE_DB_FIREWALL
fi

# ── Let's Encrypt SSL ────────────────────────────────────────────────────────
CONFIGURE_SSL="false"
ask_yes_no "Configure SSL with Let's Encrypt?" "n" CONFIGURE_SSL

SSL_FQDN=""
SSL_EMAIL=""

if [[ "$CONFIGURE_SSL" == "true" ]]; then
    echo ""
    output "Let's Encrypt configuration:"
    required_input "Fully Qualified Domain Name (FQDN) for this node" SSL_FQDN
    required_input "Email address for Let's Encrypt notifications" SSL_EMAIL
fi

###############################################################################
# SUMMARY
###############################################################################

echo ""
print_brake 60
echo -e "${BOLD}${ORANGE}  INSTALLATION SUMMARY${RESET}"
print_brake 60
echo ""
echo -e "  ${WHITE}Operating System   : ${YELLOW}${OS} ${OS_VERSION}${RESET}"
echo -e "  ${WHITE}Configure Firewall : ${YELLOW}${CONFIGURE_FIREWALL}${RESET}"
echo -e "  ${WHITE}Install MariaDB    : ${YELLOW}${INSTALL_MARIADB}${RESET}"
if [[ "$INSTALL_MARIADB" == "true" ]]; then
    echo -e "  ${WHITE}  DB Username      : ${YELLOW}${DB_USER}${RESET}"
    echo -e "  ${WHITE}  DB Password      : ${YELLOW}********${RESET}"
    echo -e "  ${WHITE}  DB Bind Address  : ${YELLOW}${DB_HOST}${RESET}"
    echo -e "  ${WHITE}  Open port 3306   : ${YELLOW}${CONFIGURE_DB_FIREWALL}${RESET}"
fi
echo -e "  ${WHITE}Let's Encrypt SSL  : ${YELLOW}${CONFIGURE_SSL}${RESET}"
if [[ "$CONFIGURE_SSL" == "true" ]]; then
    echo -e "  ${WHITE}  FQDN             : ${YELLOW}${SSL_FQDN}${RESET}"
    echo -e "  ${WHITE}  Email            : ${YELLOW}${SSL_EMAIL}${RESET}"
fi
echo ""
print_brake 60

CONFIRM_INSTALL="false"
ask_yes_no "Proceed with installation?" "y" CONFIRM_INSTALL

if [[ "$CONFIRM_INSTALL" != "true" ]]; then
    warning "Installation cancelled by user."
    exit 0
fi

echo ""
print_brake 60
echo -e "${BOLD}${ORANGE}  STARTING INSTALLATION${RESET}"
print_brake 60
echo ""

###############################################################################
# INSTALLATION FUNCTIONS
###############################################################################

# ── Install dependencies & Docker CE ────────────────────────────────────────
dep_install() {
    output "Installing base dependencies..."

    case "$OS_FAMILY" in
        debian)
            update_repos
            install_packages ca-certificates curl gnupg lsb-release software-properties-common apt-transport-https

            # Docker official GPG key & repository
            output "Adding Docker repository..."
            install -m 0755 -d /etc/apt/keyrings
            if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
                curl -fsSL "https://download.docker.com/linux/${OS}/gpg" | \
                    gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
                chmod a+r /etc/apt/keyrings/docker.gpg
            fi

            local codename
            codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
            local arch
            arch="$(dpkg --print-architecture)"

            echo \
                "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} ${codename} stable" \
                > /etc/apt/sources.list.d/docker.list

            update_repos
            install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            # MariaDB
            if [[ "$INSTALL_MARIADB" == "true" ]]; then
                install_packages mariadb-server
            fi

            # Certbot
            if [[ "$CONFIGURE_SSL" == "true" ]]; then
                install_packages certbot
            fi
            ;;

        rhel)
            update_repos
            install_packages ca-certificates curl gnupg2 yum-utils tar

            # Docker official repository
            output "Adding Docker repository..."
            dnf config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo" >/dev/null 2>&1 || \
                yum-config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo" >/dev/null 2>&1

            install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            # MariaDB
            if [[ "$INSTALL_MARIADB" == "true" ]]; then
                install_packages mariadb-server
            fi

            # Certbot (via EPEL)
            if [[ "$CONFIGURE_SSL" == "true" ]]; then
                install_packages epel-release
                install_packages certbot
            fi
            ;;
    esac

    success "All dependencies installed."
}

# ── Enable & start services ─────────────────────────────────────────────────
enable_services() {
    output "Enabling and starting Docker..."
    systemctl enable --now docker >/dev/null 2>&1
    success "Docker is running."

    if [[ "$INSTALL_MARIADB" == "true" ]]; then
        output "Enabling and starting MariaDB..."
        systemctl enable --now mariadb >/dev/null 2>&1
        success "MariaDB is running."
    fi
}

# ── Download Wings binary ───────────────────────────────────────────────────
ptdl_dl() {
    output "Downloading Pterodactyl Wings..."

    # Detect architecture
    local ARCH
    case "$(uname -m)" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            error "Unsupported CPU architecture: $(uname -m)"
            error "Wings supports amd64 and arm64 only."
            exit 1
            ;;
    esac

    output "Architecture detected: ${ARCH}"

    local WINGS_DL_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH}"

    mkdir -p /etc/pterodactyl
    curl -fsSL -o /usr/local/bin/wings "$WINGS_DL_URL"
    chmod u+x /usr/local/bin/wings

    success "Wings binary installed to /usr/local/bin/wings"
}

# ── Create systemd service file ─────────────────────────────────────────────
systemd_file() {
    output "Creating Wings systemd service..."

    cat > /etc/systemd/system/wings.service <<'UNIT_EOF'
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
UNIT_EOF

    systemctl daemon-reload >/dev/null 2>&1
    success "Wings systemd service created."
}

# ── Configure firewall ports ────────────────────────────────────────────────
firewall_ports() {
    if [[ "$CONFIGURE_FIREWALL" != "true" ]]; then
        warning "Firewall configuration skipped."
        return 0
    fi

    install_firewall

    local ports=("22" "8080" "2022")

    if [[ "$CONFIGURE_SSL" == "true" ]]; then
        ports+=("80" "443")
    fi

    if [[ "$CONFIGURE_DB_FIREWALL" == "true" ]]; then
        ports+=("3306")
    fi

    firewall_allow_ports "${ports[@]}"
    success "Firewall configured."
}

# ── Let's Encrypt ───────────────────────────────────────────────────────────
letsencrypt() {
    if [[ "$CONFIGURE_SSL" != "true" ]]; then
        return 0
    fi

    output "Obtaining Let's Encrypt SSL certificate..."
    output "Domain: ${SSL_FQDN}"
    output "Email:  ${SSL_EMAIL}"

    # Stop anything on port 80 briefly
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    systemctl stop httpd 2>/dev/null || true

    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --preferred-challenges http \
        -d "$SSL_FQDN" \
        --email "$SSL_EMAIL"

    success "SSL certificate obtained for ${SSL_FQDN}"
    output "Certificate: /etc/letsencrypt/live/${SSL_FQDN}/fullchain.pem"
    output "Private Key: /etc/letsencrypt/live/${SSL_FQDN}/privkey.pem"
}

# ── Configure MariaDB ───────────────────────────────────────────────────────
configure_mysql() {
    if [[ "$INSTALL_MARIADB" != "true" ]]; then
        return 0
    fi

    output "Configuring MariaDB for Pterodactyl..."

    # Create the Wings database user
    create_db_user "$DB_USER" "$DB_PASSWORD" "$DB_HOST"
    grant_all_privileges "$DB_USER" "$DB_HOST"

    # If bind address is not 127.0.0.1, update MariaDB config for remote access
    if [[ "$DB_HOST" != "127.0.0.1" && "$DB_HOST" != "localhost" ]]; then
        output "Updating MariaDB bind-address for remote access..."

        local mariadb_conf=""
        if [[ -d /etc/mysql/mariadb.conf.d ]]; then
            mariadb_conf="/etc/mysql/mariadb.conf.d/50-server.cnf"
        elif [[ -f /etc/my.cnf.d/mariadb-server.cnf ]]; then
            mariadb_conf="/etc/my.cnf.d/mariadb-server.cnf"
        elif [[ -f /etc/my.cnf ]]; then
            mariadb_conf="/etc/my.cnf"
        fi

        if [[ -n "$mariadb_conf" && -f "$mariadb_conf" ]]; then
            # Replace existing bind-address or add one under [mysqld]
            if grep -q "^bind-address" "$mariadb_conf" 2>/dev/null; then
                sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" "$mariadb_conf"
            elif grep -q "^\[mysqld\]" "$mariadb_conf" 2>/dev/null; then
                sed -i "/^\[mysqld\]/a bind-address = 0.0.0.0" "$mariadb_conf"
            else
                echo -e "[mysqld]\nbind-address = 0.0.0.0" >> "$mariadb_conf"
            fi

            systemctl restart mariadb >/dev/null 2>&1
            success "MariaDB bind-address set to 0.0.0.0 for remote connections."
        else
            warning "Could not locate MariaDB config. Please set bind-address manually."
        fi
    fi

    success "MariaDB configured for Pterodactyl database host."
}

###############################################################################
# PERFORM INSTALLATION
###############################################################################

perform_install() {
    dep_install
    enable_services
    ptdl_dl
    systemd_file
    firewall_ports
    configure_mysql
    letsencrypt
}

perform_install

###############################################################################
# COMPLETION
###############################################################################

echo ""
print_brake 60
echo ""
print_banner
echo -e "${BOLD}${GREEN}  ✔  WINGS INSTALLATION COMPLETE!${RESET}"
echo ""
print_brake 60
echo ""
echo -e "${WHITE}  Next steps to finish setting up this Wings node:${RESET}"
echo ""
echo -e "  ${ORANGE}1.${RESET} ${WHITE}Go to your Pterodactyl Panel admin area.${RESET}"
echo -e "  ${ORANGE}2.${RESET} ${WHITE}Navigate to ${YELLOW}Nodes${WHITE} and create a new node for this server.${RESET}"
echo -e "  ${ORANGE}3.${RESET} ${WHITE}Copy the auto-deploy configuration from the${RESET}"
echo -e "     ${WHITE}${YELLOW}Configuration${WHITE} tab of the new node.${RESET}"
echo -e "  ${ORANGE}4.${RESET} ${WHITE}Paste it into ${YELLOW}/etc/pterodactyl/config.yml${WHITE} on this server.${RESET}"
if [[ "$CONFIGURE_SSL" == "true" ]]; then
    echo -e "  ${ORANGE}5.${RESET} ${WHITE}Update config.yml to use your SSL certificate paths:${RESET}"
    echo -e "     ${YELLOW}  cert: /etc/letsencrypt/live/${SSL_FQDN}/fullchain.pem${RESET}"
    echo -e "     ${YELLOW}  key:  /etc/letsencrypt/live/${SSL_FQDN}/privkey.pem${RESET}"
    echo -e "  ${ORANGE}6.${RESET} ${WHITE}Start Wings:${RESET}"
else
    echo -e "  ${ORANGE}5.${RESET} ${WHITE}Start Wings:${RESET}"
fi
echo ""
echo -e "     ${YELLOW}sudo systemctl enable --now wings${RESET}"
echo ""
if [[ "$INSTALL_MARIADB" == "true" ]]; then
    echo -e "  ${WHITE}Database host credentials (save these!):${RESET}"
    echo -e "     ${WHITE}Username : ${YELLOW}${DB_USER}${RESET}"
    echo -e "     ${WHITE}Password : ${YELLOW}${DB_PASSWORD}${RESET}"
    echo -e "     ${WHITE}Host     : ${YELLOW}${DB_HOST}${RESET}"
    echo -e "     ${WHITE}Port     : ${YELLOW}3306${RESET}"
    echo ""
fi
print_brake 60
echo -e "${ORANGE}  Thank you for using ${BOLD}Sundy.Systems${RESET}${ORANGE} Wings Installer!${RESET}"
print_brake 60
echo ""
