#!/usr/bin/env bash
###############################################################################
# Unified Pterodactyl Toolkit
# - Install Pterodactyl Panel
# - Install Pterodactyl Wings
# - Install phpMyAdmin
# - Uninstall components
###############################################################################

set -euo pipefail

SCRIPT_VERSION="3.0"

PANEL_DIR="/var/www/pterodactyl"
PANEL_DL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
WINGS_DL_BASE="https://github.com/pterodactyl/wings/releases/latest/download"
PMA_DEFAULT_VERSION="5.2.3"
PMA_INSTALL_DIR="/usr/share/phpmyadmin"
PMA_TMP_DIR="/usr/share/phpmyadmin/tmp"
PMA_CONFIG_FILE="/usr/share/phpmyadmin/config.inc.php"
PMA_SNIPPET_DIR="/etc/nginx/snippets"
PMA_SNIPPET_FILE="/etc/nginx/snippets/phpmyadmin.conf"

ORANGE='\033[38;5;208m'
DARK_ORANGE='\033[38;5;202m'
YELLOW='\033[38;5;220m'
GREEN='\033[38;5;82m'
RED='\033[38;5;196m'
WHITE='\033[38;5;255m'
BOLD='\033[1m'
RESET='\033[0m'

OS_ID=""
OS_VERSION=""
OS_MAJOR=""
OS_FAMILY=""
WEBSERVER_USER=""
NGINX_AVAILABLE_DIR=""
NGINX_ENABLED_DIR=""
REDIS_SERVICE=""
PANEL_PHP_SERVICE=""
PANEL_PHP_ENDPOINT=""
DEFAULT_TIMEZONE="UTC"
MAIN_ACTION=""

PANEL_FQDN=""
PANEL_TIMEZONE=""
PANEL_ADMIN_EMAIL=""
PANEL_ADMIN_USER=""
PANEL_ADMIN_FIRST=""
PANEL_ADMIN_LAST=""
PANEL_ADMIN_PASS=""
PANEL_LE_EMAIL=""
PANEL_DB_NAME=""
PANEL_DB_USER=""
PANEL_DB_PASS=""
PANEL_ENABLE_TELEMETRY="true"
PANEL_CONFIGURE_FW="true"
PANEL_SSL_MODE="http"
PANEL_CERT_PATH=""
PANEL_KEY_PATH=""
PANEL_TRUSTED_PROXIES=""
PANEL_HAS_LOCAL_SSL="false"

WINGS_CONFIGURE_FW="true"
WINGS_INSTALL_MARIADB="false"
WINGS_DB_USER=""
WINGS_DB_PASS=""
WINGS_DB_BIND_ADDRESS="127.0.0.1"
WINGS_DB_ALLOWED_HOST="127.0.0.1"
WINGS_OPEN_DB_PORT="false"
WINGS_CERT_MODE="none"
WINGS_SSL_FQDN=""
WINGS_SSL_EMAIL=""

PMA_VERSION="$PMA_DEFAULT_VERSION"
PMA_WEB_PATH="/phpmyadmin"
PMA_SERVER_FQDN=""
PMA_BLOWFISH_SECRET=""

UNINSTALL_PANEL="false"
UNINSTALL_WINGS="false"
UNINSTALL_PMA="false"
UNINSTALL_DATABASE="false"

show_banner() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${BOLD}${ORANGE} ███████╗██╗   ██╗███╗   ██╗██████╗ ██╗   ██╗${RESET}"
    echo -e "${BOLD}${ORANGE} ██╔════╝██║   ██║████╗  ██║██╔══██╗╚██╗ ██╔╝${RESET}"
    echo -e "${BOLD}${ORANGE} ███████╗██║   ██║██╔██╗ ██║██║  ██║ ╚████╔╝${RESET}"
    echo -e "${BOLD}${ORANGE} ╚════██║██║   ██║██║╚██╗██║██║  ██║  ╚██╔╝${RESET}"
    echo -e "${BOLD}${ORANGE} ███████║╚██████╔╝██║ ╚████║██████╔╝   ██║${RESET}"
    echo -e "${BOLD}${ORANGE} ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝    ╚═╝${RESET}"
    echo -e "${DARK_ORANGE}        ┌─────────────────────────────┐${RESET}"
    echo -e "${DARK_ORANGE}        │   ${WHITE}Unified Toolkit v${SCRIPT_VERSION}${DARK_ORANGE}      │${RESET}"
    echo -e "${DARK_ORANGE}        └─────────────────────────────┘${RESET}"
    echo ""
}

print_divider() {
    local length="${1:-60}"
    local line=""
    local i
    for ((i = 0; i < length; i++)); do
        line="${line}─"
    done
    echo -e "${DARK_ORANGE}${line}${RESET}"
}

print_header() {
    echo ""
    print_divider 60
    echo -e "${BOLD}${ORANGE}  $1${RESET}"
    print_divider 60
}

output() {
    echo -e "${ORANGE}[*]${RESET} ${WHITE}$1${RESET}"
}

success() {
    echo -e "${GREEN}[✓]${RESET} ${WHITE}$1${RESET}"
}

warning() {
    echo -e "${YELLOW}[!]${RESET} ${WHITE}$1${RESET}" >&2
}

error_exit() {
    echo -e "${RED}[✗]${RESET} ${WHITE}$1${RESET}" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error_exit "Run this script as root: sudo bash $0"
    fi
}

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        error_exit "Cannot detect operating system: /etc/os-release not found."
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    OS_ID="${ID}"
    OS_VERSION="${VERSION_ID}"
    OS_MAJOR="${OS_VERSION%%.*}"

    case "${OS_ID}" in
        ubuntu)
            OS_FAMILY="debian"
            WEBSERVER_USER="www-data"
            NGINX_AVAILABLE_DIR="/etc/nginx/sites-available"
            NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
            REDIS_SERVICE="redis-server"
            DEFAULT_TIMEZONE="Europe/Moscow"
            case "${OS_VERSION}" in
                20.04|22.04|24.04) ;;
                *) error_exit "Unsupported Ubuntu version: ${OS_VERSION}" ;;
            esac
            ;;
        debian)
            OS_FAMILY="debian"
            WEBSERVER_USER="www-data"
            NGINX_AVAILABLE_DIR="/etc/nginx/sites-available"
            NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
            REDIS_SERVICE="redis-server"
            DEFAULT_TIMEZONE="Europe/Moscow"
            case "${OS_MAJOR}" in
                11|12) ;;
                *) error_exit "Unsupported Debian version: ${OS_MAJOR}" ;;
            esac
            ;;
        rocky|almalinux)
            OS_FAMILY="rhel"
            WEBSERVER_USER="nginx"
            NGINX_AVAILABLE_DIR="/etc/nginx/conf.d"
            NGINX_ENABLED_DIR=""
            REDIS_SERVICE="redis"
            DEFAULT_TIMEZONE="Europe/Moscow"
            case "${OS_MAJOR}" in
                8|9) ;;
                *) error_exit "Unsupported ${OS_ID} version: ${OS_MAJOR}" ;;
            esac
            ;;
        *)
            error_exit "Unsupported operating system: ${OS_ID}"
            ;;
    esac

    success "Detected ${OS_ID} ${OS_VERSION}"
}

update_repos() {
    output "Updating package repositories..."
    case "${OS_FAMILY}" in
        debian)
            apt-get update -y >/dev/null 2>&1
            ;;
        rhel)
            dnf makecache -y >/dev/null 2>&1
            ;;
    esac
    success "Package repositories updated."
}

install_packages() {
    local packages=("$@")
    case "${OS_FAMILY}" in
        debian)
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" >/dev/null 2>&1
            ;;
        rhel)
            dnf install -y "${packages[@]}" >/dev/null 2>&1
            ;;
    esac
}

enable_service_now() {
    local service="$1"
    systemctl enable --now "${service}" >/dev/null 2>&1
}

restart_service() {
    local service="$1"
    systemctl restart "${service}" >/dev/null 2>&1
}

reload_service() {
    local service="$1"
    systemctl reload "${service}" >/dev/null 2>&1
}

gen_password() {
    local length="${1:-32}"
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${length}"
    echo ""
}

escape_sql_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\'/\'\'}"
    printf '%s' "${value}"
}

escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

set_env_value() {
    local env_file="$1"
    local key="$2"
    local value="$3"
    local escaped
    escaped="$(escape_sed_replacement "${value}")"

    if grep -q "^${key}=" "${env_file}" 2>/dev/null; then
        sed -i "s/^${key}=.*/${key}=${escaped}/" "${env_file}"
    else
        echo "${key}=${value}" >> "${env_file}"
    fi
}

