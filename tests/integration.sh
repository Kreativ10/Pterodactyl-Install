#!/usr/bin/env bash
# Run ONLY inside a disposable Docker container. Real packages, PHP, DB, Redis and nginx.
set -Eeuo pipefail
[[ -f /.dockerenv ]] || { echo 'This test requires a disposable Docker container.' >&2; exit 1; }
cd /repo
source ./panel.sh
umask 077
INSTALL_TMP_DIR=$(mktemp -d)
code=0; log=''
trap 'code=$?; if (( code != 0 )); then for log in "$INSTALL_TMP_DIR"/*.log; do [[ ! -f "$log" ]] || tail -n 40 "$log"; done; fi; exit "$code"' EXIT

detect_os
# Containers do not boot systemd. Only service management is replaced;
# package/repository installation, FPM configuration and all app commands are real.
systemctl() { return 0; }
enable_service_now() {
    local service="$1"
    case "$service" in
        mariadb)
            install -d -m 755 -o mysql -g mysql /run/mysqld /run/mariadb
            if [[ ! -d /var/lib/mysql/mysql ]]; then
                "$(command -v mariadb-install-db || command -v mysql_install_db)" --user=mysql --basedir=/usr --datadir=/var/lib/mysql >/dev/null
            fi
            "$(command -v mariadbd || command -v mysqld || printf %s /usr/libexec/mysqld)" --user=mysql > "$INSTALL_TMP_DIR/mariadb.log" 2>&1 &
            ;;
        redis-server|redis) redis-server --daemonize yes ;;
        valkey) valkey-server --daemonize yes ;;
        php*) install -d -m 755 /run/pterodactyl-php /run/php /run/php-fpm; "$PHP_FPM_BIN" -D ;;
        nginx) nginx ;;
        cron) cron ;;
        crond|cronie) crond ;;
        pteroq)
            runuser -u "$WEBSERVER_USER" -- "$PHP_BIN" "$PANEL_DIR/artisan" queue:work --once > "$INSTALL_TMP_DIR/queue.log" 2>&1
            ;;
        *) echo "Unexpected service $service" >&2; return 1 ;;
    esac
}
restart_service() { [[ "$1" != nginx ]] || nginx -s reload; }
reload_service() { [[ "$1" != nginx ]] || nginx -s reload; }
PANEL_FQDN=panel.example.test
PANEL_TIMEZONE=UTC
PANEL_ADMIN_EMAIL=admin@example.test
PANEL_LE_EMAIL=admin@example.test
PANEL_ADMIN_USER="admin"
PANEL_ADMIN_FIRST=Test
PANEL_ADMIN_LAST=Administrator
PANEL_ADMIN_PASS="$(gen_password 24)Aa1"
PANEL_DB_NAME=panel
PANEL_DB_USER=pterodactyl
# The regression password intentionally contains literal interpolation syntax.
# shellcheck disable=SC2016
PANEL_DB_PASS='Regression$1"quote\\slash${UNDEFINED} end'
PANEL_ENABLE_TELEMETRY=false
PANEL_CONFIGURE_FW=false
PANEL_SSL_MODE=http

install_panel_dependencies
install_composer
download_panel
install_panel_composer_dependencies
create_database "$PANEL_DB_NAME"
create_database_user "$PANEL_DB_USER" "$PANEL_DB_PASS" "$PANEL_DB_NAME" 127.0.0.1
configure_panel_app_environment
set_panel_permissions
install_panel_cron
install_pteroq_service
apply_panel_nginx_config
panel_health_check
# Test the login route as well as the homepage, reject Laravel error pages.
curl -fsS --noproxy '*' --resolve panel.example.test:80:127.0.0.1 http://panel.example.test/auth/login -o "$INSTALL_TMP_DIR/login.html"
grep -q '<html' "$INSTALL_TMP_DIR/login.html"
grep -q '^PTERODACTYL_TELEMETRY_ENABLED=false$' "$PANEL_DIR/.env"
[[ "$(stat -c %a "$PANEL_DIR/.env")" == 600 ]]
[[ "$("$DATABASE_BIN" -N -e "SELECT COUNT(*) FROM panel.users WHERE root_admin=1;")" == 1 ]]
# Ensure the selected PHP, not a different system default, runs the scheduler.
crontab -u "$WEBSERVER_USER" -l | grep -F "$PHP_BIN $PANEL_DIR/artisan schedule:run"

PMA_SERVER_FQDN=$PANEL_FQDN
PMA_VERSION=$PMA_DEFAULT_VERSION
generate_blowfish_secret
download_phpmyadmin
configure_phpmyadmin_files
write_phpmyadmin_snippet
include_phpmyadmin_in_panel_nginx
phpmyadmin_health_check
curl -fsS --noproxy '*' --resolve panel.example.test:80:127.0.0.1 http://panel.example.test/phpmyadmin/ -o "$INSTALL_TMP_DIR/pma.html"
grep -qi 'phpmyadmin' "$INSTALL_TMP_DIR/pma.html"
if grep -q 'FAIL' "$INSTALL_TMP_DIR/queue.log"; then
    "$DATABASE_BIN" -N -e 'SELECT SUBSTRING_INDEX(exception, CHAR(10), 1) FROM panel.failed_jobs;'
    error_exit 'Queued notification failed.'
fi
status=$(curl -s --noproxy '*' --resolve panel.example.test:80:127.0.0.1 -o /dev/null -w '%{http_code}' http://panel.example.test/phpmyadmin/setup/index.php)
[[ "$status" == 403 ]] || error_exit "Expected phpMyAdmin setup 403, got $status."
status=$(curl -s --noproxy '*' --resolve panel.example.test:80:127.0.0.1 -o /dev/null -w '%{http_code}' http://panel.example.test/phpmyadmin/nonexistent.php)
[[ "$status" == 404 ]] || error_exit "Expected missing phpMyAdmin script 404, got $status."
printf 'INTEGRATION PASS: %s %s; PHP %s; panel + admin + DB + queue + cron + HTTP + phpMyAdmin\n' "$OS_ID" "$OS_VERSION" "$("$PHP_BIN" -r 'echo PHP_VERSION;')"
