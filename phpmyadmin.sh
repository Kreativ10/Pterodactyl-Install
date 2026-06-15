#!/bin/bash
###############################################################################
#  Sundy.Systems — phpMyAdmin Interactive Installer  v2.0
#  Self-contained • Secure • Multi-distro
#  Supports: Ubuntu 20/22/24, Debian 11/12, Rocky 8/9, AlmaLinux 8/9
###############################################################################
set -euo pipefail

# ─── Color Palette ───────────────────────────────────────────────────────────
ORANGE='\033[38;5;208m'
DARK_ORANGE='\033[38;5;202m'
YELLOW='\033[38;5;220m'
GREEN='\033[38;5;82m'
RED='\033[38;5;196m'
WHITE='\033[38;5;255m'
BOLD='\033[1m'
RESET='\033[0m'
DIM='\033[2m'
CYAN='\033[38;5;81m'

# ─── Defaults ────────────────────────────────────────────────────────────────
PMA_VERSION="5.2.1"
PMA_WEB_PATH="/phpmyadmin"
PMA_INSTALL_DIR="/usr/share/phpmyadmin"
PMA_TMP_DIR="/usr/share/phpmyadmin/tmp"
PMA_CONFIG_FILE="/usr/share/phpmyadmin/config.inc.php"
NGINX_SNIPPET_DIR="/etc/nginx/snippets"
NGINX_SNIPPET_FILE="/etc/nginx/snippets/phpmyadmin.conf"
BLOWFISH_SECRET=""
DETECTED_OS=""
DETECTED_VERSION=""
DETECTED_FAMILY=""
SERVER_FQDN=""

# ─── Helper Functions ────────────────────────────────────────────────────────

print_banner() {
    clear
    echo ""
    echo -e "${DARK_ORANGE} ███████╗██╗   ██╗███╗   ██╗██████╗ ██╗   ██╗${RESET}"
    echo -e "${ORANGE} ██╔════╝██║   ██║████╗  ██║██╔══██╗╚██╗ ██╔╝${RESET}"
    echo -e "${ORANGE} ███████╗██║   ██║██╔██╗ ██║██║  ██║ ╚████╔╝${RESET}"
    echo -e "${YELLOW} ╚════██║██║   ██║██║╚██╗██║██║  ██║  ╚██╔╝${RESET}"
    echo -e "${YELLOW} ███████║╚██████╔╝██║ ╚████║██████╔╝   ██║${RESET}"
    echo -e "${DARK_ORANGE} ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝    ╚═╝${RESET}"
    echo -e "${WHITE}        ┌─────────────────────────────┐${RESET}"
    echo -e "${WHITE}        │ ${ORANGE}  S U N D Y . S Y S T E M S ${WHITE}│${RESET}"
    echo -e "${WHITE}        │ ${YELLOW}  phpMyAdmin Installer v2.0 ${WHITE}│${RESET}"
    echo -e "${WHITE}        └─────────────────────────────┘${RESET}"
    echo ""
}

info()    { echo -e "  ${ORANGE}▸${RESET} ${WHITE}$1${RESET}"; }
success() { echo -e "  ${GREEN}✔${RESET} ${WHITE}$1${RESET}"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET} ${YELLOW}$1${RESET}"; }
fail()    { echo -e "  ${RED}✘${RESET} ${RED}$1${RESET}"; }
header()  { echo ""; echo -e "  ${BOLD}${ORANGE}━━━ $1 ━━━${RESET}"; echo ""; }
divider() { echo -e "  ${DIM}${ORANGE}─────────────────────────────────────────────────${RESET}"; }

prompt_value() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    echo -ne "  ${ORANGE}▸${RESET} ${WHITE}${prompt_text}${RESET} ${DIM}[${default_val}]${RESET}: "
    local user_input
    read -r user_input
    if [[ -z "$user_input" ]]; then
        printf -v "$var_name" '%s' "$default_val"
    else
        printf -v "$var_name" '%s' "$user_input"
    fi
}

confirm_proceed() {
    echo ""
    echo -ne "  ${ORANGE}▸${RESET} ${WHITE}Proceed with installation?${RESET} ${DIM}[Y/n]${RESET}: "
    local answer
    read -r answer
    case "${answer,,}" in
        n|no) fail "Installation cancelled by user."; exit 0 ;;
        *)    return 0 ;;
    esac
}

