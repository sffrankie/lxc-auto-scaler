#!/usr/bin/env bash

# LXC AutoScale - Otomatik Container Kurulumu
# Bu script Proxmox host üzerinde çalışarak LXC AutoScale'i ayrı bir container'da kurar
# Author: Murat
# License: MIT

set -euo pipefail

# Renkler ve semboller
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color
readonly CHECK="✓"
readonly CROSS="✗"
readonly ARROW="➜"

# Varsayılan değerler
readonly TEMPLATE="debian-13-standard_13.0-1_amd64.tar.zst"
readonly STORAGE="local"
readonly DISK_SIZE="8"
readonly CORES="2"
readonly MEMORY="2048"
readonly SWAP="512"
readonly PASSWORD="lxc-autoscale-$(date +%s)"
readonly HOSTNAME_PREFIX="lxc-autoscale"
readonly WEB_PORT="8080"

# Log fonksiyonu
log() {
    local level=$1
    shift
    local message="$*"
    case $level in
        info)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        success)
            echo -e "${GREEN}[${CHECK}]${NC} $message"
            ;;
        error)
            echo -e "${RED}[${CROSS}]${NC} $message"
            ;;
        warning)
            echo -e "${YELLOW}[!]${NC} $message"
            ;;
    esac
}

# Hata yakalama
trap 'log error "Script başarısız oldu. Satır: $LINENO"' ERR

# Root kontrolü
if [[ $EUID -ne 0 ]]; then
   log error "Bu script root olarak çalıştırılmalıdır"
   exit 1
fi

# Proxmox kontrolü
if ! command -v pveversion &> /dev/null; then
    log error "Bu script Proxmox VE üzerinde çalıştırılmalıdır"
    exit 1
fi

log info "LXC AutoScale Container Kurulumu Başlatılıyor..."

# Sıradaki container ID'yi bul
get_next_ctid() {
    local next_id=100
    while pct status $next_id &>/dev/null || qm status $next_id &>/dev/null; do
        ((next_id++))
    done
    echo $next_id
}

CTID=$(get_next_ctid)
HOSTNAME="${HOSTNAME_PREFIX}-${CTID}"

log info "Container ID: $CTID"
log info "Hostname: $HOSTNAME"

# Template kontrolü ve indirme
check_template() {
    log info "Template kontrol ediliyor..."
    
    # Mevcut template'leri listele
    if ! pveam list $STORAGE | grep -q "$TEMPLATE"; then
        log warning "Template bulunamadı, indiriliyor..."
        
        # Önce template listesini güncelle
        pveam update
        
        # Template'i indir
        if pveam download $STORAGE $TEMPLATE; then
            log success "Template indirildi"
        else
            log error "Template indirilemedi. Mevcut template'leri kontrol edin:"
            pveam available | grep debian
            exit 1
        fi
    else
        log success "Template mevcut"
    fi
}

# Container oluştur
create_container() {
    log info "Container oluşturuluyor..."
    
    pct create $CTID ${STORAGE}:vztmpl/${TEMPLATE} \
        --hostname $HOSTNAME \
        --cores $CORES \
        --memory $MEMORY \
        --swap $SWAP \
        --rootfs ${STORAGE}-lvm:${DISK_SIZE} \
        --net0 name=eth0,bridge=vmbr0,ip=dhcp \
        --features nesting=1 \
        --unprivileged 1 \
        --onboot 1 \
        --password "$PASSWORD" \
        --start 1
    
    log success "Container oluşturuldu (CTID: $CTID)"
    
    # Container'ın başlamasını bekle
    log info "Container'ın başlaması bekleniyor..."
    sleep 10
    
    # IP adresini al
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        CONTAINER_IP=$(pct exec $CTID -- hostname -I 2>/dev/null | awk '{print $1}' || true)
        if [[ -n "$CONTAINER_IP" ]]; then
            log success "Container IP: $CONTAINER_IP"
            break
        fi
        sleep 2
        ((attempt++))
    done
    
    if [[ -z "$CONTAINER_IP" ]]; then
        log error "Container IP alınamadı"
        return 1
    fi
}

