#!/bin/bash

# KRISH HOME SERVER v2.0 - Production Grade Ubuntu Server Deployment
# Enterprise-level automation for Minecraft, Nextcloud, Samba, Tailscale, and more
# Author: Advanced Infrastructure Engineer
# License: MIT

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# CONFIGURATION & GLOBALS
# =============================================================================

readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="Krish Home Server"
readonly LOG_FILE="/var/log/krish-server-setup.log"
readonly CONFIG_DIR="$HOME/.config/krish-server"
readonly BACKUP_RETENTION_DAYS=30
readonly MIN_DISK_SPACE_GB=20
readonly MIN_RAM_MB=2048

# Service versions
readonly NEXTCLOUD_VERSION="latest"
readonly MINECRAFT_VERSION="1.21.44.01"
readonly DOCKER_COMPOSE_VERSION="2.24.5"

# Colors and formatting
declare -A COLORS=(
    ["RED"]='\033[0;31m'
    ["GREEN"]='\033[0;32m'
    ["YELLOW"]='\033[1;33m'
    ["BLUE"]='\033[0;34m'
    ["PURPLE"]='\033[0;35m'
    ["CYAN"]='\033[0;36m'
    ["WHITE"]='\033[1;37m'
    ["BOLD"]='\033[1m'
    ["NC"]='\033[0m'
)

# =============================================================================
# LOGGING & OUTPUT FUNCTIONS
# =============================================================================

setup_logging() {
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    sudo touch "$LOG_FILE"
    sudo chmod 666 "$LOG_FILE"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

print_status() {
    echo -e "${COLORS[GREEN]}[✓]${COLORS[NC]} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${COLORS[YELLOW]}[⚠]${COLORS[NC]} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${COLORS[RED]}[✗]${COLORS[NC]} $1" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${COLORS[BLUE]}[ℹ]${COLORS[NC]} $1" | tee -a "$LOG_FILE"
}

print_header() {
    local title="$1"
    echo -e "\n${COLORS[PURPLE]}${'='*70}${COLORS[NC]}"
    echo -e "${COLORS[PURPLE]}$(printf "%*s" $(((70+${#title})/2)) "$title")${COLORS[NC]}"
    echo -e "${COLORS[PURPLE]}${'='*70}${COLORS[NC]}\n"
}

show_banner() {
    clear
    echo -e "${COLORS[CYAN]}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║    ██╗  ██╗██████╗ ██╗███████╗██╗  ██╗    ███████╗███████╗██████╗ ██╗   ██╗ ║
║    ██║ ██╔╝██╔══██╗██║██╔════╝██║  ██║    ██╔════╝██╔════╝██╔══██╗██║   ██║ ║
║    █████╔╝ ██████╔╝██║███████╗███████║    ███████╗█████╗  ██████╔╝██║   ██║ ║
║    ██╔═██╗ ██╔══██╗██║╚════██║██╔══██║    ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝ ║
║    ██║  ██╗██║  ██║██║███████║██║  ██║    ███████║███████╗██║  ██║ ╚████╔╝  ║
║    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═╝    ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝   ║
║                                                                              ║
║                    🔥 ENTERPRISE HOME SERVER v2.0 🔥                         ║
║                        Production-Grade Infrastructure                       ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${COLORS[NC]}"
    echo -e "${COLORS[WHITE]}${COLORS[BOLD]}Version: $SCRIPT_VERSION${COLORS[NC]}"
    echo -e "${COLORS[WHITE]}Log File: $LOG_FILE${COLORS[NC]}\n"
}

# =============================================================================
# VALIDATION & PREREQUISITE CHECKS
# =============================================================================

check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
}

check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges. Please run: sudo -v"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]] || [[ "${VERSION_ID%%.*}" -lt 20 ]]; then
        print_error "This script requires Ubuntu 20.04 or newer"
        exit 1
    fi
    
    print_status "OS check passed: $PRETTY_NAME"
}

