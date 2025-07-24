#!/bin/bash

# DNS-aware Minecraft Server Fix
# Author: Enterprise Systems Engineer
# Created: 2025-07-24 16:59:30 UTC
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

# Version and directories
MINECRAFT_VERSION="1.21.44.01"
MINECRAFT_DIR="$HOME/server-data/minecraft"
TEMP_DIR="/tmp/mcserver-$$"

# Create working directories
mkdir -p "$MINECRAFT_DIR" "$TEMP_DIR"
cd "$TEMP_DIR"

print_info "Starting DNS-aware Minecraft server fix..."

# Test internet connectivity with multiple DNS servers
test_dns() {
    local test_domain="$1"
    local dns_server="$2"
    if dig @"$dns_server" "$test_domain" +short +timeout=2 &>/dev/null; then
        return 0
    fi
    return 1
}

# Function to download with specific DNS
download_with_dns() {
    local url="$1"
    local output="$2"
    local dns="$3"
    
    print_info "Trying download with DNS $dns..."
    curl --dns-servers "$dns" --connect-timeout 10 -L -o "$output" "$url" 2>/dev/null || return 1
}

# Function to verify downloaded file
verify_file() {
    local file="$1"
    if [[ -f "$file" ]] && [[ $(stat -c%s "$file") -gt 1000000 ]]; then
        return 0
    fi
    return 1
}

# Install required packages
print_info "Installing required packages..."
sudo apt-get update -qq
sudo apt-get install -y curl wget dnsutils resolvconf

# Configure multiple DNS resolvers
print_info "Configuring DNS resolvers..."
sudo tee /etc/resolvconf/resolv.conf.d/head > /dev/null << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
nameserver 9.9.9.9
EOF

sudo resolvconf -u

# Alternative download URLs
DOWNLOAD_URLS=(
    "https://minecraft.azureedge.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
    "https://download.minecraft.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
    "https://minecraft.net/download/server/bedrock-${MINECRAFT_VERSION}.zip"
)

# DNS servers to try
DNS_SERVERS=(
    "8.8.8.8"
    "1.1.1.1"
    "8.8.4.4"
    "9.9.9.9"
)

# Try downloading with different DNS servers
success=false
for url in "${DOWNLOAD_URLS[@]}"; do
    for dns in "${DNS_SERVERS[@]}"; do
        print_info "Attempting download from $url using DNS $dns..."
        if download_with_dns "$url" "bedrock-server.zip" "$dns"; then
            if verify_file "bedrock-server.zip"; then
                success=true
                break 2
            fi
        fi
    done
done

# If direct download failed, try Docker method
if ! $success; then
    print_warning "Direct downloads failed. Attempting Docker method..."
    
    # Ensure Docker is installed and user has permissions
    if ! command -v docker &>/dev/null; then
        print_info "Installing Docker..."
        curl -fsSL https://get.docker.com | sudo sh
        sudo usermod -aG docker "$USER"
        sudo systemctl restart docker
        print_warning "Docker installed. You'll need to log out and back in for group changes to take effect."
        print_info "For now, we'll use sudo for Docker commands."
    fi
    
    print_info "Pulling Minecraft server image..."
    sudo docker pull itzg/minecraft-bedrock-server:latest
    
    print_info "Extracting server files..."
    sudo docker create --name mc-temp itzg/minecraft-bedrock-server:latest
    sudo docker cp mc-temp:/bedrock/. "$MINECRAFT_DIR/"
    sudo docker rm mc-temp
    
    if [ -f "$MINECRAFT_DIR/bedrock_server" ]; then
        success=true
    fi
fi

if $success; then
    # Move files if they're in temp dir
    if [ -f "bedrock-server.zip" ]; then
        unzip -o bedrock-server.zip -d "$MINECRAFT_DIR"
    fi
    
    cd "$MINECRAFT_DIR"
    chmod +x bedrock_server
    
    # Create server configuration
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

    # Create Docker compose file
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
    ports:
      - "19132:19132/udp"
      - "19133:19133/udp"
    volumes:
      - ./worlds:/bedrock/worlds
      - ./server.properties:/bedrock/server.properties
    restart: unless-stopped
EOF

    # Create convenience script
    cat > start-server.sh << 'EOF'
#!/bin/bash
if ! groups | grep -q docker; then
    echo "Running with sudo (first time only)..."
    sudo docker compose up -d
else
    docker compose up -d
fi
echo "Server starting! Connect using port 19132"
EOF
    chmod +x start-server.sh
    
    print_status "Server files and configuration ready!"
    print_info "To start the server:"
    echo "1. If this is your first time, log out and log back in"
    echo "2. cd $MINECRAFT_DIR"
    echo "3. ./start-server.sh"
    
    # Clean up
    rm -rf "$TEMP_DIR"
else
    print_error "All download methods failed."
    print_info "Please check your internet connection and try again."
    exit 1
fi

print_status "Fix completed successfully!"