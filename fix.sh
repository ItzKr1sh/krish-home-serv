#!/bin/bash

# Advanced Package Installation Fix for Krish Home Server
# Author: Enterprise Systems Engineer
# Date: 2025-07-24 16:26:30
# Version: 1.0

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print functions
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
print_info() { echo -e "${BLUE}[ℹ]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check for root privileges
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
    exit 1
fi

# Ensure sudo access
if ! sudo -n true 2>/dev/null; then
    print_error "This script requires sudo privileges. Please run: sudo -v"
    exit 1
fi

print_info "Starting advanced package installation fix..."

# 1. Add required repositories
print_status "Adding required repositories..."
sudo add-apt-repository universe -y
sudo add-apt-repository ppa:rmescandon/yq -y

# 2. Update package lists
print_status "Updating package lists..."
sudo apt-get update

# 3. Install btop using multiple methods
print_info "Installing btop..."
if ! sudo apt-get install -y btop; then
    print_warning "APT installation of btop failed, trying snap..."
    if ! command -v snap &> /dev/null; then
        print_info "Installing snap..."
        sudo apt-get install -y snapd
        sudo snap wait system seed.loaded
    fi
    sudo snap install btop
fi

# 4. Install yq using multiple methods
print_info "Installing yq..."
if ! sudo apt-get install -y yq; then
    print_warning "APT installation of yq failed, trying direct download..."
    YQ_VERSION="v4.40.5"
    YQ_BINARY="yq_linux_amd64"
    YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"
    
    sudo wget -q $YQ_URL -O /usr/local/bin/yq
    sudo chmod +x /usr/local/bin/yq
fi

# 5. Verify installations
print_info "Verifying installations..."

# Check btop
if command -v btop &> /dev/null; then
    print_status "btop installed successfully"
    btop --version
else
    print_error "btop installation failed"
fi

# Check yq
if command -v yq &> /dev/null; then
    print_status "yq installed successfully"
    yq --version
else
    print_error "yq installation failed"
fi

# Update the packages array in setup.sh
print_info "Updating setup.sh package list..."
sed -i 's/htop btop ncdu tree/htop ncdu tree/' "$PWD/setup.sh"

print_status "Package installation fix completed successfully!"
print_info "You can now continue with the main setup script"