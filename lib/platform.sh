#!/usr/bin/env bash
# shellcheck shell=bash
# Shared variables are consumed by panel.sh and other sourced modules.
# shellcheck disable=SC2034

# An explicit matrix prevents accidentally treating an incompatible derivative as supported.
detect_os() {
    local release_file="${1:-/etc/os-release}"
    [[ -r "$release_file" ]] || error_exit "Cannot read $release_file."
    local ID='' VERSION_ID='' VERSION_CODENAME=''
    # shellcheck source=/dev/null
    source "$release_file"
    OS_ID="$ID"
    OS_VERSION="${VERSION_ID:-rolling}"
    OS_MAJOR="${OS_VERSION%%.*}"
    OS_CODENAME="$VERSION_CODENAME"
    PHP_BIN=/usr/bin/php8.3
    PHP_FPM_BIN=/usr/sbin/php-fpm8.3
    PANEL_PHP_SERVICE=php8.3-fpm
    PHP_POOL_DIR=/etc/php/8.3/fpm/pool.d
    CRON_SERVICE=cron
    REDIS_SERVICE=redis-server
    WEBSERVER_USER=www-data
    NGINX_AVAILABLE_DIR=/etc/nginx/sites-available
    NGINX_ENABLED_DIR=/etc/nginx/sites-enabled
    case "$OS_ID:$OS_MAJOR" in
        ubuntu:22|ubuntu:24)
            [[ "$OS_VERSION" == 22.04 || "$OS_VERSION" == 24.04 ]] || error_exit "Unsupported Ubuntu version: $OS_VERSION"
            OS_FAMILY=debian ;;
        debian:11|debian:12|debian:13) OS_FAMILY=debian ;;
        almalinux:8|almalinux:9|rocky:8|rocky:9|rhel:8|rhel:9|centos:9)
            OS_FAMILY=rhel
            WEBSERVER_USER=nginx
            PHP_BIN=/usr/bin/php
            PHP_FPM_BIN=/usr/sbin/php-fpm
            PHP_POOL_DIR=/etc/php-fpm.d
            PANEL_PHP_SERVICE=php-fpm
            REDIS_SERVICE=redis
            CRON_SERVICE=crond
            NGINX_AVAILABLE_DIR=/etc/nginx/conf.d
            NGINX_ENABLED_DIR='' ;;
        arch:*)
            OS_FAMILY=arch
            WEBSERVER_USER=http
            PHP_BIN=/usr/bin/php-legacy
            PHP_FPM_BIN=/usr/bin/php-fpm-legacy
            PHP_POOL_DIR=/etc/php-legacy/php-fpm.d
            PANEL_PHP_SERVICE=php-fpm-legacy
            REDIS_SERVICE=valkey
            CRON_SERVICE=cronie
            NGINX_AVAILABLE_DIR=/etc/nginx/conf.d
            NGINX_ENABLED_DIR='' ;;
        *) error_exit "Unsupported OS: $OS_ID $OS_VERSION. See README.md for the supported matrix." ;;
    esac
    detect_panel_php_runtime
    success "Detected $OS_ID $OS_VERSION"
}

update_repos() {
    output "Updating package repositories..."
    case "$OS_FAMILY" in
        debian) apt-get update ;;
        rhel) dnf makecache -y ;;
        # Arch does not support partial upgrades: always sync AND upgrade together.
        arch) pacman -Syu --noconfirm ;;
    esac
}

install_packages() {
    case "$OS_FAMILY" in
        debian) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        rhel) dnf install -y "$@" ;;
        arch) pacman -S --needed --noconfirm "$@" ;;
    esac
}

enable_service_now() { systemctl enable --now "$1"; }
restart_service() { systemctl restart "$1"; }
reload_service() { systemctl reload "$1"; }

detect_panel_php_runtime() {
    # This is also the endpoint written to our dedicated FPM pool; no startup race.
    PANEL_PHP_ENDPOINT=unix:/run/pterodactyl-php/panel.sock
}

add_php_repo_debian() {
    [[ "$OS_ID:$OS_VERSION" != ubuntu:24.04 ]] || return 0
    if [[ "$OS_ID" == ubuntu ]]; then
        install_packages software-properties-common
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    else
        local keyring
        keyring="$(mktemp "${INSTALL_TMP_DIR}/sury.XXXXXX.deb")"
        curl -fsSL https://packages.sury.org/debsuryorg-archive-keyring.deb -o "$keyring"
        dpkg -i "$keyring"
        [[ "$OS_CODENAME" =~ ^[a-z]+$ ]] || error_exit "Missing Debian VERSION_CODENAME."
        printf 'deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ %s main\n' \
            "$OS_CODENAME" > /etc/apt/sources.list.d/sury-php.list
    fi
}

