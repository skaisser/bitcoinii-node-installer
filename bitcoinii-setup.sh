#!/usr/bin/env bash
set -euo pipefail

# === BitcoinII Mining-Only Optimizer & Service Installer (Best-Practice systemd) ===
# Target: small VM + BitAxe; wallet OFF, blocksonly ON, txindex OFF, prune ON.
# Binaries expected at: ~/.bitcoinII/{bitcoinIId,bitcoinII-cli}

# ---------- Tunables ----------
P2P_PORT=8338
RPC_PORT=8332
ZMQ_BLOCK_PORT=28332
ZMQ_HASHTX_PORT=28333
ZMQ_HASHBLOCK_PORT=28334
LOCAL_SUBNET="10.0.0.0/23"
ADDNODES=("us.bitcoinii.info:8338" "bitcoinii.ddns.net:8338")
MAXCONN_DEFAULT=32
MAXUPLOAD_MB_DAY_DEFAULT=1000
LEAVE_HEADROOM_MB=3000
# -----------------------------

# Resolve user and paths
if [[ ${SUDO_USER:-} ]]; then RUN_USER="$SUDO_USER"; else RUN_USER="$(whoami)"; fi
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
DATADIR="$RUN_HOME/.bitcoinII"
CONF="$DATADIR/bitcoinII.conf"
BIN_IID="$DATADIR/bitcoinIId"
BIN_CLI="$DATADIR/bitcoinII-cli"

timestamp() { date +%Y%m%d-%H%M%S; }

echo -e "\n=== BitcoinII Mining Optimizer for $RUN_USER ($RUN_HOME) ===\n"

# Require daemon binary in ~/.bitcoinII
if [[ ! -x "$BIN_IID" ]]; then
  echo "❌ Missing executable: $BIN_IID"
  echo "   Put bitcoinIId and bitcoinII-cli in $DATADIR or edit this script’s paths."
  exit 1
fi

mkdir -p "$DATADIR"
chown -R "$RUN_USER":"$RUN_USER" "$DATADIR"

# --------- Probe resources ----------
CPU_CORES=$(nproc)
MEM_TOTAL_MB=$(free -m | awk '/^Mem:/{print $2}')
MEM_AVAIL_MB=$(free -m | awk '/^Mem:/{print $7}')
DISK_AVAIL_MB=$(df -m "$RUN_HOME" | awk 'NR==2{print $4}')

# --------- Compute recommendations ----------
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

MAXCONN=$MAXCONN_DEFAULT
MAXUPLOAD_MB_DAY=$MAXUPLOAD_MB_DAY_DEFAULT

echo "--- Tuned ---"
echo "dbcache=${DBCACHE} MB | mempool=${MAXMEMPOOL} MB | par=${PAR} | prune=${PRUNE_MB} MB"
echo "maxconnections=${MAXCONN} | maxuploadtarget=${MAXUPLOAD_MB_DAY} MB/day"
echo "RPC/ZMQ allowed from ${LOCAL_SUBNET}"
echo

# --------- Credentials (reuse if present) ----------
RAND() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; echo; }
RPC_USER="rpc_$(RAND 6)"; RPC_PASS="$(RAND 24)"
if [[ -f "$CONF" ]]; then
  u=$(grep -E '^rpcuser=' "$CONF" | head -1 | cut -d= -f2- || true)
  p=$(grep -E '^rpcpassword=' "$CONF" | head -1 | cut -d= -f2- || true)
  [[ -n "${u:-}" ]] && RPC_USER="$u"
  [[ -n "${p:-}" ]] && RPC_PASS="$p"
fi

# --------- Backup existing config ----------
if [[ -f "$CONF" ]]; then
  cp -a "$CONF" "$CONF.bak.$(timestamp)"
  echo "🗄️  Backup: $CONF.bak.$(timestamp)"
fi

# --------- Write mining-first config ----------
cat > "$CONF" <<EOF
# ---- BitcoinII mining-only optimized ----
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
maxconnections=${MAXCONN}

# Core / Service
server=1
daemon=0
disablewallet=1
txindex=0
blocksonly=1

# Performance
dbcache=${DBCACHE}
maxmempool=${MAXMEMPOOL}
par=${PAR}
mempoolexpiry=168
persistmempool=0
maxuploadtarget=${MAXUPLOAD_MB_DAY}

# Pruning (MB)
prune=${PRUNE_MB}

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

# Address types
addresstype=bech32
changetype=bech32

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
echo "✅ Wrote $CONF"

# Optional: remove unused binaries you mentioned
for BIN in "$DATADIR/bitcoinII-wallet" "$DATADIR/bitcoinII-qt"; do
  [[ -e "$BIN" ]] && { echo "🧹 Removing $(basename "$BIN")"; rm -f "$BIN"; }
