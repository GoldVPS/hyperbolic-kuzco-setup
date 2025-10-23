#!/bin/bash

# Setup fake NVIDIA GPU RTX 4090
echo "Setting up fake NVIDIA GeForce RTX 4090..."

# Create fake nvidia-smi binary
cat > /usr/local/bin/nvidia-smi << 'EOF'
#!/bin/bash
if [ "$1" = "--setup-gpu" ]; then
    echo "Setting up GPU: $2"
    echo "✅ Fake GPU $2 configured successfully!"
    exit 0
fi

# Fake nvidia-smi output for RTX 4090
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
EOF

chmod +x /usr/local/bin/nvidia-smi

# Create fake nvidia-detector
cat > /usr/local/bin/nvidia-detector << 'EOF'
#!/bin/bash
echo "NVIDIA GeForce RTX 4090"
exit 0
EOF
chmod +x /usr/local/bin/nvidia-detector

# Create fake CUDA directory structure
mkdir -p /usr/local/cuda/bin
mkdir -p /usr/local/cuda/lib64

# Create fake nvidia-smi in cuda bin
ln -sf /usr/local/bin/nvidia-smi /usr/local/cuda/bin/nvidia-smi

# Create fake GPU device files
mkdir -p /dev/nvidia
touch /dev/nvidia0
touch /dev/nvidiactl
touch /dev/nvidia-uvm

# Create fake NVIDIA driver directory
mkdir -p /proc/driver/nvidia
echo "Model: NVIDIA GeForce RTX 4090" > /proc/driver/nvidia/version
mkdir -p /proc/driver/nvidia/gpus
mkdir -p /proc/driver/nvidia/gpus/0000:00:00.0
echo "GeForce RTX 4090" > /proc/driver/nvidia/gpus/0000:00:00.0/name

# Setup fake GPU environment variables
export CUDA_VISIBLE_DEVICES="0"
export GPU_0_NAME="NVIDIA GeForce RTX 4090"
export NVIDIA_VISIBLE_DEVICES="all"
export NVIDIA_DRIVER_CAPABILITIES="compute,utility"

echo "✅ Fake NVIDIA GeForce RTX 4090 setup complete!"

# Setup GPU seperti script asli - PENTING!
echo "Setting up fake GPU with nvidia-smi..."
nvidia-smi --setup-gpu "GeForce RTX 4090"

# Tunggu Hyperbolic server ready
echo "Waiting for Hyperbolic inference server to be ready..."
sleep 15

# Test Hyperbolic server
if curl -f http://localhost:11434/health >/dev/null 2>&1; then
    echo "✅ Hyperbolic server is ready!"
    export OLLAMA_HOST="http://localhost:11434"
    
    # Start Kuzco worker seperti script asli
    echo "Starting Kuzco worker with fake RTX 4090..."
    inference node start --code $CODE
    
else
    echo "❌ Hyperbolic server not ready. Please check hyperbolic-inference logs."
    exit 1
fi
