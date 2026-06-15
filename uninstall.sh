#!/bin/bash
###############################################################################
#                                                                             #
#   Pterodactyl Uninstaller — Sundy.Systems                                   #
#   Copyright (C) 2024-2026 Sundy.Systems — All rights reserved.             #
#                                                                             #
#   This script interactively removes Pterodactyl Panel, Wings, databases,    #
#   and associated services from Ubuntu, Debian, Rocky Linux, or AlmaLinux.   #
#                                                                             #
#   Version: 2.0                                                              #
#                                                                             #
###############################################################################

set -euo pipefail

###############################################################################
# Color Definitions
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
# Global State — set after interactive prompts
###############################################################################
REMOVE_PANEL=false
REMOVE_WINGS=false
REMOVE_DATABASE=false
OS_ID=""
OS_VERSION=""

###############################################################################
# ASCII Art Banner
###############################################################################
show_banner() {
    printf '\n'
    printf '%b' "${DARK_ORANGE}"
    cat << 'EOF'
 ███████╗██╗   ██╗███╗   ██╗██████╗ ██╗   ██╗
 ██╔════╝██║   ██║████╗  ██║██╔══██╗╚██╗ ██╔╝
 ███████╗██║   ██║██╔██╗ ██║██║  ██║ ╚████╔╝
 ╚════██║██║   ██║██║╚██╗██║██║  ██║  ╚██╔╝
 ███████║╚██████╔╝██║ ╚████║██████╔╝   ██║
 ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝    ╚═╝
EOF
    printf '%b' "${ORANGE}"
    cat << 'EOF'
        ┌─────────────────────────────┐
        │   S U N D Y . S Y S T E M S │
        │      Uninstaller v2.0       │
        └─────────────────────────────┘
EOF
    printf '%b\n' "${RESET}"
}

###############################################################################
# Helper Functions
###############################################################################

# print_brake — decorative line
print_brake() {
    local length="${1:-60}"
    local line=""
    for ((i = 0; i < length; i++)); do
        line+="─"
    done
    printf '%b%s%b\n' "${ORANGE}" "${line}" "${RESET}"
}

# output — informational message
output() {
    printf '%b[•]%b %b%s%b\n' "${ORANGE}" "${RESET}" "${WHITE}" "$1" "${RESET}"
}

# success — green success message
success() {
    printf '%b[✔]%b %b%s%b\n' "${GREEN}" "${RESET}" "${WHITE}" "$1" "${RESET}"
}

# error — red error message, exits by default
error() {
    printf '%b[✘]%b %b%s%b\n' "${RED}" "${RESET}" "${WHITE}" "$1" "${RESET}" >&2
    if [[ "${2:-exit}" == "exit" ]]; then
        exit 1
    fi
}

# warning — yellow warning message
warning() {
    printf '%b[!]%b %b%s%b\n' "${YELLOW}" "${RESET}" "${WHITE}" "$1" "${RESET}"
}

# ask_yes_no — prompt the user for y/n; returns 0 for yes, 1 for no
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local hint

    if [[ "${default}" == "y" ]]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    while true; do
        printf '%b[?]%b %b%s [%s]:%b ' "${ORANGE}" "${RESET}" "${WHITE}" "${prompt}" "${hint}" "${RESET}"
        read -r answer
        answer="${answer,,}"  # lowercase

        if [[ -z "${answer}" ]]; then
            answer="${default}"
        fi

        case "${answer}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     warning "Please answer y or n." ;;
        esac
    done
}

# validate_name — ensure a database/user name is safe (alphanumeric + underscore)
validate_name() {
    local name="$1"
    local label="${2:-name}"
    if [[ -z "${name}" ]]; then
        error "${label} cannot be empty." "noexit"
        return 1
    fi
    if [[ ! "${name}" =~ ^[a-zA-Z0-9_]+$ ]]; then
        error "${label} '${name}' contains invalid characters. Only a-z, A-Z, 0-9, and _ are allowed." "noexit"
        return 1
    fi
    if [[ "${#name}" -gt 64 ]]; then
        error "${label} '${name}' exceeds 64 characters." "noexit"
        return 1
    fi
    return 0
}

