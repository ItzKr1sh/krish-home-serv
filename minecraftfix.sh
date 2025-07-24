#!/bin/bash

# Minecraft Bedrock Server Download Fix
# Author: Enterprise Systems Engineer
# Created: 2025-07-24 16:42:19 UTC
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

# Version from main script
MINECRAFT_VERSION="1.21.44.01"
MINECRAFT_DIR="$HOME/server-data/minecraft"

print_info "Starting Minecraft Bedrock Server download fix..."

# Ensure directory exists and is clean
print_info "Preparing directory..."
mkdir -p "$MINECRAFT_DIR"
cd "$MINECRAFT_DIR"

# Configure DNS resolvers explicitly
print_info "Configuring DNS resolvers..."
sudo tee /etc/resolv.conf > /dev/null << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
EOF

# Function to attempt download with different methods
download_server() {
    local url="$1"
    local output="$2"
    
    # Try wget first
    if wget --no-check-certificate -q "$url" -O "$output"; then
        return 0
    fi
    
    # Try curl if wget fails
    if curl -kL "$url" -o "$output"; then
        return 0
    fi
    
    return 1
}

# Multiple download URLs (fallbacks)
URLS=(
    "https://minecraft.azureedge.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
    "https://minecraft.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
    "https://download.minecraft.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
)

# Try downloading from each URL
print_info "Attempting to download Minecraft Bedrock Server v${MINECRAFT_VERSION}..."
success=false

for url in "${URLS[@]}"; do
    print_info "Trying URL: $url"
    if download_server "$url" "bedrock-server.zip"; then
        success=true
        break
    fi
done

if ! $success; then
    print_error "All download attempts failed. Trying alternative method..."
    
    # Alternative: Use Docker to pull and extract server files
    print_info "Attempting to extract from Docker image..."
    
    docker pull itzg/minecraft-bedrock-server:latest
    docker create --name mc-temp itzg/minecraft-bedrock-server:latest
    docker cp mc-temp:/bedrock/. .
    docker rm mc-temp
    
    if [ -f "bedrock_server" ]; then
        success=true
        print_status "Successfully extracted server files from Docker image"
    fi
fi

if $success; then
    # Set correct permissions
    chmod +x bedrock_server
    
    # Create default server.properties if it doesn't exist
    if [ ! -f "server.properties" ]; then
        print_info "Creating default server.properties..."
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
    fi
    
    print_status "Minecraft Bedrock Server files are ready!"
    print_info "You can now restart the main setup script"
else
    print_error "Failed to obtain server files. Please check your internet connection and try again."
    exit 1
fi

# Verify files
if [ -f "bedrock_server" ] && [ -f "server.properties" ]; then
    print_status "Installation verified successfully!"
    echo
    echo "Next steps:"
    echo "1. Return to the main setup script"
    echo "2. The server will be containerized automatically"
    echo "3. Your server will be accessible at port 19132 (UDP)"
else
    print_error "Installation verification failed. Please run this script again."
    exit 1
fi