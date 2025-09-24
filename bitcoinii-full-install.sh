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

# Resolve run user/home when running via sudo
if [[ ${SUDO_USER:-} ]]; then RUN_USER="$SUDO_USER"; else RUN_USER="$(whoami)"; fi
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6 || true)"
[[ -n ${RUN_HOME:-} && -d $RUN_HOME ]] || RUN_HOME="$HOME"
DATADIR="$RUN_HOME/.bitcoinII"
CONF="$DATADIR/bitcoinII.conf"

BIN_DAEMON="$DATADIR/bitcoinIId"
BIN_CLI="$DATADIR/bitcoinII-cli"

timestamp() { date +%Y%m%d-%H%M%S; }
say() { echo -e "[bitcoinii] $*"; }

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "This installer must run with root privileges (sudo)." >&2
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
  echo "Select mode:";
  echo "  1) Mining (pruned, wallet off, blocksonly) [recommended]";
  echo "  2) Full node (no prune, wallet on, accepts txs)";
  read -rp "Enter 1 or 2 [1]: " MODE
  MODE=${MODE:-1}
  if [[ "$MODE" != "1" && "$MODE" != "2" ]]; then MODE=1; fi
}

main() {
  need_root
  ensure_tools

  say "Preparing directories at $DATADIR"
  mkdir -p "$DATADIR"
  chown -R "$RUN_USER":"$RUN_USER" "$DATADIR"

  # Download and extract release
  TMPD="$(mktemp -d)"
  TAR="$TMPD/BitcoinII.tar.gz"
  say "Downloading release…"
  wget -qO "$TAR" "$RELEASE_URL"
  say "Extracting…"
  tar -xzf "$TAR" -C "$TMPD"

  # Find daemon and cli in extracted tree
  SRC_DAEMON=$(find "$TMPD" -type f -name 'bitcoinIId' | head -1 || true)
  SRC_CLI=$(find "$TMPD" -type f -name 'bitcoinII-cli' | head -1 || true)
  if [[ -z "$SRC_DAEMON" || -z "$SRC_CLI" ]]; then
    echo "Could not locate bitcoinIId or bitcoinII-cli in the tarball." >&2
    exit 1
  fi

  install -m 0755 "$SRC_DAEMON" "$BIN_DAEMON"
  install -m 0755 "$SRC_CLI" "$BIN_CLI"

  # Remove GUI/wallet binaries if present in datadir
  rm -f "$DATADIR/bitcoinII-qt" "$DATADIR/bitcoinII-wallet" 2>/dev/null || true

  # Decide ports avoiding conflicts with Bitcoin Core
  P2P_PORT=$(next_free_port "$DEFAULT_P2P")
  # For RPC, prefer 8332 if free, else step to next free even value (8334, 8336,…)
  if port_free "$DEFAULT_RPC"; then RPC_PORT="$DEFAULT_RPC"; else RPC_PORT=$(next_free_port 8334); fi
  ZMQ_BLOCK_PORT="$ZMQ_BLOCK_PORT_DEFAULT"
  ZMQ_HASHTX_PORT="$ZMQ_HASHTX_PORT_DEFAULT"
  ZMQ_HASHBLOCK_PORT="$ZMQ_HASHBLOCK_PORT_DEFAULT"

  calc_tunables
  prompt_mode

  RPC_USER="bitcoinII"
  RPC_PASS="$(RAND 28)"

  # Backup existing config if present
  if [[ -f "$CONF" ]]; then
    cp -a "$CONF" "$CONF.bak.$(timestamp)"
    say "Backed up existing config to $CONF.bak.$(timestamp)"
  fi

  # Local subnet
  LOCAL_SUBNET="${LOCAL_SUBNET_DEFAULT}"

  # Generate config
  say "Writing configuration to $CONF"
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

  # Create systemd service
  SERVICE_FILE="/etc/systemd/system/bitcoiniid.service"
  say "Installing systemd service to $SERVICE_FILE"
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
  systemctl start bitcoiniid || true

  # Configure UFW (allow SSH, P2P; restrict RPC/ZMQ to local subnet)
  say "Configuring UFW rules"
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

  # Create CLI wrappers globally (no prompt)
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

  say "=== Summary ==="
  echo "User:        $RUN_USER ($RUN_HOME)"
  echo "Datadir:     $DATADIR"
  echo "Config:      $CONF"
  echo "Service:     $SERVICE_FILE"
  echo "Mode:        $([[ "$MODE" == "1" ]] && echo Mining/Pruned || echo Full Node)"
  echo "P2P:         $P2P_PORT | RPC: $RPC_PORT | ZMQ: $ZMQ_BLOCK_PORT,$ZMQ_HASHTX_PORT,$ZMQ_HASHBLOCK_PORT"
  echo "RPC creds:   rpcuser=$RPC_USER rpcpassword=$RPC_PASS"
  echo
  echo "Useful commands:"
  echo "  systemctl status bitcoiniid --no-pager"
  echo "  journalctl -u bitcoiniid -f"
  echo "  bitcoinII-cli -getinfo"
  echo "  bitcoinII-cli getblockchaininfo"
  if [[ "$MODE" == "2" ]]; then
    echo "  bitcoinII-cli getindexinfo  # shows txindex sync"
  fi
}

main "$@"
