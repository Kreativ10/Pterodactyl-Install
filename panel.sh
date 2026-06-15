#!/bin/bash
###############################################################################
#                                                                             #
#   Pterodactyl Panel Installer v2.0                                          #
#   Copyright (c) 2024-2026 Sundy.Systems — All rights reserved.             #
#                                                                             #
#   This script installs and configures the Pterodactyl Panel with all        #
#   required dependencies on supported Linux distributions.                   #
#                                                                             #
#   Supported OS: Ubuntu 20.04/22.04/24.04, Debian 11/12,                    #
#                 Rocky Linux 8/9, AlmaLinux 8/9                              #
#                                                                             #
###############################################################################

set -e

###############################################################################
# GLOBAL CONSTANTS
###############################################################################

PANEL_DL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
PANEL_DIR="/var/www/pterodactyl"
SCRIPT_VERSION="2.0"

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
# VARIABLES (populated during interactive session)
###############################################################################

OS=""
OS_VER=""
OS_VER_MAJOR=""
WEBSERVER_USER=""

FQDN=""
TIMEZONE=""
ADMIN_EMAIL=""
ADMIN_USER=""
ADMIN_FIRST=""
ADMIN_LAST=""
ADMIN_PASS=""
LE_EMAIL=""
DB_NAME=""
DB_USER=""
DB_PASS=""
CONFIGURE_FW="false"
CONFIGURE_SSL="false"
ASSUME_SSL="false"
ENABLE_TELEMETRY="true"

###############################################################################
# DISPLAY FUNCTIONS
###############################################################################

show_banner() {
    echo ""
    echo -e "${BOLD}${ORANGE} ███████╗██╗   ██╗███╗   ██╗██████╗ ██╗   ██╗${RESET}"
    echo -e "${BOLD}${ORANGE} ██╔════╝██║   ██║████╗  ██║██╔══██╗╚██╗ ██╔╝${RESET}"
    echo -e "${BOLD}${ORANGE} ███████╗██║   ██║██╔██╗ ██║██║  ██║ ╚████╔╝${RESET}"
    echo -e "${BOLD}${ORANGE} ╚════██║██║   ██║██║╚██╗██║██║  ██║  ╚██╔╝${RESET}"
    echo -e "${BOLD}${ORANGE} ███████║╚██████╔╝██║ ╚████║██████╔╝   ██║${RESET}"
    echo -e "${BOLD}${ORANGE} ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝    ╚═╝${RESET}"
    echo -e "${DARK_ORANGE}        ┌─────────────────────────────┐${RESET}"
    echo -e "${DARK_ORANGE}        │   ${WHITE}S U N D Y . S Y S T E M S${DARK_ORANGE} │${RESET}"
    echo -e "${DARK_ORANGE}        │    ${WHITE}Panel Installer v${SCRIPT_VERSION}${DARK_ORANGE}     │${RESET}"
    echo -e "${DARK_ORANGE}        └─────────────────────────────┘${RESET}"
    echo ""
}

output() {
    echo -e "${ORANGE}[*]${RESET} ${WHITE}$1${RESET}"
}

success() {
    echo -e "${GREEN}[✓]${RESET} ${WHITE}$1${RESET}"
}

error() {
    echo -e "${RED}[✗] ERROR:${RESET} ${WHITE}$1${RESET}" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}[!] WARNING:${RESET} ${WHITE}$1${RESET}" >&2
}

print_brake() {
    local len="${1:-60}"
    local line=""
    for ((i = 0; i < len; i++)); do
        line="${line}─"
    done
    echo -e "${DARK_ORANGE}${line}${RESET}"
}

print_header() {
    echo ""
    print_brake 60
    echo -e "${BOLD}${ORANGE}  $1${RESET}"
    print_brake 60
}

###############################################################################
# INPUT HELPER FUNCTIONS
###############################################################################

# All input functions use printf -v to set the caller's variable directly.
# Prompts are printed to stderr so they always appear on the terminal.

required_input() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local result=""

    while true; do
        if [[ -n "$default" ]]; then
            echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET} [${ORANGE}${default}${RESET}]: " >&2
        else
            echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET}: " >&2
        fi
        read -r result

        if [[ -z "$result" && -n "$default" ]]; then
            result="$default"
        fi

        if [[ -n "$result" ]]; then
            printf -v "$varname" '%s' "$result"
            return 0
        fi

        warning "This field is required. Please enter a value."
    done
}

password_input() {
    local prompt="$1"
    local varname="$2"
    local pass1=""
    local pass2=""

    while true; do
        echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET}: " >&2
        read -rs pass1
        echo "" >&2

        if [[ -z "$pass1" ]]; then
            warning "Password cannot be empty."
            continue
        fi

        if [[ "${#pass1}" -lt 8 ]]; then
            warning "Password must be at least 8 characters long."
            continue
        fi

        echo -en "${ORANGE}▸${RESET} ${WHITE}Confirm password${RESET}: " >&2
        read -rs pass2
        echo "" >&2

        if [[ "$pass1" != "$pass2" ]]; then
            warning "Passwords do not match. Please try again."
            continue
        fi

        printf -v "$varname" '%s' "$pass1"
        return 0
    done
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local varname="$3"
    local result=""

    if [[ "$default" == "y" ]]; then
        local hint="Y/n"
    else
        local hint="y/N"
    fi

    while true; do
        echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET} [${ORANGE}${hint}${RESET}]: " >&2
        read -r result

        if [[ -z "$result" ]]; then
            result="$default"
        fi

        case "${result,,}" in
            y|yes) printf -v "$varname" '%s' "y"; return 0 ;;
            n|no)  printf -v "$varname" '%s' "n"; return 0 ;;
            *) warning "Please answer y or n." ;;
        esac
    done
}

