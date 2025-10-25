#!/usr/bin/env bash
set -euo pipefail

# =========================
# GoldVPS Kuzco Installer
# =========================
REPO_URL_DEFAULT="https://github.com/GoldVPS/hyperbolic-kuzco-setup.git"
INSTALL_DIR="/root/hyperbolic-kuzco-setup"
H_DIR="$INSTALL_DIR/hyperbolic-inference"
K_DIR="$INSTALL_DIR/kuzco-main"

# Colors
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
GOLD='\e[38;5;220m'; BOLD='\e[1m'; ULINE='\e[4m'; NC='\e[0m'
LINE="${GOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

ok(){ echo -e "${GREEN}✔ $*${RESET}"; }
warn(){ echo -e "${YELLOW}⚠ $*${RESET}"; }
err(){ echo -e "${RED}✖ $*${RESET}" >&2; }
pause(){ read -n 1 -s -r -p "Press any key to return to menu"; echo; }

header(){
  clear
  echo -e "${GOLD}"
  echo " ██████╗  ██████╗ ██╗     ██████╗ ██╗   ██╗██████╗ ███████╗"
  echo "██╔════╝ ██╔═══██╗██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝"
  echo "██║  ███╗██║   ██║██║     ██║  ██║██║   ██║██████╔╝███████╗"
  echo "██║   ██║██║   ██║██║     ██║  ██║╚██╗ ██╔╝██╔═══╝ ╚════██║"
  echo "╚██████╔╝╚██████╔╝███████╗██████╔╝ ╚████╔╝ ██║     ███████║"
  echo " ╚═════╝  ╚═════╝ ╚══════╝╚═════╝   ╚═══╝  ╚═╝     ╚══════╝"
  echo -e "${NC}"
  echo -e "🚀 ${BOLD}Kuzco Without GPU Node Installer${NC} - Powered by ${BOLD}GoldVPS Team${NC} 🚀"
  echo -e "🌐 ${ULINE}https://goldvps.net${NC} • Best VPS with Low Price"
  echo
}

need_root(){
  if [[ $EUID -ne 0 ]]; then
    err "Run as root! (sudo su -)"
    exit 1
  fi
}

install_docker(){
  echo -e "${YELLOW}Installing Docker...${RESET}"
  if ! command -v docker >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg git lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker; systemctl start docker
  fi
  ok "Docker ready"
}

install_compose(){
  echo -e "${YELLOW}Installing Docker Compose...${RESET}"
  if ! command -v docker-compose >/dev/null 2>&1; then
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  fi
  ok "Docker Compose ready"
}

clone_repo(){
  echo -e "${YELLOW}Clone repository...${RESET}"
  read -rp "Repo URL [default: $REPO_URL_DEFAULT]: " REPO_URL
  REPO_URL=${REPO_URL:-$REPO_URL_DEFAULT}

  read -rp "Branch/Tag (kosongkan untuk default repo): " REPO_REF || true

  rm -rf "$INSTALL_DIR"
  if [[ -n "${REPO_REF:-}" ]]; then
    git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$INSTALL_DIR"
  else
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi
  ok "Repo cloned to $INSTALL_DIR"
}

configure_env(){
  echo -e "${YELLOW}Konfigurasi Hyperbolic .env...${RESET}"
  mkdir -p "$H_DIR"
  cd "$H_DIR"

  # Buat .env dari template kalau belum ada
  if [[ -f ".env.example" && ! -f ".env" ]]; then
    cp .env.example .env
  fi

  # Minta API key & model (pakai nilai lama jika ada)
  local cur_key cur_model
  cur_key="$(grep -E '^HYPERBOLIC_API_KEY=' .env 2>/dev/null | cut -d= -f2- || true)"
  cur_model="$(grep -E '^HYPERBOLIC_MODEL=' .env 2>/dev/null | cut -d= -f2- || true)"

  read -rp "HYPERBOLIC_API_KEY [hidden] (enter untuk keep current): " -s NEW_KEY
  echo
  read -rp "HYPERBOLIC_MODEL [default: meta-llama/Llama-3.2-3B-Instruct]: " NEW_MODEL

  NEW_KEY=${NEW_KEY:-$cur_key}
  NEW_MODEL=${NEW_MODEL:-${cur_model:-meta-llama/Llama-3.2-3B-Instruct}}

  # tulis .env
  grep -v -E '^(HYPERBOLIC_API_KEY|HYPERBOLIC_MODEL)=' .env 2>/dev/null > .env.tmp || true
  {
    echo "HYPERBOLIC_API_URL=${HYPERBOLIC_API_URL:-https://api.hyperbolic.xyz/v1}"
    echo "HYPERBOLIC_API_KEY=$NEW_KEY"
    echo "HYPERBOLIC_MODEL=$NEW_MODEL"
  } >> .env.tmp
  mv .env.tmp .env
  ok ".env configured"
}

