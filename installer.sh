#!/usr/bin/env bash
set -euo pipefail

# ================== Konfigurasi ==================
REPO_URL="https://github.com/GoldVPS/hyperbolic-kuzco-setup.git"
INSTALL_DIR="/root/hyperbolic-kuzco-setup"
HYP_DIR="$INSTALL_DIR/hyperbolic-inference"
KUZ_DIR="$INSTALL_DIR/kuzco-main"

# Branding
BRAND_NAME="GoldVPS"
BRAND_URL="https://goldvps.net"

# Warna
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
GOLD='\e[38;5;220m'; BOLD='\e[1m'; OFF='\e[0m'
LINE="${GOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${OFF}"

ok(){ echo -e "${GREEN}✔ $*${RESET}"; }
warn(){ echo -e "${YELLOW}⚠ $*${RESET}"; }
err(){ echo -e "${RED}✖ $*${RESET}" >&2; }

# Jalankan docker compose (plugin) atau docker-compose (legacy)
dc() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

header() {
  clear
  echo -e "${GOLD}"
  echo " ██████╗  ██████╗ ██╗     ██████╗ ██╗   ██╗██████╗ ███████╗"
  echo "██╔════╝ ██╔═══██╗██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝"
  echo "██║  ███╗██║   ██║██║     ██║  ██║██║   ██║██████╔╝███████╗"
  echo "██║   ██║██║   ██║██║     ██║  ██║╚██╗ ██╔╝██╔═══╝ ╚════██║"
  echo "╚██████╔╝╚██████╔╝███████╗██████╔╝ ╚████╔╝ ██║     ███████║"
  echo " ╚═════╝  ╚═════╝ ╚══════╝╚═════╝   ╚═══╝  ╚═╝     ╚══════╝"
  echo -e "${OFF}"
  echo -e "🚀 ${BOLD}${BRAND_NAME} Kuzco Auto-Installer (No-GPU)${OFF} — ${BOLD}${BRAND_URL}${OFF}"
  echo
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Jalankan sebagai root. Gunakan: sudo su -"
    exit 1
  fi
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "Docker belum terpasang. Menginstal Docker..."
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
    systemctl enable --now docker
    ok "Docker terpasang."
  else
    ok "Docker siap."
  fi
}

ensure_compose() {
  if docker compose version >/dev/null 2>&1; then
    ok "Docker Compose (plugin) tersedia."
    return
  fi
  if ! command -v docker-compose >/dev/null 2>&1; then
    warn "Menginstal docker-compose (legacy)..."
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ok "docker-compose terpasang."
  else
    ok "docker-compose siap."
  fi
}

clone_or_update_repo() {
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    warn "Repo sudah ada. Pull update terbaru..."
    git -C "$INSTALL_DIR" fetch --all --prune
    git -C "$INSTALL_DIR" reset --hard origin/main
    ok "Repo di-update."
  else
    warn "Cloning repo $REPO_URL ..."
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    ok "Repo berhasil di-clone: $INSTALL_DIR"
  fi
}

configure_hyperbolic_env() {
  local api_key="$1"
  cd "$HYP_DIR"
  if [[ -f ".env.example" ]]; then
    cp -f .env.example .env
  fi
  # Pastikan variabel kunci terisi
  grep -q '^HYPERBOLIC_API_URL=' .env || echo 'HYPERBOLIC_API_URL=https://api.hyperbolic.xyz/v1' >> .env
  sed -i "s|^HYPERBOLIC_API_URL=.*|HYPERBOLIC_API_URL=https://api.hyperbolic.xyz/v1|g" .env

  grep -q '^HYPERBOLIC_API_KEY=' .env || echo 'HYPERBOLIC_API_KEY=' >> .env
  sed -i "s|^HYPERBOLIC_API_KEY=.*|HYPERBOLIC_API_KEY=${api_key}|g" .env

  grep -q '^HYPERBOLIC_MODEL=' .env || echo 'HYPERBOLIC_MODEL=meta-llama/Llama-3.2-3B-Instruct' >> .env
  sed -i "s|^HYPERBOLIC_MODEL=.*|HYPERBOLIC_MODEL=meta-llama/Llama-3.2-3B-Instruct|g" .env

  ok "Hyperbolic .env dikonfigurasi."
}