check_resources() {
    local available_space_gb
    local available_ram_mb
    
    available_space_gb=$(df / | awk 'NR==2 {printf "%.0f", $4/1024/1024}')
    available_ram_mb=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    
    if [[ $available_space_gb -lt $MIN_DISK_SPACE_GB ]]; then
        print_error "Insufficient disk space. Required: ${MIN_DISK_SPACE_GB}GB, Available: ${available_space_gb}GB"
        exit 1
    fi
    
    if [[ $available_ram_mb -lt $MIN_RAM_MB ]]; then
        print_warning "Low RAM detected. Recommended: ${MIN_RAM_MB}MB, Available: ${available_ram_mb}MB"
    fi
    
    print_status "Resource check passed: ${available_space_gb}GB disk, ${available_ram_mb}MB RAM"
}

check_network() {
    if ! ping -c 1 google.com &> /dev/null; then
        print_error "No internet connection detected"
        exit 1
    fi
    print_status "Network connectivity verified"
}

# =============================================================================
# SYSTEM PREPARATION
# =============================================================================

update_system() {
    print_info "Updating system packages..."
    
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq
    sudo apt-get autoremove -y -qq
    sudo apt-get autoclean -qq
    
    print_status "System updated successfully"
}

install_essentials() {
    print_info "Installing essential packages..."
    
    local packages=(
        curl wget unzip git
        build-essential software-properties-common
        apt-transport-https ca-certificates gnupg lsb-release
        htop btop ncdu tree
        ufw fail2ban
        screen tmux
        nano vim
        zip unzip p7zip-full
        rsync rclone
        jq yq
        certbot python3-certbot-apache
        prometheus-node-exporter
    )
    
    sudo apt-get install -y "${packages[@]}"
    print_status "Essential packages installed"
}

setup_directories() {
    print_info "Creating directory structure..."
    
    local dirs=(
        "$CONFIG_DIR"
        "$HOME/server-data"
        "$HOME/server-data/backups"
        "$HOME/server-data/logs"
        "$HOME/server-data/minecraft"
        "$HOME/server-data/nextcloud"
        "$HOME/server-data/samba"
        "$HOME/server-data/monitoring"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    print_status "Directory structure created"
}

# =============================================================================
# DOCKER INSTALLATION
# =============================================================================

install_docker() {
    print_info "Installing Docker..."
    
    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group
    sudo usermod -aG docker "$USER"
    
    # Start and enable Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    print_status "Docker installed successfully"
}

# =============================================================================
# TAILSCALE VPN
# =============================================================================

setup_tailscale() {
    print_header "TAILSCALE VPN SETUP"
    
    print_info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    
    print_info "Starting Tailscale..."
    print_warning "Please authenticate in your browser when prompted!"
    
    sudo tailscale up --ssh --accept-routes
    
    # Wait for connection and get IP
    local max_attempts=30
    local attempt=1
    local tailscale_ip=""
    
    while [[ $attempt -le $max_attempts ]]; do
        tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "")
        if [[ -n "$tailscale_ip" ]]; then
            break
        fi
        sleep 2
        ((attempt++))
    done
    
    if [[ -n "$tailscale_ip" ]]; then
        echo "$tailscale_ip" > "$CONFIG_DIR/tailscale_ip"
        print_status "Tailscale connected! IP: $tailscale_ip"
    else
        print_warning "Tailscale IP not detected. You can check later with: tailscale ip -4"
    fi
}

# =============================================================================
# MINECRAFT BEDROCK SERVER
# =============================================================================

setup_minecraft() {
    print_header "MINECRAFT BEDROCK SERVER"
    
    local minecraft_dir="$HOME/server-data/minecraft"
    cd "$minecraft_dir"
    
    print_info "Downloading Minecraft Bedrock Server v$MINECRAFT_VERSION..."
    
    local download_url="https://minecraft.azureedge.net/bin-linux/bedrock-server-${MINECRAFT_VERSION}.zip"
    if ! curl -L -o bedrock-server.zip "$download_url"; then
        print_error "Failed to download Minecraft server"
        return 1
    fi
    
    print_info "Extracting server files..."
    unzip -oq bedrock-server.zip
    chmod +x bedrock_server
    
    # Create optimized server configuration
    cat > server.properties << 'EOF'
server-name=Krish Home Server
gamemode=survival
force-gamemode=false
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
level-name=Bedrock level
level-seed=
default-player-permission-level=member
texturepack-required=false
content-log-file-enabled=false
compression-threshold=1
compression-algorithm=zlib
server-authoritative-movement=server-auth
player-position-acceptance-threshold=0.5
player-movement-score-threshold=20
player-movement-action-direction-threshold=0.85
server-authoritative-block-breaking=false
chat-restriction=None
disable-player-interaction=false
client-side-chunk-generation-enabled=true
block-network-ids-are-hashes=true
disable-persona=false
disable-custom-skins=false
server-build-radius-ratio=Disabled
EOF
    
    # Create Docker Compose for Minecraft
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
    networks:
      - minecraft-net

networks:
  minecraft-net:
    driver: bridge
EOF
    
    # Start Minecraft server
    docker compose up -d
    
    print_status "Minecraft Bedrock server deployed with Docker!"
}