spin() {
    local pid=$1
    local msg="$2"
    local spinchars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local c="${spinchars:i%${#spinchars}:1}"
        echo -ne "\r  ${ORANGE}${c}${RESET} ${WHITE}${msg}${RESET}  "
        sleep 0.1
        ((i++)) || true
    done
    wait "$pid" 2>/dev/null
    local exit_code=$?
    echo -ne "\r"
    return $exit_code
}

generate_blowfish_secret() {
    BLOWFISH_SECRET="$(tr -dc 'A-Za-z0-9!@#%^*_+~' </dev/urandom 2>/dev/null | head -c 32 || true)"
    if [[ ${#BLOWFISH_SECRET} -lt 32 ]]; then
        BLOWFISH_SECRET="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
    fi
}

# ─── Pre-flight Checks ──────────────────────────────────────────────────────

preflight_root_check() {
    if [[ "$(id -u)" -ne 0 ]]; then
        print_banner
        fail "This script must be run as root."
        echo -e "  ${DIM}Try: sudo bash $0${RESET}"
        echo ""
        exit 1
    fi
}

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        fail "Cannot detect operating system. /etc/os-release not found."
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    DETECTED_OS="${ID}"
    DETECTED_VERSION="${VERSION_ID}"

    case "${DETECTED_OS}" in
        ubuntu)
            DETECTED_FAMILY="debian"
            case "${DETECTED_VERSION}" in
                20.04|22.04|24.04) : ;;
                *) warn "Ubuntu ${DETECTED_VERSION} is untested. Proceeding anyway." ;;
            esac
            ;;
        debian)
            DETECTED_FAMILY="debian"
            local major="${DETECTED_VERSION%%.*}"
            case "${major}" in
                11|12) : ;;
                *) warn "Debian ${DETECTED_VERSION} is untested. Proceeding anyway." ;;
            esac
            ;;
        rocky|almalinux)
            DETECTED_FAMILY="rhel"
            local major="${DETECTED_VERSION%%.*}"
            case "${major}" in
                8|9) : ;;
                *) warn "${DETECTED_OS} ${DETECTED_VERSION} is untested. Proceeding anyway." ;;
            esac
            ;;
        centos)
            DETECTED_FAMILY="rhel"
            warn "CentOS detected — limited support. Proceeding."
            ;;
        *)
            fail "Unsupported OS: ${DETECTED_OS}"
            echo -e "  ${DIM}Supported: Ubuntu, Debian, Rocky Linux, AlmaLinux${RESET}"
            exit 1
            ;;
    esac

    success "Detected OS: ${BOLD}${DETECTED_OS} ${DETECTED_VERSION}${RESET} (${DETECTED_FAMILY})"
}

check_existing_installation() {
    if [[ -d "${PMA_INSTALL_DIR}" ]]; then
        echo ""
        warn "Existing phpMyAdmin installation found at ${PMA_INSTALL_DIR}"
        echo -ne "  ${ORANGE}▸${RESET} ${WHITE}Remove existing installation and continue?${RESET} ${DIM}[y/N]${RESET}: "
        local answer
        read -r answer
        case "${answer,,}" in
            y|yes)
                rm -rf "${PMA_INSTALL_DIR}"
                success "Removed existing installation."
                ;;
            *)
                fail "Installation cancelled. Please manually remove ${PMA_INSTALL_DIR} first."
                exit 0
                ;;
        esac
    fi
}

# ─── Interactive Configuration ───────────────────────────────────────────────

