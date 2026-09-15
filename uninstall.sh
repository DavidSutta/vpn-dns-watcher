#!/bin/bash
#
# uninstall.sh — removes vpn-dns-watcher and any resolver files it manages.
# Must be run with sudo.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this with sudo: sudo ./uninstall.sh"
    exit 1
fi

PLIST="/Library/LaunchDaemons/com.github.vpn-dns-watcher.plist"
MARKER="# Managed by vpn-dns-watcher -- do not edit manually"

launchctl bootout system "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

# Remove any resolver overrides this tool created
if [ -d /etc/resolver ]; then
    for f in /etc/resolver/*; do
        [ -f "$f" ] || continue
        if grep -qF "$MARKER" "$f" 2>/dev/null; then
            echo "Removing managed resolver file: $f"
            rm -f "$f"
        fi
    done
fi

dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

read -r -p "Also remove /usr/local/libexec/vpn-dns-watcher and /usr/local/etc/vpn-dns-watcher (config included)? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    rm -rf /usr/local/libexec/vpn-dns-watcher
    rm -rf /usr/local/etc/vpn-dns-watcher
    echo "Removed."
else
    echo "Left /usr/local/etc/vpn-dns-watcher (config) and binary in place."
fi

echo "Uninstalled."