patch_compose_proxy(){
  # pastikan 14444:11434 ter-expose
  cd "$H_DIR"
  if ! grep -q '14444:11434' docker-compose.yml; then
    sed -i 's/ports:\s*$/ports:\n      - "11434:11434"\n      - "14444:11434"/' docker-compose.yml || true
    # fallback: kalau format beda, tambahkan manual
    if ! grep -q '14444:11434' docker-compose.yml; then
      awk '
      {print}
      /services:/ {svc=1}
      svc && /hyperbolic-inference:/ {inf=1}
      inf && /ports:/ && !p {print "      - \"11434:11434\"\n      - \"14444:11434\""; p=1}
      ' docker-compose.yml > dc.tmp && mv dc.tmp docker-compose.yml
    fi
    ok "Proxy compose patched (ports 11434 & 14444)"
  else
    ok "Proxy ports already correct"
  fi
}

patch_compose_kuzco(){
  cd "$K_DIR"
  # pastikan OLLAMA_HOST mapping, NODE_OPTIONS ipv4first, dan format env mapping (bukan list)
  if ! grep -q 'OLLAMA_HOST' docker-compose.yml; then
    warn "Menambahkan environment mapping ke docker-compose Kuzco..."
  fi

  # pastikan environment block berisi key:value (bukan '- KEY=VAL')
  # ganti OLLAMA_HOST ke 14444
  if grep -q 'OLLAMA_HOST:' docker-compose.yml; then
    sed -i 's|OLLAMA_HOST:.*|OLLAMA_HOST: "http://localhost:14444"|' docker-compose.yml
  else
    sed -i 's/environment:\s*$/environment:\n      OLLAMA_HOST: "http:\/\/localhost:14444"/' docker-compose.yml
  fi

  # tambahkan OLLAMA_ORIGINS jika belum
  grep -q 'OLLAMA_ORIGINS:' docker-compose.yml || \
    sed -i 's/OLLAMA_HOST: .*$/OLLAMA_HOST: "http:\/\/localhost:14444"\n      OLLAMA_ORIGINS: "*"/' docker-compose.yml

  # NODE_OPTIONS ipv4first (key:value)
  if grep -q 'NODE_OPTIONS:' docker-compose.yml; then
    sed -i 's|NODE_OPTIONS:.*|NODE_OPTIONS: "--dns-result-order=ipv4first"|' docker-compose.yml
  else
    sed -i 's/OLLAMA_ORIGINS: "\*"/OLLAMA_ORIGINS: "*"\n      NODE_OPTIONS: "--dns-result-order=ipv4first"/' docker-compose.yml
  fi

  # pastikan privileged + host network (opsional, sudah ada di repo)
  grep -q 'network_mode: host' docker-compose.yml || \
    sed -i 's/container_name:.*/container_name: kuzco-main\n    network_mode: "host"/' docker-compose.yml

  grep -q 'privileged: true' docker-compose.yml || \
    sed -i 's/network_mode: "host"/network_mode: "host"\n    privileged: true/' docker-compose.yml

  ok "Kuzco compose patched (OLLAMA_HOST 14444, IPv4 first)"
}

build_start_proxy(){
  cd "$H_DIR"
  echo -e "${YELLOW}Build & start Hyperbolic proxy...${RESET}"
  docker-compose build
  docker-compose up -d
  sleep 3
  if curl -fsS http://localhost:11434/health >/dev/null 2>&1; then
    ok "Proxy up on 11434"
  else
    warn "Health 11434 belum respon (mungkin butuh beberapa detik)"
  fi
  # test via 14444
  if curl -fsS http://localhost:14444/api/tags >/dev/null 2>&1; then
    ok "Compat route alive on 14444 (/api/tags)"
  else
    warn "Endpoint 14444/api/tags belum respon (akan dites lagi saat status)"
  fi
}

