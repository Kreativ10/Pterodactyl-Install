#!/usr/bin/env bash
# shellcheck shell=bash
# Shared variables are consumed by panel.sh and other sourced modules.
# shellcheck disable=SC2034

generate_blowfish_secret() {
    PMA_BLOWFISH_SECRET="$(gen_password 32)"
}

detect_existing_panel_url() {
    if [[ -f "${PANEL_DIR}/.env" ]]; then
        awk -F= '$1 == "APP_URL" {sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print; exit}' "${PANEL_DIR}/.env"
    fi
}

gather_phpmyadmin_input() {
    local answer=""
    local existing_url="" existing_host=""

    print_header "phpMyAdmin Configuration"

    while true; do
        required_input "phpMyAdmin version" "$PMA_DEFAULT_VERSION" PMA_VERSION
        [[ "$PMA_VERSION" =~ ^5\.[0-9]+\.[0-9]+$ ]] && break
        warning "Enter a stable 5.x release version, for example 5.2.3."
    done
    while true; do
        required_input "Web path / alias" "$PMA_WEB_PATH" PMA_WEB_PATH
        validate_web_path "$PMA_WEB_PATH" && break
        warning "Use a single path segment, such as /phpmyadmin (letters, digits, _ or -)."
    done

    PMA_SERVER_FQDN="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo localhost)"
    existing_url="$(detect_existing_panel_url)"
    if [[ "$existing_url" == http://* || "$existing_url" == https://* ]]; then
        existing_host="${existing_url#*://}"
        existing_host="${existing_host%%/*}"
        if validate_fqdn "$existing_host"; then
            PMA_SERVER_FQDN="$existing_host"
        fi
    fi
    while true; do
        required_input "Server domain or IP" "$PMA_SERVER_FQDN" PMA_SERVER_FQDN
        validate_fqdn "$PMA_SERVER_FQDN" && break
        warning "Enter a valid domain or IPv4 address."
    done

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
    install_web_dependencies
    success "phpMyAdmin dependencies installed."
}

download_phpmyadmin() {
    print_header "Downloading phpMyAdmin"
    refuse_existing_directory "$PMA_INSTALL_DIR"
    local archive="${INSTALL_TMP_DIR}/phpmyadmin.tar.gz"
    local url="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz"
    curl -fSL --retry 3 -o "$archive" "$url"
    tar -tzf "$archive" >/dev/null
    mkdir -p "$PMA_INSTALL_DIR"
    tar -xzf "$archive" --strip-components=1 -C "$PMA_INSTALL_DIR"
    [[ -f "$PMA_INSTALL_DIR/index.php" ]] || error_exit "Invalid phpMyAdmin archive."
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
\$cfg['Servers'][\$i]['host'] = '127.0.0.1';
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
    find "${PMA_INSTALL_DIR}" -type d -exec chmod 755 {} +
    find "${PMA_INSTALL_DIR}" -type f -exec chmod 644 {} +
    chmod 660 "${PMA_CONFIG_FILE}"
    chmod 750 "${PMA_TMP_DIR}"

    if [[ "$OS_FAMILY" == rhel ]] && command_exists getenforce && [[ "$(getenforce)" != Disabled ]]; then
        setsebool -P httpd_can_network_connect_db on
        semanage fcontext -a -t httpd_sys_content_t "${PMA_INSTALL_DIR}(/.*)?" || \
            semanage fcontext -m -t httpd_sys_content_t "${PMA_INSTALL_DIR}(/.*)?"
        semanage fcontext -a -t httpd_sys_rw_content_t "${PMA_TMP_DIR}(/.*)?" || \
            semanage fcontext -m -t httpd_sys_rw_content_t "${PMA_TMP_DIR}(/.*)?"
        restorecon -RF "$PMA_INSTALL_DIR" /run/pterodactyl-php
    fi
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

    location ~* ^${PMA_WEB_PATH}/(doc|sql|setup|libraries|templates|vendor)/ {
        deny all;
    }

    location ~ ^${PMA_WEB_PATH}/(.+\.php)$ {
        set \$pma_script ${PMA_INSTALL_DIR}/\$1;
        if (!-f \$pma_script) { return 404; }
        ${fastcgi_line}
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$pma_script;
        fastcgi_param HTTP_PROXY "";
        fastcgi_read_timeout 600;
    }

}
EOF

    success "Snippet created at ${PMA_SNIPPET_FILE}."
}

include_phpmyadmin_in_panel_nginx() {
    local conf_path backup="${INSTALL_TMP_DIR}/nginx-before-phpmyadmin.conf"
    conf_path="$(panel_nginx_conf_path)"
    if [[ -f "$conf_path" ]]; then
        if grep -Fq "include ${PMA_SNIPPET_FILE};" "$conf_path"; then
            nginx -t
            reload_service nginx
            return 0
        fi
        cp -p "$conf_path" "$backup"
        local tmp_file="${INSTALL_TMP_DIR}/nginx-phpmyadmin.conf"
        awk -v root="${PANEL_DIR}/public;" -v snippet="    include ${PMA_SNIPPET_FILE};" '
            {print}
            $1 == "root" && $2 == root {print snippet; inserted=1}
            END {if (!inserted) exit 1}
        ' "$conf_path" > "$tmp_file" || error_exit "Cannot locate panel root directive in $conf_path."
        cat "$tmp_file" > "$conf_path"
        if ! nginx -t; then
            cp -p "$backup" "$conf_path"
            error_exit "Invalid phpMyAdmin nginx configuration; original config restored."
        fi
    else
        conf_path="${NGINX_AVAILABLE_DIR}/phpmyadmin.conf"
        [[ ! -e "$conf_path" ]] || error_exit "Existing $conf_path detected."
        cat > "$conf_path" <<NGINX
server {
    listen 80;
    server_name ${PMA_SERVER_FQDN};
    include ${PMA_SNIPPET_FILE};
}
NGINX
        if [[ -n "$NGINX_ENABLED_DIR" ]]; then
            ln -s "$conf_path" "${NGINX_ENABLED_DIR}/phpmyadmin.conf"
        fi
        if ! nginx -t; then
            rm -f "$conf_path"
            [[ -z "$NGINX_ENABLED_DIR" ]] || rm -f "${NGINX_ENABLED_DIR}/phpmyadmin.conf"
            error_exit "Invalid phpMyAdmin nginx configuration; new virtual host removed."
        fi
    fi
    reload_service nginx
    success "phpMyAdmin nginx configuration applied."
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
    refuse_existing_directory "$PMA_INSTALL_DIR"
    gather_phpmyadmin_input
    install_phpmyadmin_dependencies
    download_phpmyadmin
    configure_phpmyadmin_files
    write_phpmyadmin_snippet
    include_phpmyadmin_in_panel_nginx
    phpmyadmin_health_check
    show_phpmyadmin_completion
}

phpmyadmin_health_check() {
    local port=80 scheme=http attempt
    if [[ -f "$(panel_nginx_conf_path)" ]] && grep -Eq '^[[:space:]]*listen 443' "$(panel_nginx_conf_path)"; then
        port=443
        scheme=https
    fi
    local response="${INSTALL_TMP_DIR}/phpmyadmin.html"
    for attempt in {1..10}; do
        if curl --fail --silent --show-error --max-time 10 --noproxy '*' \
            --resolve "${PMA_SERVER_FQDN}:${port}:127.0.0.1" \
            "${scheme}://${PMA_SERVER_FQDN}${PMA_WEB_PATH}/" -o "$response" && \
            grep -qi phpmyadmin "$response"; then
            success "phpMyAdmin HTTP response verified."
            return 0
        fi
        sleep 1
    done
    error_exit "phpMyAdmin did not become healthy; check nginx, FPM and the configured domain."
}

remove_phpmyadmin_files() {
    print_header "Removing phpMyAdmin"

    rm -rf "${PMA_INSTALL_DIR}"
    rm -f "${PMA_SNIPPET_FILE}"
    rm -f "${NGINX_AVAILABLE_DIR}/phpmyadmin.conf"
    if [[ -n "$NGINX_ENABLED_DIR" ]]; then
        rm -f "${NGINX_ENABLED_DIR}/phpmyadmin.conf"
    fi

    if [[ -f "$(panel_nginx_conf_path)" ]]; then
        sed -i "\|include ${PMA_SNIPPET_FILE};|d" "$(panel_nginx_conf_path)"
    fi

    if nginx -t >/dev/null 2>&1; then
        reload_service nginx || true
    fi

    success "phpMyAdmin removed."
}