interactive_config() {
    header "Configuration"

    prompt_value "phpMyAdmin version" "${PMA_VERSION}" PMA_VERSION
    prompt_value "Web path / alias" "${PMA_WEB_PATH}" PMA_WEB_PATH

    # Normalize web path — ensure leading slash, strip trailing slash
    PMA_WEB_PATH="/${PMA_WEB_PATH#/}"
    PMA_WEB_PATH="${PMA_WEB_PATH%/}"

    # Auto-detect server FQDN
    SERVER_FQDN="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo 'localhost')"
    prompt_value "Server FQDN (for access URL)" "${SERVER_FQDN}" SERVER_FQDN

    # Generate blowfish secret
    generate_blowfish_secret
    success "Blowfish secret auto-generated (${#BLOWFISH_SECRET} chars)"

    divider
    echo ""
    echo -e "  ${BOLD}${WHITE}Installation Summary:${RESET}"
    echo -e "  ${ORANGE}│${RESET} ${WHITE}phpMyAdmin version  :${RESET} ${CYAN}${PMA_VERSION}${RESET}"
    echo -e "  ${ORANGE}│${RESET} ${WHITE}Install directory    :${RESET} ${CYAN}${PMA_INSTALL_DIR}${RESET}"
    echo -e "  ${ORANGE}│${RESET} ${WHITE}Web path            :${RESET} ${CYAN}${PMA_WEB_PATH}${RESET}"
    echo -e "  ${ORANGE}│${RESET} ${WHITE}Nginx snippet       :${RESET} ${CYAN}${NGINX_SNIPPET_FILE}${RESET}"
    echo -e "  ${ORANGE}│${RESET} ${WHITE}Server FQDN         :${RESET} ${CYAN}${SERVER_FQDN}${RESET}"
    echo -e "  ${ORANGE}│${RESET} ${WHITE}Blowfish secret     :${RESET} ${DIM}${BLOWFISH_SECRET:0:8}••••••••••••${RESET}"
    echo ""

    confirm_proceed
}

# ─── Installation Steps ─────────────────────────────────────────────────────

install_dependencies() {
    header "Installing Dependencies"

    if [[ "${DETECTED_FAMILY}" == "debian" ]]; then
        info "Updating apt package cache..."
        apt-get update -qq >/dev/null 2>&1
        info "Installing required packages..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            wget tar nginx php-mbstring php-zip php-gd php-json \
            php-curl php-mysql php-fpm php-xml php-bz2 php-intl \
            php-opcache >/dev/null 2>&1
        success "APT packages installed."
    elif [[ "${DETECTED_FAMILY}" == "rhel" ]]; then
        info "Installing EPEL repository..."
        dnf install -y -q epel-release >/dev/null 2>&1 || true
        info "Installing required packages..."
        dnf install -y -q \
            wget tar nginx php php-mbstring php-zip php-gd php-json \
            php-curl php-mysqlnd php-fpm php-xml php-bz2 php-intl \
            php-opcache >/dev/null 2>&1
        success "DNF packages installed."
    fi
}

download_phpmyadmin() {
    header "Downloading phpMyAdmin ${PMA_VERSION}"

    local download_url="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz"
    local tmp_archive="/tmp/phpmyadmin-${PMA_VERSION}.tar.gz"

    info "URL: ${download_url}"

    if ! wget -q --show-progress --timeout=30 --tries=3 -O "${tmp_archive}" "${download_url}"; then
        fail "Failed to download phpMyAdmin ${PMA_VERSION}."
        fail "Check that version ${PMA_VERSION} exists at files.phpmyadmin.net"
        rm -f "${tmp_archive}"
        exit 1
    fi
    success "Download complete."

    # Verify the archive is valid
    if ! tar -tzf "${tmp_archive}" >/dev/null 2>&1; then
        fail "Downloaded archive is corrupt or invalid."
        rm -f "${tmp_archive}"
        exit 1
    fi
    success "Archive integrity verified."

    info "Extracting to ${PMA_INSTALL_DIR}..."
    mkdir -p "${PMA_INSTALL_DIR}"
    tar -xzf "${tmp_archive}" --strip-components=1 -C "${PMA_INSTALL_DIR}"
    rm -f "${tmp_archive}"
    success "Extraction complete."
}

