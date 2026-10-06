#!/usr/bin/env bash
# shellcheck shell=bash
# Shared variables are consumed by panel.sh and other sourced modules.
# shellcheck disable=SC2034

panel_nginx_conf_path() {
    printf '%s/pterodactyl.conf\n' "$NGINX_AVAILABLE_DIR"
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

prompt_panel_ssl_mode() {
    local answer=""

    while true; do
        echo -e "${ORANGE}▸${RESET} ${WHITE}SSL mode for the panel${RESET}"
        echo -e "    ${ORANGE}1)${RESET} HTTP only"
        echo -e "    ${ORANGE}2)${RESET} Let's Encrypt on this server"
        echo -e "    ${ORANGE}3)${RESET} Reverse proxy / Cloudflare (origin stays on HTTP)"
        echo -e "    ${ORANGE}4)${RESET} Existing certificate on this server"
        echo -en "${ORANGE}▸${RESET} ${WHITE}Choose SSL mode${RESET} [${ORANGE}2${RESET}]: " >&2
        read -r answer || error_exit "Input ended unexpectedly."
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
                while true; do
                    required_input "Trusted proxy IPv4 addresses/CIDRs (comma separated; * for all)" "" PANEL_TRUSTED_PROXIES
                    validate_trusted_proxies "$PANEL_TRUSTED_PROXIES" && break
                    warning "Enter valid IPv4 addresses/CIDRs, or * to explicitly trust all proxies."
                done
                warning "If Cloudflare is set to Full/Strict, use mode 2 or 4 instead. Mode 3 keeps the origin on HTTP."
                return 0
                ;;
            4)
                PANEL_SSL_MODE="existing_cert"
                while true; do
                    required_input "Path to certificate file" "/etc/letsencrypt/live/${PANEL_FQDN}/fullchain.pem" PANEL_CERT_PATH
                    validate_certificate_path "$PANEL_CERT_PATH" && break
                    warning "Certificate file not found: ${PANEL_CERT_PATH}"
                done
                while true; do
                    required_input "Path to private key" "/etc/letsencrypt/live/${PANEL_FQDN}/privkey.pem" PANEL_KEY_PATH
                    validate_certificate_path "$PANEL_KEY_PATH" && break
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
    while true; do
        hidden_input "Admin password" PANEL_ADMIN_PASS 8
        validate_admin_password "$PANEL_ADMIN_PASS" && break
        warning "Use at least 8 characters with upper/lowercase letters and a number."
    done

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
        if validate_db_name "${PANEL_DB_USER}" && (( ${#PANEL_DB_USER} <= 32 )); then
            break
        fi
        warning "Database username can contain only letters, numbers and underscore."
    done

    auto_pass="$(gen_password 32)"
    output "Generated a database password; it will be stored in the protected panel .env file."
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

    warning "Outgoing mail will be logged locally until SMTP is configured in panel Admin > Settings > Mail."
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

install_composer() {
    print_header "Composer"
    local setup_file="${INSTALL_TMP_DIR}/composer-setup.php" expected_sig actual_sig
    expected_sig="$(curl -fsSL https://composer.github.io/installer.sig)"
    curl -fsSL https://getcomposer.org/installer -o "$setup_file"
    # This is PHP code, not shell interpolation.
    # shellcheck disable=SC2016
    actual_sig="$("$PHP_BIN" -r 'echo hash_file("sha384", $argv[1]);' "$setup_file")"
    [[ "$expected_sig" == "$actual_sig" ]] || error_exit "Composer installer signature check failed."
    "$PHP_BIN" "$setup_file" --2 --install-dir=/usr/local/bin --filename=composer
    chmod 755 /usr/local/bin/composer
    success "Composer 2 installed."
}

download_panel() {
    print_header "Downloading Panel"
    refuse_existing_directory "$PANEL_DIR"
    local archive="${INSTALL_TMP_DIR}/panel.tar.gz"
    curl -fSL --retry 3 "$PANEL_DL_URL" -o "$archive"
    tar -tzf "$archive" >/dev/null
    [[ -d /var/www ]] || install -d -m 755 /var/www
    mkdir -p "$PANEL_DIR"
    tar -xzf "$archive" -C "$PANEL_DIR"
    [[ -f "$PANEL_DIR/artisan" && -f "$PANEL_DIR/composer.lock" ]] || error_exit "Invalid panel release archive."
    success "Panel downloaded to $PANEL_DIR."
}

install_panel_composer_dependencies() {
    print_header "Composer Dependencies"
    output "Installing PHP dependencies..."

    if [[ ! -f "${PANEL_DIR}/.env" ]]; then
        cp "${PANEL_DIR}/.env.example" "${PANEL_DIR}/.env"
    fi

    COMPOSER_ALLOW_SUPERUSER=1 "$PHP_BIN" /usr/local/bin/composer install \
        --no-dev \
        --optimize-autoloader \
        --working-dir="${PANEL_DIR}" \
        --no-interaction

    "$PHP_BIN" /usr/local/bin/composer check-platform-reqs --no-dev --working-dir="$PANEL_DIR"
    success "Composer dependencies installed."
}

configure_panel_app_environment() {
    local app_url
    app_url="$(panel_app_url)"

    print_header "Configuring Panel"
    output "Generating application key..."
    run_artisan key:generate --force --no-interaction

    output "Writing environment configuration..."
    run_artisan p:environment:setup \
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
        --no-interaction

    output "Configuring database connection..."
    set_env_value "$PANEL_DIR/.env" PTERODACTYL_TELEMETRY_ENABLED "$PANEL_ENABLE_TELEMETRY"
    run_artisan p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database="${PANEL_DB_NAME}" \
        --username="${PANEL_DB_USER}" \
        --password="${PANEL_DB_PASS}" \
        --no-interaction

    # Preserve literal passwords containing $, quotes or backslashes. Upstream's
    # regex replacement can interpret them as replacement syntax.
    set_env_literal "$PANEL_DIR/.env" DB_PASSWORD "$PANEL_DB_PASS"
    # SMTP needs real server credentials. Until configured, log queued messages locally.
    set_env_value "$PANEL_DIR/.env" MAIL_MAILER log
    set_env_value "$PANEL_DIR/.env" MAIL_FROM_ADDRESS "$PANEL_LE_EMAIL"
    output "Running migrations..."
    run_artisan migrate --seed --force --no-interaction

    output "Creating admin user..."
    run_artisan p:user:make \
        --email="${PANEL_ADMIN_EMAIL}" \
        --username="${PANEL_ADMIN_USER}" \
        --name-first="${PANEL_ADMIN_FIRST}" \
        --name-last="${PANEL_ADMIN_LAST}" \
        --password="${PANEL_ADMIN_PASS}" \
        --admin=1 \
        --no-interaction

    if [[ "${PANEL_SSL_MODE}" == "proxy_http" ]]; then
        set_env_value "${PANEL_DIR}/.env" "TRUSTED_PROXIES" "${PANEL_TRUSTED_PROXIES}"
    fi

    run_artisan config:clear
    success "Panel configured."
}

set_panel_permissions() {
    print_header "Permissions"
    output "Setting ownership and permissions..."

    chown -R "${WEBSERVER_USER}:${WEBSERVER_USER}" "${PANEL_DIR}"
    find "${PANEL_DIR}" -type d -exec chmod 755 {} +
    find "${PANEL_DIR}" -type f -exec chmod 644 {} +
    chmod -R 770 "${PANEL_DIR}/storage" "${PANEL_DIR}/bootstrap/cache"
    chmod 600 "${PANEL_DIR}/.env"
    configure_selinux

    success "Permissions updated."
}

install_panel_cron() {
    print_header "Cron"
    output "Installing scheduler cron..."

    local cron_line="* * * * * ${PHP_BIN} ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1"
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
After=network.target ${REDIS_SERVICE}.service mariadb.service
StartLimitIntervalSec=180
StartLimitBurst=30

[Service]
User=${WEBSERVER_USER}
Group=${WEBSERVER_USER}
WorkingDirectory=${PANEL_DIR}
ExecStart=${PHP_BIN} ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 /etc/systemd/system/pteroq.service
    systemctl daemon-reload
    enable_service_now pteroq
    success "pteroq service installed."
}

panel_fastcgi_pass_line() {
    printf 'fastcgi_pass %s;\n' "$PANEL_PHP_ENDPOINT"
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
    mkdir -p "$NGINX_AVAILABLE_DIR"

    case "${PANEL_SSL_MODE}" in
        existing_cert)
            write_panel_nginx_ssl_config "${conf_path}" "${PANEL_CERT_PATH}" "${PANEL_KEY_PATH}"
            ;;
        http|letsencrypt|proxy_http)
            write_panel_nginx_http_config "${conf_path}"
            ;;
    esac

    mkdir -p "$NGINX_AVAILABLE_DIR"
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
    set_env_value "${PANEL_DIR}/.env" SESSION_SECURE_COOKIE true
    run_artisan config:clear
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
            error_exit "Certificate issued but nginx HTTPS configuration failed."
        fi

        install_certificate_renewal panel
    else
        warning "Let's Encrypt request failed. The panel is left on HTTP."
        PANEL_SSL_MODE="http"
        PANEL_HAS_LOCAL_SSL="false"
        set_env_value "${PANEL_DIR}/.env" "APP_URL" "http://${PANEL_FQDN}"
        run_artisan config:clear
        error_exit "Certificate request failed. Check DNS, inbound port 80 and certbot output, then retry certificate setup."
    fi
}

panel_health_check() {
    print_header "Post-Install Check"
    local service
    for service in nginx "$PANEL_PHP_SERVICE" mariadb "$REDIS_SERVICE" "$CRON_SERVICE" pteroq; do
        systemctl is-active --quiet "$service" || error_exit "$service is not running."
    done
    nginx -t
    local url="http://${PANEL_FQDN}/auth/login" resolve="${PANEL_FQDN}:80:127.0.0.1"
    if [[ "$(panel_app_scheme)" == https && "$PANEL_SSL_MODE" != proxy_http ]]; then
        url="https://${PANEL_FQDN}/auth/login"
        resolve="${PANEL_FQDN}:443:127.0.0.1"
    fi
    local attempt
    # nginx reload is asynchronous: wait for the app route rather than accepting
    # a successful response from the distribution's default landing page.
    for attempt in {1..10}; do
        if curl --fail --silent --show-error --max-time 10 \
            --noproxy '*' --resolve "$resolve" "$url" -o /dev/null; then
            success "Services and local panel login HTTP response verified."
            return 0
        fi
        sleep 1
    done
    error_exit "The panel login route did not become healthy."
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
    warning "Email delivery requires SMTP configuration in Admin > Settings > Mail; messages currently use the local log."
}

perform_panel_install() {
    refuse_existing_directory "$PANEL_DIR"
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
    configure_panel_firewall
    obtain_panel_letsencrypt
    run_artisan queue:restart
    panel_health_check
    show_panel_completion
}
