#!/bin/bash

# Minecraft Bedrock Server Download Fix - Revised
# Author: Enterprise Systems Engineer
# Created: 2025-07-24 16:47:08 UTC
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

# Version from main script
MINECRAFT_VERSION="1.21.44.01"
MINECRAFT_DIR="$HOME/server-data/minecraft"

print_info "Starting Minecraft Bedrock Server download fix..."

# Ensure directory exists and is clean
print_info "Preparing directory..."
mkdir -p "$MINECRAFT_DIR"
cd "$MINECRAFT_DIR"

# Function to test DNS resolution
test_dns() {
    local domain="$1"
    if host "$domain" 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Function to attempt download with different methods
download_server() {
    local url="$1"
    local output="$2"
    
    # Try wget with specific DNS
    if wget --dns-servers=8.8.8.8,1.1.1.1 --no-check-certificate -q "$url" -O "$output" 2>/dev/null; then
        return 0
    fi
    
    # Try curl with specific DNS
    if curl --dns-servers 8.8.8.8,1.1.1.1 -kL "$url" -o "$output" 2>/dev/null; then
        return 0
    fi
    
    # Try with default DNS but different options
    if wget --no-dns-cache --no-check-certificate -q "$url" -O "$output" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Multiple download URLs (fallbacks)
URLS=(
    "https://minecraft.azureedge.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
    "https://download.minecraft.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
)

# Test DNS resolution first
print_info "Testing DNS resolution..."
if ! test_dns "minecraft.azureedge.net"; then
    print_warning "DNS resolution issues detected, trying alternative methods..."
fi

# Try downloading from each URL
print_info "Attempting to download Minecraft Bedrock Server v${MINECRAFT_VERSION}..."
success=false

for url in "${URLS[@]}"; do
    print_info "Trying URL: $url"
    if download_server "$url" "bedrock-server.zip"; then
        success=true
        print_status "Download successful!"
        break
    fi
done

if ! $success; then
    print_warning "Direct download failed, trying Docker method..."
    
    if ! command -v docker &>/dev/null; then
        print_error "Docker is required but not installed. Please run the main setup script first."
        exit 1
    fi
    
    # Use Docker to get server files
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
    print_error "All download methods failed. Please check your internet connection and try again."
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