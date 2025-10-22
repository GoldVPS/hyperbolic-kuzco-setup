#!/bin/bash

echo "Waiting for Hyperbolic inference server to be ready..."
sleep 10

export OLLAMA_HOST="http://localhost:11434"

inference node start --code $CODE
