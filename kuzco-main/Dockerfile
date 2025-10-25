FROM debian:stable-slim

RUN apt-get update && apt-get install -y \
    curl systemd lsof procps git uuid-runtime \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mkdir -p /app/cache

RUN curl -fsSL https://devnet.inference.net/install.sh | sh

COPY ./start.sh /usr/local/bin/inference-runtime
COPY ./execute.sh /app/execute.sh
RUN chmod +x /app/execute.sh /usr/local/bin/inference-runtime

CMD ["/app/execute.sh"]
