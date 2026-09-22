#!/bin/bash
#
# vpn-dns-watcher.sh
#
# Reconciles /etc/resolver/<domain> overrides against config.yml based on
# whether each entry's DNS server(s) are currently reachable via a utun
# (VPN) interface. Designed to be run periodically as a root LaunchDaemon.
#
# Safe to run repeatedly; only writes/removes files and flushes DNS cache
# when something actually changed.

set -uo pipefail

CONFIG_FILE="${VPN_DNS_WATCHER_CONFIG:-/usr/local/etc/vpn-dns-watcher/config.yml}"
LOG_FILE="${VPN_DNS_WATCHER_LOG:-/usr/local/var/log/vpn-dns-watcher.log}"
RESOLVER_DIR="${VPN_DNS_WATCHER_RESOLVER_DIR:-/etc/resolver}"
MARKER="# Managed by vpn-dns-watcher -- do not edit manually"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

fail() {
    log "ERROR: $*"
    exit 1
}

command -v yq >/dev/null 2>&1 || fail "yq not found in PATH (install with: brew install yq)"
[ -f "$CONFIG_FILE" ] || fail "config file not found at $CONFIG_FILE"

mkdir -p "$(dirname "$LOG_FILE")"

changed=0
declared_domains=()

host_count="$(yq -r '.hosts | length' "$CONFIG_FILE" 2>/dev/null)"
if ! [[ "$host_count" =~ ^[0-9]+$ ]]; then
    fail "could not parse 'hosts' array from $CONFIG_FILE"
fi

# C-style loop, not `seq 0 $((n-1))`: BSD seq counts *down* when the
# first value exceeds the last, so an empty hosts list would iterate over
# 0 and -1 instead of not iterating at all.
for ((i = 0; i < host_count; i++)); do
    domain="$(yq -r ".hosts[$i].domain" "$CONFIG_FILE")"

    if [ -z "$domain" ] || [ "$domain" == "null" ]; then
        log "WARNING: hosts[$i] has no domain, skipping"
        continue
    fi

    nameservers=()
    while IFS= read -r line; do
        [ -n "$line" ] && nameservers+=("$line")
    done < <(yq -r ".hosts[$i].nameservers[]" "$CONFIG_FILE" 2>/dev/null)

    if [ "${#nameservers[@]}" -eq 0 ]; then
        log "WARNING: hosts[$i] ($domain) has no nameservers, skipping"
        continue
    fi

    declared_domains+=("$domain")

    vpn_up=0
    matched_iface=""
    for ns in "${nameservers[@]}"; do
        iface="$(route -n get "$ns" 2>/dev/null | awk '/interface:/{print $2}')"
        if [[ "$iface" == utun* ]]; then
            vpn_up=1
            matched_iface="$iface"
            break
        fi
    done

    resolver_file="$RESOLVER_DIR/$domain"

    if [ "$vpn_up" -eq 1 ]; then
        desired_content="$MARKER"$'\n'
        for ns in "${nameservers[@]}"; do
            desired_content+="nameserver $ns"$'\n'
        done

        # Byte-exact comparison: command substitution strips trailing
        # newlines, which would make an unchanged file always look different
        # and cause a needless rewrite plus DNS flush on every poll.
        if ! printf '%s' "$desired_content" | cmp -s - "$resolver_file"; then
            printf '%s' "$desired_content" > "$resolver_file"
            log "Applied resolver override for $domain -> ${nameservers[*]} (via $matched_iface)"
            changed=1
        fi
    else
        if [ -f "$resolver_file" ] && grep -qF "$MARKER" "$resolver_file" 2>/dev/null; then
            rm -f "$resolver_file"
            log "Removed resolver override for $domain (no tunnel route to its DNS server)"
            changed=1
        fi
    fi
done

# Clean up managed files for domains no longer present in config.yml
if [ -d "$RESOLVER_DIR" ]; then
    for f in "$RESOLVER_DIR"/*; do
        [ -f "$f" ] || continue
        fname="$(basename "$f")"
        grep -qF "$MARKER" "$f" 2>/dev/null || continue

        found=0
        for d in "${declared_domains[@]:-}"; do
            if [ "$d" == "$fname" ]; then
                found=1
                break
            fi
        done

        if [ "$found" -eq 0 ]; then
            rm -f "$f"
            log "Removed stale managed resolver for $fname (no longer in config)"
            changed=1
        fi
    done
fi

if [ "$changed" -eq 1 ]; then
    dscacheutil -flushcache 2>/dev/null || true
    killall -HUP mDNSResponder 2>/dev/null || true
    log "Flushed DNS cache due to changes"
fi

exit 0
