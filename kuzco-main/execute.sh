#!/bin/bash

# Complete fake environment based on ViKey startup logs
echo "Setting up complete fake environment for Kuzco..."

# Create fake nvidia-smi dengan format persis ViKey
cat > /usr/local/bin/nvidia-smi << 'NVSMI'
#!/bin/bash

# Handle --setup-gpu command (from original script)
if [ "$1" = "--setup-gpu" ]; then
    echo "Setting up GPU: $2"
    echo "✅ Fake GPU $2 configured successfully!"
    exit 0
fi

# Handle the EXACT query that Kuzco uses (from ViKey logs)
if [ "$1" = "--query-gpu=uuid,driver_version,name,memory.total,pci.bus_id" ] && [ "$2" = "--format=csv,noheader,nounits" ]; then
    echo "GPU-fake-12345678-1234-1234-1234-123456789012,535.54.03,NVIDIA GeForce RTX 4090,24576,00000000:01:00.0"
    exit 0
fi

# Default nvidia-smi output
echo "NVIDIA-SMI 535.54.03"
echo "Driver Version: 535.54.03"
echo "CUDA Version: 12.2"
echo ""
echo "| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |"
echo "| Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |"
echo "|                                         |                      |               MIG M. |"
echo "|=========================================+======================+======================|"
echo "|   0  NVIDIA GeForce RTX 4090        Off |   00000000:01:00.0   Off |                  N/A |"
echo "|  0%   45C    P8             25W /  450W |      0MiB /  24576MiB |      0%      Default |"
echo "|                                         |                      |                  N/A |"
echo "+-----------------------------------------+----------------------+----------------------+"
echo ""
echo "+-----------------------------------------------------------------------------+"
echo "| Processes:                                                                  |"
echo "|  GPU   GI   CI        PID   Type   Process name                  GPU Memory |"
echo "|        ID   ID                                                   Usage      |"
echo "|=============================================================================|"
echo "|  No running processes found                                                 |"
echo "+-----------------------------------------------------------------------------+"
exit 0
NVSMI

chmod +x /usr/local/bin/nvidia-smi

# Create fake nvidia-detector
cat > /usr/local/bin/nvidia-detector << 'NVDETECT'
#!/bin/bash
echo "NVIDIA GeForce RTX 4090"
exit 0
NVDETECT
chmod +x /usr/local/bin/nvidia-detector

# Create fake PCI device files (DARI LOGS VIKEY!)
mkdir -p /sys/bus/pci/devices/0000:00:01.0
echo "0x10de" > /sys/bus/pci/devices/0000:00:01.0/vendor
echo "0x2684" > /sys/bus/pci/devices/0000:00:01.0/device

# Juga buat untuk 00000000:01:00.0 (format berbeda)
mkdir -p /sys/bus/pci/devices/0000:01:00.0
echo "0x10de" > /sys/bus/pci/devices/0000:01:00.0/vendor
echo "0x2684" > /sys/bus/pci/devices/0000:01:00.0/device

# Create fake cat command untuk handle PCI device queries
cat > /usr/local/bin/cat << 'CAT'
#!/bin/bash
# Handle specific PCI device files that Kuzco checks
if [[ "$*" == *"/sys/bus/pci/devices/0000:00:01.0/vendor"* ]]; then
    echo "0x10de"
    exit 0
elif [[ "$*" == *"/sys/bus/pci/devices/0000:00:01.0/device"* ]]; then
    echo "0x2684"
    exit 0
elif [[ "$*" == *"/sys/bus/pci/devices/0000:01:00.0/vendor"* ]]; then
    echo "0x10de"
    exit 0
elif [[ "$*" == *"/sys/bus/pci/devices/0000:01:00.0/device"* ]]; then
    echo "0x2684"
    exit 0
else
    # For other files, use real cat
    /bin/cat "$@"
fi
CAT
chmod +x /usr/local/bin/cat

# Create fake df command (DARI LOGS VIKEY!)
cat > /usr/local/bin/df << 'DF'
#!/bin/bash
if [ "$1" = "-h" ]; then
    echo "Filesystem      Size  Used Avail Use% Mounted on"
    echo "overlay          50G   12G   36G  25% /"
else
    echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
    echo "overlay         52428800 12582912 37119588  25% /"
fi
exit 0
DF
chmod +x /usr/local/bin/df

# Create fake lsof command (DARI LOGS VIKEY!)
cat > /usr/local/bin/lsof << 'LSOF'
#!/bin/bash
if [ "$1" = "-ti" ] && [ "$2" = ":8084" ]; then
    # Return empty to indicate no process using port 8084
    exit 0
elif [ "$1" = "-ti" ] && [ "$2" = ":14445" ]; then
    # Return empty to indicate no process using port 14445  
    exit 0
else
    # For other lsof commands, return empty
    exit 0
fi
LSOF
chmod +x /usr/local/bin/lsof

# Create fake fuser command (DARI LOGS VIKEY!)
cat > /usr/local/bin/fuser << 'FUSER'
#!/bin/bash
if [ "$1" = "-v" ] && [[ "$2" == /dev/nvidia* ]]; then
    # Return empty to indicate no processes using nvidia devices
    exit 0
else
    # For other fuser commands, return empty
    exit 0
fi
FUSER
chmod +x /usr/local/bin/fuser

# Create fake kill command (untuk handle cleanup)
cat > /usr/local/bin/kill << 'KILL'
#!/bin/bash
# Fake kill command - just return success
if [ "$1" = "-9" ]; then
    echo "Fake kill: Process $2 terminated"
    exit 0
else
    /bin/kill "$@"
fi
KILL
chmod +x /usr/local/bin/kill

# Create fake /dev/nvidia devices
mkdir -p /dev
mknod /dev/nvidia0 c 195 0 2>/dev/null || true
mknod /dev/nvidiactl c 195 255 2>/dev/null || true
mknod /dev/nvidia-modeset c 195 254 2>/dev/null || true

echo "✅ Complete fake environment setup complete"

# Setup GPU seperti script asli
echo "Setting up fake GPU..."
nvidia-smi --setup-gpu "GeForce RTX 4090"

# Test semua commands yang digunakan Kuzco (dari logs ViKey)
echo "Testing all Kuzco system commands..."
echo "1. Testing nvidia-smi query:"
nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits
echo "2. Testing PCI device files:"
cat /sys/bus/pci/devices/0000:01:00.0/vendor
cat /sys/bus/pci/devices/0000:01:00.0/device
echo "3. Testing df:"
df -h
echo "4. Testing lsof:"
lsof -ti :8084
echo "5. Testing fuser:"
fuser -v /dev/nvidia0

# Wait for Hyperbolic server
echo "Waiting for Hyperbolic inference server..."
sleep 10

# Test Hyperbolic server
if curl -f http://localhost:11434/health >/dev/null 2>&1; then
    echo "✅ Hyperbolic server ready!"
    export OLLAMA_HOST="http://localhost:11434"
    
    # Start Kuzco worker
    echo "Starting Kuzco worker with complete fake environment..."
    inference node start --code $CODE
else
    echo "❌ Hyperbolic server not ready"
    echo "Please check hyperbolic-inference logs: cd ~/hyperbolic-kuzco-setup/hyperbolic-inference && docker-compose logs -f"
    exit 1
fi
