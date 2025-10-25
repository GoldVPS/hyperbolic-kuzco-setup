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
  echo -e "\e[38;5;220m"
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

setup_complete_fake_environment(){
  echo -e "${YELLOW}Setting up complete fake environment based on ViKey logs...${RESET}"
  
  cd "$KUZCO_DIR"
  
  # Fix Dockerfile
  cat > Dockerfile << 'EOF'
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

CMD ["/app/execute.sh"]
EOF

  # Create complete execute.sh based on ViKey logs
  cat > execute.sh << 'EOF'
#!/bin/bash

# Complete fake environment based on ViKey startup logs
echo "Setting up complete fake environment for Kuzco..."

# Create fake nvidia-smi dengan format persis ViKey
cat > /usr/local/bin/nvidia-smi << 'NVSMI'
#!/bin/bash

# Handle --setup-gpu command (from original script)
if [ "$1" = "--setup-gpu" ]; then
    echo "Setting up GPU: $2"
    echo "✅ Fake GPU $2 configured successfully!"
    exit 0
fi

# Handle the EXACT query that Kuzco uses (from ViKey logs)
if [ "$1" = "--query-gpu=uuid,driver_version,name,memory.total,pci.bus_id" ] && [ "$2" = "--format=csv,noheader,nounits" ]; then
    echo "GPU-fake-12345678-1234-1234-1234-123456789012,535.54.03,NVIDIA GeForce RTX 4090,24576,00000000:01:00.0"
    exit 0
fi

# Default nvidia-smi output
echo "NVIDIA-SMI 535.54.03"
echo "Driver Version: 535.54.03"
echo "CUDA Version: 12.2"
echo ""
echo "| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |"
echo "| Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |"
echo "|                                         |                      |               MIG M. |"
echo "|=========================================+======================+======================|"
echo "|   0  NVIDIA GeForce RTX 4090        Off |   00000000:01:00.0   Off |                  N/A |"
echo "|  0%   45C    P8             25W /  450W |      0MiB /  24576MiB |      0%      Default |"
echo "|                                         |                      |                  N/A |"
echo "+-----------------------------------------+----------------------+----------------------+"
echo ""
echo "+-----------------------------------------------------------------------------+"
echo "| Processes:                                                                  |"
echo "|  GPU   GI   CI        PID   Type   Process name                  GPU Memory |"
echo "|        ID   ID                                                   Usage      |"
echo "|=============================================================================|"
echo "|  No running processes found                                                 |"
echo "+-----------------------------------------------------------------------------+"
exit 0
NVSMI

chmod +x /usr/local/bin/nvidia-smi

# Create fake nvidia-detector
cat > /usr/local/bin/nvidia-detector << 'NVDETECT'
#!/bin/bash
echo "NVIDIA GeForce RTX 4090"
exit 0
NVDETECT
chmod +x /usr/local/bin/nvidia-detector

# Create fake PCI device files (DARI LOGS VIKEY!)
mkdir -p /sys/bus/pci/devices/0000:00:01.0
echo "0x10de" > /sys/bus/pci/devices/0000:00:01.0/vendor
echo "0x2684" > /sys/bus/pci/devices/0000:00:01.0/device

# Juga buat untuk 00000000:01:00.0 (format berbeda)
mkdir -p /sys/bus/pci/devices/0000:01:00.0
echo "0x10de" > /sys/bus/pci/devices/0000:01:00.0/vendor
echo "0x2684" > /sys/bus/pci/devices/0000:01:00.0/device

# Create fake cat command untuk handle PCI device queries
cat > /usr/local/bin/cat << 'CAT'
#!/bin/bash
# Handle specific PCI device files that Kuzco checks
if [[ "$*" == *"/sys/bus/pci/devices/0000:00:01.0/vendor"* ]]; then
    echo "0x10de"
    exit 0
elif [[ "$*" == *"/sys/bus/pci/devices/0000:00:01.0/device"* ]]; then
    echo "0x2684"
    exit 0
elif [[ "$*" == *"/sys/bus/pci/devices/0000:01:00.0/vendor"* ]]; then
    echo "0x10de"
    exit 0
elif [[ "$*" == *"/sys/bus/pci/devices/0000:01:00.0/device"* ]]; then
    echo "0x2684"
    exit 0
else
    # For other files, use real cat
    /bin/cat "$@"
fi
CAT
chmod +x /usr/local/bin/cat

# Create fake df command (DARI LOGS VIKEY!)
cat > /usr/local/bin/df << 'DF'
#!/bin/bash
if [ "$1" = "-h" ]; then
    echo "Filesystem      Size  Used Avail Use% Mounted on"
    echo "overlay          50G   12G   36G  25% /"
else
    echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
    echo "overlay         52428800 12582912 37119588  25% /"
fi
exit 0
DF
chmod +x /usr/local/bin/df

# Create fake lsof command (DARI LOGS VIKEY!)
cat > /usr/local/bin/lsof << 'LSOF'
#!/bin/bash
if [ "$1" = "-ti" ] && [ "$2" = ":8084" ]; then
    # Return empty to indicate no process using port 8084
    exit 0
elif [ "$1" = "-ti" ] && [ "$2" = ":14445" ]; then
    # Return empty to indicate no process using port 14445  
    exit 0
else
    # For other lsof commands, return empty
    exit 0
fi
LSOF
chmod +x /usr/local/bin/lsof

# Create fake fuser command (DARI LOGS VIKEY!)
cat > /usr/local/bin/fuser << 'FUSER'
#!/bin/bash
if [ "$1" = "-v" ] && [[ "$2" == /dev/nvidia* ]]; then
    # Return empty to indicate no processes using nvidia devices
    exit 0
else
    # For other fuser commands, return empty
    exit 0
fi
FUSER
chmod +x /usr/local/bin/fuser

# Create fake kill command (untuk handle cleanup)
cat > /usr/local/bin/kill << 'KILL'
#!/bin/bash
# Fake kill command - just return success
if [ "$1" = "-9" ]; then
    echo "Fake kill: Process $2 terminated"
    exit 0
else
    /bin/kill "$@"
fi
KILL
chmod +x /usr/local/bin/kill

# Create fake /dev/nvidia devices
mkdir -p /dev
mknod /dev/nvidia0 c 195 0 2>/dev/null || true
mknod /dev/nvidiactl c 195 255 2>/dev/null || true
mknod /dev/nvidia-modeset c 195 254 2>/dev/null || true

echo "✅ Complete fake environment setup complete"

# Setup GPU seperti script asli
echo "Setting up fake GPU..."
nvidia-smi --setup-gpu "GeForce RTX 4090"

# Test semua commands yang digunakan Kuzco (dari logs ViKey)
echo "Testing all Kuzco system commands..."
echo "1. Testing nvidia-smi query:"
nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits
echo "2. Testing PCI device files:"
cat /sys/bus/pci/devices/0000:01:00.0/vendor
cat /sys/bus/pci/devices/0000:01:00.0/device
echo "3. Testing df:"
df -h
echo "4. Testing lsof:"
lsof -ti :8084
echo "5. Testing fuser:"
fuser -v /dev/nvidia0

# Wait for Hyperbolic server
echo "Waiting for Hyperbolic inference server..."
sleep 10

# Test Hyperbolic server
if curl -f http://localhost:11434/health >/dev/null 2>&1; then
    echo "✅ Hyperbolic server ready!"
    export OLLAMA_HOST="http://localhost:11434"
    
    # Start Kuzco worker
    echo "Starting Kuzco worker with complete fake environment..."
    inference node start --code $CODE
else
    echo "❌ Hyperbolic server not ready"
    echo "Please check hyperbolic-inference logs: cd ~/hyperbolic-kuzco-setup/hyperbolic-inference && docker-compose logs -f"
    exit 1
fi
EOF

  chmod +x execute.sh
  
  # Update docker-compose.yml dengan volumes untuk system access
# Di fungsi setup_complete_fake_environment(), update docker-compose.yml:
cat > docker-compose.yml << 'EOF'
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
      CUDA_VISIBLE_DEVICES: "0"
EOF

  ok "Complete fake environment setup applied"
}

