#!/bin/bash
set -euo pipefail
trap 'echo "Stopping Kuzco worker..."; exit 0' INT TERM

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
if [ ! -s "$FAKE_UUID_FILE" ]; then 
    uuidgen | sed 's/^/GPU-/' > "$FAKE_UUID_FILE"
fi
if [ ! -s "$FAKE_BUSID_FILE" ]; then 
    printf "00000000:%02x:00.0\n" $(( (RANDOM % 14) + 1 )) > "$FAKE_BUSID_FILE"
fi

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

# =========[ Fake PCI devices ]=========
mkdir -p /sys/bus/pci/devices/0000:01:00.0 2>/dev/null || true
echo "0x10de" > /sys/bus/pci/devices/0000:01:00.0/vendor 2>/dev/null || true
echo "0x2684" > /sys/bus/pci/devices/0000:01:00.0/device 2>/dev/null || true

# =========[ Fake /dev/nvidia* ]=========
mkdir -p /dev
[ -c /dev/nvidia0 ] || mknod /dev/nvidia0 c 195 0 2>/dev/null || true
[ -c /dev/nvidiactl ] || mknod /dev/nvidiactl c 195 255 2>/dev/null || true
[ -c /dev/nvidia-modeset ] || mknod /dev/nvidia-modeset c 195 254 2>/dev/null || true

echo "✅ Complete fake environment setup complete"

# =========[ Setup GPU dummy ]=========
echo "Setting up fake GPU..."
/usr/local/bin/nvidia-smi --setup-gpu "GeForce RTX 4090" || true

# =========[ Quick self-test ]=========
echo "Testing all Kuzco system commands..."
echo "1. Testing nvidia-smi query:"
/usr/local/bin/nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits || true
echo "2. Testing PCI device files:"
cat /sys/bus/pci/devices/0000:01:00.0/vendor 2>/dev/null || echo "PCI vendor: 0x10de (fake)"
cat /sys/bus/pci/devices/0000:01:00.0/device 2>/dev/null || echo "PCI device: 0x2684 (fake)"
echo "3. Testing df:"
df -h || true
echo "4. Testing lsof:"
/usr/local/bin/lsof -ti :8084 || true
echo "5. Testing fuser:"
/usr/local/bin/fuser -v /dev/nvidia0 || true

# =========[ Force Hyperbolic proxy (alias OLLAMA) & readiness check ]=========
export OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:14444}"
export OLLAMA_ORIGINS="*"
export NODE_OPTIONS="--dns-result-order=ipv4first"

echo "Waiting for Hyperbolic proxy on $OLLAMA_HOST ..."

# Test koneksi ke Hyperbolic proxy dengan timeout lebih panjang
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Testing connection to Hyperbolic proxy (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
    
    # Test semua endpoint yang diperlukan
    if curl -fsS "${OLLAMA_HOST}/health" >/dev/null 2>&1 && \
       curl -fsS "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1 && \
       curl -fsS "${OLLAMA_HOST}/api/version" >/dev/null 2>&1; then
        
        echo "✅ Basic endpoints ready"
        
        # Test chat endpoint dengan request sederhana
        if curl -fsS -X POST "${OLLAMA_HOST}/api/chat" \
           -H "Content-Type: application/json" \
           -d '{"messages":[{"role":"user","content":"hello"}],"stream":false}' >/dev/null 2>&1; then
            echo "✅ Chat endpoint ready"
            
            # Test show endpoint
            if curl -fsS -X POST "${OLLAMA_HOST}/api/show" \
               -H "Content-Type: application/json" \
               -d '{"name":"llama3.2:3b-instruct-fp16"}' >/dev/null 2>&1; then
                echo "✅ Show endpoint ready"
                break
            else
                echo "⚠️  Show endpoint not ready yet"
            fi
        else
            echo "⚠️  Chat endpoint not ready yet"
        fi
    else
        echo "⚠️  Basic endpoints not ready yet"
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Hyperbolic proxy not fully ready after $MAX_RETRIES attempts"
    echo "Testing individual endpoints:"
    echo "Health:"; curl -s "${OLLAMA_HOST}/health" || true
    echo "Tags:"; curl -s "${OLLAMA_HOST}/api/tags" || true
    echo "Version:"; curl -s "${OLLAMA_HOST}/api/version" || true
    echo "Show:"; curl -s -X POST "${OLLAMA_HOST}/api/show" -H "Content-Type: application/json" -d '{"name":"test"}' || true
    exit 1
fi

echo "✅ Hyperbolic proxy fully ready!"

# =========[ Final test sebelum start ]=========
echo "Running final connectivity test..."
echo "Health:"; curl -s "${OLLAMA_HOST}/health" | head -c 100; echo "..."
echo "Tags:"; curl -s "${OLLAMA_HOST}/api/tags" | head -c 100; echo "..."
echo "Version:"; curl -s "${OLLAMA_HOST}/api/version" | head -c 100; echo "..."

# =========[ Start node ]=========
echo "Starting Kuzco worker with Hyperbolic inference..."
echo "Using OLLAMA_HOST: $OLLAMA_HOST"
echo "Using CODE: $CODE"

exec inference node start --code "$CODE"