###############################################################################
# UTILITY FUNCTIONS
###############################################################################

gen_passwd() {
    local length="${1:-32}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
    echo ""
}

validate_fqdn() {
    local fqdn="$1"

    # Allow IP addresses
    if [[ "$fqdn" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi

    # Validate domain format: labels separated by dots, each 1-63 chars, alphanumeric + hyphens
    if [[ "$fqdn" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 0
    fi

    return 1
}

validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

validate_timezone() {
    local tz="$1"
    if [[ -f "/usr/share/zoneinfo/${tz}" ]]; then
        return 0
    fi
    return 1
}

validate_db_name() {
    local name="$1"
    # Only allow alphanumeric and underscores, must start with a letter or underscore
    if [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,63}$ ]]; then
        return 0
    fi
    return 1
}

validate_username() {
    local name="$1"
    # Alphanumeric, underscores, hyphens, 1-32 chars
    if [[ "$name" =~ ^[a-zA-Z0-9_-]{1,32}$ ]]; then
        return 0
    fi
    return 1
}

escape_sql_password() {
    local pass="$1"
    # Escape single quotes by doubling them for SQL
    pass="${pass//\'/\'\'}"
    # Escape backslashes
    pass="${pass//\\/\\\\}"
    echo "$pass"
}

###############################################################################
# OS DETECTION
###############################################################################

detect_os() {
    output "Detecting operating system..."

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS="${ID}"
        OS_VER="${VERSION_ID}"
    else
        error "Cannot detect operating system. /etc/os-release not found."
    fi

    # Extract major version
    OS_VER_MAJOR="${OS_VER%%.*}"

    # Determine web server user
    case "$OS" in
        ubuntu|debian)
            WEBSERVER_USER="www-data"
            ;;
        rocky|almalinux)
            WEBSERVER_USER="nginx"
            ;;
        *)
            error "Unsupported operating system: ${OS}"
            ;;
    esac

    # Verify supported versions
    case "$OS" in
        ubuntu)
            case "$OS_VER" in
                20.04|22.04|24.04) ;;
                *) error "Unsupported Ubuntu version: ${OS_VER}. Supported: 20.04, 22.04, 24.04" ;;
            esac
            ;;
        debian)
            case "$OS_VER_MAJOR" in
                11|12) ;;
                *) error "Unsupported Debian version: ${OS_VER_MAJOR}. Supported: 11, 12" ;;
            esac
            ;;
        rocky)
            case "$OS_VER_MAJOR" in
                8|9) ;;
                *) error "Unsupported Rocky Linux version: ${OS_VER_MAJOR}. Supported: 8, 9" ;;
            esac
            ;;
        almalinux)
            case "$OS_VER_MAJOR" in
                8|9) ;;
                *) error "Unsupported AlmaLinux version: ${OS_VER_MAJOR}. Supported: 8, 9" ;;
            esac
            ;;
        *)
            error "Unsupported operating system: ${OS}"
            ;;
    esac

    success "Detected: ${OS} ${OS_VER} (web user: ${WEBSERVER_USER})"
}

###############################################################################
# PACKAGE MANAGEMENT
###############################################################################

update_repos() {
    output "Updating package repositories..."
    case "$OS" in
        ubuntu|debian)
            apt-get update -y > /dev/null 2>&1
            ;;
        rocky|almalinux)
            dnf makecache -y > /dev/null 2>&1
            ;;
    esac
    success "Package repositories updated."
}

install_packages() {
    local packages=("$@")
    case "$OS" in
        ubuntu|debian)
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" > /dev/null 2>&1
            ;;
        rocky|almalinux)
            dnf install -y "${packages[@]}" > /dev/null 2>&1
            ;;
    esac
}

###############################################################################
# FIREWALL FUNCTIONS
###############################################################################

install_firewall() {
    output "Installing firewall..."
    case "$OS" in
        ubuntu|debian)
            install_packages ufw
            success "UFW installed."
            ;;
        rocky|almalinux)
            install_packages firewalld
            systemctl enable --now firewalld > /dev/null 2>&1
            success "Firewalld installed and enabled."
            ;;
    esac
}

firewall_allow_ports() {
    output "Configuring firewall rules..."
    case "$OS" in
        ubuntu|debian)
            ufw allow 22/tcp > /dev/null 2>&1 || true
            ufw allow 80/tcp > /dev/null 2>&1 || true
            ufw allow 443/tcp > /dev/null 2>&1 || true
            yes | ufw enable > /dev/null 2>&1 || true
            success "UFW configured: ports 22, 80, 443 opened."
            ;;
        rocky|almalinux)
            firewall-cmd --permanent --add-service=ssh > /dev/null 2>&1 || true
            firewall-cmd --permanent --add-service=http > /dev/null 2>&1 || true
            firewall-cmd --permanent --add-service=https > /dev/null 2>&1 || true
            firewall-cmd --reload > /dev/null 2>&1 || true
            success "Firewalld configured: SSH, HTTP, HTTPS services opened."
            ;;
    esac
}

