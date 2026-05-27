#!/bin/bash
set -e

# Detect package manager / OS family
if command -v apt-get &>/dev/null; then
    OS_FAMILY="debian"
elif command -v dnf &>/dev/null; then
    OS_FAMILY="rhel"
else
    echo "Unsupported OS: need apt-get or dnf" >&2
    exit 1
fi

# Install dependencies
case "$OS_FAMILY" in
    debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y ipset iptables curl iptables-persistent ipset-persistent
        IPSET_SAVE="/etc/iptables/ipsets"
        IPTABLES_SAVE="/etc/iptables/rules.v4"
        mkdir -p /etc/iptables
        ;;
    rhel)
        dnf install -y ipset ipset-service iptables-services curl
        systemctl enable --now ipset.service iptables.service
        IPSET_SAVE="/etc/sysconfig/ipset"
        IPTABLES_SAVE="/etc/sysconfig/iptables"
        mkdir -p /etc/sysconfig
        ;;
esac

# Remove existing iptables rules referencing cf4 (idempotent)
while iptables -C INPUT -m set --match-set cf4 src -p tcp -m multiport --dports http,https -j ACCEPT 2>/dev/null; do
    iptables -D INPUT -m set --match-set cf4 src -p tcp -m multiport --dports http,https -j ACCEPT
done
while iptables -C INPUT -p tcp -m multiport --dports http,https -j DROP 2>/dev/null; do
    iptables -D INPUT -p tcp -m multiport --dports http,https -j DROP
done

# Destroy existing ipset if present
if ipset list cf4 &>/dev/null; then
    ipset destroy cf4
fi

# Create + populate ipset
ipset create cf4 hash:net
for x in $(curl -s https://www.cloudflare.com/ips-v4); do
    ipset add cf4 "$x"
done

# Apply iptables rules (ACCEPT inserted last → ends up on top)
iptables -I INPUT -p tcp -m multiport --dports http,https -j DROP
iptables -I INPUT -m set --match-set cf4 src -p tcp -m multiport --dports http,https -j ACCEPT

# Persist
ipset save > "$IPSET_SAVE"
iptables-save > "$IPTABLES_SAVE"

# Daily update job
cat <<EOF >/etc/cron.daily/cf4-update
#!/bin/bash
ipset flush cf4
for x in \$(curl -s https://www.cloudflare.com/ips-v4); do
    ipset add cf4 "\$x"
done
ipset save > "$IPSET_SAVE"
EOF
chmod +x /etc/cron.daily/cf4-update