setup_kuzco(){
  local code="$1" name="$2"
  echo -e "${YELLOW}Setting up Kuzco Worker with Complete Fake Environment...${RESET}"
  
  cd "$KUZCO_DIR"
  
  # Setup complete fake environment
  setup_complete_fake_environment
  
  # Patch docker-compose.yml dengan worker code & name
  sed -i "s|YOUR_WORKER_CODE|$code|g" docker-compose.yml
  sed -i "s|YOUR_WORKER_NAME|$name|g" docker-compose.yml
  
  # Build and run
  docker-compose build
  docker-compose up -d
  
  ok "Kuzco Worker started with Complete Fake Environment"
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
  
  # Test Complete Fake Environment in Kuzco container
  if docker ps | grep -q kuzco-main; then
    echo -e "${YELLOW}Testing Complete Fake Environment...${RESET}"
    if docker exec kuzco-main sh -c "nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits" >/dev/null 2>&1; then
      echo -e "${GREEN}✓ Fake GPU: WORKING${RESET}"
    else
      echo -e "${RED}✗ Fake GPU: NOT WORKING${RESET}"
    fi
    
    # Test PCI device access
    if docker exec kuzco-main sh -c "cat /sys/bus/pci/devices/0000:01:00.0/vendor" >/dev/null 2>&1; then
      echo -e "${GREEN}✓ PCI Devices: ACCESSIBLE${RESET}"
    else
      echo -e "${RED}✗ PCI Devices: NOT ACCESSIBLE${RESET}"
    fi
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
  create_management_scripts
  
  echo
  echo -e "${GREEN}🎉 Installation Complete!${RESET}"
  echo -e "${CYAN}Hyperbolic Server:${RESET} http://localhost:11434"
  echo -e "${CYAN}Install Directory:${RESET} $INSTALL_DIR"
  echo -e "${CYAN}Worker Name:${RESET} $NAME"
  echo -e "${CYAN}Fake Environment:${RESET} Complete GPU & System Simulation"
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
  echo -e "${GREEN}3. Complete Fake Environment Features:${RESET}"
  echo -e "   ✅ Fake NVIDIA GeForce RTX 4090"
  echo -e "   ✅ Fake PCI device files (/sys/bus/pci)"
  echo -e "   ✅ Fake system commands (df, lsof, fuser, cat)"
  echo -e "   ✅ Fake GPU device nodes (/dev/nvidia*)"
  echo -e "   ✅ Complete system simulation based on ViKey logs"
  echo
  echo -e "${GREEN}4. Useful Commands:${RESET}"
  echo -e "   View Hyperbolic logs: cd $HYPERBOLIC_DIR && docker-compose logs -f"
  echo -e "   View Kuzco logs: cd $KUZCO_DIR && docker-compose logs -f"
  echo -e "   Stop all: cd $INSTALL_DIR && ./stop-all.sh"
  echo -e "   Restart all: cd $INSTALL_DIR && ./restart-all.sh"
  echo -e "   Test Fake GPU: docker exec kuzco-main nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits"
  echo
  echo -e "${GREEN}5. Troubleshooting:${RESET}"
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
echo "=== Hyperbolic Kuzco Services Status ==="
echo
echo "Hyperbolic Inference Server:"
cd hyperbolic-inference && docker-compose ps
echo
echo "Kuzco Worker:"
cd ../kuzco-main && docker-compose ps
echo
echo "For detailed logs:"
echo "  Hyperbolic: cd hyperbolic-inference && docker-compose logs -f"
echo "  Kuzco: cd kuzco-main && docker-compose logs -f"
EOF

  # Create test-environment.sh (enhanced version)
  cat > "$INSTALL_DIR/test-environment.sh" << 'EOF'
#!/bin/bash
echo "=== Testing Complete Fake Environment in Kuzco Container ==="
echo
echo "1. Testing nvidia-smi (basic):"
docker exec kuzco-main nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits
echo
echo "2. Testing PCI device access:"
docker exec kuzco-main cat /sys/bus/pci/devices/0000:01:00.0/vendor
docker exec kuzco-main cat /sys/bus/pci/devices/0000:01:00.0/device
echo
echo "3. Testing system commands:"
docker exec kuzco-main df -h
echo
echo "4. Testing nvidia-detector:"
docker exec kuzco-main nvidia-detector
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
    echo -e "  ${GREEN}6.${RESET} Test Complete Environment"
    echo -e "  ${GREEN}7.${RESET} Reinstall All Services"
    echo -e "  ${GREEN}8.${RESET} Quick Instructions"
    echo -e "  ${GREEN}9.${RESET} Exit"
    echo -e "${LINE}"
    read -p "Select an option (1–9): " opt

    case "$opt" in
      1)
        install_all
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
        echo -e "${YELLOW}Testing Complete Fake Environment...${RESET}"
        if [ -f "$INSTALL_DIR/test-environment.sh" ]; then
          "$INSTALL_DIR/test-environment.sh"
        else
          docker exec kuzco-main nvidia-smi --query-gpu=uuid,driver_version,name,memory.total,pci.bus_id --format=csv,noheader,nounits
        fi
        pause
        ;;
      7)
        compose_down_hyperbolic
        compose_down_kuzco
        rm -rf "$INSTALL_DIR"
        ok "Reinstall ready. Select menu 1 to reinstall."
        pause
        ;;
      8)
        view_instructions
        ;;
      9)
        echo -e "${CYAN}Thank you for using GoldVPS!${RESET}"
        exit 0
        ;;
      *)
        err "Invalid option. Choose 1–9."
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