prepare_rhel_repos() {
    install_packages dnf-plugins-core
    if [[ "$OS_ID" == rhel ]]; then
        command_exists subscription-manager || error_exit "RHEL requires an active subscription and subscription-manager."
        subscription-manager repos --enable "codeready-builder-for-rhel-${OS_MAJOR}-$(uname -m)-rpms"
        install_packages "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_MAJOR}.noarch.rpm"
    else
        install_packages epel-release
        if [[ "$OS_MAJOR" == 8 ]]; then
            dnf config-manager --set-enabled powertools
        else
            dnf config-manager --set-enabled crb
        fi
    fi
    install_packages "https://rpms.remirepo.net/enterprise/remi-release-${OS_MAJOR}.rpm"
    dnf module reset -y php
    dnf module enable -y php:remi-8.3
}

configure_arch_php() {
    local extension
    mkdir -p /etc/php-legacy/conf.d
    # Enable shared extensions; mbstring, dom, openssl and posix are compiled in.
    for extension in bcmath iconv sodium curl gd pdo_mysql mysqli zip intl; do
        # Avoid duplicate loading when the administrator enabled an extension already.
        if ! "$PHP_BIN" -r "exit(extension_loaded('$extension') ? 0 : 1);"; then
            printf 'extension=%s\n' "$extension" > "/etc/php-legacy/conf.d/pterodactyl-${extension}.ini"
            chmod 644 "/etc/php-legacy/conf.d/pterodactyl-${extension}.ini"
        fi
    done
    if ! "$PHP_BIN" -r "exit(extension_loaded('Zend OPcache') ? 0 : 1);"; then
        printf 'zend_extension=opcache\n' > /etc/php-legacy/conf.d/pterodactyl-opcache.ini
        chmod 644 /etc/php-legacy/conf.d/pterodactyl-opcache.ini
    fi
}

validate_php_runtime() {
    # PHP variables must reach PHP unchanged.
    # shellcheck disable=SC2016
    local validation_code='
        if (PHP_MAJOR_VERSION !== 8 || !in_array(PHP_MINOR_VERSION, [2, 3], true)) {
            fwrite(STDERR, "Pterodactyl requires a supported PHP 8.2/8.3 runtime; installed: " . PHP_VERSION . "\n"); exit(1);
        }
        $required = ["openssl", "gd", "pdo_mysql", "mbstring", "tokenizer", "bcmath", "dom", "curl", "zip", "posix", "sodium", "iconv"];
        $missing = array_filter($required, fn($extension) => !extension_loaded($extension));
        if ($missing) { fwrite(STDERR, "Missing PHP extensions: " . implode(", ", $missing) . "\n"); exit(1); }
    '
    "$PHP_BIN" -r "$validation_code"
    # Verify the same extensions are readable by the queue and cron user.
    runuser -u "$WEBSERVER_USER" -- "$PHP_BIN" -r "$validation_code"
}

configure_php_fpm() {
    install -d -m 755 /var/lib/pterodactyl-php
    install -d -m 700 -o "$WEBSERVER_USER" -g "$WEBSERVER_USER" /var/lib/pterodactyl-php/sessions
    mkdir -p "$PHP_POOL_DIR" "/etc/systemd/system/${PANEL_PHP_SERVICE}.service.d"
    cat > "$PHP_POOL_DIR/pterodactyl.conf" <<POOL
[pterodactyl]
user = ${WEBSERVER_USER}
group = ${WEBSERVER_USER}
listen = /run/pterodactyl-php/panel.sock
listen.owner = ${WEBSERVER_USER}
listen.group = ${WEBSERVER_USER}
listen.mode = 0660
pm = ondemand
pm.max_children = 10
pm.process_idle_timeout = 10s
pm.max_requests = 500
php_admin_value[session.save_path] = /var/lib/pterodactyl-php/sessions
POOL
    cat > "/etc/systemd/system/${PANEL_PHP_SERVICE}.service.d/pterodactyl.conf" <<'UNIT'
[Service]
RuntimeDirectory=pterodactyl-php
RuntimeDirectoryMode=0755
UNIT
    chmod 644 "/etc/systemd/system/${PANEL_PHP_SERVICE}.service.d/pterodactyl.conf"
    "$PHP_FPM_BIN" -t
    if [[ "$OS_FAMILY" == rhel ]] && command_exists getenforce && [[ "$(getenforce)" != Disabled ]]; then
        semanage fcontext -a -t httpd_var_run_t '/run/pterodactyl-php(/.*)?' || \
            semanage fcontext -m -t httpd_var_run_t '/run/pterodactyl-php(/.*)?'
        install -d -m 755 /run/pterodactyl-php
        restorecon -RF /run/pterodactyl-php
        semanage fcontext -a -t httpd_sys_rw_content_t '/var/lib/pterodactyl-php(/.*)?' || \
            semanage fcontext -m -t httpd_sys_rw_content_t '/var/lib/pterodactyl-php(/.*)?'
        restorecon -RF /var/lib/pterodactyl-php
    fi
    systemctl daemon-reload
    enable_service_now "$PANEL_PHP_SERVICE"
    restart_service "$PANEL_PHP_SERVICE"
}

