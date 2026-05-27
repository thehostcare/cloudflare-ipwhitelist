# cf-only

Restrict inbound HTTP/HTTPS traffic to [Cloudflare IPv4 ranges](https://www.cloudflare.com/ips-v4) only, using `ipset` + `iptables`.

Useful when your origin sits behind Cloudflare and you want to prevent attackers from bypassing the proxy by hitting the origin IP directly.

## Supported distributions

- Debian 11+
- Ubuntu 20.04+
- AlmaLinux 8/9
- Rocky Linux 8/9

## What it does

1. Detects the OS family (`apt-get` vs `dnf`) and installs `ipset`, `iptables`, and the persistence packages.
2. Creates an ipset named `cf4` populated from `https://www.cloudflare.com/ips-v4`.
3. Inserts two `iptables` rules on the `INPUT` chain:
   - `DROP` all traffic to ports 80/443.
   - `ACCEPT` traffic to ports 80/443 from any IP in the `cf4` set (inserted last, so it's evaluated first).
4. Saves the ruleset to the distro's persistence path so it survives reboot.
5. Installs `/etc/cron.daily/cf4-update` to refresh the Cloudflare list once a day.

The script is **idempotent** — re-running it removes any prior `cf4` ipset and matching `INPUT` rules before reapplying.

## Usage

```bash
curl -O https://raw.githubusercontent.com/<you>/<repo>/main/cf-only.sh
chmod +x cf-only.sh
sudo ./cf-only.sh
```

## Important notes

### RHEL-family: disable firewalld

AlmaLinux and Rocky ship with `firewalld` enabled, which conflicts with `iptables.service`. Disable it before running:

```bash
systemctl disable --now firewalld
```

### SSH and other ports

The rules only affect ports 80 and 443. SSH (22) and anything else are untouched. If you expose other services publicly, make sure they're not on 80/443.

### IPv6

This script handles IPv4 only. If your server has a public IPv6 address, traffic on `::/0` to ports 80/443 is **not** filtered. Either disable IPv6 on the interface or extend the script with an equivalent `ipset` + `ip6tables` setup using Cloudflare's [IPv6 list](https://www.cloudflare.com/ips-v6).

### Cron job

The daily job (`/etc/cron.daily/cf4-update`) flushes and repopulates `cf4` from Cloudflare's published list, then persists the set. If Cloudflare is unreachable when cron fires, the set is left empty and **all traffic to 80/443 will be dropped** until the next successful refresh. Add error handling if that's a concern for you.

## Verifying

```bash
# Confirm the set is populated
ipset list cf4 | head

# Confirm rules are in place
iptables -L INPUT -n --line-numbers | grep -E 'cf4|dpts:80'

# Test from a non-Cloudflare IP (should hang / fail)
curl -m 5 http://your-server-ip/

# Test through Cloudflare (should succeed)
curl https://your-domain/
```

## Uninstall

```bash
# Remove rules
iptables -D INPUT -m set --match-set cf4 src -p tcp -m multiport --dports http,https -j ACCEPT
iptables -D INPUT -p tcp -m multiport --dports http,https -j DROP

# Destroy the set
ipset destroy cf4

# Remove the cron job
rm -f /etc/cron.daily/cf4-update

# Persist the cleaned state
# Debian/Ubuntu:
iptables-save > /etc/iptables/rules.v4 && : > /etc/iptables/ipsets
# RHEL family:
iptables-save > /etc/sysconfig/iptables && : > /etc/sysconfig/ipset
```

## License

MIT
