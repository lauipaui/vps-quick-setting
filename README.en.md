# VPS Quick Setting Plus

[中文](README.md) | **English**

A lightweight initialization/baseline script for new VPS hosts, based on [chzzfly/vps-quick-setting](https://github.com/chzzfly/vps-quick-setting). Script version: `2.0.2`. Supports Debian/Ubuntu/Alpine, systemd/OpenRC, SSH settings, Fail2ban, chrony, optional Swap and dual-stack nftables input filtering.

> **This is a root script that changes behavior, not a read-only audit or universal optimization tool.** `--auto` means non-interactive, not a dry run. Evaluate the changes before running it on a live production host.

## Before running

- Keep a working provider console/out-of-band path and the current SSH session open.
- Install and independently test the intended login user's SSH key in another session.
- Back up SSH, nftables, Fail2ban, timezone, hostname and `/etc/fstab`; use a disk snapshot when appropriate.
- Inventory required business ports and Docker/router/WARP/Tailscale rules. Existing listeners alone do not describe every traffic requirement or safe exposure.
- Requires Bash (prepare it first on Alpine) and reachable package repositories; it installs packages and enables services.

**Key-detection limitation:** code searches for nonempty `authorized_keys` under `/root/.ssh` and `/home`. That does not prove the current login user's key works or that Include/Match settings are effective. Finding a file can trigger disabling password authentication. When none is found it retains password/root login to reduce lockout risk, not as a recommended permanent security policy.

## Review and run

```sh
git clone https://github.com/lauipaui/vps-quick-setting.git
cd vps-quick-setting
less vps-quick-setting.sh
bash -n vps-quick-setting.sh
bash vps-quick-setting.sh --help
# Only after review and access/backup checks
sudo bash vps-quick-setting.sh
```

Public remote entry (review it first; automatic mode for a new host):

```sh
curl -fsSL https://raw.githubusercontent.com/lauipaui/vps-quick-setting/main/vps-quick-setting.sh | sudo bash -s -- --auto
```

This documentation update did not run initialization, reconfigure SSH/firewalls or validate a live server.

## Options

| Option | Effect / default |
| --- | --- |
| `--auto` | No prompts, still modifies the system |
| `--hostname NAME` | Set hostname; automatic mode leaves it unchanged if omitted |
| `--timezone ZONE` | Default `Asia/Shanghai`; changes the timezone when the zone exists |
| `--ssh-port PORT` | Custom port 1024–65535; otherwise read the existing port, falling back to 22 |
| `--allow PORT/PROTO` | Additional `tcp`/`udp` allowance; repeatable |
| `--swap-mb MB` | Default 0; active existing Swap causes creation to be skipped |
| `--no-preserve-listeners` | Do not automatically allow detected listeners; default allowances remain |
| `--no-firewall` | Skip this project's firewall configuration, not the other changes |
| `-h`, `--help` | Help and exit, without initialization |

```sh
sudo bash vps-quick-setting.sh --auto --ssh-port 22222 --allow 443/tcp --allow 8443/udp
sudo bash vps-quick-setting.sh --auto --hostname edge-jp
sudo bash vps-quick-setting.sh --auto --swap-mb 2048
sudo bash vps-quick-setting.sh --auto --no-firewall
```

IPv6-only hosts use the same `inet` table; this does not provide a missing IPv4 path.

## What changes

- Installs base packages including OpenSSH, chrony, Fail2ban and nftables; enables time synchronization and Fail2ban.
- Writes `/etc/ssh/sshd_config.d/99-vps-quick-setting.conf`, adds Include when needed, validates with `sshd -t`, then reloads/restarts SSH. Syntax validity does not prove the desired port/policy wins precedence or Match blocks; inspect effective `sshd -T` and a fresh connection.
- Applies timezone, optional hostname, and optional `/swapfile` plus `/etc/fstab` entry.
- Writes `/etc/nftables.d/90-vps-quick-setting.nft`; table `inet vps_quick_setting` uses an input drop policy with loopback, established/related, ICMP and configured port allowances.
- By default permits SSH, 80/tcp, 443/tcp, detected existing listeners and all `--allow` entries. Automatic preservation may expose a previously private listener; for a stricter policy use `--no-preserve-listeners` and review the list. That option still leaves default 80/443 allowances.

At installation time the script replaces only its own table rather than reloading the full ruleset and does not add a rejecting forward chain. **That is not universal compatibility with other firewalls, Docker or tunnels.** Other input base-chain drops still apply; Docker published traffic may follow forward paths and bypass input filtering.

It can create `/etc/nftables.conf` containing `flush ruleset` and enable boot loading. Not flushing other tables during installation does not prove a later reload/reboot will preserve them. **Review full boot rules and Docker/WARP/Tailscale recovery ordering before rebooting.**

## Backup, acceptance and recovery

- Script backups: `/root/vps-quick-setting-backup/<timestamp>/`, principally selected preexisting SSH/nftables files. **Not a full-system backup**; package changes, timezone, hostname, Fail2ban, fstab and complete runtime rules are not all saved automatically.
- Baseline reports: `/root/baseline/<timestamp>-system-baseline.txt`. Redact addresses, ports and account paths before sharing.
- Keep old SSH open and independently check fresh key login, target port, business traffic, IPv4/IPv6 and time sync before closing it.
- SSH syntax failure attempts a local file rollback only. There is no general uninstall, dry-run or complete transactional rollback mode.
- Use a surviving session/console to restore your own recorded known-good settings, validate with `sshd -t` and `nft -c -f /etc/nftables.conf` (or the path of the ruleset you are restoring), then load appropriate services. Removing this project's table does not undo all changes; do not blindly flush unrelated rules.
- Swap removal needs a capacity/use/fstab review before swapoff or deletion; no universal production-safe removal command is supplied here.

## Attribution and licensing

Retains attribution to [chzzfly/vps-quick-setting](https://github.com/chzzfly/vps-quick-setting). No standalone `LICENSE` is included; do not assume unrestricted relicensing permission where upstream has not declared one. System components retain their own licenses and terms.