###############################################################################
# DATABASE FUNCTIONS
###############################################################################

create_db() {
    local db_name="$1"

    if ! validate_db_name "$db_name"; then
        error "Invalid database name: ${db_name}"
    fi

    output "Creating database '${db_name}'..."
    mariadb -u root -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;" 2>/dev/null
    success "Database '${db_name}' created."
}

create_db_user() {
    local db_user="$1"
    local db_pass="$2"
    local db_name="$3"

    if ! validate_db_name "$db_user"; then
        error "Invalid database username: ${db_user}"
    fi

    local escaped_pass
    escaped_pass="$(escape_sql_password "$db_pass")"

    output "Creating database user '${db_user}'..."
    mariadb -u root <<EOSQL
CREATE USER IF NOT EXISTS '${db_user}'@'127.0.0.1' IDENTIFIED BY '${escaped_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOSQL

    success "Database user '${db_user}' created and granted privileges on '${db_name}'."
}

###############################################################################
# ROOT CHECK
###############################################################################

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be run as root. Please use 'sudo bash $0' or run as root."
    fi
}

###############################################################################
# INTERACTIVE MENU — GATHER USER INPUT
###############################################################################

gather_input() {
    print_header "Panel Configuration"
    echo ""

    # FQDN
    while true; do
        required_input "Panel FQDN (domain name or IP address)" "" FQDN
        if validate_fqdn "$FQDN"; then
            break
        fi
        warning "Invalid FQDN format. Enter a valid domain (e.g., panel.example.com) or IP address."
    done
    echo ""

    # Timezone
    while true; do
        required_input "Timezone" "Europe/Moscow" TIMEZONE
        if validate_timezone "$TIMEZONE"; then
            break
        fi
        warning "Invalid timezone. Must be a valid timezone from /usr/share/zoneinfo."
    done
    echo ""

    print_header "Admin Account"
    echo ""

    # Admin Email
    while true; do
        required_input "Admin email address" "" ADMIN_EMAIL
        if validate_email "$ADMIN_EMAIL"; then
            break
        fi
        warning "Invalid email format. Please enter a valid email address."
    done
    echo ""

    # Admin Username
    while true; do
        required_input "Admin username" "admin" ADMIN_USER
        if validate_username "$ADMIN_USER"; then
            break
        fi
        warning "Invalid username. Use 1-32 alphanumeric characters, underscores, or hyphens."
    done
    echo ""

    # Admin First Name
    required_input "Admin first name" "Admin" ADMIN_FIRST
    echo ""

    # Admin Last Name
    required_input "Admin last name" "User" ADMIN_LAST
    echo ""

    # Admin Password
    password_input "Admin password (min 8 characters)" ADMIN_PASS
    echo ""

    print_header "Email & SSL"
    echo ""

    # Let's Encrypt / Panel Email
    while true; do
        required_input "Email for Let's Encrypt / Panel notifications" "$ADMIN_EMAIL" LE_EMAIL
        if validate_email "$LE_EMAIL"; then
            break
        fi
        warning "Invalid email format."
    done
    echo ""

    print_header "Database Configuration"
    echo ""

    # Database Name
    while true; do
        required_input "MySQL database name" "panel" DB_NAME
        if validate_db_name "$DB_NAME"; then
            break
        fi
        warning "Invalid database name. Use alphanumeric characters and underscores only."
    done
    echo ""

    # Database Username
    while true; do
        required_input "MySQL username" "pterodactyl" DB_USER
        if validate_db_name "$DB_USER"; then
            break
        fi
        warning "Invalid username. Use alphanumeric characters and underscores only."
    done
    echo ""

    # Database Password
    local auto_pass
    auto_pass="$(gen_passwd 32)"
    echo -e "${ORANGE}▸${RESET} ${WHITE}Auto-generated MySQL password:${RESET} ${GREEN}${auto_pass}${RESET}"
    local customize_pw
    ask_yes_no "Would you like to set a custom MySQL password instead?" "n" customize_pw
    if [[ "$customize_pw" == "y" ]]; then
        password_input "MySQL password (min 8 characters)" DB_PASS
    else
        DB_PASS="$auto_pass"
    fi
    echo ""

    print_header "Additional Options"
    echo ""

    # Firewall
    local fw_answer
    ask_yes_no "Configure firewall (UFW/firewalld)?" "y" fw_answer
    [[ "$fw_answer" == "y" ]] && CONFIGURE_FW="true"
    echo ""

    # SSL with Let's Encrypt
    local ssl_answer
    ask_yes_no "Configure SSL with Let's Encrypt?" "y" ssl_answer
    if [[ "$ssl_answer" == "y" ]]; then
        CONFIGURE_SSL="true"
        ASSUME_SSL="true"
    else
        echo ""
        local assume_answer
        ask_yes_no "Assume SSL (e.g., behind a reverse proxy)?" "n" assume_answer
        [[ "$assume_answer" == "y" ]] && ASSUME_SSL="true"
    fi
    echo ""

    # Telemetry
    local tele_answer
    ask_yes_no "Enable Pterodactyl telemetry?" "y" tele_answer
    [[ "$tele_answer" == "n" ]] && ENABLE_TELEMETRY="false"
    echo ""
}

