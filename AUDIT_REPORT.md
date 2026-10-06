# Аудит и исправления установщика

Дата: 2026-10-06. Изменения выполнены локально; репозиторий не опубликован,
боевой сервер не изменялся.

## Почему исходный установщик не работал

1. **Подтверждение установки терялось.** `ask_yes_no` объявлял локальную
   `answer`, а вызывающий код тоже передавал имя `answer`. `printf -v` менял
   внутреннюю переменную; внешняя оставалась пустой. Даже ответ `yes` приводил
   к отмене. Воспроизведено на исходном коде и покрыто тестом всего диалога.
2. **Генератор пароля завершал Bash с кодом 141.** `tr /dev/urandom | head`
   получал SIGPIPE под `set -euo pipefail`. Заменён чтением конечного объёма
   случайных байтов; нет бесконечного producer и скрытого `|| true`.
3. **Arch падал до определения ОС.** `VERSION_ID` в `/etc/os-release` может
   отсутствовать. Теперь используется безопасное значение для rolling-release.
4. **PHP-FPM получал ошибочный адрес.** На RHEL проверялся ещё не созданный
   socket, после чего выбирался TCP 9000, хотя штатный pool слушал Unix socket.
   Теперь отдельный pool и известный endpoint задаются до запуска службы.
5. **Ошибки Laravel скрывались.** `p:environment:setup` и другие обязательные
   команды могли завершиться ошибкой, а установщик продолжал работу. Ошибки
   останавливают установку; диагностика содержит этап и защищённый файл лога.
6. **Пакеты и репозитории были несовместимы с минимальными образами.**
   Исправлены curl/curl-minimal на EL, php-process/posix и sodium;
   убраны неподходящие generic PHP-пакеты и необязательный MariaDB repo setup.
   Ошибки Remi/EPEL/CRB/PowerTools больше не игнорируются.
7. **Cron не запускался.** Установка пакета и crontab не обеспечивала запуск
   службы. Теперь включаются cron/crond/cronie, очередь и выбранный PHP.
8. **Firewall применялся после ACME.** Это блокировало выпуск сертификата при
   закрытом порте 80. Изменён порядок; SSH-порты берутся из sshd/SSH_CONNECTION,
   ошибки настройки firewall больше не выдаются за успех.
9. **Повторный запуск мог уничтожить панель и APP_KEY.** Переустановка больше
   не удаляет непустые каталоги. Создание существующей БД/аккаунта не маскируется
   `IF NOT EXISTS` и не меняет чужой пароль.
10. **Неполная проверка входных данных.** Добавлены проверки октетов IPv4,
    путей phpMyAdmin, сертификатов, proxy CIDR, длины DB username, timezone
    и требований Pterodactyl к admin password. EOF даёт явную ошибку.
