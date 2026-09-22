#!/bin/bash
#
# install.sh — installs vpn-dns-watcher as a root LaunchDaemon.
# Must be run with sudo.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this with sudo: sudo ./install.sh"
    exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "yq is required but was not found in PATH."
    echo "Install it first (as your normal user, not root):"
    echo "    brew install yq"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="/usr/local/libexec/vpn-dns-watcher"
ETC_DIR="/usr/local/etc/vpn-dns-watcher"
LOG_DIR="/usr/local/var/log"
PLIST_DEST="/Library/LaunchDaemons/com.github.vpn-dns-watcher.plist"

mkdir -p "$BIN_DIR" "$ETC_DIR" "$LOG_DIR"

install -m 755 "$REPO_DIR/bin/vpn-dns-watcher.sh" "$BIN_DIR/vpn-dns-watcher.sh"

if [ ! -f "$ETC_DIR/config.yml" ]; then
    install -m 644 "$REPO_DIR/config.yml" "$ETC_DIR/config.yml"
    echo "Installed default config to $ETC_DIR/config.yml"
    echo "  -> Edit this file to add your own domain/nameserver entries."
else
    echo "Existing config found at $ETC_DIR/config.yml — leaving it untouched."
fi

install -m 644 "$REPO_DIR/launchd/com.github.vpn-dns-watcher.plist" "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"

# launchd refuses to bootstrap a quarantined daemon, failing with the
# unhelpful "Bootstrap failed: 5: Input/output error". `install` copies
# extended attributes along with the file, so a com.apple.quarantine flag
# on the checked-out plist follows it into /Library/LaunchDaemons.
xattr -d com.apple.quarantine "$PLIST_DEST" 2>/dev/null || true
xattr -d com.apple.quarantine "$BIN_DIR/vpn-dns-watcher.sh" 2>/dev/null || true

# Unload first in case of re-install, ignore errors if not currently loaded
launchctl bootout system "$PLIST_DEST" 2>/dev/null || true

if ! launchctl bootstrap system "$PLIST_DEST"; then
    echo ""
    echo "launchctl could not start the daemon (see the error above)."
    echo "Things worth checking:"
    echo "  - Is it already running?   sudo launchctl print system/com.github.vpn-dns-watcher"
    echo "  - Is it disabled?          sudo launchctl print-disabled system | grep vpn-dns"
    echo "  - Any leftover quarantine? xattr $PLIST_DEST"
    exit 1
fi

echo ""
echo "Installed and started vpn-dns-watcher."
echo "  Config: $ETC_DIR/config.yml"
echo "  Logs:   $LOG_DIR/vpn-dns-watcher.log"
echo ""
echo "It polls every 5 seconds and requires no further action —"
echo "edit the config file any time; changes apply on the next poll."