required_input() {
    local prompt="$1"
    local default_value="$2"
    local var_name="$3"
    local value=""

    while true; do
        if [[ -n "${default_value}" ]]; then
            echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET} [${ORANGE}${default_value}${RESET}]: " >&2
        else
            echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET}: " >&2
        fi
        read -r value

        if [[ -z "${value}" && -n "${default_value}" ]]; then
            value="${default_value}"
        fi

        if [[ -n "${value}" ]]; then
            printf -v "${var_name}" '%s' "${value}"
            return 0
        fi

        warning "This field is required."
    done
}

hidden_input() {
    local prompt="$1"
    local var_name="$2"
    local min_length="${3:-8}"
    local first=""
    local second=""

    while true; do
        echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET}: " >&2
        read -rs first
        echo "" >&2

        if [[ "${#first}" -lt "${min_length}" ]]; then
            warning "Minimum length: ${min_length} characters."
            continue
        fi

        echo -en "${ORANGE}▸${RESET} ${WHITE}Confirm password${RESET}: " >&2
        read -rs second
        echo "" >&2

        if [[ "${first}" != "${second}" ]]; then
            warning "Passwords do not match."
            continue
        fi

        printf -v "${var_name}" '%s' "${first}"
        return 0
    done
}

optional_input() {
    local prompt="$1"
    local default_value="$2"
    local var_name="$3"
    local value=""

    if [[ -n "${default_value}" ]]; then
        echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET} [${ORANGE}${default_value}${RESET}]: " >&2
    else
        echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET}: " >&2
    fi
    read -r value

    if [[ -z "${value}" ]]; then
        value="${default_value}"
    fi

    printf -v "${var_name}" '%s' "${value}"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local var_name="$3"
    local hint=""
    local answer=""

    if [[ "${default}" == "y" ]]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    while true; do
        echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET} [${ORANGE}${hint}${RESET}]: " >&2
        read -r answer
        answer="${answer:-${default}}"
        case "${answer,,}" in
            y|yes)
                printf -v "${var_name}" '%s' "y"
                return 0
                ;;
            n|no)
                printf -v "${var_name}" '%s' "n"
                return 0
                ;;
            *)
                warning "Please answer y or n."
                ;;
        esac
    done
}

validate_fqdn() {
    local value="$1"
    if [[ "${value}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        return 0
    fi
    [[ "${value}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

validate_email() {
    local value="$1"
    [[ "${value}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

validate_timezone() {
    local value="$1"
    [[ -f "/usr/share/zoneinfo/${value}" ]]
}

validate_db_name() {
    local value="$1"
    [[ "${value}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}$ ]]
}

validate_username() {
    local value="$1"
    [[ "${value}" =~ ^[A-Za-z0-9_-]{1,32}$ ]]
}

validate_bind_address() {
    local value="$1"
    [[ "${value}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

validate_mysql_host_pattern() {
    local value="$1"
    [[ "${value}" =~ ^[%A-Za-z0-9._:-]+$ ]]
}

panel_nginx_conf_path() {
    if [[ "${OS_FAMILY}" == "debian" ]]; then
        echo "${NGINX_AVAILABLE_DIR}/pterodactyl.conf"
    else
        echo "${NGINX_AVAILABLE_DIR}/pterodactyl.conf"
    fi
}

detect_panel_php_runtime() {
    local php_version=""
    local socket=""

    if [[ "${OS_FAMILY}" == "debian" ]]; then
        php_version="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || true)"
        if [[ -n "${php_version}" ]]; then
            PANEL_PHP_SERVICE="php${php_version}-fpm"
            socket="/run/php/php${php_version}-fpm.sock"
            if [[ -S "${socket}" ]]; then
                PANEL_PHP_ENDPOINT="unix:${socket}"
                return 0
            fi
        fi

        socket="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' -print -quit 2>/dev/null || true)"
        if [[ -n "${socket}" ]]; then
            PANEL_PHP_ENDPOINT="unix:${socket}"
        else
            PANEL_PHP_ENDPOINT="unix:/run/php/php8.3-fpm.sock"
        fi

        if [[ -z "${PANEL_PHP_SERVICE}" ]]; then
            PANEL_PHP_SERVICE="php8.3-fpm"
        fi
    else
        PANEL_PHP_SERVICE="php-fpm"
        if [[ -S /run/php-fpm/www.sock ]]; then
            PANEL_PHP_ENDPOINT="unix:/run/php-fpm/www.sock"
        else
            PANEL_PHP_ENDPOINT="127.0.0.1:9000"
        fi
    fi
}

panel_app_scheme() {
    case "${PANEL_SSL_MODE}" in
        http) echo "http" ;;
        letsencrypt)
            if [[ "${PANEL_HAS_LOCAL_SSL}" == "true" ]]; then
                echo "https"
            else
                echo "http"
            fi
            ;;
        proxy_http|existing_cert) echo "https" ;;
        *) echo "http" ;;
    esac
}

panel_app_url() {
    echo "$(panel_app_scheme)://${PANEL_FQDN}"
}

wait_for_mariadb() {
    local tries=30
    local i
    for ((i = 1; i <= tries; i++)); do
        if mariadb-admin ping >/dev/null 2>&1; then
            success "MariaDB is ready."
            return 0
        fi
        sleep 1
    done
    error_exit "MariaDB did not become ready in time."
}

create_database() {
    local db_name="$1"
    output "Creating database ${db_name}..."
    mariadb -u root -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;" >/dev/null 2>&1
    success "Database ${db_name} is ready."
}

create_database_user() {
    local db_user="$1"
    local db_pass="$2"
    local db_name="$3"
    local db_host="${4:-127.0.0.1}"
    local safe_pass

    safe_pass="$(escape_sql_string "${db_pass}")"

    output "Creating MariaDB user ${db_user}@${db_host}..."
    mariadb -u root <<EOSQL
CREATE USER IF NOT EXISTS '${db_user}'@'${db_host}' IDENTIFIED BY '${safe_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'${db_host}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOSQL
    success "Database user ${db_user}@${db_host} is ready."
}

create_global_database_user() {
    local db_user="$1"
    local db_pass="$2"
    local db_host="$3"
    local safe_pass

    safe_pass="$(escape_sql_string "${db_pass}")"

    output "Creating MariaDB user ${db_user}@${db_host} with global privileges..."
    mariadb -u root <<EOSQL
CREATE USER IF NOT EXISTS '${db_user}'@'${db_host}' IDENTIFIED BY '${safe_pass}';
GRANT ALL PRIVILEGES ON *.* TO '${db_user}'@'${db_host}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOSQL
    success "Global MariaDB user ${db_user}@${db_host} is ready."
}

install_firewall() {
    case "${OS_FAMILY}" in
        debian)
            install_packages ufw
            success "UFW installed."
            ;;
        rhel)
            install_packages firewalld
            enable_service_now firewalld
            success "firewalld installed."
            ;;
    esac
}

firewall_allow_tcp() {
    local port="$1"
    case "${OS_FAMILY}" in
        debian)
            ufw allow "${port}/tcp" >/dev/null 2>&1 || true
            ;;
        rhel)
            firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true
            ;;
    esac
}

firewall_allow_service() {
    local service_name="$1"
    case "${OS_FAMILY}" in
        debian)
            case "${service_name}" in
                ssh) ufw allow 22/tcp >/dev/null 2>&1 || true ;;
                http) ufw allow 80/tcp >/dev/null 2>&1 || true ;;
                https) ufw allow 443/tcp >/dev/null 2>&1 || true ;;
            esac
            ;;
        rhel)
            firewall-cmd --permanent --add-service="${service_name}" >/dev/null 2>&1 || true
            ;;
    esac
}

firewall_reload() {
    case "${OS_FAMILY}" in
        debian)
            yes | ufw enable >/dev/null 2>&1 || true
            ;;
        rhel)
            firewall-cmd --reload >/dev/null 2>&1 || true
            ;;
    esac
}

configure_panel_firewall() {
    if [[ "${PANEL_CONFIGURE_FW}" != "true" ]]; then
        warning "Firewall configuration skipped."
        return 0
    fi

    print_header "Firewall"
    install_firewall
    firewall_allow_service ssh
    firewall_allow_service http
    case "${PANEL_SSL_MODE}" in
        letsencrypt|existing_cert)
            firewall_allow_service https
            ;;
    esac
    firewall_reload
    success "Firewall rules updated for the panel."
}

