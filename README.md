# BitcoinII Quick Installer

<p align="center">
  <img src="img/bc2-logo.png" alt="BitcoinII" width="300" />
</p>

This repo provides two scripts to install and configure BitcoinII on Linux.

## Quick Start
- One‑liner install (fetches the full installer from GitHub and runs it with sudo):
  - `bash -c "$(wget -qO- https://raw.githubusercontent.com/skaisser/bitcoinii-node-installer/main/bitcoinii-full-install.sh)"`  (or)
  - `curl -fsSL https://raw.githubusercontent.com/skaisser/bitcoinii-node-installer/main/bitcoinii-full-install.sh | sudo bash`

- Full install (download + configure + service + UFW):
  - `sudo bash bitcoinii-full-install.sh`
  - Select mode: `1` Mining (pruned, wallet off, blocksonly) or `2` Full node (txindex=1, wallet off, no prune).
- Setup only (you already placed binaries in `~/.bitcoinII`):
  - `sudo bash bitcoinii-setup.sh`
  - Writes `~/.bitcoinII/bitcoinII.conf`, configures service, UFW, and CLI wrappers.

## Compatibility

| Distro | Status |
|---|---|
| Ubuntu 24.04 LTS (Noble) | ✅ Tested |
| Ubuntu 22.04 LTS (Jammy) | ❌ Not supported |

Also works on recent Debian-based systems with `systemd` and `ufw` available.

## Check Progress
- Service status: `systemctl status bitcoiniid --no-pager`
- Live logs: `journalctl -u bitcoiniid -f`
- Node info: `bitcoinII-cli -getinfo`
- Sync status: `bitcoinII-cli getblockchaininfo`
- Full node index (if enabled): `bitcoinII-cli getindexinfo`

## Global CLI
- The installer automatically adds `bitcoinII-cli` and `bitcoinii-cli` wrappers to `/usr/local/bin` with the correct `-datadir` and `-conf`.

## Notes
- Config is tuned to your machine (dbcache, mempool, prune, parallelism) and avoids Bitcoin Core port conflicts.
- UFW is configured: SSH open, P2P allowed, RPC/ZMQ allowed only from your local subnet.
- RPC credentials: `rpcuser=bitcoinII` and a generated secure password shown at the end of the run. Keep it safe.
