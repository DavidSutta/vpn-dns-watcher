# vpn-dns-watcher

Automatically turns macOS split-DNS overrides on when your VPN connects,
and off when it disconnects — without any help from the VPN client.

## The problem this solves

You connect to a corporate VPN to reach an internal service. The tunnel
is up, but the name still resolves to the wrong address — a public IP, or
nothing at all — so every connection hangs or is refused:

```
$ nslookup myservice.internal.example.com
Address: 203.0.113.10          # public IP, not the private one behind the VPN

$ psql -h myservice.internal.example.com
psql: error: connection to server ... failed: Operation timed out
```

The fix is a `/etc/resolver/<domain>` file telling macOS to resolve that
domain through the VPN's private DNS server. But it has to be created
when you connect and **deleted when you disconnect** — leave it in place
off-VPN and every lookup for that domain hangs against an unreachable
nameserver.

Older VPN clients let you script this with connect/disconnect hooks.
Modern macOS clients built on Apple's Network Extension framework (the
Azure VPN Client among them) expose no such hooks, so you are left doing
it by hand, with sudo, several times a day.

`vpn-dns-watcher` does it for you.

## How it works

It needs no hook because it never asks the VPN client anything. A root
LaunchDaemon wakes every 5 seconds and, for each domain you configured,
runs `route -n get <nameserver-ip>` to ask which interface macOS would
use to reach that nameserver. If the answer is a `utun*` interface, the
tunnel is up: write the resolver file. If not: remove it.

Two useful consequences:

- **Works with any VPN client**, since nothing depends on app names or on
  a specific `utun` number (those change between sessions).
- **Handles several VPNs at once**, since each entry is tested on its own.

It only writes when something actually changed, and only touches files
carrying its own marker comment — resolver files you wrote yourself are
never modified or deleted.

## Install

Requires [`yq`](https://github.com/mikefarah/yq) (`brew install yq`).

```bash
git clone <this-repo> vpn-dns-watcher
cd vpn-dns-watcher
sudo ./install.sh
```

| What | Where |
|---|---|
| Watcher script | `/usr/local/libexec/vpn-dns-watcher/vpn-dns-watcher.sh` |
| Config | `/usr/local/etc/vpn-dns-watcher/config.yml` |
| Log | `/usr/local/var/log/vpn-dns-watcher.log` |
| LaunchDaemon | `/Library/LaunchDaemons/com.github.vpn-dns-watcher.plist` |

It runs as root because writing `/etc/resolver/` and flushing the DNS
cache require it — this avoids configuring passwordless sudo.

## Configure

The shipped config is empty. Add your domains to
`/usr/local/etc/vpn-dns-watcher/config.yml`:

```yaml
hosts:
  - domain: internal.example.com
    nameservers:
      - 10.0.0.53

  - domain: db.internal.example.com
    nameservers:
      - 10.0.0.53
      - 10.0.1.53
```

- `domain` — the DNS suffix to override; this becomes the
  `/etc/resolver/` filename.
- `nameservers` — the DNS server(s) to use for it, listed in priority
  order. These should be servers that are only reachable over the VPN.

No restart needed; the daemon re-reads the config on the next poll.
To change the 5-second interval, edit `StartInterval` in the plist and
re-run `install.sh`.

## Check it

```bash
tail -f /usr/local/var/log/vpn-dns-watcher.log
```

```
2026-01-15 09:12:03 Applied resolver override for internal.example.com -> 10.0.0.53 (via utun4)
2026-01-15 17:40:18 Removed resolver override for internal.example.com (no tunnel route to its DNS server)
```

## Uninstall

```bash
sudo ./uninstall.sh
```

Removes the daemon and the resolver files it created, then offers to
remove the config.

## Limits

- DNS only. If traffic still fails after the name resolves correctly,
  that is a routing problem on the VPN client or gateway, not here.
- IPv6 is not handled.
- Shorter poll intervals react faster but wake the CPU more often.

## License

MIT — see [LICENSE](LICENSE).