###############################################################################
# DISPLAY SUMMARY & CONFIRM
###############################################################################

show_summary() {
    print_header "Installation Summary"
    echo ""
    echo -e "  ${BOLD}${WHITE}OS Detected:${RESET}          ${ORANGE}${OS} ${OS_VER}${RESET}"
    echo -e "  ${BOLD}${WHITE}Panel FQDN:${RESET}           ${ORANGE}${FQDN}${RESET}"
    echo -e "  ${BOLD}${WHITE}Timezone:${RESET}             ${ORANGE}${TIMEZONE}${RESET}"
    echo -e "  ${BOLD}${WHITE}Admin Email:${RESET}          ${ORANGE}${ADMIN_EMAIL}${RESET}"
    echo -e "  ${BOLD}${WHITE}Admin Username:${RESET}       ${ORANGE}${ADMIN_USER}${RESET}"
    echo -e "  ${BOLD}${WHITE}Admin Name:${RESET}           ${ORANGE}${ADMIN_FIRST} ${ADMIN_LAST}${RESET}"
    echo -e "  ${BOLD}${WHITE}LE/Panel Email:${RESET}       ${ORANGE}${LE_EMAIL}${RESET}"
    echo -e "  ${BOLD}${WHITE}DB Name:${RESET}              ${ORANGE}${DB_NAME}${RESET}"
    echo -e "  ${BOLD}${WHITE}DB User:${RESET}              ${ORANGE}${DB_USER}${RESET}"
    echo -e "  ${BOLD}${WHITE}DB Password:${RESET}          ${ORANGE}(hidden)${RESET}"
    echo -e "  ${BOLD}${WHITE}Firewall:${RESET}             ${ORANGE}${CONFIGURE_FW}${RESET}"
    echo -e "  ${BOLD}${WHITE}Let's Encrypt SSL:${RESET}    ${ORANGE}${CONFIGURE_SSL}${RESET}"
    echo -e "  ${BOLD}${WHITE}Assume SSL:${RESET}           ${ORANGE}${ASSUME_SSL}${RESET}"
    echo -e "  ${BOLD}${WHITE}Telemetry:${RESET}            ${ORANGE}${ENABLE_TELEMETRY}${RESET}"
    echo ""
    print_brake 60

    echo ""
    local confirm
    ask_yes_no "Proceed with installation?" "y" confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${YELLOW}Installation cancelled by user.${RESET}"
        exit 0
    fi
    echo ""
}

###############################################################################
# DEPENDENCY INSTALLATION
###############################################################################

dep_install() {
    print_header "Installing Dependencies"
    echo ""

    case "$OS" in
        ubuntu|debian)
            dep_install_debian
            ;;
        rocky|almalinux)
            dep_install_rhel
            ;;
    esac
}

dep_install_debian() {
    output "Installing base packages..."
    install_packages software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release

    # Add PHP repository (Ondrej PPA for Ubuntu, sury.org for Debian)
    output "Adding PHP 8.3 repository..."
    case "$OS" in
        ubuntu)
            LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
            ;;
        debian)
            curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb 2>/dev/null
            dpkg -i /tmp/debsuryorg-archive-keyring.deb > /dev/null 2>&1
            rm -f /tmp/debsuryorg-archive-keyring.deb
            echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
                > /etc/apt/sources.list.d/sury-php.list
            ;;
    esac

    # Add MariaDB repository
    output "Adding MariaDB repository..."
    local mariadb_setup
    mariadb_setup="$(mktemp)"
    curl -sS -o "$mariadb_setup" https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
    bash "$mariadb_setup" --mariadb-server-version=mariadb-10.11 > /dev/null 2>&1 || true
    rm -f "$mariadb_setup"

    update_repos

    output "Installing PHP 8.3, MariaDB, nginx, Redis, and utilities..."
    install_packages \
        php8.3 \
        php8.3-common \
        php8.3-cli \
        php8.3-gd \
        php8.3-mysql \
        php8.3-mbstring \
        php8.3-bcmath \
        php8.3-xml \
        php8.3-fpm \
        php8.3-curl \
        php8.3-zip \
        php8.3-intl \
        php8.3-sqlite3 \
        mariadb-server \
        nginx \
        redis-server \
        tar \
        unzip \
        git \
        cron \
        certbot \
        python3-certbot-nginx

    # Enable and start services
    output "Enabling services..."
    systemctl enable --now mariadb > /dev/null 2>&1
    systemctl enable --now redis-server > /dev/null 2>&1
    systemctl enable --now nginx > /dev/null 2>&1
    systemctl enable --now "php8.3-fpm" > /dev/null 2>&1

    success "All Debian/Ubuntu dependencies installed."
}