###############################################################################
# OS Detection
###############################################################################
detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect operating system. /etc/os-release not found."
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-0}"

    case "${OS_ID}" in
        ubuntu)
            output "Detected OS: Ubuntu ${OS_VERSION}"
            ;;
        debian)
            output "Detected OS: Debian ${OS_VERSION}"
            ;;
        rocky)
            output "Detected OS: Rocky Linux ${OS_VERSION}"
            ;;
        almalinux)
            output "Detected OS: AlmaLinux ${OS_VERSION}"
            ;;
        *)
            error "Unsupported operating system: ${OS_ID}. Supported: Ubuntu, Debian, Rocky Linux, AlmaLinux."
            ;;
    esac
}

###############################################################################
# Root Check
###############################################################################
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        error "This script must be run as root (or with sudo)."
    fi
}

###############################################################################
# Uninstall Functions
###############################################################################

# Remove the cron job for Pterodactyl scheduler
rm_cron() {
    output "Removing Pterodactyl cron job…"

    local tmpfile
    tmpfile="$(mktemp)"
    if crontab -l 2>/dev/null | grep -v 'pterodactyl' > "${tmpfile}"; then
        crontab "${tmpfile}"
        success "Pterodactyl cron job removed."
    else
        # If grep -v fails (no lines remain) install empty crontab
        crontab -r 2>/dev/null || true
        success "Crontab cleared (no remaining entries)."
    fi
    rm -f "${tmpfile}"
}

# Disable and remove pteroq and redis services
rm_services() {
    output "Disabling Pterodactyl queue worker (pteroq)…"

    if systemctl is-active --quiet pteroq.service 2>/dev/null; then
        systemctl stop pteroq.service
    fi
    if systemctl is-enabled --quiet pteroq.service 2>/dev/null; then
        systemctl disable pteroq.service
    fi
    rm -f /etc/systemd/system/pteroq.service
    success "pteroq service removed."

    output "Stopping Redis (if managed by panel)…"
    if systemctl is-active --quiet redis-server.service 2>/dev/null; then
        systemctl stop redis-server.service
        systemctl disable redis-server.service
        success "redis-server service stopped and disabled."
    elif systemctl is-active --quiet redis.service 2>/dev/null; then
        systemctl stop redis.service
        systemctl disable redis.service
        success "redis service stopped and disabled."
    else
        output "Redis service not found or already stopped — skipping."
    fi

    systemctl daemon-reload
}

# Remove Panel files, Composer cache, and Nginx configuration
rm_panel_files() {
    output "Removing Pterodactyl Panel files…"

    # Panel directory
    if [[ -d /var/www/pterodactyl ]]; then
        rm -rf /var/www/pterodactyl
        success "Removed /var/www/pterodactyl"
    else
        warning "/var/www/pterodactyl does not exist — skipping."
    fi

    # Composer cache for the panel user (root)
    if [[ -d /root/.composer ]]; then
        rm -rf /root/.composer
        success "Removed /root/.composer cache."
    fi

    # Nginx site config
    output "Removing Nginx configuration for Pterodactyl…"
    local nginx_removed=false

    for conf_path in \
        /etc/nginx/sites-enabled/pterodactyl.conf \
        /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/conf.d/pterodactyl.conf; do
        if [[ -e "${conf_path}" ]]; then
            rm -f "${conf_path}"
            success "Removed ${conf_path}"
            nginx_removed=true
        fi
    done

    if [[ "${nginx_removed}" == false ]]; then
        warning "No Pterodactyl Nginx configs found — skipping."
    fi

    # Re-enable the default Nginx site on Debian/Ubuntu
    if [[ "${OS_ID}" == "ubuntu" || "${OS_ID}" == "debian" ]]; then
        if [[ -f /etc/nginx/sites-available/default && ! -e /etc/nginx/sites-enabled/default ]]; then
            ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
            output "Restored default Nginx site."
        fi
    fi

    # Reload Nginx if running
    if systemctl is-active --quiet nginx.service 2>/dev/null; then
        if nginx -t 2>/dev/null; then
            systemctl reload nginx
            success "Nginx reloaded."
        else
            warning "Nginx config test failed — please review your Nginx configuration."
        fi
    fi
}

