#!/usr/bin/env bash
set -euo pipefail

# BitcoinII smart one-shot installer for miners or full nodes.
# - Downloads v29.0.0 tarball, installs binaries into ~/.bitcoinII
# - Removes GUI/wallet binaries
# - Generates tuned bitcoinii.conf (mining-pruned or full)
# - Creates a hardened systemd service
# - Optionally creates CLI convenience wrappers

# ---------- Settings (edit if needed) ----------
RELEASE_URL="https://github.com/Bitcoin-II/BitcoinII-Core/releases/download/v29.0.0/BitcoinII-29.0.0-Linux_x86_64.tar.gz"
LOCAL_SUBNET_DEFAULT="10.0.0.0/23"
DEFAULT_P2P=8338         # Avoids Bitcoin Core 8333
DEFAULT_RPC=8332         # Will auto-shift if occupied (e.g., by Bitcoin Core)
ZMQ_BLOCK_PORT_DEFAULT=28332
ZMQ_HASHTX_PORT_DEFAULT=28333
ZMQ_HASHBLOCK_PORT_DEFAULT=28334
LEAVE_HEADROOM_MB=3000   # Keep at least this much free disk
ADDNODES=("us.bitcoinii.info:8338" "bitcoinii.ddns.net:8338")
# ------------------------------------------------

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Resolve run user/home when running via sudo
if [[ ${SUDO_USER:-} ]]; then RUN_USER="$SUDO_USER"; else RUN_USER="$(whoami)"; fi
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6 || true)"
[[ -n ${RUN_HOME:-} && -d $RUN_HOME ]] || RUN_HOME="$HOME"
DATADIR="$RUN_HOME/.bitcoinII"
CONF="$DATADIR/bitcoinII.conf"

BIN_DAEMON="$DATADIR/bitcoinIId"
BIN_CLI="$DATADIR/bitcoinII-cli"

timestamp() { date +%Y%m%d-%H%M%S; }
say() { echo -e "${BLUE}[BitcoinII]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }
info() { echo -e "${CYAN}ℹ${NC} $*"; }

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    error "This installer must run with root privileges (sudo)."
    exit 1
  fi
}

ensure_tools() {
  for t in wget tar awk grep sed head tr cut; do
    command -v "$t" >/dev/null 2>&1 || MISSING+=" $t"
  done
  if [[ -n ${MISSING:-} ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      say "Installing missing tools:${MISSING}"
      apt-get update -y && apt-get install -y wget tar
    else
      echo "Missing tools:${MISSING}. Install them and re-run." >&2
      exit 1
    fi
  fi
}

port_free() { # port
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ! ss -ltn | awk '{print $4}' | grep -q ":$p$"
  else
    ! netstat -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$p$"
  fi
}

next_free_port() { # start_port
  local p="$1"
  for ((i=0;i<20;i++)); do
    local try=$((p + 2*i))
    if port_free "$try"; then echo "$try"; return 0; fi
  done
  echo "$p"; return 0
}

RAND() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-24}"; echo; }

calc_tunables() {
  CPU_CORES=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN || echo 2)
  if command -v free >/dev/null 2>&1; then
    MEM_TOTAL_MB=$(free -m | awk '/^Mem:/{print $2}')
    MEM_AVAIL_MB=$(free -m | awk '/^Mem:/{print $7}')
  else
    MEM_TOTAL_MB=2048; MEM_AVAIL_MB=1024
  fi
  DISK_AVAIL_MB=$(df -m "$RUN_HOME" | awk 'NR==2{print $4}')

  DBCACHE=$(( MEM_AVAIL_MB / 4 )); (( DBCACHE < 450 )) && DBCACHE=450; (( DBCACHE > 4096 )) && DBCACHE=4096
  MAXMEMPOOL=$(( MEM_AVAIL_MB / 12 )); (( MAXMEMPOOL < 200 )) && MAXMEMPOOL=200
  PAR=$(( CPU_CORES - 1 )); (( PAR < 1 )) && PAR=1
  if (( DISK_AVAIL_MB > LEAVE_HEADROOM_MB + 1000 )); then
    PRUNE_MB=$(( DISK_AVAIL_MB - LEAVE_HEADROOM_MB ))
  else
    PRUNE_MB=550
  fi
  (( PRUNE_MB < 550 )) && PRUNE_MB=550
  (( PRUNE_MB > 200000 )) && PRUNE_MB=200000
}

