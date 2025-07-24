#!/bin/bash

# Fix script for krish-home-serv btop and yq installation
# Created: 2025-07-24 16:17:38 UTC
# Author: ItzKr1sh

# Set error handling
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print functions
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
    exit 1
fi

# Check sudo access
if ! sudo -n true 2>/dev/null; then
    print_error "This script requires sudo privileges. Please run: sudo -v"
    exit 1
fi

echo "=== Krish Home Server Package Fix ==="
echo "Starting package installation fix..."

# Add universe repository
print_status "Adding universe repository..."
sudo add-apt-repository universe -y

# Update package lists
print_status "Updating package lists..."
sudo apt-get update

# Try to install btop via apt
print_status "Attempting to install btop..."
if ! sudo apt-get install -y btop; then
    print_warning "apt installation of btop failed, trying snap..."
    sudo snap install btop
fi

# Install yq via snap
print_status "Installing yq..."
if ! command -v yq &> /dev/null; then
    if ! sudo snap install yq; then
        print_warning "snap installation of yq failed, downloading from GitHub..."
        YQ_VERSION="v4.40.5"
        sudo wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 -O /usr/bin/yq
        sudo chmod +x /usr/bin/yq
    fi
fi

# Verify installations
echo -e "\nVerifying installations..."

if command -v btop &> /dev/null; then
    print_status "btop installed successfully: $(btop --version 2>&1 | head -n1)"
else
    print_error "btop installation failed"
fi

if command -v yq &> /dev/null; then
    print_status "yq installed successfully: $(yq --version 2>&1)"
else
    print_error "yq installation failed"
fi

echo -e "\n=== Fix Complete ==="
print_status "You can now continue with the main setup script"