11. **Некорректная работа с секретами.** Генерируемый DB password больше не
    печатается; `.env` имеет права 600. Пароли с `$`, кавычками и `\` сохраняются
    буквально. Вывод Artisan/SQL с потенциальными секретами защищён.
12. **phpMyAdmin мог не иметь доступного virtual host.** Добавлены standalone
    virtual host, проверка реальной HTML страницы, возврат исходного nginx config
    при ошибке, TCP localhost, запрет служебных директорий и отсутствующих PHP.
13. **Ложное сообщение об успехе.** Health check проверяет службы и маршрут
    `/auth/login`, а не только синтаксис nginx или штатную стартовую страницу.
    Учитывается асинхронное применение nginx reload, включая phpMyAdmin.
14. **Продление сертификатов не гарантировало reload служб.** Добавлены
    deploy hooks, определение certbot timer и cron fallback. Для standalone
    сертификата Wings сохраняется/восстанавливается состояние web-сервисов.
15. **Удаление cron/БД было слишком нестрогим.** Остальные cron задания
    сохраняются; системные DB/root accounts защищены; ошибочное удаление БД
    больше не сопровождается сообщением об успехе.

16. **Совместимость с nginx 1.20 на EL.** phpMyAdmin regex alias с
    `$request_filename` давал `fastcgi request length mismatch` и HTTP 500.
    PHP filename сохраняется в отдельную переменную перед FastCGI обработкой;
    исправление проверено настоящими запросами на AlmaLinux.
17. **Runtime/permissions на Arch и EL.** `.ini` должны читаться пользователем
    очереди, а PHP session directory — пользователем pool. Добавлены явные права,
    отдельный session directory и проверка расширений от имени web user.
    Утилиты MariaDB 10.3 на EL8 используют имена mysql/mysqladmin; это учитывается.

## Поддержка новых платформ

Новый `lib/platform.sh` содержит явную матрицу Ubuntu 22.04/24.04/26.04,
Debian 11/12/13, AlmaLinux/Rocky/RHEL 8/9, CentOS Stream 9, Arch Linux.
CLI, Composer, FPM, очередь и cron используют единый выбранный PHP 8.3.
Для Ubuntu 26.04 (`resolute`) подключается подписанный репозиторий Sury:
штатный PHP 8.5 не выбирается, а прежний Launchpad PPA не содержит `resolute`.
Ubuntu 24.04 сохраняет штатные пакеты, Ubuntu 22.04 — прежний PPA.
Arch использует официальные php-legacy, MariaDB и Valkey; PHP extensions
включаются явно, их `.ini` читаются пользователем очереди. Для nginx добавлен
include conf.d, MariaDB инициализируется только при отсутствии системных таблиц.
SELinux сохраняется: задаются постоянные labels для приложения, writable
Laravel directories и socket directory **до** запуска FPM.

Монолит разделён на `lib/common.sh`, `platform.sh`, `firewall.sh`, `panel.sh`,
`wings.sh`, `phpmyadmin.sh`, `uninstall.sh`. Entrypoint и прежние wrappers сохранены;
теперь требуется полный checkout вместе с `lib/`.

## Проверка

Проверены Pterodactyl Panel v1.15.1, phpMyAdmin 5.2.3 и Wings v1.13.3.

| Контейнер | PHP | Результат |
| --- | --- | --- |
| Ubuntu 24.04 | 8.3.6 (пакет с обновлениями Ubuntu) | PASS |
| Ubuntu 26.04 | 8.3.35, Sury | PASS |
| Debian 13 | 8.3.35, Sury | PASS |
| Arch Linux (образ 20261004) | 8.3.35, php-legacy | PASS |
| AlmaLinux 8.10 | 8.3.35, Remi | PASS |
| AlmaLinux 9.8 | 8.3.35, Remi | PASS |

На каждой платформе проверены настоящие migrations/admin/DB/queue/cron command,
HTTP login и phpMyAdmin, отказ setup (403), отсутствующий PHP script (404),
literal DB password и выключение telemetry. На AlmaLinux финальный прогон
использовал уже установленные настоящие пакеты в тех же изолированных контейнерах;
тестовые процессы перезапущены, тестовые application DB/files созданы заново.

- `make check`: Bash syntax, ShellCheck и 40 регрессионных тестов — PASS.
- Ubuntu 26.04: `panel.sh --check` и `bash tests/run-integration.sh ubuntu:26.04`
  — PASS. Проверены настоящие зависимости, migrations/admin/DB/queue/cron,
  HTTP панели и phpMyAdmin. `systemd` в контейнере заменён прямым запуском служб.
- Тесты определения ОС принимают 26.04 и отклоняют 26.10/26.01; выбор PHP repo
  проверяет Sury для 26.04, штатные пакеты для 24.04 и PPA для 22.04.
- Установочный диалог, SIGPIPE, отсутствие VERSION_ID, ошибочные IP/CIDR,
  сохранность существующего APP_KEY, literal passwords, порядок ACME/firewall,
  ошибки Artisan/package manager/firewall, cron и CLI покрыты тестами.
- Бинарник Wings v1.13.3 скачан и запущен с командой `version` — PASS.
  Генерация unit проверена; без node config служба не запускается.

В Integration используются реальные пакеты, Composer, PHP-FPM, MariaDB,
Redis/Valkey, nginx, migrations/admin/queue, HTTP панели и phpMyAdmin.
Заменено только управление systemd прямыми процессами. Проверяются DB password
со спецсимволами, `.env` permissions, cron command, phpMyAdmin 403/404.

## Границы проверки

Для запуска одной командой добавлен `install.sh`: скачивает архив ветки `main`
с GitHub, проверяет наличие entrypoint и всех модулей, открывает меню действий
(с `sudo`, если нужен root), передаёт аргументы и код завершения. Временная
копия удаляется на успехе и ошибке. README использует `pipefail`, чтобы ошибка
первоначального скачивания скрипта не превращалась в успешное завершение.
Двенадцать тестов загрузчика проверяют команду из README с локальными архивами,
настоящие модули установщика, передачу аргументов, sudo, cleanup, неполные
загрузки/архивы и коды ошибок. Отдельный тест запускает команду через pipe
в псевдотерминале: настоящее меню предлагает все действия, выбор Wings
читается из `/dev/tty`. Явные `--action` передаются без изменения;
принудительный `--action panel` удалён. Эти проверки не устанавливают пакеты на хост.
На момент проверки remote URL `main/install.sh` возвращает HTTP 404:
для удалённого запуска необходимо опубликовать новые файлы в GitHub.

Не подтверждены на реальном сервере: boot/systemd lifecycle, SELinux Enforcing,
firewall по SSH, публичный DNS/Let's Encrypt и продление реального сертификата,
SMTP, Wings с настоящим node config/Docker/game server, ARM64.
Сторонние дистрибутивы и версии из матрицы, не участвовавшие в container run,
имеют реализации и тесты определения ОС, но не подтверждённый полный install.

Для SMTP нет предоставленных credentials: до настройки mail в Admin UI
письма записываются локально. Для Wings необходимо добавить конфигурацию узла.

Использованы Skills `debugging-and-error-recovery`, `code-review-and-quality`
и Plugin Context7. Требования сверены с первичными источниками:

- [Pterodactyl requirements / OS matrix](https://github.com/pterodactyl/documentation/blob/master/panel/1.0/getting_started.md)
- [EL dependency/FPM setup](https://github.com/pterodactyl/documentation/blob/master/community/installation-guides/panel/centos8.md)
- [Debian 11/12/13 setup](https://github.com/pterodactyl/documentation/blob/master/community/installation-guides/panel/debian.md)
- [Sury repository setup](https://packages.sury.org/php/README.txt)
- [Sury packages for Ubuntu 26.04 resolute](https://packages.sury.org/php/dists/resolute/)
- [Arch php-legacy](https://archlinux.org/packages/extra/x86_64/php-legacy/)
- [Upstream Composer requirements](https://github.com/pterodactyl/panel/blob/1.0-develop/composer.json)