build_start_kuzco(){
  cd "$K_DIR"
  echo -e "${YELLOW}Build & start Kuzco worker...${RESET}"

  # inject CODE & WORKER_NAME jika placeholder masih default
  read -rp "Masukkan Worker CODE (biarkan kosong untuk keep): " NEW_CODE || true
  read -rp "Masukkan WORKER_NAME (biarkan kosong untuk keep): " NEW_NAME || true
  [[ -n "${NEW_CODE:-}" ]] && sed -i "s|CODE: \".*\"|CODE: \"$NEW_CODE\"|" docker-compose.yml
  [[ -n "${NEW_NAME:-}" ]] && sed -i "s|WORKER_NAME: \".*\"|WORKER_NAME: \"$NEW_NAME\"|" docker-compose.yml

  docker-compose build
  docker-compose up -d
  ok "Kuzco started"
}

status_all(){
  echo -e "${YELLOW}=== STATUS ===${RESET}"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo
  echo -e "${YELLOW}Test endpoints:${RESET}"
  curl -s http://localhost:11434/health || true; echo
  curl -s http://localhost:14444/api/tags || true; echo
}

logs_proxy(){ cd "$H_DIR" && docker-compose logs -f --tail=200; }
logs_kuzco(){ cd "$K_DIR" && docker-compose logs -f --tail=200; }

stop_all(){
  (cd "$K_DIR" && docker-compose down || true)
  (cd "$H_DIR" && docker-compose down || true)
  ok "All services stopped"
}

restart_all(){
  (cd "$H_DIR" && docker-compose restart || true)
  (cd "$K_DIR" && docker-compose restart || true)
  ok "All services restarted"
}

pull_update(){
  echo -e "${YELLOW}Git pull update...${RESET}"
  (cd "$INSTALL_DIR" && git pull --rebase) || warn "git pull gagal/ada perubahan lokal"
  ok "Repo updated (jika ada)"
}

# Opsional: enable compatibility shim untuk app.py (DEFAULT: OFF)
enable_compat_shim(){
  echo -e "${YELLOW}Mengaktifkan compatibility shim (opsional)...${RESET}"
  echo "Shim ini hanya dipakai bila file app.py repo belum punya route /api/chat dll."
  read -rp "Aktifkan shim sekarang? [y/N]: " yn
  case "${yn:-N}" in
    y|Y)
      cd "$H_DIR"
      cat > app.compat.patch.note <<'NOTE'
