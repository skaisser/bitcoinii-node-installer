# BitcoinII Smart Node Installer

<p align="center">
  <img src="img/bc2-logo.png" alt="BitcoinII" width="300" />
</p>

<p align="center">
  <strong>Intelligent, automated BitcoinII node deployment for Linux systems</strong>
</p>

<p align="center">
  <a href="https://bitcoin-ii.org/">Official Website</a> •
  <a href="https://bitcoinii.ddns.net/explorer/">Explorer</a> •
  <a href="https://bitcoinii.ddns.net/NodeMap.html">Node Map</a> •
  <a href="https://bitcoinii.ddns.net/DailyReport.html">Daily Report</a>
</p>

---

## 🚀 One-Command Installation

Simply copy and run this command in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/skaisser/bitcoinii-node-installer/main/bitcoinii-full-install.sh | sudo bash
```

Or if you prefer `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/skaisser/bitcoinii-node-installer/main/bitcoinii-full-install.sh | sudo bash
```

That's it! The smart installer will handle everything automatically.

## 🧠 Smart Installation Features

This is not just another installer script. Our **SMART Installer** automatically:

- **🔍 Analyzes your system** - Detects available resources (RAM, CPU cores, disk space)
- **⚙️ Optimizes configuration** - Automatically tunes `dbcache`, `mempool`, `prune` settings, and parallelism based on YOUR machine
- **🛡️ Configures security** - Sets up UFW firewall rules intelligently (SSH preserved, P2P allowed, RPC restricted to local subnet)
- **🔧 Creates systemd service** - Professional-grade service management with automatic startup and restart on failure
- **🔗 Installs global CLI access** - Creates symlinks in `/usr/local/bin` so you can run `bitcoinII-cli` from anywhere
- **🎯 Avoids port conflicts** - Intelligently configures ports to avoid conflicts with Bitcoin Core or other services

## 📦 Installation Options

### Option 1: Full Automated Install (Recommended)
The one-command installation above handles everything:
- Downloads BitcoinII binaries
- Configures based on your system specs
- Sets up systemd service
- Configures firewall
- Creates CLI symlinks

### Option 2: Manual Full Install
```bash
git clone https://github.com/skaisser/bitcoinii-node-installer
cd bitcoinii-node-installer
sudo bash bitcoinii-full-install.sh
```
Choose your node type when prompted:
- **Mining Node** - Pruned blockchain, optimized for mining
- **Full Node** - Complete blockchain with transaction indexing

### Option 3: Configuration Only
If you've already downloaded the binaries to `~/.bitcoinII`:
```bash
sudo bash bitcoinii-setup.sh
```

## 🖥️ System Requirements

| Component | Minimum | Recommended |
|---|---|---|
| **OS** | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| **RAM** | 4 GB | 8 GB+ |
| **Storage** | 50 GB (pruned) | 500 GB+ (full node) |
| **CPU** | 2 cores | 4+ cores |
| **Network** | Broadband | Unlimited bandwidth |

### Tested Compatibility
| Distribution | Version | Status |
|---|---|---|
| Ubuntu | 24.04 LTS (Noble) | ✅ Fully Tested |
| Ubuntu | 22.04 LTS (Jammy) | ❌ Not Supported |
| Debian | 12 (Bookworm) | ⚠️ Should Work |
| Debian | 11 (Bullseye) | ⚠️ Should Work |

## 🔍 Monitor Your Node

After installation, use these commands to monitor your node:

### Check Service Status
```bash
systemctl status bitcoiniid
```

### View Live Logs
```bash
journalctl -u bitcoiniid -f
```

### Node Information
```bash
bitcoinII-cli -getinfo
```

### Blockchain Sync Status
```bash
bitcoinII-cli getblockchaininfo
```

### Check Transaction Index (Full Node)
```bash
bitcoinII-cli getindexinfo
```

## 🔐 Security Features

The installer automatically implements enterprise-grade security:

- **Systemd Service Management**
  - Automatic startup on boot
  - Automatic restart on failure
  - Resource limits and sandboxing
  - Proper logging to journald

- **UFW Firewall Configuration**
  - SSH access preserved (never locked out)
  - P2P port (8334) open for node communication
  - RPC port (8333) restricted to local subnet only
  - ZMQ ports configured for local access only

- **RPC Security**
  - Strong random password generation
  - Credentials displayed once at installation end
  - Local subnet access only by default

## 🛠️ Advanced Configuration

The smart installer automatically optimizes these settings based on your system:

- **Database Cache** - Scaled to available RAM
- **Memory Pool** - Optimized for transaction throughput
- **Thread Parallelism** - Matches CPU core count
- **Prune Settings** - Based on available disk space
- **Network Limits** - Tuned to bandwidth availability

## 📊 Resources

- **Official Website**: [https://bitcoin-ii.org/](https://bitcoin-ii.org/)
- **Block Explorer**: [https://bitcoinii.ddns.net/explorer/](https://bitcoinii.ddns.net/explorer/)
- **Network Node Map**: [https://bitcoinii.ddns.net/NodeMap.html](https://bitcoinii.ddns.net/NodeMap.html)
- **Daily Balance Report**: [https://bitcoinii.ddns.net/DailyReport.html](https://bitcoinii.ddns.net/DailyReport.html)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is open source and available under the MIT License.

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/skaisser">skaisser</a>
</p>