dep_install_rhel() {
    output "Installing base packages and enabling repositories..."

    # Enable required repos
    if [[ "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
        case "$OS_VER_MAJOR" in
            8)
                dnf install -y epel-release > /dev/null 2>&1
                dnf module reset -y php > /dev/null 2>&1 || true
                ;;
            9)
                dnf install -y epel-release > /dev/null 2>&1
                dnf config-manager --set-enabled crb > /dev/null 2>&1 || \
                    dnf config-manager --set-enabled powertools > /dev/null 2>&1 || true
                ;;
        esac
    fi

    # Add Remi repo for PHP 8.3
    output "Adding Remi PHP repository..."
    dnf install -y "https://rpms.remirepo.net/enterprise/remi-release-${OS_VER_MAJOR}.rpm" > /dev/null 2>&1 || true
    dnf module reset -y php > /dev/null 2>&1 || true
    dnf module enable -y php:remi-8.3 > /dev/null 2>&1 || true

    # Add MariaDB repository
    output "Adding MariaDB repository..."
    local mariadb_setup
    mariadb_setup="$(mktemp)"
    curl -sS -o "$mariadb_setup" https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
    bash "$mariadb_setup" --mariadb-server-version=mariadb-10.11 > /dev/null 2>&1 || true
    rm -f "$mariadb_setup"

    dnf makecache -y > /dev/null 2>&1

    output "Installing PHP 8.3, MariaDB, nginx, Redis, and utilities..."
    install_packages \
        php \
        php-common \
        php-cli \
        php-gd \
        php-mysqlnd \
        php-mbstring \
        php-bcmath \
        php-xml \
        php-fpm \
        php-curl \
        php-zip \
        php-intl \
        php-sqlite3 \
        mariadb-server \
        nginx \
        redis \
        tar \
        unzip \
        git \
        cronie \
        certbot \
        python3-certbot-nginx

    # Configure PHP-FPM for nginx
    output "Configuring PHP-FPM..."
    local fpm_conf="/etc/php-fpm.d/www.conf"
    if [[ -f "$fpm_conf" ]]; then
        sed -i 's/^user = apache/user = nginx/' "$fpm_conf"
        sed -i 's/^group = apache/group = nginx/' "$fpm_conf"
        sed -i 's|^listen = .*|listen = /run/php-fpm/www.sock|' "$fpm_conf"
        sed -i 's/^;listen.owner = .*/listen.owner = nginx/' "$fpm_conf"
        sed -i 's/^;listen.group = .*/listen.group = nginx/' "$fpm_conf"
        sed -i 's/^listen.owner = .*/listen.owner = nginx/' "$fpm_conf"
        sed -i 's/^listen.group = .*/listen.group = nginx/' "$fpm_conf"
    fi

    # Enable and start services
    output "Enabling services..."
    systemctl enable --now mariadb > /dev/null 2>&1
    systemctl enable --now redis > /dev/null 2>&1
    systemctl enable --now nginx > /dev/null 2>&1
    systemctl enable --now php-fpm > /dev/null 2>&1

    # SELinux adjustments
    if command -v setsebool &>/dev/null; then
        output "Configuring SELinux..."
        setsebool -P httpd_can_network_connect 1 > /dev/null 2>&1 || true
        setsebool -P httpd_execmem 1 > /dev/null 2>&1 || true
        setsebool -P httpd_unified 1 > /dev/null 2>&1 || true
    fi

    success "All RHEL/Rocky/Alma dependencies installed."
}

###############################################################################
# COMPOSER INSTALLATION
###############################################################################

install_composer() {
    output "Installing Composer..."

    local expected_sig
    expected_sig="$(curl -sSL https://composer.github.io/installer.sig 2>/dev/null)"

    curl -sSL https://getcomposer.org/installer -o /tmp/composer-setup.php 2>/dev/null

    local actual_sig
    actual_sig="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"

    if [[ "$expected_sig" != "$actual_sig" ]]; then
        rm -f /tmp/composer-setup.php
        error "Composer installer signature verification failed!"
    fi

    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer > /dev/null 2>&1
    rm -f /tmp/composer-setup.php

    if command -v composer &>/dev/null; then
        success "Composer installed: $(composer --version 2>/dev/null | head -1)"
    else
        error "Composer installation failed."
    fi
}

###############################################################################
# DOWNLOAD PTERODACTYL PANEL
###############################################################################

ptdl_dl() {
    output "Downloading Pterodactyl Panel..."

    mkdir -p "$PANEL_DIR"

    curl -sSL "$PANEL_DL_URL" -o /tmp/panel.tar.gz 2>/dev/null

    if [[ ! -f /tmp/panel.tar.gz ]]; then
        error "Failed to download Pterodactyl Panel."
    fi

    tar -xzf /tmp/panel.tar.gz -C "$PANEL_DIR" --strip-components=0
    rm -f /tmp/panel.tar.gz

    success "Pterodactyl Panel downloaded to ${PANEL_DIR}."
}

###############################################################################
# COMPOSER DEPENDENCIES
###############################################################################