configure_phpmyadmin() {
    header "Configuring phpMyAdmin"

    # Create tmp directory
    mkdir -p "${PMA_TMP_DIR}"
    success "Created tmp directory: ${PMA_TMP_DIR}"

    # Determine the web server user
    local web_user="www-data"
    if [[ "${DETECTED_FAMILY}" == "rhel" ]]; then
        web_user="nginx"
    fi

    # Write config.inc.php
    info "Writing config.inc.php..."
    cat > "${PMA_CONFIG_FILE}" <<PMACONFIG
<?php
/**
 * phpMyAdmin Configuration File
 * Generated by Sundy.Systems Installer v2.0
 * Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
 *
 * WARNING: Do not edit the blowfish_secret after data has been encrypted.
 */

/**
 * Blowfish secret for cookie-based authentication.
 * Must be exactly 32 characters.
 */
\$cfg['blowfish_secret'] = '${BLOWFISH_SECRET}';

/**
 * Server configuration
 */
\$i = 0;
\$i++;

/* Authentication type */
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';

/* Server parameters */
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['port'] = '';
\$cfg['Servers'][\$i]['socket'] = '';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;

/**
 * phpMyAdmin configuration storage (optional — disable if not needed)
 */
// \$cfg['Servers'][\$i]['controluser'] = 'pma';
// \$cfg['Servers'][\$i]['controlpass'] = '';
// \$cfg['Servers'][\$i]['pmadb'] = 'phpmyadmin';

/**
 * Directories
 */
\$cfg['UploadDir'] = '';
\$cfg['SaveDir'] = '';
\$cfg['TempDir'] = '${PMA_TMP_DIR}';

/**
 * Security hardening
 */
\$cfg['LoginCookieValidity'] = 1800;
\$cfg['LoginCookieStore'] = 0;
\$cfg['LoginCookieDeleteAll'] = true;
\$cfg['MaxRows'] = 50;
\$cfg['SendErrorReports'] = 'never';

/**
 * Display settings
 */
\$cfg['ShowPhpInfo'] = false;
\$cfg['ShowDbStructureCharset'] = true;
\$cfg['ShowDbStructureCreation'] = true;
\$cfg['ShowDbStructureLastUpdate'] = true;
\$cfg['ShowDbStructureLastCheck'] = true;
PMACONFIG

    success "config.inc.php written."

    # Set file permissions
    info "Setting file permissions..."
    chown -R "${web_user}:${web_user}" "${PMA_INSTALL_DIR}"
    find "${PMA_INSTALL_DIR}" -type d -exec chmod 755 {} \;
    find "${PMA_INSTALL_DIR}" -type f -exec chmod 644 {} \;
    chmod 660 "${PMA_CONFIG_FILE}"
    chmod 750 "${PMA_TMP_DIR}"
    success "Permissions configured (owner: ${web_user})."
}

