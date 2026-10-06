#!/usr/bin/env bash

# Keep execution after the complete function definition so a truncated download
# cannot start an installation while this script is being read from a pipe.
main() (
    set -Eeuo pipefail
    umask 077

    local dependency argument module workdir
    local archive_url="https://codeload.github.com/Kreativ10/Pterodactyl-Install/tar.gz/refs/heads/main"
    local -a runner=(bash)
    local needs_root=true

    for dependency in curl tar mktemp; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            printf 'Required command is missing: %s\n' "$dependency" >&2
            return 1
        fi
    done

    for argument in "$@"; do
        case "$argument" in
            --check|--help|-h) needs_root=false ;;
        esac
    done
    if [[ "$needs_root" == true && "$EUID" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            printf 'Run this command as root, or install sudo.\n' >&2
            return 1
        fi
        runner=(sudo bash)
    fi

    workdir="$(mktemp -d "${TMPDIR:-/tmp}/pterodactyl-bootstrap.XXXXXX")"
    trap 'rm -rf -- "$workdir"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mkdir "$workdir/source"

    printf 'Downloading the installer from GitHub...\n' >&2
    curl --fail --silent --show-error --location --retry 3 \
        --connect-timeout 15 --max-time 180 \
        "$archive_url" --output "$workdir/repository.tar.gz"
    tar -xzf "$workdir/repository.tar.gz" --strip-components=1 -C "$workdir/source"

    for module in panel.sh lib/common.sh lib/platform.sh lib/firewall.sh \
        lib/panel.sh lib/wings.sh lib/phpmyadmin.sh lib/uninstall.sh; do
        if [[ ! -s "$workdir/source/$module" ]]; then
            printf 'The downloaded repository is incomplete: missing %s\n' "$module" >&2
            return 1
        fi
    done

    "${runner[@]}" "$workdir/source/panel.sh" "$@"
)

main "$@"
