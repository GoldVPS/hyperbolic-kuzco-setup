#!/bin/bash

echo "🚀 Deploying Hyperbolic Kuzco Setup..."

# Install Docker jika belum ada
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    newgrp docker
fi

# Install Docker Compose jika belum ada
if ! command -v docker-compose &> /dev/null; then
    echo "📦 Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Setup Hyperbolic Inference
echo "🔧 Setting up Hyperbolic Inference..."
cd hyperbolic-inference

if [ ! -f .env ]; then
    echo "⚠️  Please create .env file with your Hyperbolic API key"
    echo "   Copy from .env.example and fill in your API key"
    exit 1
fi

docker-compose up -d

echo "⏳ Waiting for Hyperbolic server to start..."
sleep 15

# Test Hyperbolic server
curl -f http://localhost:11434/api/tags || {
    echo "❌ Hyperbolic server failed to start"
    exit 1
}

# Setup Kuzco
echo "🔧 Setting up Kuzco..."
cd ../kuzco-main

# Check if CODE is set
if grep -q "YOUR_WORKER_CODE" docker-compose.yml; then
    echo "⚠️  Please update docker-compose.yml with your WORKER_CODE and WORKER_NAME"
    exit 1
fi

docker-compose up -d

echo "🎉 Deployment complete!"
echo "📊 Check logs:"
echo "   Hyperbolic: docker-compose logs -f (in hyperbolic-inference folder)"
echo "   Kuzco: docker-compose logs -f (in kuzco-main folder)"
echo "🔍 Test inference: curl http://localhost:11434/api/tags"