configure_wings_firewall() {
    if [[ "${WINGS_CONFIGURE_FW}" != "true" ]]; then
        warning "Firewall configuration skipped."
        return 0
    fi

    print_header "Firewall"
    install_firewall
    firewall_allow_service ssh
    firewall_allow_tcp 8080
    firewall_allow_tcp 2022

    if [[ "${WINGS_CERT_MODE}" == "letsencrypt" ]]; then
        firewall_allow_service http
        firewall_allow_service https
    fi

    if [[ "${WINGS_OPEN_DB_PORT}" == "true" ]]; then
        firewall_allow_tcp 3306
    fi

    firewall_reload
    success "Firewall rules updated for Wings."
}

choose_main_action() {
    local answer=""
    while true; do
        print_header "Main Menu"
        echo -e "  ${ORANGE}1)${RESET} ${WHITE}Install Pterodactyl Panel${RESET}"
        echo -e "  ${ORANGE}2)${RESET} ${WHITE}Install Pterodactyl Wings${RESET}"
        echo -e "  ${ORANGE}3)${RESET} ${WHITE}Install phpMyAdmin${RESET}"
        echo -e "  ${ORANGE}4)${RESET} ${WHITE}Uninstall Components${RESET}"
        echo -e "  ${ORANGE}5)${RESET} ${WHITE}Exit${RESET}"
        echo ""
        echo -en "${ORANGE}▸${RESET} ${WHITE}Choose an action${RESET} [${ORANGE}1${RESET}]: " >&2
        read -r answer
        answer="${answer:-1}"
        case "${answer}" in
            1) MAIN_ACTION="panel"; return 0 ;;
            2) MAIN_ACTION="wings"; return 0 ;;
            3) MAIN_ACTION="phpmyadmin"; return 0 ;;
            4) MAIN_ACTION="uninstall"; return 0 ;;
            5) exit 0 ;;
            *) warning "Choose a number from 1 to 5." ;;
        esac
    done
}

parse_cli_args() {
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    case "$1" in
        --action)
            [[ $# -ge 2 ]] || error_exit "Usage: $0 --action <panel|wings|phpmyadmin|uninstall>"
            MAIN_ACTION="$2"
            ;;
        --help|-h)
            cat <<EOF
Usage:
  sudo bash $0
  sudo bash $0 --action panel
  sudo bash $0 --action wings
  sudo bash $0 --action phpmyadmin
  sudo bash $0 --action uninstall
EOF
            exit 0
            ;;
        *)
            error_exit "Unknown argument: $1"
            ;;
    esac
}

prompt_panel_ssl_mode() {
    local answer=""

    while true; do
        echo -e "${ORANGE}▸${RESET} ${WHITE}SSL mode for the panel${RESET}"
        echo -e "    ${ORANGE}1)${RESET} HTTP only"
        echo -e "    ${ORANGE}2)${RESET} Let's Encrypt on this server"
        echo -e "    ${ORANGE}3)${RESET} Reverse proxy / Cloudflare (origin stays on HTTP)"
        echo -e "    ${ORANGE}4)${RESET} Existing certificate on this server"
        echo -en "${ORANGE}▸${RESET} ${WHITE}Choose SSL mode${RESET} [${ORANGE}2${RESET}]: " >&2
        read -r answer
        answer="${answer:-2}"

        case "${answer}" in
            1)
                PANEL_SSL_MODE="http"
                return 0
                ;;
            2)
                PANEL_SSL_MODE="letsencrypt"
                return 0
                ;;
            3)
                PANEL_SSL_MODE="proxy_http"
                required_input "Trusted proxy IPs/CIDRs for TRUSTED_PROXIES" "*" PANEL_TRUSTED_PROXIES
                warning "If Cloudflare is set to Full/Strict, use mode 2 or 4 instead. Mode 3 keeps the origin on HTTP."
                return 0
                ;;
            4)
                PANEL_SSL_MODE="existing_cert"
                while true; do
                    required_input "Path to certificate file" "/etc/letsencrypt/live/${PANEL_FQDN}/fullchain.pem" PANEL_CERT_PATH
                    [[ -f "${PANEL_CERT_PATH}" ]] && break
                    warning "Certificate file not found: ${PANEL_CERT_PATH}"
                done
                while true; do
                    required_input "Path to private key" "/etc/letsencrypt/live/${PANEL_FQDN}/privkey.pem" PANEL_KEY_PATH
                    [[ -f "${PANEL_KEY_PATH}" ]] && break
                    warning "Private key file not found: ${PANEL_KEY_PATH}"
                done
                PANEL_HAS_LOCAL_SSL="true"
                return 0
                ;;
            *)
                warning "Choose a number from 1 to 4."
                ;;
        esac
    done
}

gather_panel_input() {
    local answer=""
    local auto_pass=""

    print_header "Panel Configuration"

    while true; do
        required_input "Panel domain or IP" "" PANEL_FQDN
        if validate_fqdn "${PANEL_FQDN}"; then
            break
        fi
        warning "Enter a valid domain like panel.example.com or an IP."
    done
    echo ""

    while true; do
        required_input "Timezone" "${DEFAULT_TIMEZONE}" PANEL_TIMEZONE
        if validate_timezone "${PANEL_TIMEZONE}"; then
            break
        fi
        warning "Timezone not found in /usr/share/zoneinfo."
    done
    echo ""

    print_header "Admin Account"

    while true; do
        required_input "Admin email" "" PANEL_ADMIN_EMAIL
        if validate_email "${PANEL_ADMIN_EMAIL}"; then
            break
        fi
        warning "Invalid email format."
    done

    while true; do
        required_input "Admin username" "admin" PANEL_ADMIN_USER
        if validate_username "${PANEL_ADMIN_USER}"; then
            break
        fi
        warning "Use 1-32 letters, numbers, underscore or dash."
    done

    required_input "Admin first name" "Admin" PANEL_ADMIN_FIRST
    required_input "Admin last name" "User" PANEL_ADMIN_LAST
    hidden_input "Admin password" PANEL_ADMIN_PASS 8

    print_header "Database"

    while true; do
        required_input "Database name" "panel" PANEL_DB_NAME
        if validate_db_name "${PANEL_DB_NAME}"; then
            break
        fi
        warning "Database name can contain only letters, numbers and underscore."
    done

    while true; do
        required_input "Database user" "pterodactyl" PANEL_DB_USER
        if validate_db_name "${PANEL_DB_USER}"; then
            break
        fi
        warning "Database username can contain only letters, numbers and underscore."
    done

    auto_pass="$(gen_password 32)"
    echo -e "${ORANGE}▸${RESET} ${WHITE}Generated database password:${RESET} ${GREEN}${auto_pass}${RESET}"
    ask_yes_no "Set a custom database password?" "n" answer
    if [[ "${answer}" == "y" ]]; then
        hidden_input "Database password" PANEL_DB_PASS 8
    else
        PANEL_DB_PASS="${auto_pass}"
    fi

    print_header "Email & SSL"

    while true; do
        required_input "Email for Let's Encrypt / notifications" "${PANEL_ADMIN_EMAIL}" PANEL_LE_EMAIL
        if validate_email "${PANEL_LE_EMAIL}"; then
            break
        fi
        warning "Invalid email format."
    done

    prompt_panel_ssl_mode

    print_header "Additional Options"

    ask_yes_no "Configure firewall automatically?" "y" answer
    [[ "${answer}" == "y" ]] && PANEL_CONFIGURE_FW="true" || PANEL_CONFIGURE_FW="false"

    ask_yes_no "Enable Pterodactyl telemetry?" "y" answer
    [[ "${answer}" == "y" ]] && PANEL_ENABLE_TELEMETRY="true" || PANEL_ENABLE_TELEMETRY="false"

    print_header "Summary"
    echo -e "  ${WHITE}Domain:${RESET}               ${ORANGE}${PANEL_FQDN}${RESET}"
    echo -e "  ${WHITE}APP_URL:${RESET}              ${ORANGE}$(panel_app_url)${RESET}"
    echo -e "  ${WHITE}Timezone:${RESET}             ${ORANGE}${PANEL_TIMEZONE}${RESET}"
    echo -e "  ${WHITE}Admin:${RESET}                ${ORANGE}${PANEL_ADMIN_USER} <${PANEL_ADMIN_EMAIL}>${RESET}"
    echo -e "  ${WHITE}Database:${RESET}             ${ORANGE}${PANEL_DB_NAME} / ${PANEL_DB_USER}${RESET}"
    echo -e "  ${WHITE}SSL Mode:${RESET}             ${ORANGE}${PANEL_SSL_MODE}${RESET}"
    echo -e "  ${WHITE}Firewall:${RESET}             ${ORANGE}${PANEL_CONFIGURE_FW}${RESET}"
    echo ""

    ask_yes_no "Proceed with panel installation?" "y" answer
    [[ "${answer}" == "y" ]] || exit 0
}