patch_kuzco_compose_ipv4_ollama() {
  # Patch kuzo-main/docker-compose.yml supaya
  # - host network
  # - privileged
  # - OLLAMA_HOST -> http://localhost:11434
  # - NODE_OPTIONS ipv4first
  # - apparmor unconfined
  local f="$KUZ_DIR/docker-compose.yml"
  [[ -f "$f" ]] || return 0

  # Hapus baris 'version:' (warning obsolete)
  sed -i '/^version:/d' "$f"

  # Pastikan network_mode host
  if ! grep -q 'network_mode:\s*host' "$f"; then
    sed -i 's/^\(\s*kuzco-main:\)/\1\n    network_mode: "host"/' "$f"
  fi

  # privileged true
  if ! grep -q 'privileged:\s*true' "$f"; then
    sed -i 's/^\(\s*kuzco-main:\)/\1\n    privileged: true/' "$f"
  fi

  # security_opt apparmor unconfined
  if ! grep -q 'security_opt:' "$f"; then
    sed -i 's/^\(\s*kuzco-main:\)/\1\n    security_opt:\n      - apparmor:unconfined/' "$f"
  fi

  # OLLAMA_HOST -> 11434
  if grep -q 'OLLAMA_HOST' "$f"; then
    sed -i 's|OLLAMA_HOST:.*|OLLAMA_HOST: "http://localhost:11434"|' "$f"
  else
    sed -i 's/^\(\s*environment:\)/\1\n      OLLAMA_HOST: "http:\/\/localhost:11434"/' "$f"
  fi

  # Tambah NODE_OPTIONS ipv4first
  if grep -q 'NODE_OPTIONS' "$f"; then
    sed -i 's|NODE_OPTIONS:.*|NODE_OPTIONS: "--dns-result-order=ipv4first"|' "$f"
  else
    sed -i 's/^\(\s*environment:\)/\1\n      NODE_OPTIONS: "--dns-result-order=ipv4first"/' "$f"
  fi

  ok "docker-compose Kuzco dipatch (IPv4-first, OLLAMA_HOST=11434, host+privileged)."
}

configure_kuzco_env() {
  local worker_code="$1"
  local worker_name="$2"

  patch_kuzco_compose_ipv4_ollama

  # Ganti CODE & WORKER_NAME pada compose Kuzco
  local f="$KUZ_DIR/docker-compose.yml"
  if grep -q 'CODE:' "$f"; then
    sed -i "s|CODE:.*|CODE: \"${worker_code}\"|" "$f"
  else
    sed -i "s/^\(\s*environment:\)/\1\n      CODE: \"${worker_code}\"/" "$f"
  fi

  if grep -q 'WORKER_NAME:' "$f"; then
    sed -i "s|WORKER_NAME:.*|WORKER_NAME: \"${worker_name}\"|" "$f"
  else
    sed -i "s/^\(\s*environment:\)/\1\n      WORKER_NAME: \"${worker_name}\"/" "$f"
  fi

  ok "Kuzco env (CODE, WORKER_NAME) diset."
}

build_start_hyperbolic() {
  header; echo -e "${LINE}"
  echo -e "Build & start ${BOLD}Hyperbolic Inference${OFF}..."
  cd "$HYP_DIR"
  dc build
  dc up -d
  sleep 5
  if curl -fsS http://localhost:11434/health >/dev/null 2>&1; then
    ok "Hyperbolic sehat di :11434"
  else
    warn "Health belum OK. Cek logs:"
    dc logs --tail=100
  fi
}

build_start_kuzco() {
  header; echo -e "${LINE}"
  echo -e "Build & start ${BOLD}Kuzco Worker${OFF}..."
  cd "$KUZ_DIR"
  dc build
  dc up -d
  ok "Kuzco up."
}

