"""Exercise GitHub bootstrap with local archives and no system installation."""
import errno
import fcntl
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import termios
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULES = (
    'lib/common.sh', 'lib/platform.sh', 'lib/firewall.sh', 'lib/panel.sh',
    'lib/wings.sh', 'lib/phpmyadmin.sh', 'lib/uninstall.sh',
)


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='bootstrap tests ')
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        self.work = self.directory / 'work'
        self.work.mkdir()
        self.repository = self.directory / 'repository'
        self.repository.mkdir()
        (self.repository / 'panel.sh').write_text(
            '#!/usr/bin/env bash\n'
            'printf "%s\\n" "$@" > "$BOOTSTRAP_ARGUMENTS"\n'
            'printf "%s\\n" "${BASH_SOURCE[0]}" > "$BOOTSTRAP_ENTRYPOINT"\n'
            'exit "${BOOTSTRAP_EXIT:-0}"\n'
        )
        for module in MODULES:
            path = self.repository / module
            path.parent.mkdir(exist_ok=True)
            path.write_text('# fixture\n')
        self.archive = self.directory / 'repository.tar.gz'
        self.pack()
        self.arguments = self.directory / 'arguments'
        self.entrypoint = self.directory / 'entrypoint'
        self.sudo_log = self.directory / 'sudo-called'
        self.env = {
            **os.environ,
            'PATH': str(self.bin) + os.pathsep + os.environ['PATH'],
            'TMPDIR': str(self.work),
            'BOOTSTRAP_ARCHIVE': str(self.archive),
            'BOOTSTRAP_ARGUMENTS': str(self.arguments),
            'BOOTSTRAP_ENTRYPOINT': str(self.entrypoint),
            'BOOTSTRAP_SUDO_LOG': str(self.sudo_log),
            'BOOTSTRAP_SCRIPT': str(ROOT / 'install.sh'),
            'BOOTSTRAP_CURL_EXIT': '0',
            'BOOTSTRAP_SCRIPT_CURL_EXIT': '0',
            'BOOTSTRAP_EXIT': '0',
        }
        self.command('curl', '''#!/usr/bin/env bash
set -euo pipefail
output=""
for argument in "$@"; do
    if [[ "$argument" == https://raw.githubusercontent.com/* ]]; then
        cat "$BOOTSTRAP_SCRIPT"
        exit "$BOOTSTRAP_SCRIPT_CURL_EXIT"
    fi
done
[[ "$BOOTSTRAP_CURL_EXIT" == 0 ]] || exit "$BOOTSTRAP_CURL_EXIT"
while (($#)); do
    case "$1" in
        --output) output="$2"; shift ;;
    esac
    shift
done
[[ -n "$output" ]]
cp "$BOOTSTRAP_ARCHIVE" "$output"
''')
        self.command('sudo', '''#!/usr/bin/env bash
printf 'called\\n' > "$BOOTSTRAP_SUDO_LOG"
"$@"
''')

    def command(self, name, contents):
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o755)

    def pack(self):
        with tarfile.open(self.archive, 'w:gz') as archive:
            archive.add(self.repository, arcname='Pterodactyl-Install-main')

    def run_bootstrap(self, *arguments, env=None, command=None):
        result = subprocess.run(
            command or ['bash', str(ROOT / 'install.sh'), *arguments],
            env={**self.env, **(env or {})}, text=True, capture_output=True,
            timeout=10,
        )
        self.assertEqual(list(self.work.iterdir()), [], result.stderr)
        return result

    def readme_command(self):
        commands = re.findall(r"^bash -o pipefail -c '[^\n]+'$", (ROOT / 'README.md').read_text(), re.M)
        self.assertGreaterEqual(len(commands), 2)
        return ['bash', '-c', commands[0]]

    def test_readme_one_command_leaves_action_selection_to_menu(self):
        result = self.run_bootstrap(command=self.readme_command())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments.read_text().splitlines(), [''])
        self.assertEqual(self.sudo_log.exists(), os.geteuid() != 0)
        self.assertFalse(Path(self.entrypoint.read_text().strip()).exists())

    def test_arguments_forwarded_without_sudo_for_check(self):
        result = self.run_bootstrap('--check', '--action', 'wings', 'argument with spaces')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments.read_text().splitlines(),
                         ['--check', '--action', 'wings', 'argument with spaces'])
        self.assertFalse(self.sudo_log.exists())

    def test_explicit_actions_forwarded_unchanged(self):
        for action in ('panel', 'wings', 'phpmyadmin', 'uninstall'):
            with self.subTest(action=action):
                result = self.run_bootstrap('--action', action)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.arguments.read_text().splitlines(), ['--action', action])

    def test_readme_pipeline_opens_menu_and_reads_choice_from_terminal(self):
        for module in MODULES:
            shutil.copyfile(ROOT / module, self.repository / module)
        shutil.copyfile(ROOT / 'panel.sh', self.repository / 'toolkit.sh')
        (self.repository / 'panel.sh').write_text('''#!/usr/bin/env bash
source "$(dirname -- "$0")/toolkit.sh"
parse_cli_args "$@"
exec < /dev/tty
[[ -n "$MAIN_ACTION" ]] || choose_main_action
printf '%s\\n' "$MAIN_ACTION" > "$BOOTSTRAP_ARGUMENTS"
''')
        self.pack()

        def connect_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        master, slave = os.openpty()
        try:
            process = subprocess.Popen(
                self.readme_command(), env=self.env, stdin=slave, stdout=slave,
                stderr=slave, preexec_fn=connect_terminal,
            )
        finally:
            os.close(slave)
        try:
            os.write(master, b'2\n')
            try:
                status = process.wait(timeout=10)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
            output = bytearray()
            while True:
                try:
                    chunk = os.read(master, 4096)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
                if not chunk:
                    break
                output.extend(chunk)
        finally:
            os.close(master)

        self.assertEqual(status, 0, output.decode())
        for label in ('Main Menu', 'Install Pterodactyl Panel', 'Install Pterodactyl Wings',
                      'Install phpMyAdmin', 'Uninstall Components', 'Exit'):
            self.assertIn(label, output.decode())
        self.assertEqual(self.arguments.read_text(), 'wings\n')
        self.assertEqual(list(self.work.iterdir()), [])

    def test_help_does_not_require_sudo(self):
        result = self.run_bootstrap('--help')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.sudo_log.exists())

    def test_archive_loads_real_installer_modules(self):
        for module in ('panel.sh', *MODULES):
            shutil.copyfile(ROOT / module, self.repository / module)
        self.pack()
        result = self.run_bootstrap('--help')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--action panel|wings|phpmyadmin|uninstall', result.stdout)
        self.assertFalse(self.sudo_log.exists())

    def test_installer_exit_code_propagated(self):
        result = self.run_bootstrap('--check', env={'BOOTSTRAP_EXIT': '42'})
        self.assertEqual(result.returncode, 42, result.stderr)

    def test_archive_download_failure_stops_installation(self):
        result = self.run_bootstrap('--check', env={'BOOTSTRAP_CURL_EXIT': '22'})
        self.assertEqual(result.returncode, 22, result.stderr)
        self.assertFalse(self.arguments.exists())

    def test_invalid_archive_stops_installation(self):
        self.archive.write_text('not an archive')
        result = self.run_bootstrap('--check')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.arguments.exists())

    def test_incomplete_repository_stops_installation(self):
        (self.repository / 'lib/platform.sh').unlink()
        self.pack()
        result = self.run_bootstrap('--check')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('missing lib/platform.sh', result.stderr)
        self.assertFalse(self.arguments.exists())

    def test_readme_command_reports_script_download_failure(self):
        empty_script = self.directory / 'empty.sh'
        empty_script.write_text('')
        result = self.run_bootstrap(command=self.readme_command(), env={
            'BOOTSTRAP_SCRIPT': str(empty_script), 'BOOTSTRAP_SCRIPT_CURL_EXIT': '22',
        })
        self.assertEqual(result.returncode, 22, result.stderr)
        self.assertFalse(self.arguments.exists())

    def test_truncated_script_cannot_start_installation(self):
        truncated_script = self.directory / 'truncated.sh'
        truncated_script.write_text((ROOT / 'install.sh').read_text().split('    tar -xzf')[0])
        result = self.run_bootstrap(command=self.readme_command(), env={
            'BOOTSTRAP_SCRIPT': str(truncated_script), 'BOOTSTRAP_SCRIPT_CURL_EXIT': '18',
        })
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.arguments.exists())
