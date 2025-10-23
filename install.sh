#!/usr/bin/env bash
set -euo pipefail

# ========= Konfigurasi repo =========
REPO_URL="https://github.com/GoldVPS/hyperbolic-kuzco-setup.git"
INSTALL_DIR="/root/hyperbolic-kuzco-setup"
HYPERBOLIC_DIR="$INSTALL_DIR/hyperbolic-inference"
KUZCO_DIR="$INSTALL_DIR/kuzco-main"

# ========= Warna =========
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
LGOLD='\e[1;33m'; ULINE='\e[4;33m'; NC='\e[0m'
LINE="\e[38;5;220m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"

ok(){ echo -e "${GREEN}✔ $*${RESET}"; }
warn(){ echo -e "${YELLOW}⚠ $*${RESET}"; }
err(){ echo -e "${RED}✖ $*${RESET}" >&2; }
pause(){ read -n 1 -s -r -p "Press any key to return to menu"; echo; }

header(){
  clear
  echo -e "${LGOLD}"
  echo " ██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗  ██████╗ ██╗  ██╗"
  echo " ██║  ██║██║   ██║██╔══██╗██╔════╝██╔══██╗██╔═══██╗██║ ██╔╝"
  echo " ███████║██║   ██║██████╔╝█████╗  ██████╔╝██║   ██║█████╔╝ "
  echo " ██╔══██║██║   ██║██╔══██╗██╔══╝  ██╔══██╗██║   ██║██╔═██╗ "
  echo " ██║  ██║╚██████╔╝██████╔╝███████╗██║  ██║╚██████╔╝██║  ██╗"
  echo " ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝"
  echo "   ██╗  ██╗██╗   ██╗██████╗  ██████╗ ██████╗ "
  echo "   ██║ ██╔╝██║   ██║██╔══██╗██╔═══██╗██╔══██╗"
  echo "   █████╔╝ ██║   ██║██████╔╝██║   ██║██████╔╝"
  echo "   ██╔═██╗ ██║   ██║██╔══██╗██║   ██║██╔══██╗"
  echo "   ██║  ██╗╚██████╔╝██████╔╝╚██████╔╝██║  ██║"
  echo "   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝"
  echo -e "${NC}"
  echo -e "🚀 ${LGOLD}Hyperbolic Kuzco Node Installer${NC} – Powered by ${LGOLD}GoldVPS Team${NC} 🚀"
  echo -e "🌐 ${ULINE}https://goldvps.net${NC} – Best VPS with Low Price"
  echo -e "👤 ${YELLOW}Running as: $(whoami)${NC}"
  echo ""
}

install_docker(){
  echo -e "${YELLOW}Installing Docker...${RESET}"
  if ! command -v docker >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg git lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
  fi
  ok "Docker ready"
}

install_docker_compose(){
  echo -e "${YELLOW}Installing Docker Compose...${RESET}"
  if ! command -v docker-compose >/dev/null 2>&1; then
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  fi
  ok "Docker Compose ready"
}

clone_repo(){
  echo -e "${YELLOW}Syncing repository...${RESET}"
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" || { err "Failed to clone repository."; exit 1; }
  ok "Repository cloned to $INSTALL_DIR"
}

setup_hyperbolic(){
  local api_key="$1"
  echo -e "${YELLOW}Setting up Hyperbolic Inference Server...${RESET}"
  
  cd "$HYPERBOLIC_DIR"
  
  # Create .env from template
  cp .env.example .env
  sed -i "s|your_hyperbolic_api_key_here|$api_key|g" .env
  
  # Build and run
  docker-compose build
  docker-compose up -d
  
  # Wait and test
  echo -e "${YELLOW}Waiting for Hyperbolic server to start...${RESET}"
  sleep 15
  
  # Test server
  if curl -f http://localhost:11434/api/tags >/dev/null 2>&1; then
    ok "Hyperbolic Inference Server running on port 11434"
  else
    err "Hyperbolic server failed to start"
    docker-compose logs
    return 1
  fi
}

setup_kuzco(){
  local code="$1" name="$2"
  echo -e "${YELLOW}Setting up Kuzco Worker...${RESET}"
  
  cd "$KUZCO_DIR"
  
  # Patch docker-compose.yml
  sed -i "s|YOUR_WORKER_CODE|$code|g" docker-compose.yml
  sed -i "s|YOUR_WORKER_NAME|$name|g" docker-compose.yml
  
  # Build and run
  docker-compose build
  docker-compose up -d
  
  ok "Kuzco Worker started"
}

compose_logs_hyperbolic(){
  ( cd "$HYPERBOLIC_DIR" && docker-compose logs -f --tail 100 )
}

compose_logs_kuzco(){
  ( cd "$KUZCO_DIR" && docker-compose logs -f --tail 100 )
}

compose_down_hyperbolic(){
  ( cd "$HYPERBOLIC_DIR" && docker-compose down || true )
  ok "Hyperbolic Server stopped"
}

compose_down_kuzco(){
  ( cd "$KUZCO_DIR" && docker-compose down || true )
  ok "Kuzco Worker stopped"
}