# =============================================================================
# NEXTCLOUD SETUP
# =============================================================================

setup_nextcloud() {
    print_header "NEXTCLOUD PRIVATE CLOUD"
    
    local nextcloud_dir="$HOME/server-data/nextcloud"
    cd "$nextcloud_dir"
    
    # Generate secure passwords
    local db_password
    local admin_password
    db_password=$(openssl rand -base64 32)
    admin_password=$(openssl rand -base64 16)
    
    # Save passwords securely
    cat > "$CONFIG_DIR/nextcloud_credentials.txt" << EOF
Database Password: $db_password
Admin Password: $admin_password
Admin Username: admin
EOF
    chmod 600 "$CONFIG_DIR/nextcloud_credentials.txt"
    
    # Create Docker Compose for Nextcloud with full stack
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  db:
    image: mariadb:10.11
    container_name: nextcloud-db
    restart: unless-stopped
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    volumes:
      - ./db:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: $db_password
      MYSQL_PASSWORD: $db_password
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
    networks:
      - nextcloud-net

  redis:
    image: redis:alpine
    container_name: nextcloud-redis
    restart: unless-stopped
    networks:
      - nextcloud-net

  app:
    image: nextcloud:latest
    container_name: nextcloud-app
    restart: unless-stopped
    ports:
      - "8080:80"
    links:
      - db
      - redis
    volumes:
      - ./nextcloud:/var/www/html
      - ./data:/var/www/html/data
    environment:
      MYSQL_PASSWORD: $db_password
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_HOST: db
      REDIS_HOST: redis
      NEXTCLOUD_ADMIN_USER: admin
      NEXTCLOUD_ADMIN_PASSWORD: $admin_password
      NEXTCLOUD_TRUSTED_DOMAINS: localhost $(cat "$CONFIG_DIR/tailscale_ip" 2>/dev/null || echo "")
    depends_on:
      - db
      - redis
    networks:
      - nextcloud-net

  cron:
    image: nextcloud:latest
    container_name: nextcloud-cron
    restart: unless-stopped
    volumes:
      - ./nextcloud:/var/www/html
      - ./data:/var/www/html/data
    entrypoint: /cron.sh
    depends_on:
      - db
      - redis
    networks:
      - nextcloud-net

networks:
  nextcloud-net:
    driver: bridge
EOF
    
    # Start Nextcloud stack
    docker compose up -d
    
    # Wait for Nextcloud to be ready
    print_info "Waiting for Nextcloud to initialize..."
    sleep 30
    
    print_status "Nextcloud deployed! Credentials saved to $CONFIG_DIR/nextcloud_credentials.txt"
}

# =============================================================================
# SAMBA FILE SERVER
# =============================================================================