initialize_mariadb() {
    detect_mariadb_runtime
    if [[ "$OS_FAMILY" == arch && ! -d /var/lib/mysql/mysql ]]; then
        mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    fi
    enable_service_now mariadb
    wait_for_mariadb
}

detect_mariadb_runtime() {
    if command_exists mariadb; then DATABASE_BIN=mariadb; else DATABASE_BIN=mysql; fi
    if command_exists mariadb-admin; then DATABASE_ADMIN_BIN=mariadb-admin; else DATABASE_ADMIN_BIN=mysqladmin; fi
    if ! command_exists "$DATABASE_BIN" || ! command_exists "$DATABASE_ADMIN_BIN"; then
        error_exit "MariaDB client/admin binaries are missing."
    fi
}

configure_nginx_layout() {
    mkdir -p "$NGINX_AVAILABLE_DIR" /var/log/nginx
    if [[ "$OS_FAMILY" == arch ]]; then
        # Arch's stock nginx.conf does not include conf.d (unlike Debian and EL).
        if ! grep -Eq '^[[:space:]]*include[[:space:]]+/etc/nginx/conf\.d/\*\.conf;' /etc/nginx/nginx.conf; then
            sed -i '/^[[:space:]]*http[[:space:]]*{/a\    include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
        fi
        grep -Eq '^[[:space:]]*include[[:space:]]+/etc/nginx/conf\.d/\*\.conf;' /etc/nginx/nginx.conf || \
            error_exit "Cannot configure custom nginx.conf: add include /etc/nginx/conf.d/*.conf; inside http {}."
    fi
}

configure_selinux() {
    [[ "$OS_FAMILY" == rhel ]] || return 0
    command_exists getenforce || return 0
    [[ "$(getenforce)" != Disabled ]] || return 0
    setsebool -P httpd_can_network_connect on
    setsebool -P httpd_can_network_connect_db on
    # Persist labels across relabel/reboot; only Laravel writable directories get write access.
    semanage fcontext -a -t httpd_sys_content_t "${PANEL_DIR}(/.*)?" || \
        semanage fcontext -m -t httpd_sys_content_t "${PANEL_DIR}(/.*)?"
    local directory
    for directory in storage bootstrap/cache; do
        semanage fcontext -a -t httpd_sys_rw_content_t "${PANEL_DIR}/${directory}(/.*)?" || \
            semanage fcontext -m -t httpd_sys_rw_content_t "${PANEL_DIR}/${directory}(/.*)?"
    done
    restorecon -RF "$PANEL_DIR" /run/pterodactyl-php
}

install_web_dependencies() {
    update_repos
    case "$OS_FAMILY" in
        debian)
            install_packages ca-certificates curl gnupg tar unzip git cron tzdata
            add_php_repo_debian
            update_repos
            install_packages php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath \
                php8.3-xml php8.3-fpm php8.3-curl php8.3-zip php8.3-intl nginx certbot python3-certbot-nginx ;;
        rhel)
            install_packages ca-certificates tar unzip git cronie tzdata
            command_exists curl || install_packages curl
            prepare_rhel_repos
            install_packages php-cli php-gd php-mysqlnd php-mbstring php-bcmath php-xml php-fpm \
                php-curl php-zip php-intl php-sodium php-process nginx certbot python3-certbot-nginx policycoreutils-python-utils ;;
        arch)
            install_packages ca-certificates curl tar unzip git cronie tzdata php-legacy php-legacy-fpm \
                php-legacy-gd php-legacy-sodium nginx certbot certbot-nginx
            configure_arch_php ;;
    esac
    validate_php_runtime
    configure_php_fpm
    configure_nginx_layout
    enable_service_now "$CRON_SERVICE"
    enable_service_now nginx
}

install_panel_dependencies() {
    print_header "Installing Dependencies"
    install_web_dependencies
    case "$OS_FAMILY" in
        arch) install_packages mariadb valkey ;;
        *) install_packages mariadb-server "$REDIS_SERVICE" ;;
    esac
    initialize_mariadb
    enable_service_now "$REDIS_SERVICE"
    success "Panel dependencies installed."
}
