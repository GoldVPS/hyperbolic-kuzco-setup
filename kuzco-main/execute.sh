#!/bin/bash
set -euo pipefail
trap 'echo "Stopping..."; exit 0' INT TERM

echo "Setting up complete fake environment for Kuzco..."

# =========[ Fake GPU identity (unik & stabil per VPS) ]=========
FAKE_DIR="/app/cache"
mkdir -p "$FAKE_DIR"

: "${FAKE_DRIVER:=535.54.03}"
: "${FAKE_NAME:=NVIDIA GeForce RTX 4090}"
: "${FAKE_VRAM_MB:=24576}"

FAKE_UUID_FILE="$FAKE_DIR/fake_gpu_uuid"
FAKE_BUSID_FILE="$FAKE_DIR/fake_pci_busid"

# generate sekali lalu dipakai terus (unik antar VPS, stabil di VPS ini)
if [ ! -s "$FAKE_UUID_FILE" ]; then uuidgen | sed 's/^/GPU-/' > "$FAKE_UUID_FILE"; fi
if [ ! -s "$FAKE_BUSID_FILE" ]; then printf "00000000:%02x:00.0\n" $(( (RANDOM % 14) + 1 )) > "$FAKE_BUSID_FILE"; fi

FAKE_UUID="$(cat "$FAKE_UUID_FILE")"
FAKE_BUSID="$(cat "$FAKE_BUSID_FILE")"

# =========[ Fake nvidia-smi (tanpa nyentuh /sys) ]=========
cat > /usr/local/bin/nvidia-smi << 'NVSMI'
#!/bin/bash
set -euo pipefail
D="/app/cache"
U="$(cat "$D/fake_gpu_uuid" 2>/dev/null || echo GPU-fallback-0000)"
B="$(cat "$D/fake_pci_busid" 2>/dev/null || echo 00000000:01:00.0)"
DR="${FAKE_DRIVER:-535.54.03}"
NM="${FAKE_NAME:-NVIDIA GeForce RTX 4090}"
VM="${FAKE_VRAM_MB:-24576}"

# setup dummy
if [ "${1:-}" = "--setup-gpu" ]; then
  echo "Setting up GPU: ${2:-$NM}"
  echo "✅ Fake GPU ${2:-$NM} configured successfully!"
  exit 0
fi

# query yang dipakai Kuzco
if [ "${1:-}" = "--query-gpu=uuid,driver_version,name,memory.total,pci.bus_id" ] && \
   [ "${2:-}" = "--format=csv,noheader,nounits" ]; then
  echo "${U},${DR},${NM},${VM},${B}"
  exit 0
fi

# default minimal
echo "NVIDIA-SMI ${DR}"
echo "Driver Version: ${DR}"
echo "CUDA Version: 12.2"
exit 0
NVSMI
chmod +x /usr/local/bin/nvidia-smi

# =========[ Fake nvidia-detector ]=========
cat > /usr/local/bin/nvidia-detector << 'NVDETECT'
#!/bin/bash
echo "NVIDIA GeForce RTX 4090"
exit 0
NVDETECT
chmod +x /usr/local/bin/nvidia-detector

# =========[ lsof/fuser minimal (jangan override util lain) ]=========
cat > /usr/local/bin/lsof << 'LSOF'
#!/bin/bash
# kosongkan port-cek umum; selebihnya fallback ke binary asli bila ada
if [ "$1" = "-ti" ] && [[ "$2" =~ ^:(8084|14445)$ ]]; then
  exit 0
fi
if command -v /usr/bin/lsof >/dev/null 2>&1; then
  exec /usr/bin/lsof "$@"
else
  exit 0
fi
LSOF
chmod +x /usr/local/bin/lsof

cat > /usr/local/bin/fuser << 'FUSER'
#!/bin/bash
if [ "$1" = "-v" ] && [[ "${2:-}" == /dev/nvidia* ]]; then
  exit 0
fi
if command -v /usr/bin/fuser >/dev/null 2>&1; then
  exec /usr/bin/fuser "$@"
else
  exit 0
fi
FUSER
chmod +x /usr/local/bin/fuser

echo "✅ Complete fake environment setup complete"

# =========[ Setup GPU dummy ]=========
echo "Setting up fake GPU..."
/usr/local/bin/nvidia-smi --setup-gpu "GeForce RTX 4090" || true

# =========[ Quick self-test ]=========
echo "Testing all Kuzco system commands..."
echo "1. Testing nvidia-smi query:"
/usr/local/bin/nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits || true
echo "2. Testing df:"
df -h || true
echo "3. Testing lsof:"
/usr/local/bin/lsof -ti :8084 || true
echo "4. Testing fuser:"
/usr/local/bin/fuser -v /dev/nvidia0 || true

# =========[ Force Hyperbolic proxy (alias OLLAMA) & readiness check ]=========
export OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:14444}"
export OLLAMA_ORIGINS="*"

echo "Waiting Hyperbolic proxy on $OLLAMA_HOST ..."
# butuh /health DAN /api/tags siap supaya awal tidak 404
until curl -fsS "$OLLAMA_HOST/health" >/dev/null 2>&1 \
   && curl -fsS "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; do
  sleep 1
done
echo "✅ Hyperbolic proxy ready!"

# =========[ Start node ]=========
echo "Starting Kuzco worker with Hyperbolic inference..."
exec inference node start --code "$CODE"