install_composer_deps() {
    output "Installing Composer dependencies (this may take a moment)..."

    cp -- "${PANEL_DIR}/.env.example" "${PANEL_DIR}/.env"

    COMPOSER_ALLOW_SUPERUSER=1 composer install \
        --no-dev \
        --optimize-autoloader \
        --working-dir="$PANEL_DIR" \
        --no-interaction \
        > /dev/null 2>&1

    success "Composer dependencies installed."
}

###############################################################################
# PANEL CONFIGURATION
###############################################################################

configure() {
    output "Configuring Pterodactyl Panel..."

    local app_url
    if [[ "$ASSUME_SSL" == "true" ]]; then
        app_url="https://${FQDN}"
    else
        app_url="http://${FQDN}"
    fi

    # Generate application key
    php "${PANEL_DIR}/artisan" key:generate --force --no-interaction > /dev/null 2>&1
    success "Application key generated."

    # Environment setup
    output "Setting up environment configuration..."
    php "${PANEL_DIR}/artisan" p:environment:setup \
        --author="${LE_EMAIL}" \
        --url="${app_url}" \
        --timezone="${TIMEZONE}" \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=127.0.0.1 \
        --redis-pass="" \
        --redis-port=6379 \
        --settings-ui=true \
        --no-interaction \
        > /dev/null 2>&1 || {
            warning "Environment setup command encountered an issue, continuing..."
        }
    success "Environment configured."

    # Telemetry
    if [[ "$ENABLE_TELEMETRY" == "true" ]]; then
        php "${PANEL_DIR}/artisan" p:environment:setup \
            --telemetry=true \
            --no-interaction \
            > /dev/null 2>&1 || true
    fi

    # Database configuration
    output "Configuring database connection..."
    php "${PANEL_DIR}/artisan" p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database="${DB_NAME}" \
        --username="${DB_USER}" \
        --password="${DB_PASS}" \
        --no-interaction \
        > /dev/null 2>&1
    success "Database connection configured."

    # Run migrations
    output "Running database migrations..."
    php "${PANEL_DIR}/artisan" migrate --seed --force --no-interaction > /dev/null 2>&1
    success "Database migrations completed."

    # Create admin user
    output "Creating admin user..."
    php "${PANEL_DIR}/artisan" p:user:make \
        --email="${ADMIN_EMAIL}" \
        --username="${ADMIN_USER}" \
        --name-first="${ADMIN_FIRST}" \
        --name-last="${ADMIN_LAST}" \
        --password="${ADMIN_PASS}" \
        --admin=1 \
        --no-interaction \
        > /dev/null 2>&1
    success "Admin user '${ADMIN_USER}' created."
}

###############################################################################
# FILE PERMISSIONS
###############################################################################

set_folder_permissions() {
    output "Setting file permissions..."

    chown -R "${WEBSERVER_USER}:${WEBSERVER_USER}" "$PANEL_DIR"
    find "$PANEL_DIR" -type f -exec chmod 644 {} \;
    find "$PANEL_DIR" -type d -exec chmod 755 {} \;

    # Storage and cache need to be writable
    chmod -R 755 "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache"

    success "File permissions set (owner: ${WEBSERVER_USER})."
}

###############################################################################
# CRON JOB
###############################################################################

insert_cronjob() {
    output "Installing cron job..."

    local cron_line="* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1"
    local existing_cron

    existing_cron="$(crontab -u "${WEBSERVER_USER}" -l 2>/dev/null || true)"

    if echo "$existing_cron" | grep -qF "artisan schedule:run"; then
        warning "Cron job already exists, skipping."
    else
        (echo "$existing_cron"; echo "$cron_line") | crontab -u "${WEBSERVER_USER}" -
        success "Cron job installed for user '${WEBSERVER_USER}'."
    fi
}

###############################################################################
# PTEROQ SYSTEMD SERVICE
###############################################################################

install_pteroq() {
    output "Creating pteroq systemd service..."

    local redis_service
    case "$OS" in
        ubuntu|debian) redis_service="redis-server.service" ;;
        rocky|almalinux) redis_service="redis.service" ;;
    esac

    cat > /etc/systemd/system/pteroq.service <<EOSERVICE
# Pterodactyl Queue Worker Service
# Installed by Sundy.Systems Panel Installer v${SCRIPT_VERSION}

[Unit]
Description=Pterodactyl Queue Worker
After=${redis_service}

[Service]
User=${WEBSERVER_USER}
Group=${WEBSERVER_USER}
Restart=always
ExecStart=/usr/bin/php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOSERVICE

    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable --now pteroq > /dev/null 2>&1

    success "pteroq service created and enabled."
}

###############################################################################
# NGINX CONFIGURATION
###############################################################################

