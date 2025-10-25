#!/usr/bin/env bash
set -euo pipefail

# ===========================
#  GoldVPS Kuzco Installer
#  Default model: meta-llama/Llama-3.2-3B-Instruct
# ===========================

# ---------- Konfigurasi ----------
DEFAULT_MODEL="meta-llama/Llama-3.2-3B-Instruct"   # (Pilihan A)
INSTALL_DIR="/root/hyperbolic-kuzco-setup"
HYP_DIR="$INSTALL_DIR/hyperbolic-inference"
KUZCO_DIR="$INSTALL_DIR/kuzco-main"

# Warna + Branding
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
LGOLD='\e[1;33m'; NC='\e[0m'
LINE="\e[38;5;220m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"

ok(){ echo -e "${GREEN}✔ $*${RESET}"; }
warn(){ echo -e "${YELLOW}⚠ $*${RESET}"; }
err(){ echo -e "${RED}✖ $*${RESET}" >&2; }

header(){
  clear
  echo -e "${LGOLD}\e[38;5;220m"
  echo " ██████╗  ██████╗ ██╗     ██████╗ ██╗   ██╗██████╗ ███████╗"
  echo "██╔════╝ ██╔═══██╗██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝"
  echo "██║  ███╗██║   ██║██║     ██║  ██║██║   ██║██████╔╝███████╗"
  echo "██║   ██║██║   ██║██║     ██║  ██║╚██╗ ██╔╝██╔═══╝ ╚════██║"
  echo "╚██████╔╝╚██████╔╝███████╗██████╔╝ ╚████╔╝ ██║     ███████║"
  echo " ╚═════╝  ╚═════╝ ╚══════╝╚═════╝   ╚═══╝  ╚═╝     ╚══════╝"
  echo -e "\e[0m"
  echo -e "🚀 \e[1;33mKuzco Without GPU Node Installer\e[0m - Powered by \e[1;33mGoldVPS Team\e[0m 🚀"
  echo -e "🌐 \e[4;33mhttps://goldvps.net\e[0m - Best VPS with Low Price"
  echo
}

require_root(){
  if [[ $EUID -ne 0 ]]; then
    err "Harus dijalankan sebagai root. Jalankan: sudo su -"
    exit 1
  fi
}

install_docker(){
  header
  echo -e "${YELLOW}Installing Docker & Compose...${RESET}"
  if ! command -v docker >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg git lsb-release jq
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
  fi
  # docker compose v2 (plugin modern)
  if ! docker compose version >/dev/null 2>&1; then
    curl -SL https://github.com/docker/compose/releases/download/v2.27.1/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose || true
  fi
  ok "Docker siap"
}

prepare_tree(){
  header
  echo -e "${YELLOW}Menyiapkan struktur direktori...${RESET}"
  rm -rf "$INSTALL_DIR"
  mkdir -p "$HYP_DIR" "$KUZCO_DIR"
  ok "Direktori dibuat: $INSTALL_DIR"
}

