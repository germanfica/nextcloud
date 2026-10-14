# Nextcloud AIO + Nginx Proxy Manager (Ansible)

An Ubuntu/Debian installer for **Nextcloud All-in-One (AIO)** and **Nginx Proxy Manager (NPM)**, using Docker Compose. Supports local installations, virtual machines, remote servers over SSH, and multi-host Ansible inventories.

**Scope:** Ansible installs/configures the AIO mastercontainer and NPM. You must finish Nextcloud's first-time setup, issue a trusted TLS certificate, and create the NPM proxy host through their respective web UIs. This project does not automatically configure DNS, firewall rules, routers, backups, ACME accounts, or the Nextcloud application.

## Network overview

```text
Client -- HTTPS (your-domain.example) --> NPM on TARGET_BIND_IP:443
                                         |
                                         | Docker bridge: nextcloud-proxy
                                         v
                                   nextcloud-aio-apache:11000
                                         |
                                         v
                                   Nextcloud AIO containers

SSH tunnel --> target 127.0.0.1:8080 --> AIO admin (HTTPS)
SSH tunnel --> target 127.0.0.1:81   --> NPM admin (HTTP)
```

AIO and NPM share an internal Docker network. Only NPM serves client HTTPS. AIO's admin (8080) and NPM's admin (81) bind to **127.0.0.1 on the target host**. Nextcloud's Apache port is bound to the target host's loopback by AIO. NPM accesses Apache over the shared Docker network, not via the VM IP or host localhost.

Docker Engine may publish ports outside UFW's expected filtering path. Protect interfaces with your infrastructure firewall and routing; merely choosing a private IP is not equivalent to access control.

## Project files

| Path | Purpose |
|---|---|
| `install.sh` | Local machine launcher (Docker + services, or `--skip-docker`) |
| `playbooks/deploy-remote.yml` | Remote SSH deploy, Docker already installed |
| `playbooks/deploy-remote-all.yml` | Remote SSH deploy, including Docker installation |
| `playbooks/install-all.yml` | Docker, AIO, then NPM |
| `playbooks/install-services.yml` | AIO and NPM without installing Docker |
| `playbooks/install-docker.yml` | Official Docker APT repo/Engine/Compose |
| `playbooks/install-nextcloud.yml` | Official AIO mastercontainer |
| `playbooks/install-nginx-proxy-manager.yml` | Separate NPM Compose project |
| `vars/nextcloud.yml`, `vars/nginx-proxy-manager.yml` | Committed cross-user defaults |
| `vars/site.yml.example` | Public sample for local per-deployment overrides |
| `vars/site.yml` | Optional local overrides, **gitignored**, never commit |
| `templates/*.j2` | Compose templates rendered directly on the target |

**There is intentionally no root `docker-compose.yml`.** Compose configuration is generated into `/opt/nextcloud-aio/docker-compose.yml` and `/opt/nginx-proxy-manager/docker-compose.yml` on the **target**, using the vars. Do not use an obsolete root Compose file left over from an earlier version.

## Prerequisites

