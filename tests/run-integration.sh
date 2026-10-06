#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname -- "$SCRIPT_DIR")"
images=("$@")
if (( ${#images[@]} == 0 )); then
    images=(ubuntu:24.04 almalinux:9 archlinux:base)
fi
for image in "${images[@]}"; do
    # Copy the entrypoint so changes in the mounted checkout cannot shift Bash's
    # position in a running test. No host ports, data mounts or privileged access.
    docker run --rm -v "$REPO_DIR:/repo:ro" "$image" \
        bash -c 'cp /repo/tests/integration.sh /tmp/pterodactyl-qa.sh; bash /tmp/pterodactyl-qa.sh'
done