add_php_repo_debian() {
    output "Adding PHP 8.3 repository..."
    install_packages software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release

    case "${OS_ID}" in
        ubuntu)
            LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
            ;;
        debian)
            curl -fsSL -o /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
            dpkg -i /tmp/debsuryorg-archive-keyring.deb >/dev/null 2>&1
            rm -f /tmp/debsuryorg-archive-keyring.deb
            echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
                > /etc/apt/sources.list.d/sury-php.list
            ;;
    esac
}

add_mariadb_repo() {
    output "Adding MariaDB repository..."
    local setup_file
    setup_file="$(mktemp)"
    curl -fsSL -o "${setup_file}" https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
    bash "${setup_file}" --mariadb-server-version=mariadb-10.11 >/dev/null 2>&1 || true
    rm -f "${setup_file}"
}

install_panel_dependencies() {
    print_header "Installing Dependencies"

    case "${OS_FAMILY}" in
        debian)
            add_php_repo_debian
            add_mariadb_repo
            update_repos

            output "Installing panel dependencies..."
            install_packages \
                php8.3 php8.3-common php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring \
                php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip php8.3-intl \
                php8.3-sqlite3 mariadb-server nginx "${REDIS_SERVICE}" tar unzip git cron \
                certbot python3-certbot-nginx
            ;;
        rhel)
            output "Enabling required repositories..."
            install_packages epel-release dnf-plugins-core
            if [[ "${OS_MAJOR}" == "9" ]]; then
                dnf config-manager --set-enabled crb >/dev/null 2>&1 || \
                    dnf config-manager --set-enabled powertools >/dev/null 2>&1 || true
            fi
            dnf install -y "https://rpms.remirepo.net/enterprise/remi-release-${OS_MAJOR}.rpm" >/dev/null 2>&1 || true
            dnf module reset -y php >/dev/null 2>&1 || true
            dnf module enable -y php:remi-8.3 >/dev/null 2>&1 || true
            add_mariadb_repo
            update_repos

            output "Installing panel dependencies..."
            install_packages \
                php php-common php-cli php-gd php-mysqlnd php-mbstring php-bcmath php-xml \
                php-fpm php-curl php-zip php-intl php-sqlite3 mariadb-server nginx "${REDIS_SERVICE}" \
                tar unzip git cronie certbot python3-certbot-nginx

            if [[ -f /etc/php-fpm.d/www.conf ]]; then
                sed -i 's/^user = .*/user = nginx/' /etc/php-fpm.d/www.conf
                sed -i 's/^group = .*/group = nginx/' /etc/php-fpm.d/www.conf
                sed -i 's|^listen = .*|listen = /run/php-fpm/www.sock|' /etc/php-fpm.d/www.conf
                sed -i 's/^;listen.owner = .*/listen.owner = nginx/' /etc/php-fpm.d/www.conf
                sed -i 's/^;listen.group = .*/listen.group = nginx/' /etc/php-fpm.d/www.conf
                sed -i 's/^listen.owner = .*/listen.owner = nginx/' /etc/php-fpm.d/www.conf
                sed -i 's/^listen.group = .*/listen.group = nginx/' /etc/php-fpm.d/www.conf
            fi

            if command_exists setsebool; then
                setsebool -P httpd_can_network_connect 1 >/dev/null 2>&1 || true
                setsebool -P httpd_unified 1 >/dev/null 2>&1 || true
            fi
            ;;
    esac

    detect_panel_php_runtime
    enable_service_now mariadb
    enable_service_now "${REDIS_SERVICE}"
    enable_service_now nginx
    enable_service_now "${PANEL_PHP_SERVICE}"
    wait_for_mariadb

    success "Panel dependencies installed."
}

install_composer() {
    print_header "Composer"
    output "Installing Composer..."

    local expected_sig=""
    local actual_sig=""

    expected_sig="$(curl -fsSL https://composer.github.io/installer.sig)"
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
    actual_sig="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"

    if [[ "${expected_sig}" != "${actual_sig}" ]]; then
        rm -f /tmp/composer-setup.php
        error_exit "Composer installer signature check failed."
    fi

    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1
    rm -f /tmp/composer-setup.php

    command_exists composer || error_exit "Composer installation failed."
    success "Composer installed."
}

download_panel() {
    print_header "Downloading Panel"

    if [[ -d "${PANEL_DIR}" ]] && [[ -n "$(ls -A "${PANEL_DIR}" 2>/dev/null || true)" ]]; then
        local answer=""
        ask_yes_no "Existing ${PANEL_DIR} detected. Remove it and reinstall?" "n" answer
        [[ "${answer}" == "y" ]] || error_exit "Panel installation cancelled."
        rm -rf "${PANEL_DIR}"
    fi

    mkdir -p "${PANEL_DIR}"
    curl -fsSL "${PANEL_DL_URL}" -o /tmp/panel.tar.gz
    tar -xzf /tmp/panel.tar.gz -C "${PANEL_DIR}"
    rm -f /tmp/panel.tar.gz
    success "Panel downloaded to ${PANEL_DIR}."
}

install_panel_composer_dependencies() {
    print_header "Composer Dependencies"
    output "Installing PHP dependencies..."

    if [[ ! -f "${PANEL_DIR}/.env" ]]; then
        cp "${PANEL_DIR}/.env.example" "${PANEL_DIR}/.env"
    fi

    COMPOSER_ALLOW_SUPERUSER=1 composer install \
        --no-dev \
        --optimize-autoloader \
        --working-dir="${PANEL_DIR}" \
        --no-interaction

    success "Composer dependencies installed."
}

configure_panel_app_environment() {
    local app_url
    app_url="$(panel_app_url)"

    print_header "Configuring Panel"
    output "Generating application key..."
    php "${PANEL_DIR}/artisan" key:generate --force --no-interaction >/dev/null 2>&1

    output "Writing environment configuration..."
    php "${PANEL_DIR}/artisan" p:environment:setup \
        --author="${PANEL_LE_EMAIL}" \
        --url="${app_url}" \
        --timezone="${PANEL_TIMEZONE}" \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=127.0.0.1 \
        --redis-pass="" \
        --redis-port=6379 \
        --settings-ui=true \
        --telemetry="${PANEL_ENABLE_TELEMETRY}" \
        --no-interaction >/dev/null 2>&1 || true

    output "Configuring database connection..."
    php "${PANEL_DIR}/artisan" p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database="${PANEL_DB_NAME}" \
        --username="${PANEL_DB_USER}" \
        --password="${PANEL_DB_PASS}" \
        --no-interaction >/dev/null 2>&1

    output "Running migrations..."
    php "${PANEL_DIR}/artisan" migrate --seed --force --no-interaction >/dev/null 2>&1

    output "Creating admin user..."
    php "${PANEL_DIR}/artisan" p:user:make \
        --email="${PANEL_ADMIN_EMAIL}" \
        --username="${PANEL_ADMIN_USER}" \
        --name-first="${PANEL_ADMIN_FIRST}" \
        --name-last="${PANEL_ADMIN_LAST}" \
        --password="${PANEL_ADMIN_PASS}" \
        --admin=1 \
        --no-interaction >/dev/null 2>&1

    if [[ "${PANEL_SSL_MODE}" == "proxy_http" ]]; then
        set_env_value "${PANEL_DIR}/.env" "TRUSTED_PROXIES" "${PANEL_TRUSTED_PROXIES}"
    fi

    php "${PANEL_DIR}/artisan" config:clear >/dev/null 2>&1 || true
    success "Panel configured."
}

set_panel_permissions() {
    print_header "Permissions"
    output "Setting ownership and permissions..."

    chown -R "${WEBSERVER_USER}:${WEBSERVER_USER}" "${PANEL_DIR}"
    find "${PANEL_DIR}" -type d -exec chmod 755 {} \;
    find "${PANEL_DIR}" -type f -exec chmod 644 {} \;
    chmod -R 775 "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache"

    success "Permissions updated."
}

install_panel_cron() {
    print_header "Cron"
    output "Installing scheduler cron..."

    local cron_line="* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1"
    local existing=""
    existing="$(crontab -u "${WEBSERVER_USER}" -l 2>/dev/null || true)"

    if ! grep -Fq "${cron_line}" <<< "${existing}"; then
        {
            printf '%s\n' "${existing}"
            printf '%s\n' "${cron_line}"
        } | crontab -u "${WEBSERVER_USER}" -
    fi

    success "Scheduler cron installed."
}

