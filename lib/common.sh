#!/usr/bin/env bash
# shellcheck shell=bash
# Shared variables are consumed by panel.sh and other sourced modules.
# shellcheck disable=SC2034

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

gen_password() {
    local length="${1:-32}" password='' chunk=''
    if [[ ! "$length" =~ ^[0-9]+$ ]] || (( length == 0 || length > 4096 )); then
        error_exit "Invalid password length."
    fi
    # Finite input avoids SIGPIPE from tr | head under pipefail.
    while (( ${#password} < length )); do
        chunk="$(od -An -N64 -tx1 /dev/urandom | tr -d ' \n')"
        password+="$chunk"
    done
    printf '%s\n' "${password:0:length}"
}

escape_sql_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\'/\'\'}"
    printf '%s' "${value}"
}

escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'
}

set_env_value() {
    local env_file="$1"
    local key="$2"
    local value="$3"
    local escaped
    escaped="$(escape_sed_replacement "${value}")"

    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || error_exit "Invalid environment key or multiline value."
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
    local entered_value=""

    while true; do
        if [[ -n "${default_value}" ]]; then
            echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET} [${ORANGE}${default_value}${RESET}]: " >&2
        else
            echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET}: " >&2
        fi
        read -r entered_value || error_exit "Input ended unexpectedly."

        if [[ -z "${entered_value}" && -n "${default_value}" ]]; then
            entered_value="${default_value}"
        fi

        if [[ -n "${entered_value}" ]]; then
            printf -v "${var_name}" '%s' "${entered_value}"
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
        read -rs first || error_exit "Input ended unexpectedly."
        echo "" >&2

        if [[ "${#first}" -lt "${min_length}" ]]; then
            warning "Minimum length: ${min_length} characters."
            continue
        fi

        echo -en "${ORANGE}▸${RESET} ${WHITE}Confirm password${RESET}: " >&2
        read -rs second || error_exit "Input ended unexpectedly."
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
    local entered_value=""

    if [[ -n "${default_value}" ]]; then
        echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET} [${ORANGE}${default_value}${RESET}]: " >&2
    else
        echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET}: " >&2
    fi
    read -r entered_value || error_exit "Input ended unexpectedly."

    if [[ -z "${entered_value}" ]]; then
        entered_value="${default_value}"
    fi

    printf -v "${var_name}" '%s' "${entered_value}"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local var_name="$3"
    local hint=""
    local response=""

    if [[ "${default}" == "y" ]]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    while true; do
        echo -en "${ORANGE}▸${RESET} ${WHITE}${prompt}${RESET} [${ORANGE}${hint}${RESET}]: " >&2
        read -r response || error_exit "Input ended unexpectedly."
        response="${response:-${default}}"
        case "${response,,}" in
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
    if [[ "$value" =~ ^[0-9.]+$ ]]; then
        validate_bind_address "$value"
        return
    fi
    (( ${#value} <= 253 )) && [[ "$value" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]
}

validate_email() {
    local value="$1"
    [[ "${value}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

validate_timezone() {
    local value="$1"
    [[ "$value" != *..* && "$value" =~ ^[A-Za-z0-9_+/-]+$ && -f "/usr/share/zoneinfo/$value" ]]
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
    local value="$1" octet
    [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local octets=()
    IFS=. read -r -a octets <<< "$value"
    for octet in "${octets[@]}"; do
        (( 10#$octet <= 255 )) || return 1
        [[ "$octet" == 0 || "$octet" != 0* ]] || return 1
    done
}

validate_mysql_host_pattern() {
    local value="$1"
    [[ "${value}" =~ ^[%A-Za-z0-9._:-]+$ ]]
}

wait_for_mariadb() {
    local tries=30
    local i
    for ((i = 1; i <= tries; i++)); do
        if "$DATABASE_ADMIN_BIN" ping >/dev/null 2>&1; then
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
    validate_db_name "$db_name" || error_exit "Invalid database name."
    "$DATABASE_BIN" -u root -e "CREATE DATABASE \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    success "Database ${db_name} is ready."
}

create_database_user() {
    local db_user="$1"
    local db_pass="$2"
    local db_name="$3"
    local db_host="${4:-127.0.0.1}"
    local safe_pass

    (( ${#db_user} <= 32 )) || error_exit "MariaDB usernames cannot exceed 32 characters."
    validate_db_name "$db_user" || error_exit "Invalid database username."
    validate_mysql_host_pattern "$db_host" || error_exit "Invalid database host."
    safe_pass="$(escape_sql_string "${db_pass}")"

    validate_db_name "$db_name" || error_exit "Invalid database name."
    output "Creating MariaDB user ${db_user}@${db_host}..."
    run_database -u root <<EOSQL
SET SESSION sql_mode = '';
CREATE USER '${db_user}'@'${db_host}' IDENTIFIED BY '${safe_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'${db_host}';
FLUSH PRIVILEGES;
EOSQL
    success "Database user ${db_user}@${db_host} is ready."
}

create_global_database_user() {
    local db_user="$1"
    local db_pass="$2"
    local db_host="$3"
    local safe_pass

    (( ${#db_user} <= 32 )) || error_exit "MariaDB usernames cannot exceed 32 characters."
    validate_db_name "$db_user" || error_exit "Invalid database username."
    validate_mysql_host_pattern "$db_host" || error_exit "Invalid database host."
    safe_pass="$(escape_sql_string "${db_pass}")"

    output "Creating MariaDB user ${db_user}@${db_host} with global privileges..."
    run_database -u root <<EOSQL
SET SESSION sql_mode = '';
CREATE USER '${db_user}'@'${db_host}' IDENTIFIED BY '${safe_pass}';
GRANT ALL PRIVILEGES ON *.* TO '${db_user}'@'${db_host}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOSQL
    success "Global MariaDB user ${db_user}@${db_host} is ready."
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
        read -r answer || error_exit "Input ended unexpectedly."
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
    while (( $# )); do
        case "$1" in
            --action)
                (( $# >= 2 )) || error_exit "--action requires a value."
                case "$2" in
                    panel|wings|phpmyadmin|uninstall) MAIN_ACTION="$2" ;;
                    *) error_exit "Unknown action: $2" ;;
                esac
                shift 2 ;;
            --check) CHECK_ONLY=true; shift ;;
            --help|-h)
                printf 'Usage: sudo bash %s [--action panel|wings|phpmyadmin|uninstall]\n       bash %s --check\n' "$0" "$0"
                exit 0 ;;
            *) error_exit "Unknown argument: $1" ;;
        esac
    done
}


cleanup_install() {
    local status="$1"
    if [[ "${WINGS_ACME_STARTED:-false}" == true ]]; then
        /etc/letsencrypt/pterodactyl-wings-start || warning "Could not restart web services after ACME; check systemctl."
    fi
    if [[ -n "$INSTALL_TMP_DIR" && -d "$INSTALL_TMP_DIR" ]]; then
        if (( status == 0 )); then
            rm -rf -- "$INSTALL_TMP_DIR"
        else
            warning "Protected diagnostic files retained at $INSTALL_TMP_DIR (root only)."
        fi
    fi
}

installation_error() {
    local status="$1" line="$2"
    trap - ERR
    warning "Installation failed at line $line (status $status)."
    exit "$status"
}

run_artisan() {
    # Artisan can echo environment values. Keep output in a protected file, not the terminal.
    if ! "$PHP_BIN" "${PANEL_DIR}/artisan" "$@" > "${INSTALL_TMP_DIR}/artisan.log" 2>&1; then
        error_exit "Artisan $1 failed. See ${INSTALL_TMP_DIR}/artisan.log (root only)."
    fi
}

validate_admin_password() {
    [[ ${#1} -ge 8 && "$1" =~ [a-z] && "$1" =~ [A-Z] && "$1" =~ [0-9] ]]
}

validate_web_path() {
    [[ "$1" =~ ^/[a-zA-Z0-9_-]+$ ]]
}

validate_certificate_path() {
    [[ "$1" =~ ^/[A-Za-z0-9_./-]+$ && -r "$1" ]]
}

validate_trusted_proxies() {
    [[ "$1" == '*' ]] && return 0
    local address prefix item
    local items=()
    IFS=, read -r -a items <<< "$1"
    [[ ${#items[@]} -gt 0 && "$1" != *, ]] || return 1
    for item in "${items[@]}"; do
        address="${item%%/*}"
        validate_bind_address "$address" || return 1
        if [[ "$item" == */* ]]; then
            prefix="${item#*/}"
            [[ "$prefix" =~ ^([0-9]|[12][0-9]|3[0-2])$ ]] || return 1
        fi
    done
}

refuse_existing_directory() {
    local directory="$1"
    if [[ -e "$directory" || -L "$directory" ]]; then
        [[ -d "$directory" && ! -L "$directory" && -z "$(ls -A "$directory")" ]] || \
            error_exit "Existing $directory detected. Back up and use the upstream upgrade procedure; this installer never deletes an existing installation."
    fi
}

install_certificate_renewal() {
    local component="$1"
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    local hook="/etc/letsencrypt/renewal-hooks/deploy/pterodactyl-${component}"
    if [[ "$component" == panel ]]; then
        printf '#!/bin/sh\nnginx -t && systemctl reload nginx\n' > "$hook"
    else
        printf '#!/bin/sh\nif systemctl is-active --quiet wings; then systemctl restart wings; fi\n' > "$hook"
    fi
    chmod 750 "$hook"
    local timer
    for timer in certbot.timer certbot-renew.timer; do
        if systemctl list-unit-files "$timer" --no-legend | grep -q "^$timer"; then
            enable_service_now "$timer"
            return 0
        fi
    done
    case "$OS_FAMILY" in
        debian) install_packages cron; CRON_SERVICE=cron ;;
        rhel) install_packages cronie; CRON_SERVICE=crond ;;
        arch) install_packages cronie; CRON_SERVICE=cronie ;;
    esac
    enable_service_now "$CRON_SERVICE"
    printf '0 23 * * * root /usr/bin/certbot renew --quiet\n' > /etc/cron.d/pterodactyl-certbot
    chmod 644 /etc/cron.d/pterodactyl-certbot
}

set_env_literal() {
    local literal="$3"
    literal="${literal//\\/\\\\}"
    literal="${literal//\"/\\\"}"
    literal="${literal//\$/\\\$}"
    set_env_value "$1" "$2" "\"${literal}\""
}

run_database() {
    if [[ -n "$INSTALL_TMP_DIR" ]]; then
        if ! "$DATABASE_BIN" "$@" > "$INSTALL_TMP_DIR/database.log" 2>&1; then
            error_exit "MariaDB operation failed. See $INSTALL_TMP_DIR/database.log (root only)."
        fi
    else
        # Also allows the sourced helpers to be exercised with a mock client.
        "$DATABASE_BIN" "$@"
    fi
}