setup_samba() {
    print_header "SAMBA FILE SERVER"
    
    local samba_dir="$HOME/server-data/samba"
    mkdir -p "$samba_dir"/{public,private}
    
    print_info "Installing Samba..."
    sudo apt-get install -y samba samba-common-bin
    
    # Backup original config
    sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup
    
    # Create optimized Samba configuration
    sudo tee /etc/samba/smb.conf > /dev/null << EOF
[global]
   workgroup = WORKGROUP
   server string = Krish Home Server
   netbios name = KRISHSERVER
   security = user
   map to guest = bad user
   dns proxy = no
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d
   server role = standalone server
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes
   socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
   deadtime = 30
   getwd cache = yes
   lpq cache time = 30
   
   # Performance optimizations
   read raw = yes
   write raw = yes
   oplocks = yes
   max xmit = 65535
   dead time = 15
   large readwrite = yes

[Public]
   comment = Public Files
   path = $samba_dir/public
   browseable = yes
   read only = no
   guest ok = yes
   create mask = 0664
   directory mask = 0775
   force user = $USER
   force group = $USER

[Private]
   comment = Private Files (Authentication Required)
   path = $samba_dir/private
   browseable = yes
   read only = no
   guest ok = no
   valid users = $USER
   create mask = 0600
   directory mask = 0700
   force user = $USER
   force group = $USER
EOF

    # Set up Samba user
    print_info "Setting up Samba user..."
    echo -e "Please enter a password for Samba file sharing:"
    sudo smbpasswd -a "$USER"
    
    # Set permissions
    sudo chown -R "$USER:$USER" "$samba_dir"
    chmod -R 755 "$samba_dir/public"
    chmod -R 700 "$samba_dir/private"
    
    # Start and enable Samba
    sudo systemctl restart smbd nmbd
    sudo systemctl enable smbd nmbd
    
    print_status "Samba file server configured successfully!"
}

# =============================================================================
# MONITORING & MANAGEMENT
# =============================================================================

setup_monitoring() {
    print_header "MONITORING SETUP"
    
    local monitoring_dir="$HOME/server-data/monitoring"
    cd "$monitoring_dir"
    
    # Create monitoring stack with Prometheus, Grafana, and Portainer
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin123
    volumes:
      - grafana_data:/var/lib/grafana

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'

volumes:
  portainer_data:
  grafana_data:
  prometheus_data:
EOF

    # Create Prometheus configuration
    cat > prometheus.yml << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['host.docker.internal:9100']
  
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

    # Start monitoring stack
    docker compose up -d
    
    print_status "Monitoring stack deployed!"
}

# =============================================================================
# SECURITY HARDENING
# =============================================================================

setup_security() {
    print_header "SECURITY CONFIGURATION"
    
    print_info "Configuring UFW firewall..."
    
    # Reset and configure firewall
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Allow essential services
    sudo ufw allow OpenSSH
    sudo ufw allow 8080/tcp       # Nextcloud
    sudo ufw allow 9000/tcp       # Portainer
    sudo ufw allow 3000/tcp       # Grafana
    sudo ufw allow 9090/tcp       # Prometheus
    sudo ufw allow 19132/udp      # Minecraft Bedrock
    sudo ufw allow 19133/udp      # Minecraft Bedrock IPv6
    sudo ufw allow 139/tcp        # Samba
    sudo ufw allow 445/tcp        # Samba
    
    sudo ufw --force enable
    
    print_info "Configuring Fail2Ban..."
    
    # Configure Fail2Ban for additional security
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
    
    # Create custom jail for SSH
    sudo tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

    sudo systemctl restart fail2ban
    
    print_status "Security hardening complete!"
}

# =============================================================================
# BACKUP SYSTEM
# =============================================================================

setup_backup_system() {
    print_header "BACKUP AUTOMATION"
    
    local backup_script="$HOME/krish-backup.sh"
    
    # Create comprehensive backup script
    cat > "$backup_script" << EOF
#!/bin/bash
# Automated backup script for Krish Home Server v2.0

set -euo pipefail

# Configuration
BACKUP_BASE_DIR="\$HOME/server-data/backups"
DATE=\$(date +%Y-%m-%d_%H-%M-%S)
RETENTION_DAYS=$BACKUP_RETENTION_DAYS
LOG_FILE="\$HOME/server-data/logs/backup.log"

# Logging function
log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" | tee -a "\$LOG_FILE"
}

log "Starting backup process..."

# Create backup directories
mkdir -p "\$BACKUP_BASE_DIR"/{minecraft,nextcloud,samba,configs}

# Backup Minecraft worlds
if docker ps --format 'table {{.Names}}' | grep -q minecraft-bedrock; then
    log "Backing up Minecraft worlds..."
    docker exec minecraft-bedrock tar czf - /bedrock/worlds 2>/dev/null | cat > "\$BACKUP_BASE_DIR/minecraft/worlds_\$DATE.tar.gz" || log "Minecraft backup failed"