done

# --------- UFW firewall ----------
echo -e "\n=== UFW ==="
if ! command -v ufw >/dev/null 2>&1; then
  apt-get update -y && apt-get install -y ufw
fi
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow ${P2P_PORT}/tcp >/dev/null 2>&1 || true
ufw allow from ${LOCAL_SUBNET} to any port ${RPC_PORT} proto tcp >/dev/null 2>&1 || true
ufw allow from ${LOCAL_SUBNET} to any port ${ZMQ_BLOCK_PORT} proto tcp >/dev/null 2>&1 || true
ufw allow from ${LOCAL_SUBNET} to any port ${ZMQ_HASHTX_PORT} proto tcp >/dev/null 2>&1 || true
ufw allow from ${LOCAL_SUBNET} to any port ${ZMQ_HASHBLOCK_PORT} proto tcp >/dev/null 2>&1 || true
if ! ufw status | grep -q "Status: active"; then echo "y" | ufw enable >/dev/null; fi
echo "✅ UFW ok (SSH open; P2P ${P2P_PORT}; RPC/ZMQ only from ${LOCAL_SUBNET})"

# --------- systemd service (best practices for user home datadir) ----------
SERVICE_FILE="/etc/systemd/system/bitcoiniid.service"
systemctl stop bitcoiniid >/dev/null 2>&1 || true

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=BitcoinII Daemon (Mining-Only)
Documentation=man:bitcoiniid(1)
After=network-online.target
Wants=network-online.target

[Service]
# Run as the login user who owns the datadir (no root long-running process)
User=${RUN_USER}
Group=${RUN_USER}

# Don't background; systemd manages lifecycle
Type=simple

# Always use explicit datadir & conf; do not pass ports (use defaults)
ExecStart=${BIN_IID} -datadir=${DATADIR} -conf=${CONF}
WorkingDirectory=${DATADIR}

# Restart policy
Restart=on-failure
RestartSec=10s
TimeoutStopSec=90s
KillSignal=SIGTERM
KillMode=process

# File & process limits
LimitNOFILE=1048576
Nice=5
IOSchedulingClass=best-effort
IOSchedulingPriority=6

# Security hardening (balanced for home datadir writes)
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

# Allow writes only to the datadir; everything else read-only
ReadWritePaths=${DATADIR}

# Hide /home except this user's directory (requires ProtectHome=no above)
UMask=0077

# Environment (optional place to pin locale to avoid logs parsing issues)
Environment=LC_ALL=C.UTF-8

# Log to journald; also see ~/.bitcoinII/debug.log
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bitcoiniid
systemctl start bitcoiniid
sleep 1
systemctl is-active --quiet bitcoiniid && echo "✅ bitcoiniid running." || { echo "❌ Failed to start. Check: sudo journalctl -u bitcoiniid -e"; exit 1; }

# --------- CLI wrappers (best: always pass datadir/conf) ----------
sudo rm -f /usr/local/bin/bitcoinii-cli /usr/local/bin/bitcoinII-cli || true

tee /usr/local/bin/bitcoinii-cli >/dev/null <<'EOF'
#!/usr/bin/env bash
exec "$HOME/.bitcoinII/bitcoinII-cli" \
  -datadir="$HOME/.bitcoinII" \
  -conf="$HOME/.bitcoinII/bitcoinII.conf" "$@"
EOF
chmod +x /usr/local/bin/bitcoinii-cli

tee /usr/local/bin/bitcoinII-cli >/dev/null <<'EOF'
#!/usr/bin/env bash
exec "$HOME/.bitcoinII/bitcoinII-cli" \
  -datadir="$HOME/.bitcoinII" \
  -conf="$HOME/.bitcoinII/bitcoinII.conf" "$@"
EOF
chmod +x /usr/local/bin/bitcoinII-cli

# --------- Summary ----------
echo -e "\n=== Summary ==="
echo "Datadir:     $DATADIR"
echo "Config:      $CONF"
echo "Service:     $SERVICE_FILE"
echo "RPC:         ${RPC_PORT} (user: ${RPC_USER})"
echo "ZMQ:         ${ZMQ_BLOCK_PORT}, ${ZMQ_HASHTX_PORT}, ${ZMQ_HASHBLOCK_PORT} on 0.0.0.0 and 127.0.0.1"
echo "P2P:         ${P2P_PORT}"
echo "Optimized:   blocksonly=1, disablewallet=1, txindex=0, prune=${PRUNE_MB}MB"
echo
echo "Commands:"
echo "  systemctl status bitcoiniid --no-pager"
echo "  journalctl -u bitcoiniid -f"
echo "  bitcoinii-cli -getinfo"
echo "  bitcoinii-cli getblockchaininfo"
