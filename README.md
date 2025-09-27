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

## 🚀 Installation

Download and run the installer with these three commands:

```bash
wget https://raw.githubusercontent.com/skaisser/bitcoinii-node-installer/main/bitcoinii-full-install.sh
chmod +x bitcoinii-full-install.sh
sudo ./bitcoinii-full-install.sh
```

The smart installer will guide you through the configuration and handle everything automatically.

### Non‑Interactive Installation
For automated deployments, you can run without prompts:

```bash
# Mining node with auto-detected subnet
sudo ./bitcoinii-full-install.sh --mode mining --subnet auto -y

# Full node with local-only access
sudo ./bitcoinii-full-install.sh --mode full --subnet local-only -y
```

## 🧠 Smart Installation Features

This is not just another installer script. Our **SMART Installer** automatically:

- **🔍 Analyzes your system** - Detects available resources (RAM, CPU cores, disk space)
- **⚙️ Optimizes configuration** - Automatically tunes `dbcache`, `mempool`, `prune` settings, and parallelism based on YOUR machine
- **🛡️ Configures security** - Sets up UFW firewall rules intelligently (SSH preserved, P2P allowed, RPC restricted to local subnet)
- **🔧 Creates systemd service** - Professional-grade service management with automatic startup and restart on failure
- **🔗 Installs global CLI access** - Creates symlinks in `/usr/local/bin` so you can run `bitcoinII-cli` from anywhere
- **🎯 Avoids port conflicts** - Intelligently configures ports to avoid conflicts with Bitcoin Core or other services

## 📦 What the Installer Does

The installer will:
1. Download BitcoinII v29.0.0 binaries
2. Analyze your system resources (CPU, RAM, disk space)
3. Configure optimal settings based on your hardware
4. Set up systemd service for automatic startup
5. Configure UFW firewall with appropriate rules
6. Create global CLI commands (`bitcoinII-cli`)
7. Display your RPC credentials (save these!)

During installation, you'll be prompted to choose:
- **Node Type**: Mining Node (pruned) or Full Node (complete blockchain)
- **Network Access**: Auto-detect subnet, custom subnet, or local-only

### Alternative: Clone Repository
If you prefer to clone the repository first:
```bash
git clone https://github.com/skaisser/bitcoinii-node-installer
cd bitcoinii-node-installer
sudo ./bitcoinii-full-install.sh
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
  - P2P port (8338) open for node communication (auto-checks for availability)
  - RPC port (default 8332; auto-shifts if in use) restricted to local subnet only
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