create_nginx_snippet() {
    header "Creating Nginx Configuration"

    # Detect PHP-FPM socket
    local php_socket=""
    local php_version=""

    if [[ "${DETECTED_FAMILY}" == "debian" ]]; then
        # Find the active PHP-FPM version
        php_version="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || echo "")"
        if [[ -n "${php_version}" ]]; then
            php_socket="/run/php/php${php_version}-fpm.sock"
        fi
        # Fallback: search for any existing socket
        if [[ -z "${php_socket}" ]] || [[ ! -S "${php_socket}" ]]; then
            php_socket="$(find /run/php/ -name 'php*-fpm.sock' -print -quit 2>/dev/null || echo "")"
        fi
        if [[ -z "${php_socket}" ]]; then
            php_socket="/run/php/php8.1-fpm.sock"
            warn "Could not detect PHP-FPM socket — defaulting to ${php_socket}"
        fi
    elif [[ "${DETECTED_FAMILY}" == "rhel" ]]; then
        php_socket="/run/php-fpm/www.sock"
        if [[ ! -S "${php_socket}" ]]; then
            # Try default TCP
            php_socket="127.0.0.1:9000"
            warn "PHP-FPM socket not found — falling back to TCP ${php_socket}"
        fi
    fi

    success "PHP-FPM endpoint: ${php_socket}"

    # Create the snippets directory if it doesn't exist
    mkdir -p "${NGINX_SNIPPET_DIR}"

    # Determine fastcgi_pass directive
    local fastcgi_pass_directive
    if [[ "${php_socket}" == 127.* ]]; then
        fastcgi_pass_directive="fastcgi_pass ${php_socket};"
    else
        fastcgi_pass_directive="fastcgi_pass unix:${php_socket};"
    fi

    # Write nginx snippet
    info "Writing nginx snippet to ${NGINX_SNIPPET_FILE}..."
    cat > "${NGINX_SNIPPET_FILE}" <<NGINXCONF
# ─────────────────────────────────────────────────────────────
#  phpMyAdmin — Nginx Location Snippet
#  Generated by Sundy.Systems Installer v2.0
#  Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
#
#  Include this file inside a server {} block:
#      include ${NGINX_SNIPPET_FILE};
# ─────────────────────────────────────────────────────────────

location ${PMA_WEB_PATH} {
    alias ${PMA_INSTALL_DIR}/;

    index index.php index.html;

    # Security: deny access to sensitive files
    location ~ /(\\.ht|config\\.inc\\.php|libraries|templates|tmp) {
        deny all;
        return 404;
    }

    location ~ \\.php\$ {
        # Prevent URI path traversal attacks
        fastcgi_split_path_info ^(${PMA_WEB_PATH//\//\\/})(/.*\\.php)(/.*)?\$;
        if (!-f \$request_filename) {
            return 404;
        }

        ${fastcgi_pass_directive}
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$request_filename;
        include fastcgi_params;

        # Security headers
        fastcgi_param HTTP_PROXY "";
        fastcgi_read_timeout 600;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }
}
NGINXCONF

    success "Nginx snippet created."

    # Test for existing pterodactyl/panel config and offer to include the snippet
    local ptero_conf=""
    for conf_candidate in \
        /etc/nginx/sites-enabled/pterodactyl.conf \
        /etc/nginx/sites-enabled/panel.conf \
        /etc/nginx/conf.d/pterodactyl.conf \
        /etc/nginx/conf.d/panel.conf; do
        if [[ -f "${conf_candidate}" ]]; then
            ptero_conf="${conf_candidate}"
            break
        fi
    done

    if [[ -n "${ptero_conf}" ]]; then
        info "Detected Pterodactyl nginx config: ${ptero_conf}"

        if grep -q "include.*phpmyadmin" "${ptero_conf}" 2>/dev/null; then
            success "Snippet already included in ${ptero_conf}."
        else
            echo -ne "  ${ORANGE}▸${RESET} ${WHITE}Add include to ${ptero_conf}?${RESET} ${DIM}[Y/n]${RESET}: "
            local answer
            read -r answer
            case "${answer,,}" in
                n|no)
                    warn "Skipped auto-include. Add manually:"
                    echo -e "    ${CYAN}include ${NGINX_SNIPPET_FILE};${RESET}"
                    ;;
                *)
                    # Insert the include directive before the last closing brace
                    sed -i "/^}/i \\    # phpMyAdmin (added by Sundy.Systems installer)\\n    include ${NGINX_SNIPPET_FILE//\//\\/};" "${ptero_conf}"
                    success "Include directive added to ${ptero_conf}."
                    ;;
            esac
        fi
    else
        warn "No Pterodactyl nginx config found."
        info "Add the following to your nginx server {} block:"
        echo -e "    ${CYAN}include ${NGINX_SNIPPET_FILE};${RESET}"
    fi

    # Test & reload nginx
    info "Testing nginx configuration..."
    if nginx -t 2>/dev/null; then
        success "Nginx configuration test passed."
        info "Reloading nginx..."
        systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
        success "Nginx reloaded."
    else
        warn "Nginx configuration test failed!"
        warn "Please fix the errors above and reload nginx manually:"
        echo -e "    ${CYAN}nginx -t && systemctl reload nginx${RESET}"
    fi
}

ensure_services() {
    header "Enabling Services"

    # Enable and start PHP-FPM
    local fpm_service=""
    if [[ "${DETECTED_FAMILY}" == "debian" ]]; then
        local php_ver
        php_ver="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;' 2>/dev/null || echo "8.1")"
        fpm_service="php${php_ver}-fpm"
    else
        fpm_service="php-fpm"
    fi

    if systemctl is-active --quiet "${fpm_service}" 2>/dev/null; then
        success "${fpm_service} is already running."
    else
        info "Starting ${fpm_service}..."
        systemctl enable --now "${fpm_service}" 2>/dev/null || true
        success "${fpm_service} started and enabled."
    fi

    # Make sure nginx is enabled
    if systemctl is-active --quiet nginx 2>/dev/null; then
        success "Nginx is already running."
    else
        info "Starting nginx..."
        systemctl enable --now nginx 2>/dev/null || true
        success "Nginx started and enabled."
    fi
}