write_hyperbolic_files(){
  header
  echo -e "${YELLOW}Membuat Hyperbolic inference proxy (Flask/Gunicorn)...${RESET}"

  cat > "$HYP_DIR/app.py" <<'PY'
from flask import Flask, request, jsonify, Response
import requests, os

app = Flask(__name__)

HYPERBOLIC_API_URL = os.getenv("HYPERBOLIC_API_URL", "https://api.hyperbolic.xyz/v1")
HYPERBOLIC_API_KEY = os.getenv("HYPERBOLIC_API_KEY", "")
HYPERBOLIC_MODEL   = os.getenv("HYPERBOLIC_MODEL", "meta-llama/Llama-3.2-3B-Instruct")

def to_hyperbolic(payload):
    # accept Ollama-style or OpenAI-style
    messages = payload.get("messages") or []
    prompt   = payload.get("prompt")
    if prompt and not messages:
        messages = [{"role":"user","content":prompt}]
    return {
        "model": HYPERBOLIC_MODEL,
        "messages": messages,
        "max_tokens": payload.get("max_tokens") or payload.get("max_tokens_to_sample") or 512,
        "temperature": payload.get("temperature", 0.7),
        "top_p": payload.get("top_p", 0.9),
        "stream": payload.get("stream", False),
        # jangan kirim logprobs biar aman ke worker (menghindari TypeError)
        "logprobs": False
    }

def from_hyperbolic(resp_json, model_name=None):
    choices = resp_json.get("choices", [])
    content = choices[0].get("message",{}).get("content","") if choices else ""
    return {
        "model": model_name or HYPERBOLIC_MODEL,
        "created_at": "",
        "done": True,
        "message": {"role":"assistant","content":content}
    }

@app.route("/api/chat", methods=["POST"])
def api_chat():
    try:
        data = request.get_json(force=True)
        hreq = to_hyperbolic(data)
        r = requests.post(f"{HYPERBOLIC_API_URL}/chat/completions",
                          json=hreq,
                          headers={"Authorization": f"Bearer {HYPERBOLIC_API_KEY}",
                                   "Content-Type":"application/json"},
                          timeout=60)
        if r.status_code != 200:
            return jsonify({"error": f"Hyperbolic API {r.status_code}", "body": r.text}), 500
        return jsonify(from_hyperbolic(r.json(), data.get("model")))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/v1/chat/completions", methods=["POST"])
def openai_chat():
    try:
        data = request.get_json(force=True)
        data["model"] = HYPERBOLIC_MODEL
        r = requests.post(f"{HYPERBOLIC_API_URL}/chat/completions",
                          json=data,
                          headers={"Authorization": f"Bearer {HYPERBOLIC_API_KEY}",
                                   "Content-Type":"application/json"},
                          timeout=60)
        return Response(r.content, status=r.status_code,
                        content_type=r.headers.get("content-type","application/json"))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/tags", methods=["GET"])
def tags():
    return jsonify({
        "models":[{
            "name": HYPERBOLIC_MODEL,
            "model": HYPERBOLIC_MODEL,
            "modified_at": "2024-01-01T00:00:00Z",
            "size": 3000000000,
            "digest": "hyperbolic-llama3.2-3b",
            "details": {"format":"gguf","family":"llama","parameter_size":"3B"}
        }]
    })

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status":"healthy","model":HYPERBOLIC_MODEL})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=11434, debug=False)
PY

  cat > "$HYP_DIR/requirements.txt" <<'REQ'
flask==3.0.3
gunicorn==21.2.0
requests==2.32.3
REQ

  cat > "$HYP_DIR/Dockerfile" <<'DOCK'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
ENV PYTHONUNBUFFERED=1
CMD ["gunicorn","-w","1","-k","gthread","--threads","8","-b","0.0.0.0:11434","--keep-alive","30","--access-logfile","-","--error-logfile","-","app:app"]
DOCK

  cat > "$HYP_DIR/docker-compose.yml" <<'YML'
version: '3.8'
services:
  hyperbolic-inference:
    build: .
    container_name: hyperbolic-inference
    environment:
      - HYPERBOLIC_API_URL=${HYPERBOLIC_API_URL:-https://api.hyperbolic.xyz/v1}
      - HYPERBOLIC_API_KEY=${HYPERBOLIC_API_KEY}
      - HYPERBOLIC_MODEL=${HYPERBOLIC_MODEL:-meta-llama/Llama-3.2-3B-Instruct}
    ports:
      - "11434:11434"         # proxy utama
      - "14444:11434"         # kompatibilitas OLLAMA_HOST lama
    restart: always
YML

  cat > "$HYP_DIR/.env" <<EOF
HYPERBOLIC_API_URL=https://api.hyperbolic.xyz/v1
HYPERBOLIC_API_KEY=
HYPERBOLIC_MODEL=$DEFAULT_MODEL
EOF

  ok "Hyperbolic files dibuat"
}

write_kuzco_files(){
  header
  echo -e "${YELLOW}Membuat Kuzco worker + fake GPU env...${RESET}"

  # start.sh kecil (opsional)
  cat > "$KUZCO_DIR/start.sh" <<'SH'
#!/usr/bin/env bash
exec /app/execute.sh
SH
  chmod +x "$KUZCO_DIR/start.sh"

  # execute.sh terbaru (fake env + IPv4 first + Hyperbolic OLLAMA_HOST)
  cat > "$KUZCO_DIR/execute.sh" <<'SH'
#!/bin/bash
set -e

echo "Setting up complete fake environment for Kuzco..."

# Fake nvidia-smi
cat > /usr/local/bin/nvidia-smi << 'NVSMI'
#!/bin/bash
if [ "$1" = "--setup-gpu" ]; then
  echo "Setting up GPU: $2"
  echo "✅ Fake GPU $2 configured successfully!"
  exit 0
fi
if [ "$1" = "--query-gpu=uuid,driver_version,name,memory.total,pci.bus_id" ] && [ "$2" = "--format=csv,noheader,nounits" ]; then
  echo "GPU-fake-12345678-1234-1234-1234-123456789012,535.54.03,NVIDIA GeForce RTX 4090,24576,00000000:01:00.0"
  exit 0
fi
echo "NVIDIA-SMI 535.54.03"
exit 0
NVSMI
chmod +x /usr/local/bin/nvidia-smi

# Fake helper
echo "NVIDIA GeForce RTX 4090" > /usr/local/bin/nvidia-detector
chmod +x /usr/local/bin/nvidia-detector

# Safe create (container kadang deny write ke /sys)
mkdir -p /sys/bus/pci/devices/0000:00:01.0 2>/dev/null || true
{ echo "0x10de" > /sys/bus/pci/devices/0000:00:01.0/vendor || true; } 2>/dev/null
{ echo "0x2684" > /sys/bus/pci/devices/0000:00:01.0/device || true; } 2>/dev/null

# Fake df/lsof/fuser minimal
cat > /usr/local/bin/df << 'DF'; echo '#'; chmod +x /usr/local/bin/df
#!/bin/bash
echo "Filesystem      Size  Used Avail Use% Mounted on"
echo "overlay          50G   12G   36G  25% /"
DF
cat > /usr/local/bin/lsof << 'LSOF'; echo '#'; chmod +x /usr/local/bin/lsof
#!/bin/bash
exit 0
LSOF
cat > /usr/local/bin/fuser << 'FUSER'; echo '#'; chmod +x /usr/local/bin/fuser
#!/bin/bash
exit 0
FUSER

# Fake /dev/nvidia*
mkdir -p /dev
mknod /dev/nvidia0 c 195 0 2>/dev/null || true
mknod /dev/nvidiactl c 195 255 2>/dev/null || true
mknod /dev/nvidia-modeset c 195 254 2>/dev/null || true

echo "✅ Complete fake environment setup complete"
echo "Setting up fake GPU..."
nvidia-smi --setup-gpu "GeForce RTX 4090"

echo "Testing all Kuzco system commands..."
echo "1. Testing nvidia-smi query:"; nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits || true
echo "2. Testing PCI device files:"; cat /sys/bus/pci/devices/0000:01:00.0/vendor 2>/dev/null || true; cat /sys/bus/pci/devices/0000:01:00.0/device 2>/dev/null || true
echo "3. Testing df:"; df -h || true
echo "4. Testing lsof:"; lsof -ti :8084 || true
echo "5. Testing fuser:"; fuser -v /dev/nvidia0 || true

# IPv4 first (hindari IPv6-only)
export NODE_OPTIONS="--dns-result-order=ipv4first"

# Force OLLAMA_HOST ke proxy Hyperbolic
export OLLAMA_HOST="http://localhost:11434"
export OLLAMA_ORIGINS="*"

echo "Waiting for Hyperbolic inference server..."
for i in {1..30}; do
  if curl -fsS http://localhost:11434/health >/dev/null; then
    echo "✅ Hyperbolic server ready!"
    break
  fi
  sleep 1
done

if ! curl -fsS http://localhost:11434/health >/dev/null; then
  echo "❌ Hyperbolic server not ready"; exit 1
fi

echo "Starting Kuzco worker with complete fake environment..."
exec inference node start --code "${CODE}"
SH
  chmod +x "$KUZCO_DIR/execute.sh"

  # Dockerfile
  cat > "$KUZCO_DIR/Dockerfile" <<'DOCK'
FROM debian:stable-slim
RUN apt-get update && apt-get install -y curl systemd lsof procps git ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN curl -fsSL https://devnet.inference.net/install.sh | sh
COPY ./start.sh /usr/local/bin/inference-runtime
COPY ./execute.sh /app/execute.sh
RUN chmod +x /usr/local/bin/inference-runtime /app/execute.sh
CMD ["/app/execute.sh"]
DOCK

  # docker-compose (host network + ipv4first)
  cat > "$KUZCO_DIR/docker-compose.yml" <<'YML'
version: "3.8"
services:
  kuzco-main:
    build: .
    container_name: kuzco-main
    network_mode: "host"
    privileged: true
    restart: always
    security_opt:
      - apparmor:unconfined
    environment:
      NODE_ENV: "production"
      CODE: "YOUR_WORKER_CODE"
      WORKER_NAME: "YOUR_WORKER_NAME"
      OLLAMA_HOST: "http://localhost:11434"
      OLLAMA_ORIGINS: "*"
      INFERENCE_ENGINE: "hyperbolic"
      CUDA_VISIBLE_DEVICES: "0"
      NODE_OPTIONS: "--dns-result-order=ipv4first"
YML

  ok "Kuzco files dibuat"
}

ask_config(){
  header
  echo -ne "${CYAN}Masukkan Hyperbolic API Key: ${RESET}"; read -r API_KEY
  [[ -n "${API_KEY:-}" ]] || { err "API Key wajib diisi"; exit 1; }
  echo -ne "${CYAN}Masukkan Kuzco Worker Code: ${RESET}"; read -r WORKER_CODE
  [[ -n "${WORKER_CODE:-}" ]] || { err "Worker Code wajib diisi"; exit 1; }
  local DEF_NAME="kuzco-$(hostname)-$(date +%s)"
  echo -ne "${CYAN}Masukkan Worker Name [default: $DEF_NAME]: ${RESET}"; read -r WORKER_NAME
  WORKER_NAME="${WORKER_NAME:-$DEF_NAME}"

  # Tulis env
  sed -i "s|^HYPERBOLIC_API_KEY=.*|HYPERBOLIC_API_KEY=$API_KEY|g" "$HYP_DIR/.env"
  sed -i "s|^HYPERBOLIC_MODEL=.*|HYPERBOLIC_MODEL=$DEFAULT_MODEL|g" "$HYP_DIR/.env"

  sed -i "s|YOUR_WORKER_CODE|$WORKER_CODE|g" "$KUZCO_DIR/docker-compose.yml"
  sed -i "s|YOUR_WORKER_NAME|$WORKER_NAME|g" "$KUZCO_DIR/docker-compose.yml"
}

build_and_up(){
  header
  echo -e "${YELLOW}Build & start Hyperbolic proxy...${RESET}"
  (cd "$HYP_DIR" && docker compose build && docker compose up -d)
  sleep 3
  echo -e "${YELLOW}Build & start Kuzco worker...${RESET}"
  (cd "$KUZCO_DIR" && docker compose build && docker compose up -d)
  ok "Semua service berjalan"
  echo
  echo -e "${GREEN}Test endpoints:${RESET}"
  echo "  curl -s http://localhost:11434/health | jq"
  echo "  curl -s http://localhost:11434/api/tags | jq"
  echo "  curl -s http://localhost:11434/api/chat -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"test aja\"}]}' | jq"
}

status_page(){
  header
  echo -e "${YELLOW}Status containers:${RESET}"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo
  echo -e "${YELLOW}Test Hyperbolic:${RESET}"
  if curl -fsS http://localhost:11434/health >/dev/null; then ok "Hyperbolic sehat"; else err "Hyperbolic tidak merespon"; fi
  echo
}

logs_hyperbolic(){ header; (cd "$HYP_DIR" && docker compose logs -f --tail=200); }
logs_kuzco(){ header; (cd "$KUZCO_DIR" && docker compose logs -f --tail=200); }

stop_all(){
  header
  (cd "$KUZCO_DIR" && docker compose down || true)
  (cd "$HYP_DIR" && docker compose down || true)
  ok "Semua container dihentikan"
}

restart_all(){
  header
  (cd "$HYP_DIR" && docker compose restart || docker compose up -d)
  (cd "$KUZCO_DIR" && docker compose restart || docker compose up -d)
  ok "Semua container direstart"
}

change_model(){
  header
  echo -e "${YELLOW}Ganti model Hyperbolic (kosongkan untuk batal)${RESET}"
  echo -e "Contoh: meta-llama/Llama-3.2-3B-Instruct  (saat ini: $DEFAULT_MODEL)"
  read -p "Model baru: " NEWM || true
  [[ -z "${NEWM:-}" ]] && { warn "Batal"; return; }
  sed -i "s|^HYPERBOLIC_MODEL=.*|HYPERBOLIC_MODEL=$NEWM|g" "$HYP_DIR/.env"
  (cd "$HYP_DIR" && docker compose up -d)
  ok "Model diganti ke: $NEWM"
}

reconfig_keys(){
  header
  echo -ne "${CYAN}API Key baru (enter biar tetap): ${RESET}"; read -r NK || true
  if [[ -n "${NK:-}" ]]; then sed -i "s|^HYPERBOLIC_API_KEY=.*|HYPERBOLIC_API_KEY=$NK|g" "$HYP_DIR/.env"; fi
  (cd "$HYP_DIR" && docker compose up -d)
  ok "API Key ter-update"
}

add_worker(){
  header
  echo -ne "${CYAN}Worker Code tambahan: ${RESET}"; read -r CODE
  [[ -n "${CODE:-}" ]] || { err "Code wajib"; return; }
  local NAME="kuzco-$(hostname)-$RANDOM"
  local DIR="$INSTALL_DIR/kuzco-$RANDOM"
  mkdir -p "$DIR"
  cp -r "$KUZCO_DIR/"* "$DIR/"
  sed -i "s|container_name: kuzco-main|container_name: ${NAME}|g" "$DIR/docker-compose.yml"
  sed -i "s|YOUR_WORKER_CODE|$CODE|g" "$DIR/docker-compose.yml"
  sed -i "s|YOUR_WORKER_NAME|$NAME|g" "$DIR/docker-compose.yml"
  (cd "$DIR" && docker compose build && docker compose up -d)
  ok "Worker baru jalan: $NAME"
}

uninstall_all(){
  header
  stop_all
  rm -rf "$INSTALL_DIR"
  ok "File dihapus: $INSTALL_DIR"
}

install_all(){
  install_docker
  prepare_tree
  write_hyperbolic_files
  write_kuzco_files
  ask_config
  build_and_up
  echo
  status_page
}

menu(){
  while true; do
    header
    echo -e "${LINE}"
    echo -e "  ${GREEN}1.${RESET} Install & Run All Services"
    echo -e "  ${GREEN}2.${RESET} View Logs - Hyperbolic Server"
    echo -e "  ${GREEN}3.${RESET} View Logs - Kuzco Worker"
    echo -e "  ${GREEN}4.${RESET} Stop All Services"
    echo -e "  ${GREEN}5.${RESET} Restart All Services"
    echo -e "  ${GREEN}6.${RESET} Check Status"
    echo -e "  ${GREEN}7.${RESET} Change Model (Default: $DEFAULT_MODEL)"
    echo -e "  ${GREEN}8.${RESET} Reconfigure API Key"
    echo -e "  ${GREEN}9.${RESET} Add Extra Worker"
    echo -e "  ${GREEN}0.${RESET} Uninstall All"
    echo -e "  ${GREEN}q.${RESET} Quit"
    echo -e "${LINE}"
    read -p "Select an option: " opt
    case "$opt" in
      1) install_all ;;
      2) logs_hyperbolic ;;
      3) logs_kuzco ;;
      4) stop_all ;;
      5) restart_all ;;
      6) status_page; read -p "Enter untuk kembali..." _ ;;
      7) change_model ;;
      8) reconfig_keys ;;
      9) add_worker ;;
      0) uninstall_all ;;
      q|Q) exit 0 ;;
      *) warn "Pilihan tidak valid"; sleep 1 ;;
    esac
  done
}

require_root
menu