# Docker cleanup (Wings containers)
rm_docker_containers() {
    output "Cleaning up Docker resources used by Wings…"

    if ! command -v docker &>/dev/null; then
        warning "Docker is not installed — skipping container cleanup."
        return 0
    fi

    # Stop all running containers
    local running_containers
    running_containers="$(docker ps -q 2>/dev/null || true)"
    if [[ -n "${running_containers}" ]]; then
        warning "The following running containers will be stopped:"
        docker ps --format '  {{.ID}}  {{.Names}}  {{.Image}}' 2>/dev/null || true
        printf '\n'

        if ask_yes_no "Stop and remove ALL Docker containers?" "n"; then
            docker stop $(docker ps -q) 2>/dev/null || true
            docker rm $(docker ps -a -q) 2>/dev/null || true
            success "All Docker containers stopped and removed."
        else
            output "Skipping Docker container removal."
            return 0
        fi
    else
        output "No running Docker containers found."
    fi

    # System prune
    if ask_yes_no "Run docker system prune to free disk space?" "n"; then
        docker system prune -a -f --volumes 2>/dev/null || true
        success "Docker system pruned."
    fi
}

# Disable and remove Wings service and files
rm_wings_files() {
    output "Removing Wings…"

    # Stop and disable the service
    if systemctl is-active --quiet wings.service 2>/dev/null; then
        systemctl stop wings.service
    fi
    if systemctl is-enabled --quiet wings.service 2>/dev/null; then
        systemctl disable wings.service
    fi
    rm -f /etc/systemd/system/wings.service
    systemctl daemon-reload
    success "Wings service removed."

    # Remove the Wings binary
    if [[ -f /usr/local/bin/wings ]]; then
        rm -f /usr/local/bin/wings
        success "Removed /usr/local/bin/wings"
    fi

    # Remove Wings configuration
    if [[ -d /etc/pterodactyl ]]; then
        rm -rf /etc/pterodactyl
        success "Removed /etc/pterodactyl"
    fi

    # Remove Wings data (server volumes)
    if [[ -d /var/lib/pterodactyl ]]; then
        warning "Found Wings data directory /var/lib/pterodactyl"
        if ask_yes_no "Delete ALL server data in /var/lib/pterodactyl? This is IRREVERSIBLE" "n"; then
            rm -rf /var/lib/pterodactyl
            success "Removed /var/lib/pterodactyl"
        else
            output "Kept /var/lib/pterodactyl intact."
        fi
    fi

    # Remove Wings log directory
    if [[ -d /var/log/pterodactyl ]]; then
        rm -rf /var/log/pterodactyl
        success "Removed /var/log/pterodactyl"
    fi
}