install_pteroq_service() {
    print_header "Queue Worker"
    output "Creating pteroq service..."

    cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=${REDIS_SERVICE}.service

[Service]
User=${WEBSERVER_USER}
Group=${WEBSERVER_USER}
WorkingDirectory=${PANEL_DIR}
ExecStart=/usr/bin/php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
Restart=always
RestartSec=5s
StartLimitInterval=180
StartLimitBurst=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    enable_service_now pteroq
    success "pteroq service installed."
}

panel_fastcgi_pass_line() {
    if [[ "${PANEL_PHP_ENDPOINT}" == unix:* ]]; then
        echo "fastcgi_pass ${PANEL_PHP_ENDPOINT};"
    else
        echo "fastcgi_pass ${PANEL_PHP_ENDPOINT};"
    fi
}

write_panel_nginx_http_config() {
    local conf_path="$1"
    local fastcgi_line=""

    fastcgi_line="$(panel_fastcgi_pass_line)"

    cat > "${conf_path}" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${PANEL_FQDN};

    root ${PANEL_DIR}/public;
    index index.php;
    charset utf-8;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        ${fastcgi_line}
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

    location ~ /\.ht {
        deny all;
    }
}
EOF
}

write_panel_nginx_ssl_config() {
    local conf_path="$1"
    local cert_path="$2"
    local key_path="$3"
    local fastcgi_line=""

    fastcgi_line="$(panel_fastcgi_pass_line)"

    cat > "${conf_path}" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${PANEL_FQDN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${PANEL_FQDN};

    root ${PANEL_DIR}/public;
    index index.php;
    charset utf-8;

    ssl_certificate ${cert_path};
    ssl_certificate_key ${key_path};
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        ${fastcgi_line}
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

    location ~ /\.ht {
        deny all;
    }
}
EOF
}

link_panel_nginx_config() {
    if [[ "${OS_FAMILY}" == "debian" ]]; then
        mkdir -p "${NGINX_ENABLED_DIR}"
        ln -sf "$(panel_nginx_conf_path)" "${NGINX_ENABLED_DIR}/pterodactyl.conf"
        rm -f "${NGINX_ENABLED_DIR}/default" 2>/dev/null || true
        rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true
    else
        rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true
    fi
}

apply_panel_nginx_config() {
    local conf_path
    conf_path="$(panel_nginx_conf_path)"

    print_header "Nginx"
    output "Writing nginx configuration..."

    case "${PANEL_SSL_MODE}" in
        existing_cert)
            write_panel_nginx_ssl_config "${conf_path}" "${PANEL_CERT_PATH}" "${PANEL_KEY_PATH}"
            ;;
        http|letsencrypt|proxy_http)
            write_panel_nginx_http_config "${conf_path}"
            ;;
    esac

    link_panel_nginx_config

    if nginx -t >/dev/null 2>&1; then
        restart_service nginx
        success "Nginx configuration applied."
    else
        nginx -t || true
        error_exit "Nginx configuration test failed."
    fi
}

panel_post_ssl_finalize() {
    PANEL_HAS_LOCAL_SSL="true"
    set_env_value "${PANEL_DIR}/.env" "APP_URL" "https://${PANEL_FQDN}"
    php "${PANEL_DIR}/artisan" config:clear >/dev/null 2>&1 || true
}

obtain_panel_letsencrypt() {
    local conf_path=""

    [[ "${PANEL_SSL_MODE}" == "letsencrypt" ]] || return 0

    print_header "Let's Encrypt"

    if [[ "${PANEL_FQDN}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        warning "Let's Encrypt cannot issue a certificate for an IP address. Keeping the panel on HTTP."
        PANEL_SSL_MODE="http"
        set_env_value "${PANEL_DIR}/.env" "APP_URL" "http://${PANEL_FQDN}"
        return 0
    fi

    warning "If the domain is proxied through Cloudflare, temporarily disable the orange cloud or use SSL mode 4."
    output "Requesting certificate for ${PANEL_FQDN}..."

    if certbot certonly --nginx --non-interactive --agree-tos \
        --email "${PANEL_LE_EMAIL}" -d "${PANEL_FQDN}"; then
        PANEL_CERT_PATH="/etc/letsencrypt/live/${PANEL_FQDN}/fullchain.pem"
        PANEL_KEY_PATH="/etc/letsencrypt/live/${PANEL_FQDN}/privkey.pem"
        PANEL_HAS_LOCAL_SSL="true"
        conf_path="$(panel_nginx_conf_path)"
        write_panel_nginx_ssl_config "${conf_path}" "${PANEL_CERT_PATH}" "${PANEL_KEY_PATH}"

        if nginx -t >/dev/null 2>&1; then
            reload_service nginx || restart_service nginx
            panel_post_ssl_finalize
            success "Let's Encrypt certificate installed."
        else
            nginx -t || true
            warning "Certificate was issued, but nginx SSL config test failed. Reverting to HTTP config."
            write_panel_nginx_http_config "${conf_path}"
            reload_service nginx || restart_service nginx || true
            PANEL_HAS_LOCAL_SSL="false"
            PANEL_SSL_MODE="http"
        fi

        systemctl enable --now certbot.timer >/dev/null 2>&1 || {
            (crontab -l 2>/dev/null || true; echo "0 23 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'") | crontab -
        }
    else
        warning "Let's Encrypt request failed. The panel is left on HTTP."
        PANEL_SSL_MODE="http"
        PANEL_HAS_LOCAL_SSL="false"
        set_env_value "${PANEL_DIR}/.env" "APP_URL" "http://${PANEL_FQDN}"
        php "${PANEL_DIR}/artisan" config:clear >/dev/null 2>&1 || true
    fi
}

panel_health_check() {
    print_header "Post-Install Check"
    systemctl is-active --quiet nginx && success "nginx is running." || warning "nginx is not running."
    systemctl is-active --quiet "${PANEL_PHP_SERVICE}" && success "${PANEL_PHP_SERVICE} is running." || warning "${PANEL_PHP_SERVICE} is not running."
    systemctl is-active --quiet mariadb && success "mariadb is running." || warning "mariadb is not running."
    systemctl is-active --quiet "${REDIS_SERVICE}" && success "${REDIS_SERVICE} is running." || warning "${REDIS_SERVICE} is not running."
    nginx -t >/dev/null 2>&1 && success "nginx config test passed." || warning "nginx config test failed."

    case "${PANEL_SSL_MODE}" in
        letsencrypt|existing_cert)
            if ss -ltn | awk '$4 ~ /:443$/ { found=1 } END { exit(found ? 0 : 1) }'; then
                success "Origin is listening on port 443."
            else
                warning "Origin is not listening on port 443."
            fi
            ;;
        proxy_http)
            if ss -ltn | awk '$4 ~ /:80$/ { found=1 } END { exit(found ? 0 : 1) }'; then
                success "Origin is listening on port 80 for proxy traffic."
            else
                warning "Origin is not listening on port 80."
            fi
            warning "If Cloudflare SSL mode is Full or Strict, switch the panel to Let's Encrypt or Existing certificate mode."
            ;;
    esac
}

show_panel_completion() {
    local url
    url="$(panel_app_url)"

    print_header "Panel Installed"
    echo -e "  ${WHITE}Panel URL:${RESET}           ${ORANGE}${url}${RESET}"
    echo -e "  ${WHITE}Admin User:${RESET}          ${ORANGE}${PANEL_ADMIN_USER}${RESET}"
    echo -e "  ${WHITE}Admin Email:${RESET}         ${ORANGE}${PANEL_ADMIN_EMAIL}${RESET}"
    echo -e "  ${WHITE}DB Name:${RESET}             ${ORANGE}${PANEL_DB_NAME}${RESET}"
    echo -e "  ${WHITE}DB User:${RESET}             ${ORANGE}${PANEL_DB_USER}${RESET}"
    echo -e "  ${WHITE}SSL Mode:${RESET}            ${ORANGE}${PANEL_SSL_MODE}${RESET}"
    echo ""
    echo -e "  ${WHITE}Installation summary saved to:${RESET} ${ORANGE}${PANEL_DIR}/.install-summary.txt${RESET}"

    cat > "${PANEL_DIR}/.install-summary.txt" <<EOF
Date: $(date)
Panel URL: ${url}
Domain: ${PANEL_FQDN}
Admin User: ${PANEL_ADMIN_USER}
Admin Email: ${PANEL_ADMIN_EMAIL}
Database: ${PANEL_DB_NAME}
Database User: ${PANEL_DB_USER}
SSL Mode: ${PANEL_SSL_MODE}
Firewall: ${PANEL_CONFIGURE_FW}
EOF
    chmod 600 "${PANEL_DIR}/.install-summary.txt"
}