# LXC AutoScale kurulumu
install_autoscale() {
    log info "LXC AutoScale kurulumu başlatılıyor..."
    
    # Sistem güncellemesi
    log info "Sistem güncelleniyor..."
    pct exec $CTID -- bash -c "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
    
    # Gerekli paketleri kur
    log info "Gerekli paketler kuruluyor..."
    pct exec $CTID -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
        python3 \
        python3-pip \
        python3-yaml \
        python3-requests \
        python3-paramiko \
        python3-cryptography \
        curl \
        git \
        nano \
        openssh-client \
        ca-certificates"
    
    # LXC AutoScale indir
    log info "LXC AutoScale indiriliyor..."
    pct exec $CTID -- bash -c "cd /opt && git clone https://github.com/fabriziosalmi/proxmox-lxc-autoscale.git"
    
    # Dizinleri oluştur
    pct exec $CTID -- mkdir -p /etc/lxc_autoscale
    pct exec $CTID -- mkdir -p /var/log
    pct exec $CTID -- mkdir -p /var/lib/lxc_autoscale/backups
    
    # Python scriptini kopyala
    pct exec $CTID -- cp /opt/proxmox-lxc-autoscale/lxc_autoscale/lxc_autoscale.py /usr/local/bin/lxc_autoscale.py
    pct exec $CTID -- chmod +x /usr/local/bin/lxc_autoscale.py
    
    # Örnek config oluştur
    log info "Yapılandırma dosyası oluşturuluyor..."
    
    cat > /tmp/lxc_autoscale_config.yaml << 'EOF'
DEFAULTS:
  log_file: /var/log/lxc_autoscale.log
  lock_file: /var/lock/lxc_autoscale.lock
  backup_dir: /var/lib/lxc_autoscale/backups
  reserve_cpu_percent: 10
  reserve_memory_mb: 2048
  off_peak_start: 22
  off_peak_end: 6
  behaviour: normal
  cpu_upper_threshold: 80
  cpu_lower_threshold: 20
  memory_upper_threshold: 70
  memory_lower_threshold: 20
  min_cores: 1
  max_cores: 4
  min_memory: 512
  max_memory: 4096
  check_interval: 300
  use_remote_proxmox: true
  ssh_user: root
  ssh_key: /root/.ssh/id_rsa
  proxmox_host: HOST_IP_PLACEHOLDER

TIER_DEFAULT:
  cpu_upper_threshold: 80
  cpu_lower_threshold: 20
  memory_upper_threshold: 70
  memory_lower_threshold: 20
  min_cores: 1
  max_cores: 4
  min_memory: 512
  max_memory: 4096
  lxc_containers: []
EOF
    
    # Host IP'yi al ve config'e yerleştir
    HOST_IP=$(hostname -I | awk '{print $1}')
    sed -i "s/HOST_IP_PLACEHOLDER/$HOST_IP/g" /tmp/lxc_autoscale_config.yaml
    
    pct push $CTID /tmp/lxc_autoscale_config.yaml /etc/lxc_autoscale/lxc_autoscale.yaml
    rm /tmp/lxc_autoscale_config.yaml
    
    log success "Yapılandırma dosyası oluşturuldu"
}

# SSH anahtarı kurulumu
setup_ssh() {
    log info "SSH anahtarı yapılandırılıyor..."
    
    # Container'da SSH key oluştur
    pct exec $CTID -- bash -c "ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N '' -q"
    
    # Public key'i al
    SSH_PUBLIC_KEY=$(pct exec $CTID -- cat /root/.ssh/id_rsa.pub)
    
    # Host'a public key ekle
    if ! grep -q "$SSH_PUBLIC_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
        echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
        log success "SSH anahtarı host'a eklendi"
    fi
    
    # Host'u known_hosts'a ekle
    HOST_IP=$(hostname -I | awk '{print $1}')
    pct exec $CTID -- bash -c "ssh-keyscan -H $HOST_IP >> /root/.ssh/known_hosts 2>/dev/null"
    
    log success "SSH yapılandırması tamamlandı"
}

# Systemd servisi oluştur
create_systemd_service() {
    log info "Systemd servisi oluşturuluyor..."
    
    cat > /tmp/lxc_autoscale.service << 'EOF'
[Unit]
Description=LXC AutoScale Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/bin
ExecStart=/usr/bin/python3 /usr/local/bin/lxc_autoscale.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    pct push $CTID /tmp/lxc_autoscale.service /etc/systemd/system/lxc_autoscale.service
    rm /tmp/lxc_autoscale.service
    
    # Servisi etkinleştir ve başlat
    pct exec $CTID -- systemctl daemon-reload
    pct exec $CTID -- systemctl enable lxc_autoscale.service
    pct exec $CTID -- systemctl start lxc_autoscale.service
    
    sleep 3
    
    # Servis durumunu kontrol et
    if pct exec $CTID -- systemctl is-active --quiet lxc_autoscale.service; then
        log success "LXC AutoScale servisi başarıyla başlatıldı"
    else
        log warning "LXC AutoScale servisi başlatılamadı, loglara bakın"
    fi
}