# ─── Final Summary ───────────────────────────────────────────────────────────

print_summary() {
    echo ""
    divider
    echo ""
    echo -e "  ${BOLD}${GREEN}✔  phpMyAdmin ${PMA_VERSION} Installed Successfully!${RESET}"
    echo ""
    echo -e "  ${ORANGE}┌──────────────────────────────────────────────────────┐${RESET}"
    echo -e "  ${ORANGE}│${RESET}  ${BOLD}${WHITE}Access URL${RESET}                                         ${ORANGE}│${RESET}"
    echo -e "  ${ORANGE}│${RESET}  ${CYAN}https://${SERVER_FQDN}${PMA_WEB_PATH}${RESET}"
    echo -e "  ${ORANGE}│${RESET}                                                      ${ORANGE}│${RESET}"
    echo -e "  ${ORANGE}│${RESET}  ${BOLD}${WHITE}Install Path${RESET}                                       ${ORANGE}│${RESET}"
    echo -e "  ${ORANGE}│${RESET}  ${WHITE}${PMA_INSTALL_DIR}${RESET}"
    echo -e "  ${ORANGE}│${RESET}                                                      ${ORANGE}│${RESET}"
    echo -e "  ${ORANGE}│${RESET}  ${BOLD}${WHITE}Config File${RESET}                                        ${ORANGE}│${RESET}"
    echo -e "  ${ORANGE}│${RESET}  ${WHITE}${PMA_CONFIG_FILE}${RESET}"
    echo -e "  ${ORANGE}│${RESET}                                                      ${ORANGE}│${RESET}"
    echo -e "  ${ORANGE}│${RESET}  ${BOLD}${WHITE}Nginx Snippet${RESET}                                      ${ORANGE}│${RESET}"
    echo -e "  ${ORANGE}│${RESET}  ${WHITE}${NGINX_SNIPPET_FILE}${RESET}"
    echo -e "  ${ORANGE}│${RESET}                                                      ${ORANGE}│${RESET}"
    echo -e "  ${ORANGE}│${RESET}  ${BOLD}${WHITE}Blowfish Secret${RESET}                                    ${ORANGE}│${RESET}"
    echo -e "  ${ORANGE}│${RESET}  ${DIM}${BLOWFISH_SECRET:0:8}••••••••••••••••••••••••${RESET}"
    echo -e "  ${ORANGE}└──────────────────────────────────────────────────────┘${RESET}"
    echo ""
    echo -e "  ${YELLOW}Security Reminders:${RESET}"
    echo -e "  ${DIM}  •${RESET} ${WHITE}Restrict access by IP if possible (e.g. allow/deny in nginx).${RESET}"
    echo -e "  ${DIM}  •${RESET} ${WHITE}Consider renaming the web path from ${PMA_WEB_PATH} to something unique.${RESET}"
    echo -e "  ${DIM}  •${RESET} ${WHITE}Enable HTTPS / TLS on your nginx server block.${RESET}"
    echo -e "  ${DIM}  •${RESET} ${WHITE}Keep phpMyAdmin updated to patch security vulnerabilities.${RESET}"
    echo -e "  ${DIM}  •${RESET} ${WHITE}The blowfish secret is stored in ${PMA_CONFIG_FILE} — protect it.${RESET}"
    echo ""
    echo -e "  ${DIM}Powered by ${ORANGE}Sundy.Systems${RESET} ${DIM}— $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    preflight_root_check
    print_banner

    header "System Detection"
    detect_os
    check_existing_installation

    interactive_config

    install_dependencies
    download_phpmyadmin
    configure_phpmyadmin
    create_nginx_snippet
    ensure_services

    print_summary
}

# Trap for cleanup on unexpected exit
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        echo ""
        fail "Installation failed with exit code ${exit_code}."
        fail "Check the output above for details."
        echo -e "  ${DIM}If you need help, visit https://sundy.systems/support${RESET}"
        echo ""
    fi
    # Clean up temp files
    rm -f /tmp/phpmyadmin-*.tar.gz 2>/dev/null || true
}
trap cleanup EXIT

main "$@"
