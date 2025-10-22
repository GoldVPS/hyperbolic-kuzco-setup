#!/bin/bash

if [ "$1" == "serve" ]; then
    echo "Running Inference using Hyperbolic Proxy"
    echo "Hyperbolic inference server is running separately on host"
else
    exit 1
fi