# Web arayüzü kurulumu
setup_web_ui() {
    log info "Web arayüzü kuruluyor..."
    
    # Nginx kur
    pct exec $CTID -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y nginx"
    
    # UI dosyalarını kopyala
    pct exec $CTID -- mkdir -p /var/www/lxc-autoscale
    pct exec $CTID -- cp -r /opt/proxmox-lxc-autoscale/lxc_autoscale/ui/* /var/www/lxc-autoscale/ 2>/dev/null || true
    
    # Nginx yapılandırması
    cat > /tmp/lxc-autoscale-nginx << EOF
server {
    listen $WEB_PORT;
    server_name _;
    
    root /var/www/lxc-autoscale;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location /api/logs {
        alias /var/log/lxc_autoscale.log;
        default_type text/plain;
    }
    
    location /api/metrics {
        alias /var/log/lxc_autoscale.json;
        default_type application/json;
    }
}
EOF
    
    pct push $CTID /tmp/lxc-autoscale-nginx /etc/nginx/sites-available/lxc-autoscale
    rm /tmp/lxc-autoscale-nginx
    
    pct exec $CTID -- ln -sf /etc/nginx/sites-available/lxc-autoscale /etc/nginx/sites-enabled/
    pct exec $CTID -- rm -f /etc/nginx/sites-enabled/default
    pct exec $CTID -- systemctl restart nginx
    
    log success "Web arayüzü yapılandırıldı"
}

# Özet bilgiler
print_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         LXC AutoScale Kurulumu Tamamlandı!                    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Container Bilgileri:${NC}"
    echo -e "  ${ARROW} Container ID  : ${GREEN}$CTID${NC}"
    echo -e "  ${ARROW} Hostname      : ${GREEN}$HOSTNAME${NC}"
    echo -e "  ${ARROW} IP Adresi     : ${GREEN}$CONTAINER_IP${NC}"
    echo -e "  ${ARROW} Root Şifre    : ${YELLOW}$PASSWORD${NC}"
    echo ""
    echo -e "${BLUE}Web Arayüzü:${NC}"
    echo -e "  ${ARROW} URL           : ${GREEN}http://${CONTAINER_IP}:${WEB_PORT}${NC}"
    echo ""
    echo -e "${BLUE}Yapılandırma:${NC}"
    echo -e "  ${ARROW} Config Dosyası: ${GREEN}/etc/lxc_autoscale/lxc_autoscale.yaml${NC}"
    echo -e "  ${ARROW} Log Dosyası   : ${GREEN}/var/log/lxc_autoscale.log${NC}"
    echo -e "  ${ARROW} JSON Metrikleri: ${GREEN}/var/log/lxc_autoscale.json${NC}"
    echo ""
    echo -e "${BLUE}Servis Yönetimi (Container içinde):${NC}"
    echo -e "  ${ARROW} Durum         : ${GREEN}systemctl status lxc_autoscale${NC}"
    echo -e "  ${ARROW} Başlat        : ${GREEN}systemctl start lxc_autoscale${NC}"
    echo -e "  ${ARROW} Durdur        : ${GREEN}systemctl stop lxc_autoscale${NC}"
    echo -e "  ${ARROW} Yeniden Başlat: ${GREEN}systemctl restart lxc_autoscale${NC}"
    echo -e "  ${ARROW} Logları İzle  : ${GREEN}journalctl -u lxc_autoscale -f${NC}"
    echo ""
    echo -e "${BLUE}Container'a Bağlanma:${NC}"
    echo -e "  ${ARROW} Console       : ${GREEN}pct enter $CTID${NC}"
    echo -e "  ${ARROW} SSH           : ${GREEN}ssh root@${CONTAINER_IP}${NC}"
    echo ""
    echo -e "${YELLOW}ÖNEMLİ NOTLAR:${NC}"
    echo -e "  ${ARROW} Config dosyasını düzenleyerek container'ları ekleyin"
    echo -e "  ${ARROW} Proxmox host üzerindeki container'ları yönetmek için SSH anahtarı yapılandırıldı"
    echo -e "  ${ARROW} Host IP'si config'e otomatik eklendi: ${GREEN}$HOST_IP${NC}"
    echo ""
    echo -e "${BLUE}Sonraki Adımlar:${NC}"
    echo -e "  1. Container'a girin: ${GREEN}pct enter $CTID${NC}"
    echo -e "  2. Config'i düzenleyin: ${GREEN}nano /etc/lxc_autoscale/lxc_autoscale.yaml${NC}"
    echo -e "  3. Container ID'leri ekleyin (TIER_DEFAULT -> lxc_containers kısmı)"
    echo -e "  4. Servisi yeniden başlatın: ${GREEN}systemctl restart lxc_autoscale${NC}"
    echo -e "  5. Web arayüzünü kontrol edin: ${GREEN}http://${CONTAINER_IP}:${WEB_PORT}${NC}"
    echo ""
}

# Ana kurulum
main() {
    check_template
    create_container
    install_autoscale
    setup_ssh
    create_systemd_service
    setup_web_ui
    print_summary
}

main
