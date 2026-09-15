# vpn-dns-watcher

A tiny macOS root daemon that automatically manages `/etc/resolver/<domain>`
split-DNS overrides based on whether a VPN tunnel is actually up — no
hooks required from the VPN client itself.

## Why

Many macOS VPN clients (Azure VPN Client included) are built on Apple's
Network Extension framework and don't expose any pre/post-connect
scripting hooks the way older OpenVPN-based clients did. This makes it
hard to automatically switch DNS resolution for specific internal domains
(e.g. private-endpoint-backed Azure services) on and off as you connect
and disconnect.

`vpn-dns-watcher` sidesteps this by not needing a hook at all: it polls
the routing table every few seconds and asks, for each domain you
configure, *"is this domain's DNS server currently reachable through a
VPN tunnel interface?"* If yes, it writes the matching `/etc/resolver`
override. If no, it removes it. Your normal DNS resolution is otherwise
untouched.

## Requirements

- macOS
- [`yq`](https://github.com/mikefarah/yq) (the Go version, by mikefarah):
  ```bash
  brew install yq
  ```

## Install

```bash
git clone <this-repo> vpn-dns-watcher
cd vpn-dns-watcher
sudo ./install.sh
```

This installs:

| What | Where |
|---|---|
| Watcher script | `/usr/local/libexec/vpn-dns-watcher/vpn-dns-watcher.sh` |
| Config | `/usr/local/etc/vpn-dns-watcher/config.yml` |
| Logs | `/usr/local/var/log/vpn-dns-watcher.log` |
| LaunchDaemon | `/Library/LaunchDaemons/com.github.vpn-dns-watcher.plist` |

It runs as **root** (via LaunchDaemon, not a per-user LaunchAgent), which
is required to write to `/etc/resolver/` and flush the DNS cache — this
avoids needing any passwordless-sudo configuration.

## Configuring hosts

Edit `/usr/local/etc/vpn-dns-watcher/config.yml`:

```yaml
hosts:
  - domain: database.windows.net
    nameservers:
      - 10.0.0.53

  - domain: privatelink.blob.core.windows.net
    nameservers:
      - 10.0.0.53
      - 168.63.129.16
```

- `domain` — the DNS suffix to override (matches how `/etc/resolver`
  files work; this becomes the filename).
- `nameservers` — one or more DNS servers to use for that domain **while
  at least one of them is reachable through a `utun*` interface**.

No restart is needed after editing — the daemon re-reads the config on
every poll (every 5 seconds by default; change `StartInterval` in the
plist and re-run `install.sh` to adjust).

You can add as many host entries as you like, pointing at different DNS
servers for different VPNs — detection is per-entry, so this scales to
multiple unrelated tunnels without any extra configuration.

## How detection works

For each configured nameserver IP, the watcher runs:

```bash
route -n get <nameserver-ip>
```

and checks whether the interface macOS would actually use to reach that
IP starts with `utun`. If so, the tunnel is considered "up" for that
entry, regardless of which specific VPN client created it. This avoids
hardcoding a particular `utun` number (which can change between VPN
sessions) or depending on a specific VPN app's naming.

## Logs

```bash
tail -f /usr/local/var/log/vpn-dns-watcher.log
```

## Uninstall

```bash
sudo ./uninstall.sh
```

Removes the LaunchDaemon and any `/etc/resolver` files this tool
created (identified by an internal marker comment — your own manually
created resolver files are left untouched).

## Caveats

- Polling interval is a trade-off: shorter intervals react faster to
  connect/disconnect but wake the CPU more often. 5 seconds is a
  reasonable default for interactive dev use.
- This only manages DNS resolution for the domains you list — it does
  not touch routing tables. If your VPN client also has a forced-tunnel
  routing gap (traffic not actually going through the tunnel even after
  DNS resolves correctly), that's a separate problem to solve on the
  VPN client / gateway side.
- IPv6 is not addressed by this tool.

## License

MIT — see [LICENSE](LICENSE).
