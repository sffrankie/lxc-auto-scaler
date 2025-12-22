# LXC AutoScale - Otomatik Container Kurulumu

Bu script, Proxmox VE üzerinde LXC AutoScale'i ayrı bir container içinde otomatik olarak kurar.

## Özellikler

- ✅ Otomatik container oluşturma ve yapılandırma
- ✅ Sıralı container ID atama (200'den başlar)
- ✅ Otomatik hostname oluşturma (lxc-autoscale-XXX)
- ✅ DHCP ile otomatik IP atama
- ✅ LXC AutoScale kurulumu ve yapılandırması
- ✅ SSH anahtarı otomatik kurulumu
- ✅ Systemd servisi oluşturma ve başlatma
- ✅ Web arayüzü kurulumu (Nginx)
- ✅ Tüm bilgilerin özet çıktısı

## Gereksinimler

- Proxmox VE 8.x
- Root erişimi
- İnternet bağlantısı

## Kurulum

### Tek Komutla Kurulum

```bash
bash <(curl -s https://raw.githubusercontent.com/YOUR_REPO/install-lxc-autoscale.sh)
```

### Manuel Kurulum

```bash
# Script'i indir
wget https://raw.githubusercontent.com/YOUR_REPO/install-lxc-autoscale.sh

# Çalıştırılabilir yap
chmod +x install-lxc-autoscale.sh

# Çalıştır
./install-lxc-autoscale.sh
```

## Script Ne Yapar?

1. **Template Kontrolü**: Debian 12 template'ini kontrol eder ve yoksa indirir
2. **Container Oluşturma**: 
   - Sıradaki boş ID'yi bulur (200+)
   - 2 CPU core, 2GB RAM, 512MB swap
   - 8GB disk alanı
   - DHCP ile IP atama
   - Nesting özelliği aktif
3. **Sistem Kurulumu**:
   - Sistem güncellemesi
   - Python3 ve gerekli paketler
   - Git, curl, openssh-client
4. **LXC AutoScale Kurulumu**:
   - GitHub'dan repository klonlama
   - Yapılandırma dosyası oluşturma
   - Log dizinleri oluşturma
5. **SSH Yapılandırması**:
   - Container'da SSH anahtarı oluşturma
   - Host'a public key ekleme
   - Otomatik bağlantı için yapılandırma
6. **Systemd Servisi**:
   - Servis dosyası oluşturma
   - Otomatik başlatma aktif etme
   - Servisi başlatma
7. **Web Arayüzü**:
   - Nginx kurulumu
   - UI dosyalarının kopyalanması
   - API endpoint'leri (logs, metrics)

## Kurulum Sonrası

Script tamamlandığında size şu bilgiler verilir:

- Container ID
- Hostname
- IP Adresi
- Root şifresi
- Web arayüz URL'si
- Yapılandırma dosyası yolları

## Yapılandırma

### 1. Container'a Girin

```bash
pct enter CONTAINER_ID
```

### 2. Config Dosyasını Düzenleyin

```bash
nano /etc/lxc_autoscale/lxc_autoscale.yaml
```

### 3. Container ID'leri Ekleyin

```yaml
TIER_DEFAULT:
  lxc_containers:
    - 100
    - 101
    - 102
```

### 4. Servisi Yeniden Başlatın

```bash
systemctl restart lxc_autoscale
```

### 5. Logları İzleyin

```bash
journalctl -u lxc_autoscale -f
```

## Servis Yönetimi

```bash
# Durum kontrolü
systemctl status lxc_autoscale

# Başlat
systemctl start lxc_autoscale

# Durdur
systemctl stop lxc_autoscale

# Yeniden başlat
systemctl restart lxc_autoscale

# Logları göster
journalctl -u lxc_autoscale -f
```

## Web Arayüzü

Web arayüzü 8080 portunda çalışır:

```
http://CONTAINER_IP:8080
```

API Endpoints:
- `/api/logs` - Log dosyası
- `/api/metrics` - JSON metrikleri

## Özelleştirme

Script başında varsayılan değerleri değiştirebilirsiniz:

```bash
readonly DISK_SIZE="8"        # Disk boyutu (GB)
readonly CORES="2"            # CPU core sayısı
readonly MEMORY="2048"        # RAM (MB)
readonly SWAP="512"           # Swap (MB)
readonly WEB_PORT="8080"      # Web arayüz portu
```

## Sorun Giderme

### Container başlamıyor

```bash
pct start CONTAINER_ID
journalctl -xe
```

### Servis çalışmıyor

```bash
pct enter CONTAINER_ID
systemctl status lxc_autoscale
journalctl -u lxc_autoscale -n 100
```

### SSH bağlantısı başarısız

```bash
# Container içinde
ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ''
cat /root/.ssh/id_rsa.pub

# Host'ta
echo "PUBLIC_KEY" >> /root/.ssh/authorized_keys
```

## Kaldırma

Container'ı tamamen kaldırmak için:

```bash
pct stop CONTAINER_ID
pct destroy CONTAINER_ID
```

## Lisans

MIT License

## Katkıda Bulunma

Pull request'ler kabul edilir. Büyük değişiklikler için önce issue açın.

## Destek

Sorunlar için GitHub Issues kullanın.
