# Nextcloud All-in-One: local Ubuntu / Debian installer

This repository deploys the **official AIO mastercontainer**, not a complete
Nextcloud instance. Completing the initial setup requires the AIO web UI.

## Layout

- `install.sh`: local Ansible launcher, with sudo/become support.
- `playbooks/install-all.yml`: Docker + Nextcloud deployment entry point.
- `playbooks/install-docker.yml`: the supplied existing Docker installer, unchanged.
- `playbooks/install-nextcloud.yml`: validates and deploys AIO on localhost.
- `vars/nextcloud.yml`: source of deployment settings.
- `templates/docker-compose.yml.j2`: Ansible's deployed Compose source.
- `docker-compose.yml`: a rendered example using the included defaults. **It is not
  used by the installer**; change `vars/nextcloud.yml` instead.

## Before installation

Install Ansible on the machine where the command will run:

```sh
sudo apt update
sudo apt install -y ansible
```

For a new Ubuntu Server VM, run:

```sh
chmod +x install.sh
./install.sh
```

If Docker Engine and `docker compose` are already installed, use:

```sh
./install.sh --skip-docker
```

If sudo does not require a password (or you run as root), use
`--no-ask-become-pass` to suppress the password prompt.

The script always targets **localhost**. It does not SSH into a remote host.
It uses `sudo` via Ansible and does not execute `docker compose down -v`,
`docker volume rm`, or destructive application rebuilds.

## Storage

Set `NEXTCLOUD_DATADIR` in `vars/nextcloud.yml` before the first AIO
installation. Default: `/srv/nextcloud/data` **inside the Ubuntu VM**.
It is not necessarily a folder on the QEMU/KVM host.

If the data must be on a separately mounted disk, configure the actual mount
point and set `NEXTCLOUD_DATA_MOUNTPOINT` to enforce that it is mounted before
deployment. Example:

```yaml
NEXTCLOUD_DATADIR: /mnt/nextcloud-hdd/data
NEXTCLOUD_DATA_MOUNTPOINT: /mnt/nextcloud-hdd
```

The installer creates only the **parent** of the configured data directory.
AIO is responsible for creating/managing the data directory. Never change
`NEXTCLOUD_DATADIR` after installing Nextcloud without a documented migration.
The installer records the initial path and rejects subsequent changes.

AIO's Docker config is stored in the named volume
`nextcloud_aio_mastercontainer` on the guest VM's Docker installation.
Back up both this volume and Nextcloud application data using AIO's supported
backup procedure. A backup kept only on the same HDD does not protect against
physical disk failure.

## AIO administration and first-time setup

The mastercontainer admin UI listens on **127.0.0.1:8080** (HTTPS,
self-signed certificate). On the VM itself, open:

```text
https://127.0.0.1:8080
```

To connect from the QEMU/KVM host or any SSH-capable LAN client, forward
port 8080 from your client machine:

```sh
ssh -L 8080:127.0.0.1:8080 USER@VM_IP
```

Then open `https://127.0.0.1:8080` locally. Accept the self-signed
certificate warning for the AIO administration interface.

**AIO cannot complete the Nextcloud application setup with only an IP address.**
Nextcloud itself needs a domain and a valid HTTPS certificate, even for a
LAN-only installation. The official guide recommends the built-in free deSEC
`*.dedyn.io` registration, with Caddy and dnsmasq, or alternatives such as
Tailscale. The AIO panel walks through that step. Consult:

- https://github.com/nextcloud/all-in-one/blob/main/local-instance.md
- https://github.com/nextcloud/all-in-one

Port 80 of the guest is published. Port 8080 is deliberately loopback-only.
The managed Nextcloud Apache container may use port 443, so make sure 80/443
are not occupied by another service (for example, a Nextcloud snap).
Firewall and DNS/TLS network setup must be handled separately; this script
will not change your router, enable WAN port forwarding, or configure UFW.

## Check deployment

```sh
sudo docker compose -f /opt/nextcloud-aio/docker-compose.yml ps
sudo docker logs nextcloud-aio-mastercontainer --tail=100
sudo docker volume inspect nextcloud_aio_mastercontainer
```

## Limitations and safety

- Only Ubuntu/Debian local installations are targeted.
- Re-running the playbook preserves the named Docker volume and data path.
- It refuses to take over a preexisting unmanaged AIO mastercontainer.
- The Docker installer you provided edits the host Docker APT repository
  configuration and adds the invoking user to the `docker` group. Membership
  in that group grants near-root access; use `--skip-docker` if Docker is
  already correctly installed, and review that playbook before running it.
- Upgrades of AIO sibling containers are controlled from the AIO interface;
  updating the mastercontainer image is a separate maintenance action.
- The Docker socket bind mount gives the official AIO mastercontainer powerful
  host control despite being marked read-only; only use trusted AIO images.
