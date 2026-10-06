"""Regression tests: no package installation or writes to system directories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def bash(self, script, *, success=True, env=None, stdin=''):
        result = subprocess.run(
            ['bash', '-c', 'source ./panel.sh\n' + script], cwd=ROOT,
            input=stdin, text=True, capture_output=True,
            env={**os.environ, **(env or {})}, timeout=10,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def test_password_generator_survives_pipefail(self):
        for length in (1, 32, 128):
            with self.subTest(length=length):
                result = self.bash(f'p=$(gen_password {length}); printf "%s" "$p"')
                self.assertEqual(len(result.stdout), length)
                self.assertRegex(result.stdout, r'^[a-f0-9]+$')
        self.bash('gen_password 0', success=False)

    def test_yes_no_updates_callers_answer(self):
        for response, default, expected in [('yes', 'n', 'y'), ('no', 'y', 'n'), ('', 'n', 'n')]:
            self.bash(f'f() {{ local answer=""; ask_yes_no Question {default} answer; [[ "$answer" == {expected} ]]; }}; f', stdin=response+'\n')

    def test_input_helpers_update_callers_value(self):
        for helper in ('required_input', 'optional_input'):
            self.bash(f'f() {{ local value=""; {helper} Question default value; [[ "$value" == test ]]; }}; f', stdin='test\n')

    def test_eof_fails_with_diagnostic(self):
        result = self.bash('answer=""; ask_yes_no Question y answer', success=False)
        self.assertIn('Input ended unexpectedly', result.stderr)

    def test_os_matrix_and_arch_without_version(self):
        cases = [('ubuntu', '22.04', 'debian', 'www-data'), ('ubuntu', '24.04', 'debian', 'www-data'),
                 ('debian', '11', 'debian', 'www-data'), ('debian', '12', 'debian', 'www-data'), ('debian', '13', 'debian', 'www-data'),
                 ('almalinux', '8.10', 'rhel', 'nginx'), ('almalinux', '9.7', 'rhel', 'nginx'),
                 ('rocky', '8.10', 'rhel', 'nginx'), ('rocky', '9.6', 'rhel', 'nginx'),
                 ('rhel', '9.6', 'rhel', 'nginx'), ('centos', '9', 'rhel', 'nginx'), ('arch', None, 'arch', 'http')]
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)/'os-release'
            for os_id, version, family, user in cases:
                with self.subTest(os_id=os_id, version=version):
                    fixture.write_text(f'ID={os_id}\n'+(f'VERSION_ID={version}\n' if version else ''))
                    self.bash(f'detect_os "$FIXTURE"; [[ "$OS_FAMILY" == {family} && "$WEBSERVER_USER" == {user} && "$PANEL_PHP_ENDPOINT" == unix:/run/pterodactyl-php/panel.sock ]]', env={'FIXTURE': str(fixture)})
            for os_id, version in [('ubuntu', '20.04'), ('almalinux', '10'), ('debian', '10'), ('alpine', '3.23')]:
                fixture.write_text(f'ID={os_id}\nVERSION_ID={version}\n')
                self.bash('detect_os "$FIXTURE"', success=False, env={'FIXTURE': str(fixture)})

    def test_ipv4_fqdn_and_injection_validation(self):
        self.bash('validate_fqdn panel.example.com; validate_fqdn 192.0.2.1; validate_bind_address 0.0.0.0')
        for value in ('999.1.2.3', '01.2.3.4', 'panel.example.com;evil', 'https://panel.example.com', 'a..com'):
            self.bash('validate_fqdn "$VALUE"', success=False, env={'VALUE': value})
        self.bash('validate_timezone ../zone.tab', success=False)
        self.bash('validate_web_path /phpmyadmin; validate_trusted_proxies 10.0.0.0/8,192.0.2.1')
        for value in ('/../', '/x;evil', '/x.y', '/'):
            self.bash('validate_web_path "$VALUE"', success=False, env={'VALUE': value})
        for value in ('127.0.0.1/99', 'x;evil', '127.0.0.1,'):
            self.bash('validate_trusted_proxies "$VALUE"', success=False, env={'VALUE': value})

    def test_admin_password_matches_upstream_requirements(self):
        self.bash('validate_admin_password GoodPass123')
        for value in ('short', 'lowercase123', 'UPPERCASE123', 'NoNumbersHere'):
            self.bash('validate_admin_password "$VALUE"', success=False, env={'VALUE': value})

    def test_arch_never_performs_partial_upgrade(self):
        result = self.bash('OS_FAMILY=arch; pacman() { printf "%s\\n" "$*"; }; update_repos; install_packages php-legacy')
        self.assertIn('-Syu --noconfirm', result.stdout)
        self.assertIn('-S --needed --noconfirm php-legacy', result.stdout)

    def test_package_failure_propagates(self):
        self.bash('OS_FAMILY=rhel; dnf() { return 42; }; install_packages php; echo unreachable', success=False)

    def test_env_special_characters(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory)/'.env'
            file.write_text('APP_URL=http://old\nOTHER=value\n')
            self.bash('set_env_value "$FILE" APP_URL "https://new.test/a?b=c&d=e"; set_env_value "$FILE" TRUSTED_PROXIES "10.0.0.0/8"', env={'FILE': str(file)})
            self.assertEqual(file.read_text(), 'APP_URL=https://new.test/a?b=c&d=e\nOTHER=value\nTRUSTED_PROXIES=10.0.0.0/8\n')

    def test_dotenv_literal_preserves_special_characters(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory)/'.env'
            file.write_text('DB_PASSWORD=old\n')
            self.bash('set_env_literal "$FILE" DB_PASSWORD "$PASSWORD"', env={'FILE': str(file), 'PASSWORD': 'a"b\\c$1${MISSING}'})
            self.assertEqual(file.read_text(), 'DB_PASSWORD="a\\"b\\\\c\\$1\\${MISSING}"\n')
            self.bash('set_env_value "$FILE" EVIL "$PASSWORD"', success=False,
                      env={'FILE': str(file), 'PASSWORD': 'value\nINJECT=1'})

    def test_existing_panel_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory)/'.env'
            file.write_text('APP_KEY=critical\n')
            self.bash('refuse_existing_directory "$DIRECTORY"', success=False, env={'DIRECTORY': directory})
            self.assertEqual(file.read_text(), 'APP_KEY=critical\n')

    def test_artisan_failure_is_not_reported_as_success(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.bash('INSTALL_TMP_DIR="$TEMP"; PHP_BIN=/bin/false; PANEL_DIR="$TEMP"; run_artisan migrate --force; echo unreachable', success=False, env={'TEMP': directory})
            self.assertIn('Artisan migrate failed', result.stderr)
            self.assertNotIn('unreachable', result.stdout)

    def test_sql_user_creation_preserves_password_and_scopes_grants(self):
        result = self.bash('mariadb() { cat; }; create_database_user app "$PASSWORD" panel 127.0.0.1', env={'PASSWORD': "back\\slash'quote"})
        self.assertIn("back\\\\slash''quote", result.stdout)
        self.assertNotIn('IF NOT EXISTS', result.stdout)
        self.assertNotIn('WITH GRANT OPTION', result.stdout)
        self.assertIn("SET SESSION sql_mode = '';", result.stdout)
        self.bash('create_database_user "evil\x27;" pass panel', success=False)

    def test_database_errors_do_not_print_passwords(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.bash('INSTALL_TMP_DIR="$TEMP"; mariadb() { echo "$PASSWORD" >&2; return 1; }; create_database_user app "$PASSWORD" panel',
                               success=False, env={'TEMP': directory, 'PASSWORD': 'PrivatePassword123'})
            self.assertNotIn('PrivatePassword123', result.stderr + result.stdout)
            self.assertIn('MariaDB operation failed', result.stderr)

    def test_el8_mysql_binary_aliases(self):
        self.bash('command_exists() { [[ "$1" == mysql || "$1" == mysqladmin ]]; }; detect_mariadb_runtime; [[ "$DATABASE_BIN" == mysql && "$DATABASE_ADMIN_BIN" == mysqladmin ]]')

    def test_cron_removal_preserves_unrelated_tasks(self):
        result = self.bash('''WEBSERVER_USER=www-data; PANEL_DIR=/var/www/pterodactyl
crontab() {
    if [[ "$*" == *" -l" ]]; then
        printf '%s\\n' '* * * * * php /var/www/pterodactyl/artisan schedule:run' '0 0 * * * /usr/local/bin/backup'
    else cat; fi
}
remove_panel_cron''')
        self.assertEqual(result.stdout.strip(), '0 0 * * * /usr/local/bin/backup')

    def test_ssl_and_http_nginx_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory)/'nginx.conf'
            self.bash('PANEL_FQDN=panel.example.com; PANEL_PHP_ENDPOINT=unix:/run/pterodactyl-php/panel.sock; write_panel_nginx_ssl_config "$CONF" /tmp/cert.pem /tmp/key.pem', env={'CONF': str(file)})
            config=file.read_text()
            self.assertIn('listen 443 ssl http2;', config)
            self.assertIn('fastcgi_pass unix:/run/pterodactyl-php/panel.sock;', config)
            self.assertIn('SCRIPT_FILENAME $document_root$fastcgi_script_name;', config)

    def test_install_orders_firewall_before_certificate(self):
        result = self.bash('''for step in refuse_existing_directory gather_panel_input install_panel_dependencies install_composer download_panel install_panel_composer_dependencies create_database create_database_user configure_panel_app_environment set_panel_permissions install_panel_cron install_pteroq_service apply_panel_nginx_config obtain_panel_letsencrypt configure_panel_firewall run_artisan panel_health_check show_panel_completion; do
    eval "$step() { printf '%s\\n' '$step'; }"
done
perform_panel_install''')
        self.assertLess(result.stdout.index('configure_panel_firewall'), result.stdout.index('obtain_panel_letsencrypt'))

    def test_cli_rejects_invalid_and_surplus_args(self):
        for script in ('parse_cli_args --action', 'parse_cli_args --action invalid', 'parse_cli_args --action panel unexpected'):
            self.bash(script, success=False)
        self.bash('parse_cli_args --check --action panel; [[ "$CHECK_ONLY" == true && "$MAIN_ACTION" == panel ]]')
        for wrapper in ('wings.sh', 'phpmyadmin.sh', 'uninstall.sh'):
            result = subprocess.run(['bash', wrapper, '--help'], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Usage:', result.stdout)

    def test_ssh_firewall_uses_actual_connection_port(self):
        result = self.bash('SSH_CONNECTION="192.0.2.1 55555 192.0.2.2 2222"; sshd() { echo "port 2222"; }; OS_FAMILY=debian; ufw() { printf "%s\\n" "$*"; }; firewall_allow_service ssh; firewall_reload')
        self.assertIn('allow 2222/tcp', result.stdout)
        self.assertIn('--force enable', result.stdout)

    def test_firewall_zone_discovery_failure_propagates(self):
        self.bash('OS_FAMILY=rhel; firewall-cmd() { return 42; }; firewall_allow_tcp 80; echo unreachable', success=False)

    def test_full_panel_dialog_reaches_confirmed_installation(self):
        answers = ['panel.example.com', 'UTC', 'admin@example.com', 'admin', 'Admin', 'User',
                   'StrongPass123', 'StrongPass123', 'panel', 'pterodactyl', 'n', '', '1', 'n', 'n', 'y']
        result = self.bash('gather_panel_input; [[ "$PANEL_DB_PASS" != "" && "$PANEL_SSL_MODE" == http && "$PANEL_CONFIGURE_FW" == false && "$PANEL_ENABLE_TELEMETRY" == false ]]; echo dialog-complete', stdin='\n'.join(answers)+'\n')
        self.assertIn('dialog-complete', result.stdout)
        self.assertNotIn('StrongPass123', result.stdout + result.stderr)

    def test_phpmyadmin_dialog_defaults_to_existing_panel_domain(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory)/'.env').write_text('APP_URL="https://panel.example.com"\n')
            self.bash('PANEL_DIR="$PANEL_TEST_DIR"; gather_phpmyadmin_input; [[ "$PMA_SERVER_FQDN" == panel.example.com ]]',
                      env={'PANEL_TEST_DIR': directory}, stdin='\n\n\ny\n')

    def test_health_failure_stops_completion(self):
        self.bash('systemctl() { return 1; }; panel_health_check; show_panel_completion', success=False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
