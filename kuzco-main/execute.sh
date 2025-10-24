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

# ==================== FAKE OS INFORMATION COMMANDS ====================

# Create fake uname command (untuk OS info)
cat > /usr/local/bin/uname << 'UNAME'
#!/bin/bash
if [ "$1" = "-s" ]; then
    echo "Linux"
elif [ "$1" = "-r" ]; then
    echo "5.15.0-91-generic"
elif [ "$1" = "-m" ]; then
    echo "x86_64"
elif [ "$1" = "-v" ]; then
    echo "#102-Ubuntu SMP Tue Nov 14 15:46:04 UTC 2023"
elif [ "$1" = "-o" ]; then
    echo "GNU/Linux"
else
    echo "Linux"
fi
exit 0
UNAME
chmod +x /usr/local/bin/uname

# Create fake lsb_release command (untuk OS distribution info)
cat > /usr/local/bin/lsb_release << 'LSB_RELEASE'
#!/bin/bash
if [ "$1" = "-a" ]; then
    echo "No LSB modules are available."
    echo "Distributor ID: Ubuntu"
    echo "Description:    Ubuntu 22.04.3 LTS"
    echo "Release:        22.04"
    echo "Codename:       jammy"
elif [ "$1" = "-i" ]; then
    echo "Ubuntu"
elif [ "$1" = "-d" ]; then
    echo "Ubuntu 22.04.3 LTS"
elif [ "$1" = "-r" ]; then
    echo "22.04"
elif [ "$1" = "-c" ]; then
    echo "jammy"
else
    echo "No LSB modules are available."
fi
exit 0
LSB_RELEASE
chmod +x /usr/local/bin/lsb_release

# Create fake hostname command
cat > /usr/local/bin/hostname << 'HOSTNAME'
#!/bin/bash
echo "kuzco-hyperbolic-node"
exit 0
HOSTNAME
chmod +x /usr/local/bin/hostname

# Create fake /etc/os-release file
mkdir -p /etc
cat > /etc/os-release << 'OS_RELEASE'
NAME="Ubuntu"
VERSION="22.04.3 LTS (Jammy Jellyfish)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 22.04.3 LTS"
VERSION_ID="22.04"
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
VERSION_CODENAME=jammy
UBUNTU_CODENAME=jammy
OS_RELEASE

# Create fake /proc/version
mkdir -p /proc
echo "Linux version 5.15.0-91-generic (buildd@lcy02-amd64-101) (gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0, GNU ld (GNU Binutils for Ubuntu) 2.38) #102-Ubuntu SMP Tue Nov 14 15:46:04 UTC 2023" > /proc/version

echo "✅ Complete fake environment setup complete"

# Setup GPU seperti script asli
echo "Setting up fake GPU..."
nvidia-smi --setup-gpu "GeForce RTX 4090"

# Test SEMUA commands termasuk OS commands baru
echo "Testing all Kuzco system commands..."
echo "1. Testing nvidia-smi query:"
nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits
echo "2. Testing PCI device files:"
cat /sys/bus/pci/devices/0000:01:00.0/vendor
cat /sys/bus/pci/devices/0000:01:00.0/device
echo "3. Testing OS commands:"
uname -a
lsb_release -a
hostname
echo "4. Testing df:"
df -h
echo "5. Testing lsof:"
lsof -ti :8084
echo "6. Testing fuser:"
fuser -v /dev/nvidia0

# ==================== FORCE HYPERBOLIC CONFIGURATION ====================
# Force OLLAMA_HOST ke Hyperbolic SEBELUM apapun
export OLLAMA_HOST="http://localhost:11434"
export OLLAMA_ORIGINS="*"

echo "🚀 Configuring Kuzco to use Hyperbolic server at $OLLAMA_HOST"

# Wait for Hyperbolic server
echo "Waiting for Hyperbolic inference server..."
sleep 10

# Test Hyperbolic server
if curl -f http://localhost:11434/health >/dev/null 2>&1; then
    echo "✅ Hyperbolic server ready!"
    
    # Start Kuzco worker dengan environment variables
    echo "Starting Kuzco worker with Hyperbolic inference..."
    inference node start --code $CODE
else
    echo "❌ Hyperbolic server not ready"
    echo "Please check hyperbolic-inference logs: cd ~/hyperbolic-kuzco-setup/hyperbolic-inference && docker-compose logs -f"
    exit 1
fi