- Ubuntu or Debian target, x86-64 or ARM64, with SSH and Python 3 (for remote use).
- A controller with Ansible installed (`sudo apt install ansible` on Ubuntu/Debian). For local installation, the controller and target are the same machine.
- SSH access with a user permitted to use sudo (`-K` prompts for that user's sudo password). SSH keys are recommended. No password or key is kept in this repository.
- A TCP/443 path from clients to NPM and a DNS name under your control resolving to the address clients can reach. Private-only deployments can use split-horizon DNS or `/etc/hosts`, plus ACME DNS-01 for trusted TLS.
- Outbound Internet access for image downloads and certificate issuance, plus enough disk space and backup capacity for user data.
- Ensure target ports 80/443 are not in use. SSH is needed for the two admin tunnels. Existing Nextcloud AIO instances require care (see *Safety and upgrades*).

If Docker already works on the target, **skip the Docker installer**; the Docker installer configures the host's APT repository. Installing Docker from scratch may conflict with manually installed packages or older sources. The Docker playbook refuses to delete legacy APT source definitions automatically.

## Configuration: no hardcoded server IP

The default `NPM_BIND_IP: auto` selects `ansible_facts.default_ipv4.address` **on each target machine**. This is the target's IPv4 used for its default route, not the IP of your Ansible controller. Virtual machines using NAT networking typically select their private guest address; hosts with multiple network interfaces may need a manual override. A dynamically assigned IP can change; reserve DHCP/static addressing and update private DNS where appropriate.

By default the playbook **refuses to publish NPM web ports on a public IPv4 address**. To intentionally use a public interface, explicitly configure `NPM_BIND_IP` and `NPM_ALLOW_PUBLIC_BIND: true`, and secure your network/firewall first. It **never** publishes the NPM admin panel on a non-loopback address.

For one deployment, optionally create a gitignored configuration on the **Ansible controller**:

```bash
cp vars/site.yml.example vars/site.yml
vim vars/site.yml
```

Example (replace placeholders; `cloud.example.com` is a documentation-only domain and cannot be used for your certificates):

```yaml
---
NEXTCLOUD_DOMAIN: cloud.example.com
NPM_BIND_IP: auto                    # Or your TARGET's private IPv4 on a multi-NIC host
NPM_TIMEZONE: Etc/UTC
NEXTCLOUD_SKIP_DOMAIN_VALIDATION: true  # Only after setting up private HTTPS + DNS-01
```

`NEXTCLOUD_DOMAIN` is informational for Ansible; enter your actual domain in the AIO/NPM interfaces. `NEXTCLOUD_SKIP_DOMAIN_VALIDATION` defaults to **false**; set it to true only for a correctly configured private DNS-01 setup where AIO's public reachability check cannot work. This flag does **not** bypass TLS, authentication, or DNS configuration.

On multi-host inventories the same `site.yml` applies to every target. If they need different IPs, keep `NPM_BIND_IP: auto` or provide per-run Ansible extra-vars; do not put deployment secrets in inventory committed to Git. `-e` overrides defaults and `site.yml`.

For data on a mounted disk, set `NEXTCLOUD_DATADIR` and `NEXTCLOUD_DATA_MOUNTPOINT` **before the first install**, for example:

```yaml
NEXTCLOUD_DATADIR: /mnt/nextcloud-hdd/data
NEXTCLOUD_DATA_MOUNTPOINT: /mnt/nextcloud-hdd
```

Ansible checks that the configured mount exists and refuses to silently change the data directory after deployment. The default storage is `/srv/nextcloud/data` on the **target OS** (not necessarily the physical hypervisor).

## Install locally (physical or virtual machine)

On the machine where Nextcloud will run:

```bash
sudo apt update && sudo apt install -y ansible
./install.sh --skip-docker                  # Existing Docker Engine + Compose
# or:
./install.sh                                # Fresh machine; also installs Docker
```

`--no-ask-become-pass` is available for passwordless sudo/root. By default the installer prompts for the local sudo password. Docker group access is **not** automatically granted (it is effectively root access); if required, enable `DOCKER_ADD_USER_TO_GROUP: true` and specify `DOCKER_USER` in `vars/site.yml` before the initial Docker installation.

## Deploy to a remote server over SSH

Run the commands from the **controller**, in the directory containing this repository. The IPs below come from [RFC 5737](https://www.rfc-editor.org/rfc/rfc5737) and are illustrative; **replace them with the destination**.

**Docker already installed** (equivalent to the old `--skip-docker` remote path):

```bash
ansible-playbook -i '192.0.2.10,' -u username -K playbooks/deploy-remote.yml
```

**Fresh remote server** (install Docker + both services):

```bash
ansible-playbook -i '192.0.2.10,' -u username -K playbooks/deploy-remote-all.yml
```

**Multiple servers or a normal inventory:**

```bash
ansible-playbook -i inventory.ini -u username -K --limit nextcloud_hosts playbooks/deploy-remote.yml
```

Use `-k` only if SSH password authentication is required. `-K` prompts for privilege escalation, not SSH login. Put SSH credentials in your SSH agent/SSH config or use Ansible Vault, **not** in tracked YAML. For a single SSH target, the trailing comma in `-i '192.0.2.10,'` tells Ansible it is an inline inventory rather than a filename.

Remote deployment **does not upload/extract the project** on the target, run an interactive script over `expect`, delete `~/nextcloud`, or generate a `nextcloud.tar.xz`. Ansible transfers only the necessary modules/templates and renders Compose files into their configured persistent target directories. It can be rerun as needed. Local `vars/site.yml` is read by the controller.

`playbooks/install-nextcloud.yml` and `playbooks/install-nginx-proxy-manager.yml` can also be run individually for maintenance, provided Docker and the shared proxy network are ready. Run Nextcloud's playbook before the NPM playbook.

## Finish the browser-based setup

1. **AIO admin:** from your client, create a tunnel:

   ```bash
   ssh -L 8080:127.0.0.1:8080 username@192.0.2.10
   ```

   Open `https://localhost:8080`, acknowledge the initial self-signed administration certificate if prompted, enter your configured domain, and follow AIO's installation wizard.

2. **NPM admin:** in a different terminal:

   ```bash
   ssh -L 8181:127.0.0.1:81 username@192.0.2.10
   ```

   Open `http://localhost:8181`, change initial account credentials, and configure certificate and proxy settings.

3. **TLS certificate:** for a private-only deployment with no inbound public connections, use an ACME **DNS-01** challenge from a DNS provider supported by your NPM installation. DNS provider API credentials belong in the protected NPM UI/state, never in Ansible vars, public repositories, or screenshots. DNS-01 still requires a **publicly delegated domain you control**, functional API credentials, and correct authoritative DNS. Providers may enforce outbound source-IP allowlists. For publicly accessible deployments, a supported HTTP challenge may also be an option if reachability is configured.

4. **NPM Proxy Host:** set your domain, forward **HTTP** to `nextcloud-aio-apache` on port **11000** (or the configured `NEXTCLOUD_APACHE_PORT`), enable WebSockets, attach your certificate, and force HTTPS. Suggested Advanced directives:

   ```nginx
   client_max_body_size 0;
   proxy_read_timeout 3610s;
   proxy_request_buffering off;
   ```

NPM and the managed AIO Apache container join the Docker network `nextcloud-proxy`. A `502` is normal until the AIO wizard starts the Apache container. AIO's reverse-proxy and domain documentation is authoritative if upstream requirements change.

For a **private network**, configure DNS for your clients and any necessary route to the target: a local DNS rewrite, local hosts entry, or split-horizon DNS. Illustrative hosts entry (replace both values):

```text
192.0.2.10 cloud.example.com
```

This RFC 5737 address is **not a working LAN address**. With libvirt's default NAT network, the hypervisor can normally reach the VM, but other LAN clients might need a bridge, routing, or a VPN. Do **not** assume a guest NAT IP is accessible from other devices.

### Safety and upgrades

- The installer does **not** use `docker compose down -v`, prune volumes, or delete application data. Keep separate, tested backups of the AIO mastercontainer volume, Nextcloud data, and `/opt/nginx-proxy-manager/{data,letsencrypt}`. A copy only on the same disk is insufficient.
- The official AIO mastercontainer requires the `nextcloud_aio_mastercontainer` volume and Docker socket. The Docker socket confers powerful host privileges despite the `:ro` mount: restrict target host administration.
- Repeated deploys reject a detected unmanaged AIO/NPM container instead of unconditionally taking it over. If upgrading an existing non-managed stack, plan migration rather than pointing this playbook at it without review.
- NPM image is version-pinned to `2.16.0` in public defaults; audit updates, plan downtime, and back up before changing tags. AIO mastercontainer uses the official release channel; update sibling containers through the AIO UI.
- Network readdressing: rerun the playbook after changing the target IP so NPM's port publishing updates; also update routing/DNS/hosts for clients. On a public IP, you must explicitly opt into public binding and configure the firewall before deployment.
- Docker's APT installer will not delete legacy Docker repo definitions. Existing package managers and Docker installations may need manual inspection before a fresh install.
- `vars/site.yml` is excluded from Git, **but `.gitignore` does not erase previously committed history**. If you already committed environment-specific IPs, domains, SSH names, or credentials, examine your Git history and remove sensitive information there as appropriate. Rotate actual credentials if exposed.
- The repository deliberately omits earlier hardcoded Compose files and archive-based remote deployment behavior. If merging into an existing Git checkout, remove stale tracked `docker-compose.yml` and obsolete secrets manually before publishing.

## References

- [Official Nextcloud AIO](https://github.com/nextcloud/all-in-one)
- [Official AIO reverse-proxy guide](https://github.com/nextcloud/all-in-one/blob/main/reverse-proxy.md)
- [Official AIO local instance guide](https://github.com/nextcloud/all-in-one/blob/main/local-instance.md)
- [Nginx Proxy Manager documentation](https://nginxproxymanager.com/setup/)
- [RFC 5737 documentation IPv4 blocks](https://www.rfc-editor.org/rfc/rfc5737)