perform_panel_install() {
    gather_panel_input
    install_panel_dependencies
    install_composer
    download_panel
    install_panel_composer_dependencies
    create_database "${PANEL_DB_NAME}"
    create_database_user "${PANEL_DB_USER}" "${PANEL_DB_PASS}" "${PANEL_DB_NAME}" "127.0.0.1"
    configure_panel_app_environment
    set_panel_permissions
    install_panel_cron
    install_pteroq_service
    apply_panel_nginx_config
    obtain_panel_letsencrypt
    configure_panel_firewall
    panel_health_check
    show_panel_completion
}

gather_wings_input() {
    local answer=""

    print_header "Wings Configuration"

    ask_yes_no "Configure firewall automatically?" "y" answer
    [[ "${answer}" == "y" ]] && WINGS_CONFIGURE_FW="true" || WINGS_CONFIGURE_FW="false"

    ask_yes_no "Install MariaDB for remote database hosting?" "n" answer
    [[ "${answer}" == "y" ]] && WINGS_INSTALL_MARIADB="true" || WINGS_INSTALL_MARIADB="false"

    if [[ "${WINGS_INSTALL_MARIADB}" == "true" ]]; then
        while true; do
            required_input "MariaDB username for remote access" "pterodactyluser" WINGS_DB_USER
            if validate_db_name "${WINGS_DB_USER}"; then
                break
            fi
            warning "Invalid MariaDB username."
        done

        hidden_input "MariaDB password" WINGS_DB_PASS 8

        while true; do
            required_input "MariaDB bind address" "127.0.0.1" WINGS_DB_BIND_ADDRESS
            if validate_bind_address "${WINGS_DB_BIND_ADDRESS}"; then
                break
            fi
            warning "Use an IP address like 127.0.0.1 or 0.0.0.0."
        done

        while true; do
            required_input "Allowed MySQL client host (% for any host)" "127.0.0.1" WINGS_DB_ALLOWED_HOST
            if validate_mysql_host_pattern "${WINGS_DB_ALLOWED_HOST}"; then
                break
            fi
            warning "Use a safe host pattern like 127.0.0.1, %, 10.0.0.%, or localhost."
        done

        if [[ "${WINGS_DB_BIND_ADDRESS}" == "0.0.0.0" ]]; then
            ask_yes_no "Open port 3306 in the firewall?" "n" answer
            [[ "${answer}" == "y" ]] && WINGS_OPEN_DB_PORT="true" || WINGS_OPEN_DB_PORT="false"
        fi
    fi

    print_header "Optional SSL Certificate"
    echo -e "  ${ORANGE}1)${RESET} ${WHITE}Do not obtain a certificate now${RESET}"
    echo -e "  ${ORANGE}2)${RESET} ${WHITE}Obtain Let's Encrypt certificate for this node${RESET}"
    echo ""
    echo -en "${ORANGE}▸${RESET} ${WHITE}Choose an option${RESET} [${ORANGE}1${RESET}]: " >&2
    read -r answer
    answer="${answer:-1}"
    case "${answer}" in
        2)
            WINGS_CERT_MODE="letsencrypt"
            while true; do
                required_input "Node FQDN for certificate" "" WINGS_SSL_FQDN
                if validate_fqdn "${WINGS_SSL_FQDN}"; then
                    break
                fi
                warning "Enter a valid domain."
            done

            while true; do
                required_input "Email for Let's Encrypt" "" WINGS_SSL_EMAIL
                if validate_email "${WINGS_SSL_EMAIL}"; then
                    break
                fi
                warning "Invalid email format."
            done
            ;;
        *)
            WINGS_CERT_MODE="none"
            ;;
    esac

    print_header "Summary"
    echo -e "  ${WHITE}Firewall:${RESET}            ${ORANGE}${WINGS_CONFIGURE_FW}${RESET}"
    echo -e "  ${WHITE}Install MariaDB:${RESET}      ${ORANGE}${WINGS_INSTALL_MARIADB}${RESET}"
    echo -e "  ${WHITE}Certificate:${RESET}         ${ORANGE}${WINGS_CERT_MODE}${RESET}"
    [[ "${WINGS_INSTALL_MARIADB}" == "true" ]] && \
        echo -e "  ${WHITE}DB User / Host:${RESET}      ${ORANGE}${WINGS_DB_USER} @ ${WINGS_DB_ALLOWED_HOST}${RESET}"
    echo ""

    ask_yes_no "Proceed with Wings installation?" "y" answer
    [[ "${answer}" == "y" ]] || exit 0
}

install_wings_dependencies() {
    print_header "Installing Dependencies"

    case "${OS_FAMILY}" in
        debian)
            update_repos
            install_packages ca-certificates curl gnupg lsb-release software-properties-common apt-transport-https
            install -m 0755 -d /etc/apt/keyrings
            if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
                curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | \
                    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                chmod a+r /etc/apt/keyrings/docker.gpg
            fi

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
                > /etc/apt/sources.list.d/docker.list

            update_repos
            install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            if [[ "${WINGS_INSTALL_MARIADB}" == "true" ]]; then
                install_packages mariadb-server
            fi
            if [[ "${WINGS_CERT_MODE}" == "letsencrypt" ]]; then
                install_packages certbot
            fi
            ;;
        rhel)
            update_repos
            install_packages ca-certificates curl gnupg2 yum-utils tar dnf-plugins-core
            dnf config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo" >/dev/null 2>&1 || \
                yum-config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo" >/dev/null 2>&1
            install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            if [[ "${WINGS_INSTALL_MARIADB}" == "true" ]]; then
                install_packages mariadb-server
            fi
            if [[ "${WINGS_CERT_MODE}" == "letsencrypt" ]]; then
                install_packages epel-release certbot
            fi
            ;;
    esac

    enable_service_now docker
    if [[ "${WINGS_INSTALL_MARIADB}" == "true" ]]; then
        enable_service_now mariadb
        wait_for_mariadb
    fi

    success "Wings dependencies installed."
}

download_wings_binary() {
    print_header "Downloading Wings"

    local arch=""
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) error_exit "Unsupported architecture: $(uname -m)" ;;
    esac

    mkdir -p /etc/pterodactyl
    curl -fsSL -o /usr/local/bin/wings "${WINGS_DL_BASE}/wings_linux_${arch}"
    chmod 755 /usr/local/bin/wings
    success "Wings binary installed."
}

install_wings_service() {
    print_header "Systemd"
    output "Creating Wings service..."

    cat > /etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
RuntimeDirectory=wings
PIDFile=/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5s
StartLimitInterval=180
StartLimitBurst=30
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    success "Wings service file created."
}

configure_wings_mariadb() {
    [[ "${WINGS_INSTALL_MARIADB}" == "true" ]] || return 0

    print_header "MariaDB"
    create_global_database_user "${WINGS_DB_USER}" "${WINGS_DB_PASS}" "${WINGS_DB_ALLOWED_HOST}"

    if [[ "${WINGS_DB_BIND_ADDRESS}" != "127.0.0.1" && "${WINGS_DB_BIND_ADDRESS}" != "localhost" ]]; then
        output "Updating MariaDB bind address..."

        local mariadb_conf=""
        if [[ -f /etc/mysql/mariadb.conf.d/50-server.cnf ]]; then
            mariadb_conf="/etc/mysql/mariadb.conf.d/50-server.cnf"
        elif [[ -f /etc/my.cnf.d/mariadb-server.cnf ]]; then
            mariadb_conf="/etc/my.cnf.d/mariadb-server.cnf"
        elif [[ -f /etc/my.cnf ]]; then
            mariadb_conf="/etc/my.cnf"
        fi

        if [[ -n "${mariadb_conf}" ]]; then
            if grep -q '^bind-address' "${mariadb_conf}" 2>/dev/null; then
                sed -i "s/^bind-address.*/bind-address = ${WINGS_DB_BIND_ADDRESS}/" "${mariadb_conf}"
            elif grep -q '^\[mysqld\]' "${mariadb_conf}" 2>/dev/null; then
                sed -i "/^\[mysqld\]/a bind-address = ${WINGS_DB_BIND_ADDRESS}" "${mariadb_conf}"
            else
                printf '\n[mysqld]\nbind-address = %s\n' "${WINGS_DB_BIND_ADDRESS}" >> "${mariadb_conf}"
            fi
            restart_service mariadb
            success "MariaDB bind address updated."
        else
            warning "Could not detect MariaDB config file. Update bind-address manually."
        fi
    fi
}