show_status() {
  echo -e "${YELLOW}Status container:${RESET}"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo
  echo -e "${YELLOW}Cek Hyperbolic:${RESET}"
  curl -fsS http://localhost:11434/health || true
  echo
  echo -e "${YELLOW}Cek model tags:${RESET}"
  curl -fsS http://localhost:11434/api/tags || true
  echo
}

logs_hyperbolic() { cd "$HYP_DIR" && dc logs -f --tail=200; }
logs_kuzco() { cd "$KUZ_DIR" && dc logs -f --tail=200; }

restart_all() {
  (cd "$HYP_DIR" && dc restart || true)
  (cd "$KUZ_DIR" && dc restart || true)
  ok "Semua direstart."
}

stop_all() {
  (cd "$HYP_DIR" && dc down || true)
  (cd "$KUZ_DIR" && dc down || true)
  ok "Semua dihentikan."
}

uninstall_full() {
  stop_all
  rm -rf "$INSTALL_DIR"
  ok "Repo & container dihapus."
}

install_run_all() {
  header
  read -rp "$(echo -e ${CYAN}Masukkan Hyperbolic API Key:${RESET} )" H_API
  [[ -n "${H_API:-}" ]] || { err "API Key wajib diisi"; return 1; }

  read -rp "$(echo -e ${CYAN}Masukkan Kuzco Worker Code:${RESET} )" W_CODE
  [[ -n "${W_CODE:-}" ]] || { err "Worker Code wajib diisi"; return 1; }

  DEFAULT_NAME="kuzco-$(hostname)-$(date +%s)"
  read -rp "$(echo -e ${CYAN}Masukkan Worker Name [default: $DEFAULT_NAME]:${RESET} )" W_NAME
  W_NAME=${W_NAME:-$DEFAULT_NAME}

  ensure_docker
  ensure_compose
  clone_or_update_repo
  configure_hyperbolic_env "$H_API"
  configure_kuzco_env "$W_CODE" "$W_NAME"
  build_start_hyperbolic
  build_start_kuzco
  show_status

  echo
  ok "🚀 Selesai! ${BOLD}${BRAND_NAME}${OFF} installer sukses jalan."
  echo -e " • Hyperbolic  : http://localhost:11434"
  echo -e " • Install dir : ${INSTALL_DIR}"
  echo -e " • Worker Name : ${W_NAME}"
  echo
}

main_menu() {
  while true; do
    header
    echo -e "${LINE}"
    echo -e "  ${GREEN}1.${RESET} Install & Run All (clone/update + build + start)"
    echo -e "  ${GREEN}2.${RESET} View Logs - Hyperbolic"
    echo -e "  ${GREEN}3.${RESET} View Logs - Kuzco"
    echo -e "  ${GREEN}4.${RESET} Restart All"
    echo -e "  ${GREEN}5.${RESET} Stop All"
    echo -e "  ${GREEN}6.${RESET} Check Status"
    echo -e "  ${GREEN}7.${RESET} Reinstall Fresh (full re-clone)"
    echo -e "  ${GREEN}8.${RESET} Uninstall (hapus semua)"
    echo -e "  ${GREEN}9.${RESET} Exit"
    echo -e "${LINE}"
    read -rp "Pilih menu (1-9): " opt
    case "${opt:-}" in
      1) install_run_all ;;
      2) logs_hyperbolic ;;
      3) logs_kuzco ;;
      4) restart_all; read -rp "Enter untuk kembali..." ;;
      5) stop_all; read -rp "Enter untuk kembali..." ;;
      6) show_status; read -rp "Enter untuk kembali..." ;;
      7) stop_all; rm -rf "$INSTALL_DIR"; ok "Silakan pilih menu 1 untuk install ulang."; read -rp "Enter..." ;;
      8) uninstall_full; read -rp "Enter..." ;;
      9) exit 0 ;;
      *) echo "Pilihan tidak valid"; sleep 1 ;;
    esac
  done
}

# ================== Eksekusi ==================
require_root
main_menu
