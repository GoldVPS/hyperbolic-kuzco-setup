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

# =========[ Fake nvidia-smi ]=========
cat > /usr/local/bin/nvidia-smi << 'NVSMI'
#!/bin/bash
set -euo pipefail
# lokasi cache sama dengan execute.sh
FAKE_DIR="/app/cache"
FAKE_UUID="$(cat "$FAKE_DIR/fake_gpu_uuid" 2>/dev/null || echo GPU-fallback-0000)"
FAKE_BUSID="$(cat "$FAKE_DIR/fake_pci_busid" 2>/dev/null || echo 00000000:01:00.0)"
FAKE_DRIVER="${FAKE_DRIVER:-535.54.03}"
FAKE_NAME="${FAKE_NAME:-NVIDIA GeForce RTX 4090}"
FAKE_VRAM_MB="${FAKE_VRAM_MB:-24576}"

if [ "${1:-}" = "--setup-gpu" ]; then
  echo "Setting up GPU: ${2:-$FAKE_NAME}"
  echo "✅ Fake GPU ${2:-$FAKE_NAME} configured successfully!"
  exit 0
fi

# persis query yang dipakai Kuzco
if [ "${1:-}" = "--query-gpu=uuid,driver_version,name,memory.total,pci.bus_id" ] && \
   [ "${2:-}" = "--format=csv,noheader,nounits" ]; then
  echo "${FAKE_UUID},${FAKE_DRIVER},${FAKE_NAME},${FAKE_VRAM_MB},${FAKE_BUSID}"
  exit 0
fi

# default minimal output
cat <<EOF
NVIDIA-SMI ${FAKE_DRIVER}
Driver Version: ${FAKE_DRIVER}
CUDA Version: 12.2

| GPU  Name                 Persistence-M | Bus-Id             | Volatile Uncorr. ECC |
|=========================================+====================+======================|
|   0  ${FAKE_NAME}        Off            |   ${FAKE_BUSID}   |                  N/A |
+-----------------------------------------------------------------------------+
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
EOF
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

# =========[ (Optional) lsof/fuser ringan ]=========
# Jangan override core utils lain seperti cat/df/kill/uname/lsb_release/hostname
cat > /usr/local/bin/lsof << 'LSOF'
#!/bin/bash
# Minimal: kosongkan untuk port yang biasa dicek; selain itu fallback ke lsof asli kalau ada
if [ "$1" = "-ti" ] && [[ "$2" =~ ^:(8084|14445)$ ]]; then
  exit 0
fi
# jika lsof asli ada, delegasikan
if command -v /usr/bin/lsof >/dev/null 2>&1; then exec /usr/bin/lsof "$@"; else exit 0; fi
LSOF
chmod +x /usr/local/bin/lsof

cat > /usr/local/bin/fuser << 'FUSER'
#!/bin/bash
if [ "$1" = "-v" ] && [[ "${2:-}" == /dev/nvidia* ]]; then
  exit 0
fi
if command -v /usr/bin/fuser >/dev/null 2>&1; then exec /usr/bin/fuser "$@"; else exit 0; fi
FUSER
chmod +x /usr/local/bin/fuser

echo "✅ Complete fake environment setup complete"

# =========[ Setup GPU (dummy) ]=========
echo "Setting up fake GPU..."
/usr/local/bin/nvidia-smi --setup-gpu "GeForce RTX 4090" || true

# =========[ Quick self-test ]=========
echo "Testing all Kuzco system commands..."
echo "1. Testing nvidia-smi query:"
/usr/local/bin/nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits
echo "2. Testing df:"
df -h || true
echo "3. Testing lsof:"
/usr/local/bin/lsof -ti :8084 || true
echo "4. Testing fuser:"
/usr/local/bin/fuser -v /dev/nvidia0 || true

# =========[ Force Hyperbolic proxy & readiness check ]=========
# gunakan alias Ollama: 14444
export OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:14444}"
export OLLAMA_ORIGINS="*"

echo "Waiting Hyperbolic proxy on $OLLAMA_HOST ..."
# butuh /health DAN /api/tags siap supaya awal tidak 404
until curl -fsS "$OLLAMA_HOST/health" >/dev/null 2>&1 \
   && curl -fsS "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; do
  sleep 1
done
echo "✅ Hyperbolic proxy ready!"

echo "Starting Kuzco worker with Hyperbolic inference..."
exec inference node start --code "$CODE"