obtain_wings_certificate() {
    [[ "${WINGS_CERT_MODE}" == "letsencrypt" ]] || return 0

    print_header "Let's Encrypt"
    local restart_nginx="false"
    local restart_apache2="false"
    local restart_httpd="false"
    local certbot_ok="false"

    if [[ "${WINGS_SSL_FQDN}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        warning "Let's Encrypt cannot issue certificates for IP addresses. Skipping."
        return 0
    fi

    systemctl is-active --quiet nginx && restart_nginx="true" || true
    systemctl is-active --quiet apache2 && restart_apache2="true" || true
    systemctl is-active --quiet httpd && restart_httpd="true" || true

    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    systemctl stop httpd 2>/dev/null || true

    if certbot certonly --standalone --non-interactive --agree-tos \
        --preferred-challenges http \
        -d "${WINGS_SSL_FQDN}" \
        --email "${WINGS_SSL_EMAIL}"; then
        certbot_ok="true"
    fi

    [[ "${restart_nginx}" == "true" ]] && restart_service nginx || true
    [[ "${restart_apache2}" == "true" ]] && restart_service apache2 || true
    [[ "${restart_httpd}" == "true" ]] && restart_service httpd || true

    [[ "${certbot_ok}" == "true" ]] || error_exit "Failed to obtain a certificate for ${WINGS_SSL_FQDN}."
    success "Certificate created for ${WINGS_SSL_FQDN}."
}

show_wings_completion() {
    print_header "Wings Installed"
    echo -e "  ${WHITE}Next step:${RESET} paste the node auto-deploy config into ${ORANGE}/etc/pterodactyl/config.yml${RESET}"
    echo -e "  ${WHITE}Then start Wings:${RESET} ${ORANGE}systemctl enable --now wings${RESET}"
    if [[ "${WINGS_INSTALL_MARIADB}" == "true" ]]; then
        echo ""
        echo -e "  ${WHITE}MariaDB user:${RESET}        ${ORANGE}${WINGS_DB_USER}@${WINGS_DB_ALLOWED_HOST}${RESET}"
        echo -e "  ${WHITE}MariaDB bind:${RESET}        ${ORANGE}${WINGS_DB_BIND_ADDRESS}${RESET}"
    fi
    if [[ "${WINGS_CERT_MODE}" == "letsencrypt" ]]; then
        echo ""
        echo -e "  ${WHITE}Certificate:${RESET}         ${ORANGE}/etc/letsencrypt/live/${WINGS_SSL_FQDN}/fullchain.pem${RESET}"
        echo -e "  ${WHITE}Private key:${RESET}         ${ORANGE}/etc/letsencrypt/live/${WINGS_SSL_FQDN}/privkey.pem${RESET}"
    fi
}

perform_wings_install() {
    gather_wings_input
    install_wings_dependencies
    download_wings_binary
    install_wings_service
    configure_wings_mariadb
    configure_wings_firewall
    obtain_wings_certificate
    show_wings_completion
}

generate_blowfish_secret() {
    PMA_BLOWFISH_SECRET="$(tr -dc 'A-Za-z0-9!@#%^*_+~' </dev/urandom | head -c 32 || true)"
    if [[ ${#PMA_BLOWFISH_SECRET} -lt 32 ]]; then
        PMA_BLOWFISH_SECRET="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
    fi
}

detect_existing_panel_url() {
    if [[ -f "${PANEL_DIR}/.env" ]]; then
        grep '^APP_URL=' "${PANEL_DIR}/.env" | head -n1 | cut -d'=' -f2-
    else
        echo ""
    fi
}

gather_phpmyadmin_input() {
    local answer=""

    print_header "phpMyAdmin Configuration"

    required_input "phpMyAdmin version" "${PMA_DEFAULT_VERSION}" PMA_VERSION
    required_input "Web path / alias" "${PMA_WEB_PATH}" PMA_WEB_PATH
    PMA_WEB_PATH="/${PMA_WEB_PATH#/}"
    PMA_WEB_PATH="${PMA_WEB_PATH%/}"

    PMA_SERVER_FQDN="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo localhost)"
    required_input "Server FQDN for summary URL" "${PMA_SERVER_FQDN}" PMA_SERVER_FQDN

    generate_blowfish_secret

    echo ""
    echo -e "  ${WHITE}Version:${RESET}             ${ORANGE}${PMA_VERSION}${RESET}"
    echo -e "  ${WHITE}URL Path:${RESET}            ${ORANGE}${PMA_WEB_PATH}${RESET}"
    echo -e "  ${WHITE}Server:${RESET}              ${ORANGE}${PMA_SERVER_FQDN}${RESET}"
    echo ""

    ask_yes_no "Proceed with phpMyAdmin installation?" "y" answer
    [[ "${answer}" == "y" ]] || exit 0
}

install_phpmyadmin_dependencies() {
    print_header "Installing Dependencies"

    case "${OS_FAMILY}" in
        debian)
            update_repos
            install_packages wget tar nginx php-fpm php-mbstring php-zip php-gd php-json \
                php-curl php-mysql php-xml php-bz2 php-intl php-opcache
            ;;
        rhel)
            install_packages epel-release
            update_repos
            install_packages wget tar nginx php php-mbstring php-zip php-gd php-json \
                php-curl php-mysqlnd php-fpm php-xml php-bz2 php-intl php-opcache
            ;;
    esac

    detect_panel_php_runtime
    enable_service_now "${PANEL_PHP_SERVICE}"
    enable_service_now nginx
    success "phpMyAdmin dependencies installed."
}

download_phpmyadmin() {
    print_header "Downloading phpMyAdmin"

    if [[ -d "${PMA_INSTALL_DIR}" ]] && [[ -n "$(ls -A "${PMA_INSTALL_DIR}" 2>/dev/null || true)" ]]; then
        local answer=""
        ask_yes_no "Existing phpMyAdmin detected. Remove and reinstall?" "n" answer
        [[ "${answer}" == "y" ]] || error_exit "phpMyAdmin installation cancelled."
        rm -rf "${PMA_INSTALL_DIR}"
    fi

    local archive="/tmp/phpmyadmin-${PMA_VERSION}.tar.gz"
    local url="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz"

    mkdir -p "${PMA_INSTALL_DIR}"
    wget -q -O "${archive}" "${url}"
    tar -tzf "${archive}" >/dev/null 2>&1 || error_exit "Downloaded phpMyAdmin archive is invalid."
    tar -xzf "${archive}" --strip-components=1 -C "${PMA_INSTALL_DIR}"
    rm -f "${archive}"
    success "phpMyAdmin downloaded."
}

configure_phpmyadmin_files() {
    print_header "Configuring phpMyAdmin"

    mkdir -p "${PMA_TMP_DIR}"

    cat > "${PMA_CONFIG_FILE}" <<EOF
<?php
\$cfg['blowfish_secret'] = '${PMA_BLOWFISH_SECRET}';
\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['port'] = '';
\$cfg['Servers'][\$i]['socket'] = '';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
\$cfg['UploadDir'] = '';
\$cfg['SaveDir'] = '';
\$cfg['TempDir'] = '${PMA_TMP_DIR}';
\$cfg['LoginCookieValidity'] = 1800;
\$cfg['LoginCookieDeleteAll'] = true;
\$cfg['SendErrorReports'] = 'never';
\$cfg['ShowPhpInfo'] = false;
EOF

    chown -R "${WEBSERVER_USER}:${WEBSERVER_USER}" "${PMA_INSTALL_DIR}"
    find "${PMA_INSTALL_DIR}" -type d -exec chmod 755 {} \;
    find "${PMA_INSTALL_DIR}" -type f -exec chmod 644 {} \;
    chmod 660 "${PMA_CONFIG_FILE}"
    chmod 750 "${PMA_TMP_DIR}"

    success "phpMyAdmin configuration written."
}

write_phpmyadmin_snippet() {
    print_header "Nginx Snippet"

    local fastcgi_line=""
    fastcgi_line="$(panel_fastcgi_pass_line)"
    mkdir -p "${PMA_SNIPPET_DIR}"

    cat > "${PMA_SNIPPET_FILE}" <<EOF
location = ${PMA_WEB_PATH} {
    return 301 ${PMA_WEB_PATH}/;
}

location ^~ ${PMA_WEB_PATH}/ {
    alias ${PMA_INSTALL_DIR}/;
    index index.php;

    location ~ ^${PMA_WEB_PATH}/(.+\.php)$ {
        alias ${PMA_INSTALL_DIR}/\$1;
        ${fastcgi_line}
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$request_filename;
        fastcgi_param HTTP_PROXY "";
        fastcgi_read_timeout 600;
    }

    location ~* ^${PMA_WEB_PATH}/(doc|sql|setup)/ {
        deny all;
    }
}
EOF

    success "Snippet created at ${PMA_SNIPPET_FILE}."
}

include_phpmyadmin_in_panel_nginx() {
    local conf_path=""
    local tmp_file=""

    if [[ -f "$(panel_nginx_conf_path)" ]]; then
        conf_path="$(panel_nginx_conf_path)"
    fi

    if [[ -z "${conf_path}" ]]; then
        warning "Panel nginx config not found. Add this include manually inside your server block:"
        echo "include ${PMA_SNIPPET_FILE};"
        return 0
    fi

    if grep -Fq "include ${PMA_SNIPPET_FILE};" "${conf_path}" 2>/dev/null; then
        success "phpMyAdmin snippet is already included in nginx."
        return 0
    fi

    tmp_file="$(mktemp)"
    awk -v snippet="    include ${PMA_SNIPPET_FILE};" '
        /root \/var\/www\/pterodactyl\/public;/ {
            print
            print snippet
            next
        }
        { print }
    ' "${conf_path}" > "${tmp_file}"
    mv "${tmp_file}" "${conf_path}"

    if nginx -t >/dev/null 2>&1; then
        reload_service nginx || restart_service nginx
        success "phpMyAdmin include added to ${conf_path}."
    else
        nginx -t || true
        warning "nginx test failed after adding phpMyAdmin include. Review ${conf_path}."
    fi
}

show_phpmyadmin_completion() {
    local detected_url=""
    local scheme="http"
    detected_url="$(detect_existing_panel_url)"
    if [[ -n "${detected_url}" && "${detected_url}" == http://* ]]; then
        scheme="http"
    elif [[ -n "${detected_url}" && "${detected_url}" == https://* ]]; then
        scheme="https"
    fi

    print_header "phpMyAdmin Installed"
    echo -e "  ${WHITE}Access URL:${RESET}         ${ORANGE}${scheme}://${PMA_SERVER_FQDN}${PMA_WEB_PATH}${RESET}"
    echo -e "  ${WHITE}Install Path:${RESET}       ${ORANGE}${PMA_INSTALL_DIR}${RESET}"
    echo -e "  ${WHITE}Config File:${RESET}        ${ORANGE}${PMA_CONFIG_FILE}${RESET}"
    echo -e "  ${WHITE}Nginx Snippet:${RESET}      ${ORANGE}${PMA_SNIPPET_FILE}${RESET}"
}

perform_phpmyadmin_install() {
    gather_phpmyadmin_input
    install_phpmyadmin_dependencies
    download_phpmyadmin
    configure_phpmyadmin_files
    write_phpmyadmin_snippet
    include_phpmyadmin_in_panel_nginx
    show_phpmyadmin_completion
}

ask_uninstall_choices() {
    local answer=""

    print_header "Uninstall"

    ask_yes_no "Remove Pterodactyl Panel?" "n" answer
    [[ "${answer}" == "y" ]] && UNINSTALL_PANEL="true"

    ask_yes_no "Remove Pterodactyl Wings?" "n" answer
    [[ "${answer}" == "y" ]] && UNINSTALL_WINGS="true"

    ask_yes_no "Remove phpMyAdmin?" "n" answer
    [[ "${answer}" == "y" ]] && UNINSTALL_PMA="true"

    if [[ "${UNINSTALL_PANEL}" == "true" ]]; then
        ask_yes_no "Also remove the Pterodactyl database and DB user?" "n" answer
        [[ "${answer}" == "y" ]] && UNINSTALL_DATABASE="true"
    fi

    if [[ "${UNINSTALL_PANEL}" == "false" && "${UNINSTALL_WINGS}" == "false" && "${UNINSTALL_PMA}" == "false" ]]; then
        warning "Nothing selected. Exiting."
        exit 0
    fi

    warning "This is destructive."
    ask_yes_no "Proceed with uninstall?" "n" answer
    [[ "${answer}" == "y" ]] || exit 0
}

remove_panel_cron() {
    local tmp_file
    tmp_file="$(mktemp)"
    if crontab -u "${WEBSERVER_USER}" -l 2>/dev/null | grep -v "${PANEL_DIR}/artisan schedule:run" > "${tmp_file}"; then
        crontab -u "${WEBSERVER_USER}" "${tmp_file}"
    else
        crontab -u "${WEBSERVER_USER}" -r 2>/dev/null || true
    fi
    rm -f "${tmp_file}"
}

remove_panel_files() {
    print_header "Removing Panel"

    systemctl stop pteroq 2>/dev/null || true
    systemctl disable pteroq 2>/dev/null || true
    rm -f /etc/systemd/system/pteroq.service
    systemctl daemon-reload

    remove_panel_cron

    if [[ -d "${PANEL_DIR}" ]]; then
        rm -rf "${PANEL_DIR}"
        success "Removed ${PANEL_DIR}."
    fi

    rm -f "$(panel_nginx_conf_path)" 2>/dev/null || true
    if [[ -n "${NGINX_ENABLED_DIR}" ]]; then
        rm -f "${NGINX_ENABLED_DIR}/pterodactyl.conf" 2>/dev/null || true
    fi

    if nginx -t >/dev/null 2>&1; then
        reload_service nginx || true
    fi

    success "Panel files removed."
}

remove_wings_files() {
    print_header "Removing Wings"

    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true
    rm -f /etc/systemd/system/wings.service
    rm -f /usr/local/bin/wings
    rm -rf /etc/pterodactyl
    systemctl daemon-reload

    if [[ -d /var/lib/pterodactyl ]]; then
        local answer=""
        ask_yes_no "Delete /var/lib/pterodactyl server data too?" "n" answer
        [[ "${answer}" == "y" ]] && rm -rf /var/lib/pterodactyl
    fi

    success "Wings files removed."
}

remove_phpmyadmin_files() {
    print_header "Removing phpMyAdmin"

    rm -rf "${PMA_INSTALL_DIR}"
    rm -f "${PMA_SNIPPET_FILE}"

    if [[ -f "$(panel_nginx_conf_path)" ]]; then
        sed -i "\|include ${PMA_SNIPPET_FILE};|d" "$(panel_nginx_conf_path)"
    fi

    if nginx -t >/dev/null 2>&1; then
        reload_service nginx || true
    fi

    success "phpMyAdmin removed."
}

remove_database_interactive() {
    print_header "Database Removal"

    if ! command_exists mariadb; then
        warning "mariadb client not found. Skipping database removal."
        return 0
    fi

    local db_name=""
    local db_user=""
    optional_input "Database name to drop (leave empty to skip)" "" db_name
    if [[ -n "${db_name}" ]]; then
        if validate_db_name "${db_name}"; then
            mariadb -u root -e "DROP DATABASE IF EXISTS \`${db_name}\`;" >/dev/null 2>&1 || true
            success "Database ${db_name} removed."
        else
            warning "Skipping database drop because the name contains invalid characters."
        fi
    fi

    optional_input "Database user to drop (leave empty to skip)" "" db_user
    if [[ -n "${db_user}" ]]; then
        if validate_db_name "${db_user}"; then
            while IFS= read -r host; do
                [[ -z "${host}" ]] && continue
                mariadb -u root -e "DROP USER IF EXISTS '${db_user}'@'${host}';" >/dev/null 2>&1 || true
            done < <(mariadb -N -u root -e "SELECT Host FROM mysql.user WHERE User='${db_user}';" 2>/dev/null || true)
            mariadb -u root -e "FLUSH PRIVILEGES;" >/dev/null 2>&1 || true
            success "Database user ${db_user} removed."
        else
            warning "Skipping database user drop because the username contains invalid characters."
        fi
    fi
}

perform_uninstall() {
    ask_uninstall_choices

    if [[ "${UNINSTALL_PANEL}" == "true" ]]; then
        remove_panel_files
        if [[ "${UNINSTALL_DATABASE}" == "true" ]]; then
            remove_database_interactive
        fi
    fi

    if [[ "${UNINSTALL_WINGS}" == "true" ]]; then
        remove_wings_files
    fi

    if [[ "${UNINSTALL_PMA}" == "true" ]]; then
        remove_phpmyadmin_files
    fi

    print_header "Uninstall Complete"
    success "Requested components were removed."
}

main() {
    parse_cli_args "$@"
    show_banner
    check_root
    detect_os

    if [[ -z "${MAIN_ACTION}" ]]; then
        choose_main_action
    fi

    case "${MAIN_ACTION}" in
        panel) perform_panel_install ;;
        wings) perform_wings_install ;;
        phpmyadmin) perform_phpmyadmin_install ;;
        uninstall) perform_uninstall ;;
        *) error_exit "Unknown action: ${MAIN_ACTION}" ;;
    esac
}

main "$@"
