# Changelog

All notable changes to SwizGuard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- No traffic on servers running Xray v26.10+: Xray now blocks freedom-outbound connections to loopback by default, which dropped the VLESS → `127.0.0.1:51821` hop. Setup now adds a `finalRules` entry that allows only UDP to the local WireGuard port. Existing servers can apply it with the new `sudo ./swizguard fix-loopback`
- `swizguard add` aborting silently on the first client: under `set -o pipefail`, the IP-allocation `grep` found no peers and killed the script (upstream PR #2)
- sing-box client config rejected by sing-box 1.13+ (`legacy inbound fields ... removed in sing-box 1.13.0`): dropped the inbound `sniff` field, migrated DNS to the 1.12+ server format, made route actions explicit (upstream issue #3, PR #4). Validated with `sing-box check` on 1.12.12, 1.13.8, 1.13.11, 1.14.0 and 1.14.2
- Friendly error messages in `setup`, `rekey` and `regen` were unreachable when their `grep` matched nothing — `pipefail` exited first
- `regen-client-configs.sh` returning a failure status when `private.key` was absent

### Changed
- `xray-client.json` now answers DNS itself: DNS-over-HTTPS to 1.1.1.1 through the tunnel (the VPS no longer sees plaintext lookups), plus optional split DNS for home-network domains via `LAB_DOMAINS` / `LAB_DNS` in `credentials.env`
- Camouflage target can be set at install time with `CAMOUFLAGE_DEST=... ./swizguard setup` (default stays `www.microsoft.com`)
- Minimum sing-box version for mobile clients is now 1.12.3

## [1.0.0] — 2026-04-08

First public release.

### Added
- Full WireGuard + VLESS + REALITY + Vision chain, automated end to end
- Single-command server setup: `sudo ./swizguard setup`
- Client management commands: `add`, `regen`, `share`, `list`, `remove`
- Operational commands: `status`, `upgrade-vision`, `rekey`, `nuke`
- Desktop client generation (Xray JSON with `sockopt.dialerProxy` chain)
- Mobile client generation (sing-box JSON with `detour` chain) for iOS SFI and Android SFA
- VLESS share link + QR code output for fallback clients
- Vision flow (`xtls-rprx-vision`) enabled by default — closes TLS-in-TLS fingerprinting
- Auto-detect UFW and open only port 443/tcp when present
- Debian 13 (Trixie) compatibility including the new `ssh` service name and the LXC reload bug
- Default camouflage target: `www.microsoft.com` (Xray warns against Apple/iCloud targets)
- Access logging disabled on the server by default — no record of client destinations
- Userspace WireGuard on clients via gVisor (no sudo, no kernel module, no wg-quick)
- Systemwide proxy enable/disable helpers on macOS (`enable-system-proxy` / `disable-system-proxy`)
- Comprehensive documentation: README, how-it-works, setup-guide, troubleshooting
- MIT license, security policy, and disclaimer

### Technical details
- Server: Xray-core VLESS+REALITY+Vision inbound → freedom outbound → local WireGuard (`wg1` on `127.0.0.1:51821`)
- Desktop client: single Xray process, WireGuard outbound with `sockopt.dialerProxy` chaining through VLESS+REALITY+Vision
- Mobile client (iOS/Android): single sing-box process, `wireguard` endpoint with `detour` chaining through VLESS+REALITY+Vision
- Vision flow enabled on both sides with `"flow": "xtls-rprx-vision"` on VLESS client entries
- uTLS Chrome fingerprint on REALITY clients
- Sniffing enabled at server inbound with `routeOnly: true`

### Known limitations
- Shadowrocket (iOS) cannot do the chained outbound pattern — use SFI for full chain on iPhone
- Hiddify (iOS) only supports simple share links, not chained configs
- sing-box 1.12.2 has a DNS-through-proxy bug; use 1.12.3+ or 1.13.x
- SFI for iOS requires iOS 15+
- Full chain requires a client that supports raw sing-box or Xray JSON import

### Upstream dependencies
- Xray-core v26.x recommended (server and desktop client)
- sing-box 1.11+ required for `wireguard` endpoint form (mobile client)
- WireGuard (any modern version on Linux server)
