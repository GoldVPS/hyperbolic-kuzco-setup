FROM debian:stable-slim

RUN apt-get update && apt-get install -y curl systemd lsof procps git

WORKDIR /app
RUN mkdir -p /app/cache

WORKDIR /app

RUN curl -fsSL https://devnet.inference.net/install.sh | sh

COPY ./start.sh /usr/local/bin/inference-runtime
COPY ./execute.sh /app/execute.sh
RUN chmod +x /app/execute.sh
RUN chmod +x /usr/local/bin/inference-runtime

# Create necessary directories for fake GPU
RUN mkdir -p /proc/driver/nvidia/gpus && \
    mkdir -p /dev/nvidia && \
    mkdir -p /usr/local/cuda/bin

CMD ["/app/execute.sh"]
