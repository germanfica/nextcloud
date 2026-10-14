#!/bin/sh
# Deploy Nextcloud AIO and local Nginx Proxy Manager using Ansible.
set -eu

ProjectDir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
InstallDocker=true
AskBecomePass=true

Usage() {
  cat <<'USAGE'
Usage: ./install.sh [--skip-docker] [--no-ask-become-pass] [--help]

Deploy Nextcloud AIO and Nginx Proxy Manager on the local Ubuntu/Debian host.
By default, install Docker Engine and the Compose plugin using
playbooks/install-docker.yml before deploying Nextcloud AIO and NPM.

Options:
  --skip-docker           Do not run install-docker.yml (Docker already installed).
  --no-ask-become-pass    Use passwordless sudo or run as root.
  --help                  Show this message.

Install Ansible on the host before running this script.
This script does not complete the browser-based Nextcloud AIO setup.
USAGE
}

Error() {
  printf 'install.sh: %s\n' "$1" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-docker) InstallDocker=false ;;
    --no-ask-become-pass) AskBecomePass=false ;;
    --help|-h) Usage; exit 0 ;;
    *) Error "unknown option: $1"; Usage >&2; exit 2 ;;
  esac
  shift
done

if ! command -v ansible-playbook >/dev/null 2>&1; then
  Error 'ansible-playbook is required. Install it using: sudo apt install ansible'
  exit 1
fi
if ! command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
  Error 'sudo is required to deploy Docker and Nextcloud locally.'
  exit 1
fi

if [ "$InstallDocker" = true ]; then
  Playbook="$ProjectDir/playbooks/install-all.yml"
else
  Playbook="$ProjectDir/playbooks/install-services.yml"
fi

# Use a local-only inventory. Restrict the target even if ansible.cfg exists.
set -- \
  -i 'localhost,' \
  -c local \
  "$Playbook" \
  -e TARGET_HOSTS=localhost \
  -e "DOCKER_USER=$(id -un)"

if [ "$AskBecomePass" = true ] && [ "$(id -u)" -ne 0 ]; then
  set -- "$@" --ask-become-pass
fi

exec ansible-playbook "$@"