Compat Shim Enabled:
- Menambahkan fallback route /api/* agar Kuzco tidak 404.
- Tidak mengubah file repo; hanya menyimpan salinan lokal.
NOTE
      # Salin app.py repo -> app.repo.bak jika ada
      [[ -f app.py ]] && cp app.py app.repo.bak
      # Tulis shim ke app.py
      cat > app.py <<'PY'
from flask import Flask, request, jsonify, Response
import requests, os, json

app = Flask(__name__)
HYPERBOLIC_API_URL = os.getenv("HYPERBOLIC_API_URL","https://api.hyperbolic.xyz/v1")
HYPERBOLIC_API_KEY = os.getenv("HYPERBOLIC_API_KEY","")
HYPERBOLIC_MODEL = os.getenv("HYPERBOLIC_MODEL","meta-llama/Llama-3.2-3B-Instruct")

def convert_ollama_to_hyperbolic(ollama_data):
    messages=[]
    if isinstance(ollama_data,dict):
        if "prompt" in ollama_data:
            messages=[{"role":"user","content":ollama_data["prompt"]}]
        elif "messages" in ollama_data:
            messages=ollama_data["messages"]
    return {
        "model": HYPERBOLIC_MODEL,
        "messages": messages or [{"role":"user","content":"ping"}],
        "max_tokens": ollama_data.get("max_tokens",512) if isinstance(ollama_data,dict) else 512,
        "temperature": ollama_data.get("temperature",0.7) if isinstance(ollama_data,dict) else 0.7,
        "top_p": ollama_data.get("top_p",0.9) if isinstance(ollama_data,dict) else 0.9,
        "stream": ollama_data.get("stream",False) if isinstance(ollama_data,dict) else False
    }

def convert_hyperbolic_to_ollama(resp, original_model):
    try:
        choices=resp.get("choices",[])
        content=choices[0].get("message",{}).get("content","") if choices else ""
        return {"model": original_model, "response": content, "done": True}
    except Exception as e:
        return {"model": original_model, "response": f"Error: {e}", "done": True}

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status":"healthy", "model": HYPERBOLIC_MODEL})

@app.route("/api/tags", methods=["GET"])
def tags():
    return jsonify({"models":[{
        "name": HYPERBOLIC_MODEL,
        "model": HYPERBOLIC_MODEL,
        "modified_at": "2024-01-01T00:00:00Z",
        "size": 3000000000,
        "digest": "hyperbolic-llama3.2-3b",
        "details": {"format":"gguf","family":"llama","parameter_size":"3B"}
    }]} )

@app.route("/api/chat", methods=["POST"])
def api_chat():
    data = request.get_json(force=True, silent=True) or {}
    payload = convert_ollama_to_hyperbolic(data)
    headers={"Authorization":f"Bearer {HYPERBOLIC_API_KEY}","Content-Type":"application/json"}
    r=requests.post(f"{HYPERBOLIC_API_URL}/chat/completions", json=payload, headers=headers, timeout=60)
    if r.status_code!=200:
        return jsonify({"error": f"Hyperbolic API error: {r.status_code}", "body": r.text}), 500
    resp=r.json()
    return jsonify({
        "model": payload["model"],
        "message": {"role":"assistant","content": resp.get("choices",[{}])[0].get("message",{}).get("content","")},
        "done": True
    })

@app.route("/v1/chat/completions", methods=["POST"])
def compat_v1():
    data = request.get_json(force=True, silent=True) or {}
    data["model"] = HYPERBOLIC_MODEL
    headers={"Authorization":f"Bearer {HYPERBOLIC_API_KEY}","Content-Type":"application/json"}
    r=requests.post(f"{HYPERBOLIC_API_URL}/chat/completions", json=data, headers=headers, timeout=60)
    return Response(r.content, status=r.status_code, content_type=r.headers.get("content-type","application/json"))

if __name__=="__main__":
    app.run(host="0.0.0.0", port=11434, debug=False)
PY
      ok "Compat shim diaktifkan. Rebuild proxy..."
      (cd "$H_DIR" && docker-compose build && docker-compose up -d)
      ;;
    *)
      echo "Batal."
      ;;
  esac
}

uninstall_all(){
  stop_all
  rm -rf "$INSTALL_DIR"
  ok "Folder dihapus: $INSTALL_DIR"
}

main_menu(){
  while true; do
    header
    echo -e "${LINE}"
    echo -e "  ${GREEN}1.${RESET} Install (Docker+Clone+Config+Start)"
    echo -e "  ${GREEN}2.${RESET} Start/Restart Semua"
    echo -e "  ${GREEN}3.${RESET} Logs Hyperbolic"
    echo -e "  ${GREEN}4.${RESET} Logs Kuzco"
    echo -e "  ${GREEN}5.${RESET} Status & Test"
    echo -e "  ${GREEN}6.${RESET} Git Pull Update"
    echo -e "  ${GREEN}7.${RESET} (Opsional) Enable Compat Shim"
    echo -e "  ${GREEN}8.${RESET} Stop Semua"
    echo -e "  ${GREEN}9.${RESET} Uninstall (hapus folder)"
    echo -e "  ${GREEN}0.${RESET} Exit"
    echo -e "${LINE}"
    read -rp "Pilih menu (0-9): " opt

    case "${opt:-}" in
      1)
        install_docker
        install_compose
        clone_repo
        configure_env
        patch_compose_proxy
        patch_compose_kuzco
        build_start_proxy
        build_start_kuzco
        status_all
        pause ;;
      2)
        restart_all; status_all; pause ;;
      3)
        logs_proxy ;;
      4)
        logs_kuzco ;;
      5)
        status_all; pause ;;
      6)
        pull_update; pause ;;
      7)
        enable_compat_shim; pause ;;
      8)
        stop_all; pause ;;
      9)
        uninstall_all; pause ;;
      0)
        echo -e "${CYAN}Thank you for using GoldVPS!${RESET}"; exit 0 ;;
      *)
        err "Pilihan salah."; sleep 1 ;;
    esac
  done
}

need_root
main_menu
