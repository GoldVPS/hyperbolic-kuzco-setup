#!/bin/bash

# Enhanced fake GPU setup untuk Kuzco
echo "Setting up enhanced fake NVIDIA GeForce RTX 4090..."

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

# Create additional fake GPU binaries yang mungkin di-check Kuzco
cat > /usr/local/bin/nvidia-settings << 'EOF'
#!/bin/bash
echo "Fake nvidia-settings for RTX 4090"
exit 0
EOF
chmod +x /usr/local/bin/nvidia-settings

# Setup fake GPU environment variables
export CUDA_VISIBLE_DEVICES="0"
export GPU_0_NAME="NVIDIA GeForce RTX 4090"
export NVIDIA_VISIBLE_DEVICES="all"
export NVIDIA_DRIVER_CAPABILITIES="compute,utility"

echo "✅ Enhanced fake GPU setup complete!"

# Setup GPU seperti script asli
echo "Setting up fake GPU with nvidia-smi..."
nvidia-smi --setup-gpu "GeForce RTX 4090"

# Test nvidia-smi query yang diinginkan Kuzco
echo "Testing nvidia-smi query..."
nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits

# Wait for Hyperbolic server
echo "Waiting for Hyperbolic inference server..."
sleep 15

# Test Hyperbolic server
if curl -f http://localhost:11434/health >/dev/null 2>&1; then
    echo "✅ Hyperbolic server ready!"
    export OLLAMA_HOST="http://localhost:11434"
    
    # Start Kuzco worker
    echo "Starting Kuzco worker with enhanced fake GPU..."
    inference node start --code $CODE
else
    echo "❌ Hyperbolic server not ready"
    exit 1
fi
