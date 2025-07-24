#!/bin/bash

# Final DNS and Minecraft Server Fix
# Author: Enterprise Systems Engineer
# Created: 2025-07-24 17:04:52
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

print_info "Starting final DNS and Minecraft server fix..."

# Create minecraft directory
mkdir -p "$MINECRAFT_DIR"
cd "$MINECRAFT_DIR"

# Manual DNS configuration
print_info "Configuring DNS manually..."

# Backup existing resolv.conf
if [ -f "/etc/resolv.conf" ]; then
    sudo cp /etc/resolv.conf /etc/resolv.conf.backup
fi

# Create new resolv.conf content
print_info "Setting up DNS servers..."
echo "nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
options timeout:2 attempts:3" | sudo tee /etc/resolv.conf > /dev/null

# Make resolv.conf immutable to prevent system from changing it
sudo chattr +i /etc/resolv.conf

# Function to restore DNS settings on exit
cleanup() {
    print_info "Restoring DNS settings..."
    sudo chattr -i /etc/resolv.conf
    if [ -f "/etc/resolv.conf.backup" ]; then
        sudo mv /etc/resolv.conf.backup /etc/resolv.conf
    fi
}
trap cleanup EXIT

# Install necessary packages without resolvconf
print_info "Installing required packages..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends curl wget dnsutils

# Function to try download with specific DNS server
download_with_dns() {
    local url="$1"
    local output="$2"
    print_info "Attempting download: $url"
    curl --connect-timeout 10 -L -o "$output" "$url" 2>/dev/null || return 1
}

# Docker installation (if needed)
if ! command -v docker &>/dev/null; then
    print_info "Installing Docker..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    sudo systemctl restart docker
    print_warning "Docker installed. You'll need to log out and back in later."
fi

# Try downloading server files
DOWNLOAD_URLS=(
    "https://minecraft.azureedge.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
    "https://download.minecraft.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
)

success=false
for url in "${DOWNLOAD_URLS[@]}"; do
    if download_with_dns "$url" "bedrock-server.zip"; then
        if [ -f "bedrock-server.zip" ] && [ $(stat -c%s "bedrock-server.zip") -gt 1000000 ]; then
            success=true
            break
        fi
    fi
done

# If direct download failed, use Docker method
if ! $success; then
    print_warning "Direct downloads failed. Using Docker method..."
    print_info "Pulling Minecraft server image..."
    
    if groups | grep -q docker; then
        docker pull itzg/minecraft-bedrock-server:latest
        docker create --name mc-temp itzg/minecraft-bedrock-server:latest
        docker cp mc-temp:/bedrock/. .
        docker rm mc-temp
    else
        sudo docker pull itzg/minecraft-bedrock-server:latest
        sudo docker create --name mc-temp itzg/minecraft-bedrock-server:latest
        sudo docker cp mc-temp:/bedrock/. .
        sudo docker rm mc-temp
    fi
    
    if [ -f "bedrock_server" ]; then
        success=true
    fi
fi

if $success; then
    # Ensure correct permissions
    sudo chown -R $USER:$USER .
    chmod +x bedrock_server 2>/dev/null || true
    
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

    # Create start script
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
    
    print_status "Server setup completed successfully!"
    echo
    echo "Next steps:"
    echo "1. Log out and log back in to apply Docker permissions"
    echo "2. Run: cd $MINECRAFT_DIR"
    echo "3. Run: ./start-server.sh"
    
else
    print_error "Server setup failed. Please check your internet connection and try again."
    exit 1
fi

print_status "Fix completed! Please log out and log back in to use Docker without sudo."