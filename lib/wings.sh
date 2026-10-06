#!/usr/bin/env bash
# shellcheck shell=bash
# Shared variables are consumed by panel.sh and other sourced modules.
# shellcheck disable=SC2034

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
            if validate_db_name "${WINGS_DB_USER}" && (( ${#WINGS_DB_USER} <= 32 )); then
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

        if [[ "${WINGS_DB_BIND_ADDRESS}" != "127.0.0.1" ]]; then
            ask_yes_no "Open port 3306 in the firewall?" "n" answer
            [[ "${answer}" == "y" ]] && WINGS_OPEN_DB_PORT="true" || WINGS_OPEN_DB_PORT="false"
        fi
    fi

    print_header "Optional SSL Certificate"
    echo -e "  ${ORANGE}1)${RESET} ${WHITE}Do not obtain a certificate now${RESET}"
    echo -e "  ${ORANGE}2)${RESET} ${WHITE}Obtain Let's Encrypt certificate for this node${RESET}"
    echo ""
    echo -en "${ORANGE}▸${RESET} ${WHITE}Choose an option${RESET} [${ORANGE}1${RESET}]: " >&2
    read -r answer || error_exit "Input ended unexpectedly."
    answer="${answer:-1}"
    case "${answer}" in
        2)
            WINGS_CERT_MODE="letsencrypt"
            while true; do
                required_input "Node FQDN for certificate" "" WINGS_SSL_FQDN
                if validate_fqdn "${WINGS_SSL_FQDN}" && [[ ! "$WINGS_SSL_FQDN" =~ ^[0-9.]+$ ]]; then
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
    update_repos
    install_packages ca-certificates tar
    command_exists curl || install_packages curl
    case "$OS_FAMILY" in
        debian) install_packages docker.io ;;
        rhel)
            install_packages dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            install_packages docker-ce docker-ce-cli containerd.io ;;
        arch) install_packages docker ;;
    esac
    if [[ "$WINGS_INSTALL_MARIADB" == true ]]; then
        case "$OS_FAMILY" in
            arch) install_packages mariadb ;;
            *) install_packages mariadb-server ;;
        esac
        initialize_mariadb
    fi
    if [[ "$WINGS_CERT_MODE" == letsencrypt ]]; then
        if [[ "$OS_FAMILY" == rhel ]]; then
            if [[ "$OS_ID" == rhel ]]; then
                install_packages "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_MAJOR}.noarch.rpm"
            else
                install_packages epel-release
            fi
        fi
        install_packages certbot
    fi
    enable_service_now docker
    docker info >/dev/null
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

    install -d -m 750 /etc/pterodactyl
    local binary="${INSTALL_TMP_DIR}/wings"
    curl -fSL --retry 3 -o "$binary" "${WINGS_DL_BASE}/wings_linux_${arch}"
    chmod 755 "$binary"
    "$binary" version
    install -m 755 "$binary" /usr/local/bin/wings
    success "Wings binary installed."
}

install_wings_service() {
    print_header "Systemd"
    output "Creating Wings service..."

    cat > /etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
ConditionPathExists=/etc/pterodactyl/config.yml
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service
StartLimitIntervalSec=180
StartLimitBurst=30

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
RuntimeDirectory=wings
PIDFile=/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5s
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 /etc/systemd/system/wings.service
    systemctl daemon-reload
    systemctl enable wings
    success "Wings service enabled; it will start after node configuration is provided."
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
        elif [[ -f /etc/my.cnf.d/server.cnf ]]; then
            mariadb_conf="/etc/my.cnf.d/server.cnf"
        elif [[ -f /etc/my.cnf ]]; then
            mariadb_conf="/etc/my.cnf"
        fi

        if [[ -n "${mariadb_conf}" ]]; then
            if grep -Eq '^[[:space:]]*bind-address[[:space:]]*=' "${mariadb_conf}" 2>/dev/null; then
                sed -i "s/^[[:space:]]*bind-address[[:space:]]*=.*/bind-address = ${WINGS_DB_BIND_ADDRESS}/" "${mariadb_conf}"
            elif grep -q '^\[mysqld\]' "${mariadb_conf}" 2>/dev/null; then
                sed -i "/^\[mysqld\]/a bind-address = ${WINGS_DB_BIND_ADDRESS}" "${mariadb_conf}"
            else
                printf '\n[mysqld]\nbind-address = %s\n' "${WINGS_DB_BIND_ADDRESS}" >> "${mariadb_conf}"
            fi
            restart_service mariadb
            wait_for_mariadb
            success "MariaDB bind address updated."
        else
            error_exit "Could not detect MariaDB config file."
        fi
    fi
}

obtain_wings_certificate() {
    [[ "$WINGS_CERT_MODE" == letsencrypt ]] || return 0
    print_header "Let's Encrypt"
    [[ ! "$WINGS_SSL_FQDN" =~ ^[0-9.]+$ ]] || error_exit "Use a domain name for Let's Encrypt."
    # Hooks are stored in this certificate's renewal configuration by Certbot.
    mkdir -p /etc/letsencrypt
    cat > /etc/letsencrypt/pterodactyl-wings-stop <<'STOP'
#!/bin/sh
set -eu
install -d -m 700 /run/pterodactyl-acme
for service in nginx apache2 httpd; do
    if systemctl is-active --quiet "$service"; then
        touch "/run/pterodactyl-acme/$service"
        systemctl stop "$service"
    fi
done
STOP
    cat > /etc/letsencrypt/pterodactyl-wings-start <<'START'
#!/bin/sh
set -eu
for service in nginx apache2 httpd; do
    if [ -f "/run/pterodactyl-acme/$service" ]; then
        systemctl start "$service"
        rm -f "/run/pterodactyl-acme/$service"
    fi
done
START
    chmod 750 /etc/letsencrypt/pterodactyl-wings-{stop,start}
    WINGS_ACME_STARTED=true
    local certbot_ok=false
    if certbot certonly --standalone --non-interactive --agree-tos \
        --preferred-challenges http -d "$WINGS_SSL_FQDN" --email "$WINGS_SSL_EMAIL" \
        --pre-hook /etc/letsencrypt/pterodactyl-wings-stop \
        --post-hook /etc/letsencrypt/pterodactyl-wings-start; then
        certbot_ok=true
    fi
    /etc/letsencrypt/pterodactyl-wings-start
    WINGS_ACME_STARTED=false
    [[ "$certbot_ok" == true ]] || error_exit "Failed to obtain a certificate for $WINGS_SSL_FQDN."
    install_certificate_renewal wings
    success "Certificate created for $WINGS_SSL_FQDN."
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
    case "$(uname -m)" in
        x86_64|aarch64) ;;
        *) error_exit "Wings requires x86_64 or aarch64." ;;
    esac
    [[ ! -e /etc/pterodactyl/config.yml && ! -e /usr/local/bin/wings ]] || error_exit "Existing Wings installation detected; use the upstream upgrade procedure."
    gather_wings_input
    install_wings_dependencies
    download_wings_binary
    install_wings_service
    configure_wings_mariadb
    configure_wings_firewall
    obtain_wings_certificate
    show_wings_completion
}