configure_nginx() {
    output "Configuring nginx..."

    local php_sock
    case "$OS" in
        ubuntu|debian)
            php_sock="/run/php/php8.3-fpm.sock"
            ;;
        rocky|almalinux)
            php_sock="/run/php-fpm/www.sock"
            ;;
    esac

    # Remove default nginx site if present
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true

    local nginx_conf_dir
    case "$OS" in
        ubuntu|debian)
            nginx_conf_dir="/etc/nginx/sites-available"
            mkdir -p /etc/nginx/sites-enabled
            ;;
        rocky|almalinux)
            nginx_conf_dir="/etc/nginx/conf.d"
            ;;
    esac

    if [[ "$CONFIGURE_SSL" == "true" ]]; then
        write_nginx_ssl_config "$nginx_conf_dir" "$php_sock"
    elif [[ "$ASSUME_SSL" == "true" ]]; then
        write_nginx_ssl_assumed_config "$nginx_conf_dir" "$php_sock"
    else
        write_nginx_nossl_config "$nginx_conf_dir" "$php_sock"
    fi

    # Create symlink for Debian/Ubuntu
    case "$OS" in
        ubuntu|debian)
            ln -sf "${nginx_conf_dir}/pterodactyl.conf" /etc/nginx/sites-enabled/pterodactyl.conf
            ;;
    esac

    # Test nginx config
    if nginx -t > /dev/null 2>&1; then
        systemctl restart nginx > /dev/null 2>&1
        success "Nginx configured and restarted."
    else
        warning "Nginx configuration test failed. Please review /etc/nginx manually."
        nginx -t 2>&1 || true
    fi
}

write_nginx_nossl_config() {
    local conf_dir="$1"
    local php_sock="$2"

    cat > "${conf_dir}/pterodactyl.conf" <<EONGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${FQDN};

    root ${PANEL_DIR}/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # Allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:${php_sock};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EONGINX

    success "Nginx non-SSL configuration written."
}

write_nginx_ssl_config() {
    local conf_dir="$1"
    local php_sock="$2"

    # Write initial non-SSL config for certbot to work with
    write_nginx_nossl_config "$conf_dir" "$php_sock"

    # Certbot will modify the config to add SSL
    # But we'll write the full SSL config after obtaining the cert
    # For now, mark that we need to rewrite after LE
}