fi

# Backup Nextcloud data
if [ -d "\$HOME/server-data/nextcloud/data" ]; then
    log "Backing up Nextcloud data..."
    tar czf "\$BACKUP_BASE_DIR/nextcloud/data_\$DATE.tar.gz" -C "\$HOME/server-data/nextcloud" data/ 2>/dev/null || log "Nextcloud backup failed"
fi

# Backup Samba shares
if [ -d "\$HOME/server-data/samba" ]; then
    log "Backing up Samba shares..."
    tar czf "\$BACKUP_BASE_DIR/samba/shares_\$DATE.tar.gz" -C "\$HOME/server-data" samba/ 2>/dev/null || log "Samba backup failed"
fi

# Backup configurations
log "Backing up configurations..."
tar czf "\$BACKUP_BASE_DIR/configs/configs_\$DATE.tar.gz" -C "\$HOME" .config/krish-server/ 2>/dev/null || log "Config backup failed"

# Clean old backups
log "Cleaning old backups (retention: \$RETENTION_DAYS days)..."
find "\$BACKUP_BASE_DIR" -name "*.tar.gz" -mtime +\$RETENTION_DAYS -delete 2>/dev/null || true

# Backup summary
TOTAL_SIZE=\$(du -sh "\$BACKUP_BASE_DIR" | cut -f1)
log "Backup completed successfully. Total backup size: \$TOTAL_SIZE"

# Optional: Upload to cloud storage (uncomment and configure as needed)
# rclone sync "\$BACKUP_BASE_DIR" remote:krish-server-backups/
EOF

    chmod +x "$backup_script"
    
    # Add to crontab for daily execution
    (crontab -l 2>/dev/null; echo "0 2 * * * $backup_script") | crontab -
    
    print_status "Backup system configured! Daily backups at 2:00 AM"
}

# =============================================================================
# HEALTH CHECKS & MONITORING
# =============================================================================

create_health_check() {
    local health_script="$HOME/krish-health-check.sh"
    
    cat > "$health_script" << 'EOF'
#!/bin/bash
# Health check script for Krish Home Server

check_service() {
    local service="$1"
    local container="$2"
    
    if docker ps --format 'table {{.Names}}' | grep -q "$container"; then
        echo "✓ $service: Running"
        return 0
    else
        echo "✗ $service: Not running"
        return 1
    fi
}

echo "=== Krish Home Server Health Check ==="
echo "Timestamp: $(date)"
echo

# Check Docker services
check_service "Minecraft Bedrock" "minecraft-bedrock"
check_service "Nextcloud" "nextcloud-app"
check_service "Portainer" "portainer"
check_service "Grafana" "grafana"
check_service "Prometheus" "prometheus"

echo
# Check system resources
echo "=== System Resources ==="
echo "Disk Usage:"
df -h / | tail -1 | awk '{print "  Root: " $3 " used, " $4 " available (" $5 " full)"}'

echo "Memory Usage:"
free -h | grep '^Mem' | awk '{print "  RAM: " $3 " used, " $7 " available"}'

echo "Load Average:"
uptime | awk -F'load average:' '{print "  " $2}'

echo
# Check Tailscale
if command -v tailscale &> /dev/null; then
    echo "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'Not connected')"
fi

echo "=== End Health Check ==="
EOF

    chmod +x "$health_script"
    
    # Add to crontab for hourly health checks
    (crontab -l 2>/dev/null; echo "0 * * * * $health_script >> $HOME/server-data/logs/health.log 2>&1") | crontab -
}

# =============================================================================
# FINAL SYSTEM STATUS
# =============================================================================

show_final_status() {
    clear
    print_header "DEPLOYMENT COMPLETE"
    
    local tailscale_ip
    tailscale_ip=$(cat "$CONFIG_DIR/tailscale_ip" 2>/dev/null || echo "Run 'tailscale ip -4'")
    
    echo -e "${COLORS[GREEN]}🎉 KRISH HOME SERVER v2.0 IS NOW LIVE! 🎉${COLORS[NC]}\n"
    
    echo -e "${COLORS
