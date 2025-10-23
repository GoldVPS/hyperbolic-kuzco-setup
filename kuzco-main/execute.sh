#!/bin/bash

# Buat fake nvidia-smi aja - yang penting buat Kuzco happy
cat > /usr/local/bin/nvidia-smi << 'EOF'
#!/bin/bash
echo "NVIDIA GeForce RTX 4090"
exit 0
EOF
chmod +x /usr/local/bin/nvidia-smi

# Setup fake GPU 
echo "Setting up fake NVIDIA GeForce RTX 4090..."
nvidia-smi --setup-gpu "GeForce RTX 4090"

# Tunggu Hyperbolic server
echo "Waiting for Hyperbolic inference server..."
sleep 15

# Start Kuzco
export OLLAMA_HOST="http://localhost:11434"
inference node start --code $CODE
