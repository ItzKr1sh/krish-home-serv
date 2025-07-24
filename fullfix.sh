#!/bin/bash

# Enterprise Server Full Fix Script
# Author: Enterprise Systems Engineer
# Created: 2025-07-24 16:53:43 UTC
# For: ItzKr1sh

# Set strict error handling
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Print functions
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
print_info() { echo -e "${BLUE}[ℹ]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
    exit 1
fi

# Ensure sudo access
if ! sudo -n true 2>/dev/null; then
    print_error "This script requires sudo privileges. Please run: sudo -v"
    exit 1
fi

print_info "Starting comprehensive system fix..."

# 1. Fix Docker permissions
print_info "Fixing Docker permissions..."

# Ensure Docker is installed
if ! command -v docker &>/dev/null; then
    print_info "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
fi

# Add user to Docker group
sudo usermod -aG docker $USER
sudo systemctl restart docker

# Create Docker config directory with correct permissions
mkdir -p ~/.docker
sudo chown "$USER":"$USER" /home/"$USER"/.docker -R
sudo chmod g+rwx "$HOME/.docker" -R

print_status "Docker permissions fixed. You'll need to log out and back in for changes to take effect."

# 2. Set up Minecraft directory
MINECRAFT_DIR="$HOME/server-data/minecraft"
mkdir -p "$MINECRAFT_DIR"
cd "$MINECRAFT_DIR"

# 3. Download server using multiple methods
print_info "Attempting to download Minecraft Bedrock server..."

# Function to verify download
verify_download() {
    local file="$1"
    if [[ -f "$file" && $(stat -c%s "$file") -gt 1000000 ]]; then
        return 0
    fi
    return 1
}

# Method 1: Direct download with curl
download_with_curl() {
    local url="$1"
    local output="$2"
    curl -L --retry 5 --retry-delay 3 -o "$output" "$url"
}

# Method 2: Direct download with wget
download_with_wget() {
    local url="$1"
    local output="$2"
    wget --tries=5 --timeout=20 -O "$output" "$url"
}

MINECRAFT_VERSION="1.21.44.01"
SERVER_URLS=(
    "https://minecraft.azureedge.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
    "https://download.minecraft.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
)

success=false
for url in "${SERVER_URLS[@]}"; do
    print_info "Trying URL: $url"
    if download_with_curl "$url" "bedrock-server.zip" || download_with_wget "$url" "bedrock-server.zip"; then
        if verify_download "bedrock-server.zip"; then
            success=true
            break
        fi
    fi
done

if ! $success; then
    print_warning "Direct downloads failed, attempting Docker method..."
    
    # Ensure we're in the docker group for this session
    if ! groups | grep -q docker; then
        exec sg docker "$0"
    fi
    
    # Pull and extract from Docker image
    docker pull itzg/minecraft-bedrock-server:latest
    docker create --name mc-temp itzg/minecraft-bedrock-server:latest
    docker cp mc-temp:/bedrock/. .
    docker rm mc-temp
    
    if [ -f "bedrock_server" ]; then
        success=true
    fi
fi

if $success; then
    # Set up server configuration
    chmod +x bedrock_server
    
    # Create server.properties
    cat > server.properties << 'EOF'
server-name=Krish Home Server
gamemode=survival
difficulty=easy
allow-cheats=false
max-players=20
online-mode=true
allow-list=false
server-port=19132
server-portv6=19133
enable-lan-visibility=true
view-distance=32
tick-distance=4
player-idle-timeout=30
max-threads=8
EOF

    # Create Docker Compose file
    cat > docker-compose.yml << EOF
version: '3.8'
services:
  minecraft:
    image: itzg/minecraft-bedrock-server:latest
    container_name: minecraft-bedrock
    environment:
      EULA: "TRUE"
      SERVER_NAME: "Krish Home Server"
      GAMEMODE: survival
      DIFFICULTY: easy
      ALLOW_CHEATS: "false"
      MAX_PLAYERS: 20
      ONLINE_MODE: "true"
      VIEW_DISTANCE: 32
      TICK_DISTANCE: 4
      PLAYER_IDLE_TIMEOUT: 30
      MAX_THREADS: 8
    ports:
      - "19132:19132/udp"
      - "19133:19133/udp"
    volumes:
      - ./worlds:/bedrock/worlds
      - ./resource_packs:/bedrock/resource_packs
      - ./behavior_packs:/bedrock/behavior_packs
      - ./server.properties:/bedrock/server.properties
    restart: unless-stopped
    stdin_open: true
    tty: true
EOF

    print_status "Server files and configuration prepared successfully!"
    
    # Create convenience script
    cat > start-server.sh << 'EOF'
#!/bin/bash
docker compose up -d
echo "Server starting... Check status with: docker ps"
EOF
    chmod +x start-server.sh
    
    print_info "Next steps:"
    echo "1. Log out and log back in to apply Docker group changes"
    echo "2. Run: cd $MINECRAFT_DIR && ./start-server.sh"
    echo "3. Server will be accessible on port 19132 (UDP)"
else
    print_error "All download methods failed. Please check your internet connection and try again."
    exit 1
fi

print_status "Fix script completed successfully!"