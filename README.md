# Pterodactyl Installer

Интерактивная установка Pterodactyl Panel, Wings и phpMyAdmin с nginx.
Нужны root, Bash, интернет и работающий systemd. Установка меняет пакеты,
конфигурацию служб и, если выбрано, firewall. Используйте отдельный сервер.

## Установка одной командой

Выполните в терминале сервера:

```bash
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/Kreativ10/Pterodactyl-Install/main/install.sh | bash'
```

Команда скачивает установщик и весь репозиторий из ветки `main`, затем
открывает **меню действий**: установка панели, Wings, phpMyAdmin,
удаление компонентов или выход. От root запускается напрямую, для
обычного пользователя использует `sudo`. Нужны `curl` и `tar`.
При ошибке загрузки установка не начинается; временная копия репозитория
удаляется после завершения. Сама панель скачивается из официального
GitHub release Pterodactyl во время установки.

Для проверки ОС без root и изменений:

```bash
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/Kreativ10/Pterodactyl-Install/main/install.sh | bash -s -- --check'
```

Аргументы после `bash -s --` передаются установщику. Явный `--action panel`,
`--action wings`, `--action phpmyadmin` или `--action uninstall` пропускает
главное меню и запускает мастер выбранного действия. Например, для панели:

```bash
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/Kreativ10/Pterodactyl-Install/main/install.sh | bash -s -- --action panel'
```

Один скачанный `panel.sh` не работает без модулей `lib/`; используйте
`install.sh` или клонируйте весь репозиторий.

## Запуск из локальной копии

```bash
git clone https://github.com/Kreativ10/Pterodactyl-Install.git
cd Pterodactyl-Install
bash panel.sh --check          # только определение ОС и выбранных служб; без root и изменений
sudo bash panel.sh            # меню
sudo bash panel.sh --action panel
sudo bash wings.sh
sudo bash phpmyadmin.sh
sudo bash uninstall.sh
```

`--check` показывает совместимость ОС с установщиком. Он не подтверждает,
что зависимости уже установлены, сервер настроен или панель работает.

## Дистрибутивы

| ОС | Версии | PHP / особенности |
| --- | --- | --- |
| Ubuntu | 22.04, 24.04, 26.04 LTS | PHP 8.3: Ondřej PPA на 22.04, штатные пакеты на 24.04, Sury на 26.04 |
| Debian | 11, 12, 13 | PHP 8.3 из Sury, штатные MariaDB и Redis |
| AlmaLinux / Rocky Linux | 8, 9 | EPEL, PowerTools/CRB, Remi PHP 8.3; SELinux сохраняется |
| RHEL | 8, 9 | Remi/EPEL; требуется активная подписка с доступным CodeReady Builder |
| CentOS Stream | 9 | CRB/EPEL/Remi |
| Arch Linux | rolling, x86_64 | Официальные `php-legacy` 8.3, `php-legacy-fpm`, Valkey, MariaDB |

