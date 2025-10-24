#!/bin/bash

if [ "$1" == "serve" ]; then
    echo "🚀 BLOCKING Ollama Sidecar - Using Hyperbolic Proxy Instead"
    echo "Hyperbolic server: http://localhost:11434"
    echo "Ollama sidecar disabled for Hyperbolic mode"
    
    # BLOCK dengan infinite sleep - prevent Ollama sidecar from starting
    while true; do
        sleep 86400  # Sleep for 24 hours
    done
    exit 0
else
    exit 1
fi
