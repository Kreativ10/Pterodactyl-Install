#!/usr/bin/env bash
# shellcheck shell=bash
# Shared variables are consumed by panel.sh and other sourced modules.
# shellcheck disable=SC2034

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
    local existing remaining
    existing="$(crontab -u "$WEBSERVER_USER" -l 2>/dev/null)" || return 0
    remaining="$(awk -v command="$PANEL_DIR/artisan schedule:run" 'index($0, command) == 0' <<< "$existing")"
    printf '%s
' "$remaining" | crontab -u "$WEBSERVER_USER" -
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

remove_database_interactive() {
    print_header "Database Removal"

    if ! command_exists mariadb && ! command_exists mysql; then
        warning "mariadb client not found. Skipping database removal."
        return 0
    fi

    detect_mariadb_runtime
    local db_name=""
    local db_user=""
    optional_input "Database name to drop (leave empty to skip)" "" db_name
    if [[ -n "${db_name}" ]]; then
        if validate_db_name "${db_name}" && [[ "$db_name" != mysql && "$db_name" != sys && "$db_name" != information_schema && "$db_name" != performance_schema ]]; then
            "$DATABASE_BIN" -u root -e "DROP DATABASE IF EXISTS \`${db_name}\`;"
            success "Database ${db_name} removed."
        else
            warning "Skipping database drop because the name contains invalid characters."
        fi
    fi

    optional_input "Database user to drop (leave empty to skip)" "" db_user
    if [[ -n "${db_user}" ]]; then
        if validate_db_name "${db_user}" && [[ "$db_user" != root && "$db_user" != mysql && "$db_user" != mariadb.sys ]]; then
            while IFS= read -r host; do
                [[ -z "${host}" ]] && continue
                "$DATABASE_BIN" -u root -e "DROP USER IF EXISTS '${db_user}'@'$(escape_sql_string "$host")';"
            done <<< "$("$DATABASE_BIN" -N -u root -e "SELECT Host FROM mysql.user WHERE User='${db_user}';")"
            "$DATABASE_BIN" -u root -e "FLUSH PRIVILEGES;"
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
