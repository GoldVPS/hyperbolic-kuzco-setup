#!/bin/bash

# Enhanced fake system setup untuk Kuzco
echo "Setting up enhanced fake system environment..."

# Create advanced fake nvidia-smi yang handle semua query
cat > /usr/local/bin/nvidia-smi << 'NVSMI'
#!/bin/bash

# Handle --setup-gpu command (seperti script asli)
if [ "$1" = "--setup-gpu" ]; then
    echo "Setting up GPU: $2"
    echo "✅ Fake GPU $2 configured successfully!"
    exit 0
fi

# Handle query GPU information (yang Kuzco butuhkan)
if [ "$1" = "--query-gpu=uuid,driver_version,name,memory.total,pci.bus_id" ] && [ "$2" = "--format=csv,noheader,nounits" ]; then
    echo "GPU-fake-uuid-1234,535.54.03,NVIDIA GeForce RTX 4090,24576,00000000:00:00.0"
    exit 0
fi

# Default nvidia-smi output
cat << EOL
NVIDIA-SMI 535.54.03
Driver Version: 535.54.03
CUDA Version: 12.2

| NVIDIA-SMI 535.54.03     Driver Version: 535.54.03     CUDA Version: 12.2     |
|-----------------------------------------+----------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |
|                                         |                      |               MIG M. |
|=========================================+======================+======================|
|   0  NVIDIA GeForce RTX 4090        Off |   00000000:00:00.0   Off |                  N/A |
|  0%   45C    P8             25W /  450W |      0MiB /  24576MiB |      0%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+

+-----------------------------------------------------------------------------+
| Processes:                                                                  |
|  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
|        ID   ID                                                   Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
EOL
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

# Create fake system information commands untuk hindari timeout
cat > /usr/local/bin/lscpu << 'LSCPU'
#!/bin/bash
echo "Architecture:                    x86_64"
echo "CPU op-mode(s):                  32-bit, 64-bit"
echo "Byte Order:                      Little Endian"
echo "CPU(s):                          8"
echo "On-line CPU(s) list:             0-7"
echo "Thread(s) per core:              2"
echo "Core(s) per socket:              4"
echo "Socket(s):                       1"
echo "NUMA node(s):                    1"
echo "Vendor ID:                       GenuineIntel"
echo "CPU family:                      6"
echo "Model:                           85"
echo "Model name:                      Intel Xeon Processor (Cascadelake)"
echo "Stepping:                        7"
echo "CPU MHz:                         3500.000"
echo "BogoMIPS:                        7000.00"
echo "Hypervisor vendor:               KVM"
echo "Virtualization type:             full"
echo "L1d cache:                       128 KiB"
echo "L1i cache:                       128 KiB"
echo "L2 cache:                        4 MiB"
echo "L3 cache:                        16 MiB"
echo "NUMA node0 CPU(s):               0-7"
exit 0
LSCPU
chmod +x /usr/local/bin/lscpu

# Fake free command
cat > /usr/local/bin/free << 'FREE'
#!/bin/bash
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:        16270772      523128    14563224        8192     1184420    15463288"
echo "Swap:              0           0           0"
exit 0
FREE
chmod +x /usr/local/bin/free

# Fake df command
cat > /usr/local/bin/df << 'DF'
#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "overlay         10255436 1837696   7912708  19% /"
exit 0
DF
chmod +x /usr/local/bin/df

# Fake uname command
cat > /usr/local/bin/uname << 'UNAME'
#!/bin/bash
if [ "$1" = "-r" ]; then
    echo "5.15.0-91-generic"
elif [ "$1" = "-m" ]; then
    echo "x86_64"
elif [ "$1" = "-s" ]; then
    echo "Linux"
else
    echo "Linux"
fi
exit 0
UNAME
chmod +x /usr/local/bin/uname

# Setup fake GPU environment variables
export CUDA_VISIBLE_DEVICES="0"
export GPU_0_NAME="NVIDIA GeForce RTX 4090"
export NVIDIA_VISIBLE_DEVICES="all"
export NVIDIA_DRIVER_CAPABILITIES="compute,utility"

# Setup fake CPU environment variables
export CPU_COUNT="8"
export CPU_MODEL="Intel Xeon Processor (Cascadelake)"

echo "✅ Enhanced fake system setup complete!"

# Setup GPU seperti script asli
echo "Setting up fake GPU with nvidia-smi..."
nvidia-smi --setup-gpu "GeForce RTX 4090"

# Test semua fake commands
echo "Testing fake system commands..."
nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits
lscpu | head -5
free -h | head -2

# Wait for Hyperbolic server
echo "Waiting for Hyperbolic inference server..."
sleep 10

# Test Hyperbolic server dengan timeout
echo "Testing Hyperbolic server..."
if timeout 30 bash -c 'until curl -f http://localhost:11434/health >/dev/null 2>&1; do sleep 2; done'; then
    echo "✅ Hyperbolic server ready!"
    export OLLAMA_HOST="http://localhost:11434"
    
    # Start Kuzco worker dengan environment variables tambahan
    echo "Starting Kuzco worker with enhanced fake system..."
    inference node start --code $CODE
else
    echo "❌ Hyperbolic server not ready after 30 seconds"
    echo "Please check hyperbolic-inference logs manually"
    exit 1
fi