write_nginx_ssl_assumed_config() {
    local conf_dir="$1"
    local php_sock="$2"

    cat > "${conf_dir}/pterodactyl.conf" <<EONGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${FQDN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${FQDN};

    root ${PANEL_DIR}/public;
    index index.html index.htm index.php;
    charset utf-8;

    ssl_certificate /etc/letsencrypt/live/${FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${FQDN}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    # HSTS
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # Allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:${php_sock};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EONGINX

    success "Nginx SSL configuration written."
}

finalize_nginx_ssl() {
    local conf_dir
    local php_sock
    case "$OS" in
        ubuntu|debian)
            conf_dir="/etc/nginx/sites-available"
            php_sock="/run/php/php8.3-fpm.sock"
            ;;
        rocky|almalinux)
            conf_dir="/etc/nginx/conf.d"
            php_sock="/run/php-fpm/www.sock"
            ;;
    esac

    cat > "${conf_dir}/pterodactyl.conf" <<EONGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${FQDN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${FQDN};

    root ${PANEL_DIR}/public;
    index index.html index.htm index.php;
    charset utf-8;

    ssl_certificate /etc/letsencrypt/live/${FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${FQDN}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    # HSTS
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # Allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:${php_sock};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EONGINX

    # Test and reload nginx
    if nginx -t > /dev/null 2>&1; then
        systemctl reload nginx > /dev/null 2>&1
        success "Nginx SSL configuration finalized and reloaded."
    else
        warning "Nginx config test failed after SSL finalization."
    fi
}

###############################################################################
# LET'S ENCRYPT
###############################################################################

letsencrypt() {
    output "Obtaining Let's Encrypt SSL certificate..."

    if [[ "$FQDN" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        warning "Let's Encrypt cannot issue certificates for IP addresses."
        warning "Skipping SSL configuration. Panel will run on HTTP."
        CONFIGURE_SSL="false"
        ASSUME_SSL="false"
        return 0
    fi

    # Stop nginx temporarily for standalone mode, or use webroot
    certbot certonly \
        --nginx \
        --non-interactive \
        --agree-tos \
        --email "${LE_EMAIL}" \
        -d "${FQDN}" \
        2>&1 | while IFS= read -r line; do
            output "  certbot: ${line}"
        done

    # Check if cert was obtained
    if [[ -f "/etc/letsencrypt/live/${FQDN}/fullchain.pem" ]]; then
        success "SSL certificate obtained for ${FQDN}."

        # Now rewrite nginx config with SSL
        finalize_nginx_ssl

        # Set up auto-renewal
        output "Setting up automatic certificate renewal..."
        systemctl enable --now certbot.timer > /dev/null 2>&1 || {
            # Fallback: add cron for renewal
            (crontab -l 2>/dev/null || true; echo "0 23 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'") | crontab -
        }
        success "Automatic SSL renewal configured."
    else
        warning "Failed to obtain SSL certificate. Panel will run on HTTP."
        CONFIGURE_SSL="false"
        ASSUME_SSL="false"
    fi
}

###############################################################################
# PERFORM INSTALLATION (main orchestrator)
###############################################################################

perform_install() {
    local start_time
    start_time="$(date +%s)"

    echo ""
    print_header "Starting Installation"
    echo ""

    # Step 1: Update repos
    update_repos

    # Step 2: Install dependencies
    dep_install

    # Step 3: Install Composer
    install_composer

    # Step 4: Download Panel
    ptdl_dl

    # Step 5: Install Composer dependencies
    install_composer_deps

    # Step 6: Set up database
    print_header "Database Setup"
    echo ""
    create_db "$DB_NAME"
    create_db_user "$DB_USER" "$DB_PASS" "$DB_NAME"

    # Step 7: Configure panel
    print_header "Panel Configuration"
    echo ""
    configure

    # Step 8: Set permissions
    set_folder_permissions

    # Step 9: Cron job
    insert_cronjob

    # Step 10: Queue worker service
    install_pteroq

    # Step 11: Nginx
    print_header "Web Server Configuration"
    echo ""
    configure_nginx

    # Step 12: SSL (if requested)
    if [[ "$CONFIGURE_SSL" == "true" ]]; then
        print_header "SSL Certificate"
        echo ""
        letsencrypt
    fi

    # Step 13: Firewall (if requested)
    if [[ "$CONFIGURE_FW" == "true" ]]; then
        print_header "Firewall Configuration"
        echo ""
        install_firewall
        firewall_allow_ports
    fi

    local end_time elapsed
    end_time="$(date +%s)"
    elapsed="$((end_time - start_time))"

    show_completion "$elapsed"
}

###############################################################################
# COMPLETION SUMMARY
###############################################################################

show_completion() {
    local elapsed="${1:-0}"
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    local panel_url

    if [[ "$ASSUME_SSL" == "true" ]]; then
        panel_url="https://${FQDN}"
    else
        panel_url="http://${FQDN}"
    fi

    echo ""
    echo ""
    print_brake 60
    echo -e "${BOLD}${GREEN}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║      INSTALLATION COMPLETE!                   ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${RESET}"
    print_brake 60
    echo ""
    echo -e "  ${BOLD}${ORANGE}Panel URL:${RESET}        ${WHITE}${panel_url}${RESET}"
    echo -e "  ${BOLD}${ORANGE}Admin User:${RESET}       ${WHITE}${ADMIN_USER}${RESET}"
    echo -e "  ${BOLD}${ORANGE}Admin Email:${RESET}      ${WHITE}${ADMIN_EMAIL}${RESET}"
    echo -e "  ${BOLD}${ORANGE}Admin Password:${RESET}   ${WHITE}(as set during configuration)${RESET}"
    echo ""
    echo -e "  ${BOLD}${ORANGE}DB Name:${RESET}          ${WHITE}${DB_NAME}${RESET}"
    echo -e "  ${BOLD}${ORANGE}DB User:${RESET}          ${WHITE}${DB_USER}${RESET}"
    echo -e "  ${BOLD}${ORANGE}DB Password:${RESET}      ${WHITE}${DB_PASS}${RESET}"
    echo ""
    echo -e "  ${BOLD}${ORANGE}Panel Path:${RESET}       ${WHITE}${PANEL_DIR}${RESET}"
    echo -e "  ${BOLD}${ORANGE}Web User:${RESET}         ${WHITE}${WEBSERVER_USER}${RESET}"
    echo -e "  ${BOLD}${ORANGE}SSL Enabled:${RESET}      ${WHITE}${ASSUME_SSL}${RESET}"
    echo -e "  ${BOLD}${ORANGE}Firewall:${RESET}         ${WHITE}${CONFIGURE_FW}${RESET}"
    echo ""
    echo -e "  ${BOLD}${WHITE}Installation time: ${ORANGE}${minutes}m ${seconds}s${RESET}"
    echo ""
    print_brake 60
    echo ""
    echo -e "  ${DARK_ORANGE}Thank you for using Sundy.Systems Panel Installer!${RESET}"
    echo -e "  ${WHITE}For support, visit: ${ORANGE}https://sundy.systems${RESET}"
    echo ""
    print_brake 60
    echo ""

    # Save installation summary to file
    local summary_file="${PANEL_DIR}/.install-summary.txt"
    {
        echo "Pterodactyl Panel Installation Summary"
        echo "======================================"
        echo "Installed by: Sundy.Systems Panel Installer v${SCRIPT_VERSION}"
        echo "Date: $(date)"
        echo "OS: ${OS} ${OS_VER}"
        echo "Panel URL: ${panel_url}"
        echo "FQDN: ${FQDN}"
        echo "Admin User: ${ADMIN_USER}"
        echo "Admin Email: ${ADMIN_EMAIL}"
        echo "DB Name: ${DB_NAME}"
        echo "DB User: ${DB_USER}"
        echo "DB Password: ${DB_PASS}"
        echo "Web Server User: ${WEBSERVER_USER}"
        echo "SSL: ${ASSUME_SSL}"
        echo "Firewall: ${CONFIGURE_FW}"
    } > "$summary_file"
    chmod 600 "$summary_file"

    echo -e "  ${WHITE}Installation details saved to:${RESET}"
    echo -e "  ${ORANGE}${summary_file}${RESET}"
    echo ""
}

###############################################################################
# MAIN ENTRY POINT
###############################################################################

main() {
    # Clear screen
    clear

    # Show branded banner
    show_banner

    # Must be root
    check_root

    # Detect OS
    detect_os

    echo ""

    # Gather user input interactively
    gather_input

    # Show summary and confirm
    show_summary

    # Perform the installation
    perform_install
}

# Run main
main "$@"
