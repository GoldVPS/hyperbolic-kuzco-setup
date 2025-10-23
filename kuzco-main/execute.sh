#!/bin/bash

# Simple fake GPU setup untuk Kuzco
echo "Setting up fake NVIDIA GeForce RTX 4090..."

# Create fake nvidia-smi
cat > /usr/local/bin/nvidia-smi << 'NVSMI'
#!/bin/bash
if [ "$1" = "--setup-gpu" ]; then
    echo "Setting up GPU: $2"
    echo "✅ Fake GPU $2 configured successfully!"
    exit 0
fi
echo "NVIDIA GeForce RTX 4090"
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

# Setup fake GPU
echo "Configuring fake GPU..."
nvidia-smi --setup-gpu "GeForce RTX 4090"

# Wait for Hyperbolic server
echo "Waiting for Hyperbolic inference server..."
sleep 15

# Test Hyperbolic server
if curl -f http://localhost:11434/health >/dev/null 2>&1; then
    echo "✅ Hyperbolic server ready!"
    export OLLAMA_HOST="http://localhost:11434"
    
    # Start Kuzco worker
    echo "Starting Kuzco worker..."
    inference node start --code $CODE
else
    echo "❌ Hyperbolic server not ready"
    exit 1
fi