prompt_mode() {
  echo -e "\n${BOLD}${CYAN}Select BitcoinII Node Mode:${NC}\n";
  echo -e "  ${YELLOW}1)${NC} ${BOLD}Mining Node${NC} (pruned, optimized for mining) ${GREEN}[recommended]${NC}";
  echo -e "  ${YELLOW}2)${NC} ${BOLD}Full Node${NC} (complete blockchain, transaction indexing)\n";
  read -rp "$(echo -e ${CYAN}"Enter your choice [1 or 2]:"${NC} ) " MODE
  MODE=${MODE:-1}
  if [[ "$MODE" != "1" && "$MODE" != "2" ]]; then MODE=1; fi
}

main() {
  need_root
  ensure_tools

  echo -e "\n${BOLD}${GREEN}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║     BitcoinII Smart Node Installer      ║${NC}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${NC}\n"

  say "${BOLD}Preparing installation...${NC}"
  info "Creating directories at $DATADIR"
  mkdir -p "$DATADIR"
  chown -R "$RUN_USER":"$RUN_USER" "$DATADIR"
  success "Directories prepared"

  # Download and extract release
  TMPD="$(mktemp -d)"
  TAR="$TMPD/BitcoinII.tar.gz"
  say "${BOLD}Downloading BitcoinII v29.0.0...${NC}"
  info "Source: ${RELEASE_URL##*/}"
  wget --progress=bar:force:noscroll -O "$TAR" "$RELEASE_URL" 2>&1 | grep --line-buffered "%" | sed -u 's/^.*\r//'
  success "Download complete"

  say "${BOLD}Extracting files...${NC}"
  tar -xvf "$TAR" -C "$TMPD" | while read -r file; do
    echo -ne "\r${CYAN}Extracting: ${NC}$(basename "$file")                    "
  done
  echo -ne "\r"
  success "Extraction complete"

  # Find daemon and cli in extracted tree
  SRC_DAEMON=$(find "$TMPD" -type f -name 'bitcoinIId' | head -1 || true)
  SRC_CLI=$(find "$TMPD" -type f -name 'bitcoinII-cli' | head -1 || true)
  if [[ -z "$SRC_DAEMON" || -z "$SRC_CLI" ]]; then
    error "Could not locate bitcoinIId or bitcoinII-cli in the tarball."
    exit 1
  fi

  say "${BOLD}Installing BitcoinII binaries...${NC}"
  install -m 0755 "$SRC_DAEMON" "$BIN_DAEMON"
  install -m 0755 "$SRC_CLI" "$BIN_CLI"
  success "Binaries installed"

  # Remove GUI/wallet binaries if present in datadir
  info "Cleaning up unnecessary files..."
  rm -f "$DATADIR/bitcoinII-qt" "$DATADIR/bitcoinII-wallet" 2>/dev/null || true

  # Decide ports avoiding conflicts with Bitcoin Core
  P2P_PORT=$(next_free_port "$DEFAULT_P2P")
  # For RPC, prefer 8332 if free, else step to next free even value (8334, 8336,…)
  if port_free "$DEFAULT_RPC"; then RPC_PORT="$DEFAULT_RPC"; else RPC_PORT=$(next_free_port 8334); fi
  ZMQ_BLOCK_PORT="$ZMQ_BLOCK_PORT_DEFAULT"
  ZMQ_HASHTX_PORT="$ZMQ_HASHTX_PORT_DEFAULT"
  ZMQ_HASHBLOCK_PORT="$ZMQ_HASHBLOCK_PORT_DEFAULT"

  say "${BOLD}Analyzing system resources...${NC}"
  calc_tunables
  info "CPU Cores: ${CPU_CORES}"
  info "Available RAM: ${MEM_AVAIL_MB} MB"
  info "Available Disk: ${DISK_AVAIL_MB} MB"
  success "System analysis complete"

  prompt_mode

  RPC_USER="bitcoinII"
  RPC_PASS="$(RAND 28)"

  # Backup existing config if present
  if [[ -f "$CONF" ]]; then
    cp -a "$CONF" "$CONF.bak.$(timestamp)"
    info "Backed up existing config to $CONF.bak.$(timestamp)"
  fi

  # Local subnet
  LOCAL_SUBNET="${LOCAL_SUBNET_DEFAULT}"

  # Generate config
  say "${BOLD}Generating optimized configuration...${NC}"
  info "Mode: $([[ "$MODE" == "1" ]] && echo "Mining Node (Pruned)" || echo "Full Node")"
  info "Database Cache: ${DBCACHE} MB"
  info "Memory Pool: ${MAXMEMPOOL} MB"
  info "CPU Threads: ${PAR}"
  su - "$RUN_USER" -c "cat > '$CONF'" <<EOF
# ---- BitcoinII auto-generated ----
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Datadir: $DATADIR

# Network
chain=main
testnet=0
regtest=0
listen=1
discover=1
dns=1
dnsseed=1
maxconnections=32

# Core / Service
server=1
daemon=0
disablewallet=1
txindex=$([[ "$MODE" == "2" ]] && echo 1 || echo 0)
blocksonly=$([[ "$MODE" == "1" ]] && echo 1 || echo 0)

# Performance
dbcache=${DBCACHE}
maxmempool=${MAXMEMPOOL}
par=${PAR}
mempoolexpiry=168
persistmempool=$([[ "$MODE" == "1" ]] && echo 0 || echo 1)
maxuploadtarget=1000

# Pruning (MB)
prune=$([[ "$MODE" == "1" ]] && echo ${PRUNE_MB} || echo 0)

# RPC
rpcuser=${RPC_USER}
rpcpassword=${RPC_PASS}
rpcbind=0.0.0.0
rpcallowip=127.0.0.1
rpcallowip=${LOCAL_SUBNET}
rpcport=${RPC_PORT}

# ZMQ on 0.0.0.0 and 127.0.0.1
zmqpubrawblock=tcp://0.0.0.0:${ZMQ_BLOCK_PORT}
zmqpubhashtx=tcp://0.0.0.0:${ZMQ_HASHTX_PORT}
zmqpubhashblock=tcp://0.0.0.0:${ZMQ_HASHBLOCK_PORT}
zmqpubrawblock=tcp://127.0.0.1:${ZMQ_BLOCK_PORT}
zmqpubhashtx=tcp://127.0.0.1:${ZMQ_HASHTX_PORT}
zmqpubhashblock=tcp://127.0.0.1:${ZMQ_HASHBLOCK_PORT}

# Mining-ish tweaks
blockmaxweight=4000000
blockmintxfee=0.00001

# Logging
debug=rpc
debug=zmq
shrinkdebugfile=1
logtimestamps=1
logips=0

# Peers
$(for n in "${ADDNODES[@]}"; do echo "addnode=$n"; done)

# Memory savers
peerbloomfilters=0
peerblockfilters=0
rpcworkqueue=8
rpcthreads=2
EOF

  chown "$RUN_USER":"$RUN_USER" "$CONF"
  chmod 600 "$CONF"
  success "Configuration written to $CONF"

  # Create systemd service
  SERVICE_FILE="/etc/systemd/system/bitcoiniid.service"
  say "${BOLD}Setting up systemd service...${NC}"
  info "Service file: $SERVICE_FILE"
  systemctl stop bitcoiniid >/dev/null 2>&1 || true
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=BitcoinII Daemon
After=network-online.target
Wants=network-online.target

[Service]
User=${RUN_USER}
Group=${RUN_USER}
Type=simple
ExecStart=${BIN_DAEMON} -datadir=${DATADIR} -conf=${CONF}
WorkingDirectory=${DATADIR}
Restart=on-failure
RestartSec=10s
TimeoutStopSec=90s
KillSignal=SIGTERM
KillMode=process
LimitNOFILE=1048576
Nice=5
IOSchedulingClass=best-effort
IOSchedulingPriority=6
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=no
ProtectControlGroups=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
LockPersonality=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
MemoryDenyWriteExecute=yes
RemoveIPC=yes
ReadWritePaths=${DATADIR}
UMask=0077
Environment=LC_ALL=C.UTF-8
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable bitcoiniid >/dev/null
  success "Service enabled for automatic startup"

  say "${BOLD}Starting BitcoinII daemon...${NC}"
  systemctl start bitcoiniid || true
  sleep 2
  if systemctl is-active --quiet bitcoiniid; then
    success "BitcoinII daemon is running!"
  else
    error "Failed to start daemon. Check: journalctl -u bitcoiniid -n 50"
  fi

  # Configure UFW (allow SSH, P2P; restrict RPC/ZMQ to local subnet)
  say "${BOLD}Configuring firewall (UFW)...${NC}"
  if ! command -v ufw >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y && apt-get install -y ufw
    fi
  fi
  ufw allow OpenSSH >/dev/null 2>&1 || true
  ufw allow 22/tcp >/dev/null 2>&1 || true
  ufw allow ${P2P_PORT}/tcp >/dev/null 2>&1 || true
  ufw allow from ${LOCAL_SUBNET} to any port ${RPC_PORT} proto tcp >/dev/null 2>&1 || true
  ufw allow from ${LOCAL_SUBNET} to any port ${ZMQ_BLOCK_PORT} proto tcp >/dev/null 2>&1 || true
  ufw allow from ${LOCAL_SUBNET} to any port ${ZMQ_HASHTX_PORT} proto tcp >/dev/null 2>&1 || true
  ufw allow from ${LOCAL_SUBNET} to any port ${ZMQ_HASHBLOCK_PORT} proto tcp >/dev/null 2>&1 || true
  if ! ufw status | grep -q "Status: active"; then echo "y" | ufw enable >/dev/null; fi
  success "Firewall configured and active"

  # Create CLI symlinks globally
  say "${BOLD}Creating global CLI access...${NC}"
  tee /usr/local/bin/bitcoinii-cli >/dev/null <<'EOX'
#!/usr/bin/env bash
exec "$HOME/.bitcoinII/bitcoinII-cli" -datadir="$HOME/.bitcoinII" -conf="$HOME/.bitcoinII/bitcoinII.conf" "$@"
EOX
  chmod +x /usr/local/bin/bitcoinii-cli
  tee /usr/local/bin/bitcoinII-cli >/dev/null <<'EOY'
#!/usr/bin/env bash
exec "$HOME/.bitcoinII/bitcoinII-cli" -datadir="$HOME/.bitcoinII" -conf="$HOME/.bitcoinII/bitcoinII.conf" "$@"
EOY
  chmod +x /usr/local/bin/bitcoinII-cli
  success "CLI commands available globally"

  echo -e "\n${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║          Installation Complete! 🎉                    ║${NC}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"

  echo -e "${BOLD}${CYAN}Configuration Summary:${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}User:${NC}        $RUN_USER ($RUN_HOME)"
  echo -e "${BOLD}Data Dir:${NC}    $DATADIR"
  echo -e "${BOLD}Config:${NC}      $CONF"
  echo -e "${BOLD}Service:${NC}     $SERVICE_FILE"
  echo -e "${BOLD}Node Mode:${NC}   $([[ "$MODE" == "1" ]] && echo -e "${YELLOW}Mining Node (Pruned)${NC}" || echo -e "${GREEN}Full Node${NC}")"
  echo -e "\n${BOLD}${CYAN}Network Configuration:${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}P2P Port:${NC}    $P2P_PORT"
  echo -e "${BOLD}RPC Port:${NC}    $RPC_PORT"
  echo -e "${BOLD}ZMQ Ports:${NC}   $ZMQ_BLOCK_PORT, $ZMQ_HASHTX_PORT, $ZMQ_HASHBLOCK_PORT"
  echo -e "\n${BOLD}${RED}⚠️  IMPORTANT - Save These RPC Credentials:${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}RPC User:${NC}     ${YELLOW}$RPC_USER${NC}"
  echo -e "${BOLD}RPC Password:${NC} ${YELLOW}$RPC_PASS${NC}"
  echo -e "\n${BOLD}${CYAN}Useful Commands:${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}Check service status:${NC}  systemctl status bitcoiniid --no-pager"
  echo -e "${GREEN}View live logs:${NC}        journalctl -u bitcoiniid -f"
  echo -e "${GREEN}Node info:${NC}             bitcoinII-cli -getinfo"
  echo -e "${GREEN}Blockchain status:${NC}     bitcoinII-cli getblockchaininfo"
  if [[ "$MODE" == "2" ]]; then
    echo -e "${GREEN}Transaction index:${NC}     bitcoinII-cli getindexinfo"
  fi
  echo -e "\n${BOLD}${GREEN}✓ BitcoinII node is now running!${NC}"
  echo -e "${CYAN}Monitor initial sync with:${NC} journalctl -u bitcoiniid -f\n"
}

main "$@"