Ubuntu 22.04/24.04, Debian и RHEL/Rocky/Alma 8–9 перечислены в
[официальной документации панели](https://github.com/pterodactyl/documentation/blob/master/panel/1.0/getting_started.md).
Ubuntu 26.04 — дополнительная поддержка установщика. Вместо штатного PHP 8.5
устанавливается PHP 8.3 из [Sury для `resolute`](https://packages.sury.org/php/dists/resolute/)
с отдельным подписанным keyring; CLI, FPM, очередь и cron используют PHP 8.3.
Ubuntu 26.10 и другие промежуточные версии не входят в матрицу.
Arch — дополнительная реализация установщика, **не официальная платформа поддержки Pterodactyl**.
Она использует [php-legacy](https://archlinux.org/packages/extra/x86_64/php-legacy/)
из Extra и Valkey через совместимый Redis-протокол. CLI, Composer, FPM, cron
и очередь используют один выбранный PHP. AUR и сборка PHP из исходников не нужны.
На Arch выполняется `pacman -Syu`: частичные обновления не поддерживаются.
Если версия `php-legacy` выйдет за поддерживаемые панелью 8.2/8.3,
установщик остановится с диагностикой вместо обхода требований Composer.

Wings скачивается для x86_64/aarch64; ему нужен работающий Docker и подходящая
виртуализация. Наличие aarch64-бинарника Wings не означает поддержку
Arch Linux ARM этими пакетами: матрица Arch проверяется только на x86_64.
ОС вне таблицы отклоняются до установки пакетов. Ubuntu 20.04 и CentOS 7/8
не входят в актуальную матрицу.

## Настройка и повторный запуск

- Панель: `/var/www/pterodactyl`, nginx, отдельный PHP-FPM pool,
  MariaDB, Redis/Valkey, `pteroq`, cron.
- Existing certificate, HTTP, Let's Encrypt и HTTP origin за HTTPS reverse proxy
  доступны в мастере. Для proxy указываются доверенные IPv4/CIDR;
  `*` нужно выбрать явно. Для HTTPS до origin используйте сертификат.
- Firewall открывает фактические SSH-порты, затем порты выбранного компонента.
  Для Let's Encrypt порт 80 открывается **до** запроса сертификата.
  При отключении автоматической настройки откройте необходимые порты сами.
- Пароли не выводятся в терминал. DB password сохраняется в `.env` с правами 600.
  Ошибки Artisan сохраняются в каталоге `/tmp/pterodactyl-install.*`, доступном
  только root; на успехе временные файлы удаляются.
- Для SMTP нужны реальные данные почтового сервера. До настройки
  **Admin → Settings → Mail** письма записываются в локальный журнал;
  внешняя доставка и восстановление пароля по email пока недоступны.
- Let's Encrypt настраивает renewal timer или cron и deploy hooks для nginx/Wings.
  Ошибка выпуска сертификата приводит к ненулевому завершению;
  конфигурация панели остаётся на HTTP для диагностики.
- Wings устанавливается и включается для автозапуска. Перед его запуском нужно
  создать `/etc/pterodactyl/config.yml` из конфигурации узла в панели, затем
  выполнить `systemctl enable --now wings`. Сертификат сам по себе конфигурацию
  узла не заменяет. Стандартные открытые порты: API 8080, SFTP 2022;
  при иных портах в конфигурации узла измените firewall.
- phpMyAdmin подключается к существующему virtual host панели либо получает
  свой HTTP virtual host. Используется TCP `127.0.0.1`, а не неоднозначный socket.
- Установщик предназначен для **первой установки**. Непустые каталоги панели,
  Wings и phpMyAdmin не удаляются и не перезаписываются. Существующие DB/аккаунты
  не сбрасываются; выберите свободные имена. После частичной установки сначала
  изучите ошибку и сохраните данные. Обновление панели выполняется по
  [инструкции Pterodactyl](https://github.com/pterodactyl/documentation/blob/master/panel/1.0/updating.md).
- Uninstall запрашивает подтверждение; удаление DB и данных игровых серверов
  выбирается отдельно, по умолчанию отключено. Общие пакеты не удаляются.

## Проверки

```bash
make check                     # bash -n, ShellCheck, Python unittest
make integration               # реальные пакеты и панель в четырёх Docker-контейнерах
bash tests/run-integration.sh ubuntu:26.04
bash tests/run-integration.sh debian:13 almalinux:8
```

Для `make check` нужен Python 3 и ShellCheck, либо Docker для контейнерного
ShellCheck. Integration требует Docker и интернет. Тесты не публикуют порты,
не монтируют данные хоста и не требуют `--privileged`.

Integration устанавливает release панели, Composer dependencies, PHP-FPM,
MariaDB, Redis/Valkey, nginx и phpMyAdmin; выполняет миграции, создание
администратора, обработку очереди, HTTP запросы и проверяет cron и permissions.
Управление службами заменено прямым запуском процессов, поскольку контейнеры
не загружают systemd. Это **не** проверка загрузки сервера, SELinux Enforcing,
реальных firewall, публичного DNS/ACME, SMTP или запуска игровых серверов Wings.

GitHub Actions запускает статические/регрессионные проверки при push/PR.
Полная контейнерная матрица запускается вручную через `workflow_dispatch`.
Результаты текущей проверки: [AUDIT_REPORT.md](AUDIT_REPORT.md).