check_status(){
  echo -e "${YELLOW}Checking services status...${RESET}"
  
  # Check Hyperbolic
  if ( cd "$HYPERBOLIC_DIR" && docker-compose ps | grep -q "Up" ); then
    echo -e "${GREEN}✓ Hyperbolic Server: RUNNING${RESET}"
  else
    echo -e "${RED}✗ Hyperbolic Server: STOPPED${RESET}"
  fi
  
  # Check Kuzco
  if ( cd "$KUZCO_DIR" && docker-compose ps | grep -q "Up" ); then
    echo -e "${GREEN}✓ Kuzco Worker: RUNNING${RESET}"
  else
    echo -e "${RED}✗ Kuzco Worker: STOPPED${RESET}"
  fi
  
  # Test Hyperbolic API
  if curl -s http://localhost:11434/health >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Hyperbolic API: RESPONDING${RESET}"
  else
    echo -e "${RED}✗ Hyperbolic API: NOT RESPONDING${RESET}"
  fi
  
  # Show container info
  echo -e "\n${YELLOW}Running containers:${RESET}"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

install_all(){
  echo -ne "${CYAN}Enter Hyperbolic API Key: ${RESET}"
  read -s -r API_KEY; echo
  [[ -n "$API_KEY" ]] || { err "API key is required"; pause; return 1; }

  echo -ne "${CYAN}Enter Kuzco Worker Code: ${RESET}"
  read -r CODE
  [[ -n "$CODE" ]] || { err "Worker code is required"; pause; return 1; }

  DEFAULT_NAME="kuzco-$(hostname)-$(date +%s)"
  echo -ne "${CYAN}Enter Worker Name [default: $DEFAULT_NAME]: ${RESET}"
  read -r NAME
  NAME=${NAME:-$DEFAULT_NAME}

  install_docker
  install_docker_compose
  clone_repo
  setup_hyperbolic "$API_KEY"
  setup_kuzco "$CODE" "$NAME"
  
  echo
  echo -e "${GREEN}🎉 Installation Complete!${RESET}"
  echo -e "${CYAN}Hyperbolic Server:${RESET} http://localhost:11434"
  echo -e "${CYAN}Install Directory:${RESET} $INSTALL_DIR"
  echo -e "${CYAN}Worker Name:${RESET} $NAME"
  echo
  check_status
}

view_instructions(){
  clear
  echo -e "${LGOLD}=== Quick Instructions ===${NC}"
  echo
  echo -e "${GREEN}1. Get Hyperbolic API Key:${RESET}"
  echo -e "   Visit: https://hyperbolic.xyz"
  echo -e "   Sign up and get your API key"
  echo
  echo -e "${GREEN}2. Get Kuzco Worker Code:${RESET}"
  echo -e "   Visit: https://inference.net"
  echo -e "   Create worker and get worker code"
  echo
  echo -e "${GREEN}3. Useful Commands:${RESET}"
  echo -e "   View Hyperbolic logs: cd $HYPERBOLIC_DIR && docker-compose logs -f"
  echo -e "   View Kuzco logs: cd $KUZCO_DIR && docker-compose logs -f"
  echo -e "   Stop all: cd $INSTALL_DIR && ./stop-all.sh"
  echo -e "   Restart all: cd $INSTALL_DIR && ./restart-all.sh"
  echo
  echo -e "${GREEN}4. Troubleshooting:${RESET}"
  echo -e "   Check status: docker ps"
  echo -e "   Check logs: docker logs <container-name>"
  echo -e "   Restart service: docker-compose restart"
  echo
  pause
}

create_management_scripts(){
  echo -e "${YELLOW}Creating management scripts...${RESET}"
  
  # Create stop-all.sh
  cat > "$INSTALL_DIR/stop-all.sh" << 'EOF'
#!/bin/bash
echo "Stopping all Hyperbolic Kuzco services..."
cd hyperbolic-inference && docker-compose down
cd ../kuzco-main && docker-compose down
echo "All services stopped!"
EOF

  # Create restart-all.sh
  cat > "$INSTALL_DIR/restart-all.sh" << 'EOF'
#!/bin/bash
echo "Restarting all Hyperbolic Kuzco services..."
cd hyperbolic-inference && docker-compose restart
cd ../kuzco-main && docker-compose restart
echo "All services restarted!"
EOF

  # Create status.sh
  cat > "$INSTALL_DIR/status.sh" << 'EOF'
#!/bin/bash
echo "=== Service Status ==="
cd hyperbolic-inference && echo "Hyperbolic:" && docker-compose ps
cd ../kuzco-main && echo "Kuzco:" && docker-compose ps
EOF

  chmod +x "$INSTALL_DIR"/*.sh
  ok "Management scripts created"
}

main_menu(){
  while true; do
    header
    echo -e "${LINE}"
    echo -e "  ${GREEN}1.${RESET} Install & Run All Services"
    echo -e "  ${GREEN}2.${RESET} View Logs - Hyperbolic Server"
    echo -e "  ${GREEN}3.${RESET} View Logs - Kuzco Worker" 
    echo -e "  ${GREEN}4.${RESET} Stop All Services"
    echo -e "  ${GREEN}5.${RESET} Check Status"
    echo -e "  ${GREEN}6.${RESET} Reinstall All Services"
    echo -e "  ${GREEN}7.${RESET} Quick Instructions"
    echo -e "  ${GREEN}8.${RESET} Exit"
    echo -e "${LINE}"
    read -p "Select an option (1–8): " opt

    case "$opt" in
      1)
        install_all
        create_management_scripts
        pause
        ;;
      2)
        compose_logs_hyperbolic
        ;;
      3)
        compose_logs_kuzco
        ;;
      4)
        compose_down_hyperbolic
        compose_down_kuzco
        ok "All services stopped"
        pause
        ;;
      5)
        check_status
        pause
        ;;
      6)
        compose_down_hyperbolic
        compose_down_kuzco
        rm -rf "$INSTALL_DIR"
        ok "Reinstall ready. Select menu 1 to reinstall."
        pause
        ;;
      7)
        view_instructions
        ;;
      8)
        echo -e "${CYAN}Thank you for using GoldVPS!${RESET}"
        exit 0
        ;;
      *)
        err "Invalid option. Choose 1–8."
        sleep 1
        ;;
    esac
  done
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   err "This script must be run as root!"
   echo "Switch to root user: sudo su -"
   exit 1
fi

# Main execution
main_menu
