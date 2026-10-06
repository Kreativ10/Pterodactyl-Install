#!/usr/bin/env bash
###############################################################################
# Unified Pterodactyl Toolkit
# - Install Pterodactyl Panel
# - Install Pterodactyl Wings
# - Install phpMyAdmin
# - Uninstall components
###############################################################################

set -Eeuo pipefail

SCRIPT_VERSION="3.1"

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
PHP_BIN=""
PHP_FPM_BIN=""
PHP_POOL_DIR=""
CRON_SERVICE=""
DATABASE_BIN=mariadb
DATABASE_ADMIN_BIN=mariadb-admin
OS_CODENAME=""
CHECK_ONLY=false
INSTALL_TMP_DIR=""
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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -r "$SCRIPT_DIR/lib/common.sh" ]]; then
    printf 'Download the complete repository, including lib/: git clone https://github.com/Kreativ10/Pterodactyl-Install.git\n' >&2
    exit 1
fi
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"
# shellcheck source=lib/firewall.sh
source "${SCRIPT_DIR}/lib/firewall.sh"
# shellcheck source=lib/panel.sh
source "${SCRIPT_DIR}/lib/panel.sh"
# shellcheck source=lib/wings.sh
source "${SCRIPT_DIR}/lib/wings.sh"
# shellcheck source=lib/phpmyadmin.sh
source "${SCRIPT_DIR}/lib/phpmyadmin.sh"
# shellcheck source=lib/uninstall.sh
source "${SCRIPT_DIR}/lib/uninstall.sh"

main() {
    parse_cli_args "$@"
    detect_os
    if [[ "$CHECK_ONLY" == true ]]; then
        printf 'OS: %s %s\nPHP: %s\nPHP-FPM: %s\nRedis: %s\nCron: %s\n' \
            "$OS_ID" "$OS_VERSION" "$PHP_BIN" "$PANEL_PHP_SERVICE" "$REDIS_SERVICE" "$CRON_SERVICE"
        return 0
    fi
    show_banner
    check_root
    [[ -d /run/systemd/system ]] || error_exit "A running systemd system is required."
    if [[ ! -t 0 ]]; then
        exec < /dev/tty || error_exit "Interactive input requires a terminal. Clone the repository and run sudo bash panel.sh."
    fi
    umask 077
    INSTALL_TMP_DIR="$(mktemp -d /tmp/pterodactyl-install.XXXXXX)"
    trap 'cleanup_install "$?"' EXIT
    trap 'installation_error "$?" "$LINENO"' ERR
    trap 'exit 130' INT
    trap 'exit 143' TERM

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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