# Interactive database and user removal
rm_database() {
    output "Starting interactive database removal…"
    printf '\n'

    if ! command -v mariadb &>/dev/null; then
        warning "'mariadb' client not found. Skipping database removal."
        warning "You may need to remove the database manually."
        return 0
    fi

    # ── Remove a database ──────────────────────────────────────────────────
    print_brake 50
    output "Available databases:"
    printf '\n'

    local db_list
    db_list="$(mariadb -N -e "SHOW DATABASES;" 2>/dev/null || true)"

    if [[ -z "${db_list}" ]]; then
        warning "Could not list databases — is MariaDB running?"
        return 0
    fi

    # Filter out system databases and display
    local -a user_databases=()
    while IFS= read -r db; do
        case "${db}" in
            information_schema|performance_schema|mysql|sys|"") continue ;;
            *) user_databases+=("${db}") ;;
        esac
    done <<< "${db_list}"

    if [[ ${#user_databases[@]} -eq 0 ]]; then
        output "No user databases found."
    else
        local idx=1
        for db in "${user_databases[@]}"; do
            printf '  %b%d)%b %s\n' "${ORANGE}" "${idx}" "${RESET}" "${db}"
            ((idx++))
        done
        printf '\n'

        printf '%b[?]%b %bEnter the database name to drop (or press Enter to skip):%b ' \
            "${ORANGE}" "${RESET}" "${WHITE}" "${RESET}"
        read -r chosen_db

        if [[ -n "${chosen_db}" ]]; then
            # Validate the name
            if ! validate_name "${chosen_db}" "Database name"; then
                warning "Skipping database removal due to invalid name."
            else
                # Verify the database actually exists (exact match)
                local db_exists
                db_exists="$(mariadb -N -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '${chosen_db}';" 2>/dev/null || true)"

                if [[ -z "${db_exists}" ]]; then
                    warning "Database '${chosen_db}' does not exist — skipping."
                else
                    printf '\n'
                    warning "You are about to DROP database '${chosen_db}'. ALL DATA WILL BE LOST."
                    if ask_yes_no "Are you absolutely sure?" "n"; then
                        mariadb -e "DROP DATABASE \`${chosen_db}\`;" 2>/dev/null
                        success "Database '${chosen_db}' has been dropped."
                    else
                        output "Database removal cancelled."
                    fi
                fi
            fi
        else
            output "Skipping database removal."
        fi
    fi

    printf '\n'

    # ── Remove a database user ─────────────────────────────────────────────
    print_brake 50
    output "Database users (excluding system accounts):"
    printf '\n'

    local user_list
    user_list="$(mariadb -N -e "SELECT CONCAT(User, '@', Host) FROM mysql.user WHERE User NOT IN ('root','mysql','mariadb.sys','debian-sys-maint','') ORDER BY User;" 2>/dev/null || true)"

    if [[ -z "${user_list}" ]]; then
        output "No non-system database users found."
        return 0
    fi

    local -a db_users=()
    while IFS= read -r u; do
        [[ -z "${u}" ]] && continue
        db_users+=("${u}")
    done <<< "${user_list}"

    if [[ ${#db_users[@]} -eq 0 ]]; then
        output "No non-system database users found."
        return 0
    fi

    local idx=1
    for u in "${db_users[@]}"; do
        printf '  %b%d)%b %s\n' "${ORANGE}" "${idx}" "${RESET}" "${u}"
        ((idx++))
    done
    printf '\n'

    printf '%b[?]%b %bEnter the username to drop (without @host, or press Enter to skip):%b ' \
        "${ORANGE}" "${RESET}" "${WHITE}" "${RESET}"
    read -r chosen_user

    if [[ -n "${chosen_user}" ]]; then
        if ! validate_name "${chosen_user}" "Username"; then
            warning "Skipping user removal due to invalid name."
            return 0
        fi

        # Find matching host(s)
        local user_hosts
        user_hosts="$(mariadb -N -e "SELECT Host FROM mysql.user WHERE User = '${chosen_user}';" 2>/dev/null || true)"

        if [[ -z "${user_hosts}" ]]; then
            warning "User '${chosen_user}' does not exist — skipping."
            return 0
        fi

        printf '\n'
        warning "You are about to DROP user '${chosen_user}' and revoke all privileges."
        if ask_yes_no "Are you absolutely sure?" "n"; then
            while IFS= read -r host; do
                [[ -z "${host}" ]] && continue
                mariadb -e "DROP USER \`${chosen_user}\`@\`${host}\`;" 2>/dev/null || true
                success "Dropped user '${chosen_user}'@'${host}'."
            done <<< "${user_hosts}"
            mariadb -e "FLUSH PRIVILEGES;" 2>/dev/null || true
            success "Privileges flushed."
        else
            output "User removal cancelled."
        fi
    else
        output "Skipping user removal."
    fi
}

###############################################################################
# Perform Uninstall — orchestrates based on user choices
###############################################################################
perform_uninstall() {
    print_brake 60
    printf '%b%b  Beginning uninstallation…%b\n\n' "${BOLD}" "${ORANGE}" "${RESET}"

    if [[ "${REMOVE_PANEL}" == true ]]; then
        output "── Panel Removal ──"
        rm_cron
        rm_services
        rm_panel_files
        printf '\n'

        if [[ "${REMOVE_DATABASE}" == true ]]; then
            output "── Database Removal ──"
            rm_database
            printf '\n'
        fi
    fi

    if [[ "${REMOVE_WINGS}" == true ]]; then
        output "── Wings Removal ──"
        rm_docker_containers
        rm_wings_files
        printf '\n'
    fi
}

###############################################################################
# Interactive Menu
###############################################################################
interactive_menu() {
    print_brake 60
    printf '%b%b  What would you like to uninstall?%b\n\n' "${BOLD}" "${ORANGE}" "${RESET}"

    # Ask about Panel
    if ask_yes_no "Remove Pterodactyl Panel?" "n"; then
        REMOVE_PANEL=true
    fi

    # Ask about Wings
    if ask_yes_no "Remove Pterodactyl Wings (daemon)?" "n"; then
        REMOVE_WINGS=true
    fi

    # Ask about database only if removing the panel
    if [[ "${REMOVE_PANEL}" == true ]]; then
        if ask_yes_no "Remove the Pterodactyl database and database user?" "n"; then
            REMOVE_DATABASE=true
        fi
    fi

    # Bail out if nothing was selected
    if [[ "${REMOVE_PANEL}" == false && "${REMOVE_WINGS}" == false ]]; then
        warning "Nothing selected for removal. Exiting."
        exit 0
    fi

    # Summary
    printf '\n'
    print_brake 60
    printf '%b%b  Summary of actions:%b\n\n' "${BOLD}" "${ORANGE}" "${RESET}"

    if [[ "${REMOVE_PANEL}" == true ]]; then
        printf '  %b•%b Remove Panel files, cron, services, Nginx config\n' "${ORANGE}" "${RESET}"
    fi
    if [[ "${REMOVE_DATABASE}" == true ]]; then
        printf '  %b•%b Interactively remove database and database user\n' "${ORANGE}" "${RESET}"
    fi
    if [[ "${REMOVE_WINGS}" == true ]]; then
        printf '  %b•%b Remove Wings service, binary, configs, and Docker cleanup\n' "${ORANGE}" "${RESET}"
    fi
    printf '\n'

    # Final confirmation
    warning "This operation is DESTRUCTIVE and IRREVERSIBLE."
    if ! ask_yes_no "Proceed with uninstallation?" "n"; then
        output "Uninstallation cancelled by user."
        exit 0
    fi

    printf '\n'
}

###############################################################################
# Completion Message
###############################################################################
show_complete() {
    printf '\n'
    print_brake 60
    printf '%b' "${GREEN}"
    cat << 'EOF'

   ╔═══════════════════════════════════════════════╗
   ║         Uninstallation Complete!              ║
   ╚═══════════════════════════════════════════════╝

EOF
    printf '%b' "${RESET}"

    if [[ "${REMOVE_PANEL}" == true ]]; then
        success "Panel has been removed."
    fi
    if [[ "${REMOVE_WINGS}" == true ]]; then
        success "Wings has been removed."
    fi
    if [[ "${REMOVE_DATABASE}" == true ]]; then
        success "Database removal steps completed."
    fi

    printf '\n'
    printf '  %bThank you for using %bSundy.Systems%b tools.%b\n' \
        "${WHITE}" "${ORANGE}${BOLD}" "${RESET}${WHITE}" "${RESET}"
    printf '  %bVisit %bhttps://sundy.systems%b for support.%b\n\n' \
        "${WHITE}" "${ORANGE}" "${RESET}${WHITE}" "${RESET}"
    print_brake 60
    printf '\n'
}

###############################################################################
# Main Entry Point
###############################################################################
main() {
    show_banner
    check_root
    detect_os
    printf '\n'

    interactive_menu
    perform_uninstall
    show_complete
}

main "$@"
