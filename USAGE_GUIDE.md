# LXC AutoScale - Kullanım Kılavuzu

## 📖 LXC AutoScale Nedir?

LXC AutoScale, Proxmox LXC container'larınızın CPU ve RAM kaynaklarını **otomatik olarak** yüklerine göre ayarlayan bir sistemdir.

**Basit açıklama:** Container'ınız çok RAM kullanıyorsa otomatik arttırır, az kullanıyorsa otomatik azaltır. Böylece:
- ✅ Kaynaklar boşa harcanmaz
- ✅ Container'lar yavaşlamaz (kaynak yetersizliği olmaz)
- ✅ Host sistemi daha verimli kullanılır

---

## 🎯 Nasıl Çalışır?

### 1. **İzleme Döngüsü** (Her 5 dakika)

```
┌──────────────────────────────────────────────────────┐
│  1. Container'ların CPU/RAM kullanımını ölç          │
│  2. Threshold'ları kontrol et (üst/alt limitler)     │
│  3. Gerekirse CPU core sayısını ayarla               │
│  4. Gerekirse RAM miktarını ayarla                   │
│  5. 5 dakika bekle                                   │
│  6. Tekrar başa dön                                  │
└──────────────────────────────────────────────────────┘
```

**check_interval: 300** → Her 300 saniye (5 dakika) bir kontrol

---

## 📊 RAM Scaling - Nasıl Karar Verir?

### Örnek Senaryo:

Container'ınızın şu anki durumu:
- **Mevcut RAM:** 2048 MB
- **Kullanılan RAM:** 1600 MB (78% kullanım)

Config'inizdeki ayarlar:
```yaml
memory_upper_threshold: 70  # %70 üstü → RAM arttır
memory_lower_threshold: 20  # %20 altı → RAM azalt
min_memory: 256
max_memory: 4096
memory_min_increment: 256   # En az 256MB ekle/çıkar
```

### Karar Mantığı:

```
Kullanım: 78% > 70% (üst threshold)
Sonuç: RAM ARTTIRILACAK!

Artış miktarı: 256 MB (memory_min_increment)
Yeni RAM: 2048 + 256 = 2304 MB
```

**Log'da görünen:**
```
Container 1025 - Memory usage: 78%
Increasing memory for container 1025 by 256MB (current: 2048MB, new: 2304MB)
```

---

### Azaltma Örneği:

Container durumu:
- **Mevcut RAM:** 2048 MB
- **Kullanılan RAM:** 300 MB (15% kullanım)

```
Kullanım: 15% < 20% (alt threshold)
Sonuç: RAM AZALTILACAK!

Azaltma miktarı: 128 MB (min_decrease_chunk)
Yeni RAM: 2048 - 128 = 1920 MB

Ama dikkat! min_memory: 256 altına inmez
```

---

## ⚙️ Configuration Parametreleri Detaylı Açıklama

### **DEFAULT Bölümü** (Global ayarlar)

```yaml
DEFAULT:
  reserve_memory_mb: 256
```
**Ne işe yarar?** Proxmox host'un kendisi için ayrılacak minimum RAM.
- **Düşük değer:** Host çökebilir
- **Yüksek değer:** Container'lara az RAM kalır
- **Öneri:** 256-512 MB yeterli (küçük sistem), 1024-2048 MB (büyük sistem)

---

```yaml
  cpu_upper_threshold: 80
  cpu_lower_threshold: 20
```
**Ne işe yarar?** CPU kullanımı bu değerlerin dışına çıktığında aksiyon al.
- **%80 üstü:** CPU core sayısını arttır
- **%20 altı:** CPU core sayısını azalt
- **Öneri:** 70-80 arası (üst), 15-25 arası (alt)

---

```yaml
  memory_upper_threshold: 70
  memory_lower_threshold: 20
```
**Ne işe yarar?** RAM kullanımı bu değerlerin dışına çıktığında aksiyon al.
- **%70 üstü:** RAM miktarını arttır
- **%20 altı:** RAM miktarını azalt
- **Öneri:** 60-75 arası (üst), 15-25 arası (alt)

**Önemli:** Üst threshold çok düşük olursa sürekli RAM arttırır, çok yüksek olursa container yavaşlar!

---

```yaml
  min_cores: 1
  max_cores: 6
```
**Ne işe yarar?** Container'ların sahip olabileceği minimum/maksimum CPU core sayısı.
- Container asla 1 core'dan az, 6 core'dan fazla alamaz
- **Öneri:** Host'unuzun toplam core sayısının %50-70'i

**Örnek:** 12 core CPU'nuz var → `max_cores: 8` mantıklı

---

```yaml
  min_memory: 256
  max_memory: 4096
```
**Ne işe yarar?** Container'ların sahip olabileceği minimum/maksimum RAM miktarı (MB).

**ÖNEMLİ: Container türüne göre ayarlayın!**

| Container Türü | Örnek Servisler | Minimum RAM | Maximum RAM |
|----------------|-----------------|-------------|-------------|
| Çok hafif | Static HTML, Nginx | 128 MB | 512 MB |
| Hafif | Pairdrop, Glance | 256 MB | 1024 MB |
| Orta | Homarr, Uptime-Kuma | 512 MB | 2048 MB |
| Ağır | Pihole, Nextcloud | 1024 MB | 4096 MB |
| Çok ağır | Plex, Databases | 2048 MB | 8192 MB |

**Sizin container'larınız için öneriler:**
```yaml
# 1002 - pihole: Ağır (DNS queries, logs)
min_memory: 512
max_memory: 2048

# 1011 - uptimekuma: Orta
min_memory: 512
max_memory: 2048

# 1012 - pairdrop: Hafif
min_memory: 256
max_memory: 1024

# 1013 - iventoy: Orta
min_memory: 512
max_memory: 2048

# 1017 - homarr: Orta
min_memory: 512
max_memory: 2048

# 1020 - PDM: Ağır (Python, dependencies)
min_memory: 1024
max_memory: 4096

# 1022 - glance: Hafif
min_memory: 256
max_memory: 1024

# 1025 - speedtest-tracker: Orta
min_memory: 512
max_memory: 2048
```

---

```yaml
  check_interval: 300
```
**Ne işe yarar?** Kaç saniyede bir kontrol yapılacağı.
- **300 saniye = 5 dakika** (varsayılan)
- Çok kısa (60-120 sn) → Sürekli değişiklik, sistem yükü
- Çok uzun (600-900 sn) → Geç tepki, kaynak israfı
- **Öneri:** 300-600 saniye arası

---

```yaml
  off_peak_start: 22
  off_peak_end: 6
```
**Ne işe yarar?** Gece saatlerinde daha agresif kaynak azaltma.
- Saat 22:00 - 06:00 arası "off-peak" modu
- Bu saatlerde kullanım düşükse daha hızlı RAM azaltılır
- **Kullanım:** Gece kullanılmayan servisler için

---

### **TIER_DEFAULT Bölümü** (Container'lara özel ayarlar)

```yaml
TIER_DEFAULT:
  min_memory: 128
  max_memory: 4096
  lxc_containers: [1002, 1011, ...]
```

**Ne işe yarar?** Belirli container grubu için özel ayarlar.

**Örnek:** Bazı container'larınız daha fazla RAM alabilsin:

```yaml
TIER_HEAVY:
  min_memory: 1024
  max_memory: 8192
  lxc_containers: [1002, 1020]  # pihole, PDM

TIER_LIGHT:
  min_memory: 256
  max_memory: 1024
  lxc_containers: [1012, 1022]  # pairdrop, glance

TIER_DEFAULT:
  min_memory: 512
  max_memory: 2048
  lxc_containers: [1011, 1013, 1017, 1025]  # Diğerleri
```

---

## 📝 Gerçek Hayat Örnekleri

### Örnek 1: Pihole (DNS Server)

**Durum:** Sabah 08:00, herkes internete girmeye başladı
- DNS sorguları arttı
- RAM kullanımı: %15 → %75
- CPU kullanımı: %25 → %65

**AutoScale Aksiyonları:**
```
08:05 - Container 1002 - Memory usage: 75%
08:05 - Increasing memory by 256MB (512 → 768MB)

08:10 - Container 1002 - Memory usage: 68%
08:10 - No action needed (within thresholds)

08:15 - Container 1002 - CPU usage: 68%
08:15 - No action needed (within thresholds)
```

**Sonuç:** Pihole yavaşlamadı, kullanıcılar internet kesintisi yaşamadı!

---

### Örnek 2: Pairdrop (File Share)

**Durum:** Gece 02:00, kimse dosya paylaşmıyor
- RAM kullanımı: %18
- CPU kullanımı: %5

**AutoScale Aksiyonları:**
```
02:05 - Container 1012 - Memory usage: 18%
02:05 - Decreasing memory by 128MB (1024 → 896MB)

02:10 - Container 1012 - Memory usage: 20%
02:10 - No action needed (at lower threshold)

02:15 - Container 1012 - CPU usage: 5%
02:15 - Decreasing cores by 1 (2 → 1 core)
```

**Sonuç:** Gece kullanılmayan kaynak geri alındı, host daha verimli!

---

## ⚠️ Önemli Notlar ve İpuçları

### 1. **min_memory çok düşük ayarlamayın!**

```yaml
min_memory: 128  # ← TEHLİKELİ!
```

**Neden tehlikeli?**
- Container OOM (Out of Memory) hatası alabilir
- Servis çökebilir
- Sistem unstable olabilir

**Güvenli minimum değerler:**
- Python uygulamaları: 512 MB
- Node.js uygulamaları: 512 MB
- Static web server: 256 MB
- Database: 1024 MB

---

### 2. **Threshold'ları çok dar tutmayın!**

```yaml
# KÖTÜ ÖRNEK:
memory_upper_threshold: 60
memory_lower_threshold: 55  # ← Sadece %5 fark!
```

**Sorun:** Sistem sürekli RAM arttırıp azaltır (oscillation).

**İyi örnek:**
```yaml
memory_upper_threshold: 70
memory_lower_threshold: 20  # ← %50 fark
```

---

### 3. **check_interval ve system load**

- **Çok sık kontrol (60 sn):** Sistem sürekli ölçüm yapıyor, overhead artar
- **Çok seyrek kontrol (900 sn):** 15 dakika geç tepki, kaynak israfı

**Öneri:** 300-600 saniye arası başlayın, sonra ihtiyaca göre ayarlayın.

---

### 4. **reserve_memory_mb ayarını unutmayın!**

Host'unuzun toplam RAM'i: 32 GB
Container'lar: 8 adet, her biri max 4 GB alabilir
Toplam: 8 × 4 = 32 GB

**SORUN:** Host'a RAM kalmadı!

**Çözüm:**
```yaml
reserve_memory_mb: 4096  # Host için 4 GB ayır
max_memory: 3584         # Container başına max 3.5 GB
```

---

## 🔍 Log'ları Nasıl Okursunuz?

```bash
tail -f /var/log/lxc_autoscale.log
```

**Örnek log satırları:**

```
Container 1002 - CPU usage: 22.09%, Memory usage: 47.99%
```
→ Container 1002 normal çalışıyor, aksiyon yok

```
Memory usage: 78% > 70% (upper threshold)
Increasing memory by 256MB (current: 2048MB, new: 2304MB)
```
→ RAM kullanımı yüksek, 256 MB eklendi

```
Memory usage: 15% < 20% (lower threshold)
Decreasing memory by 128MB (current: 2048MB, new: 1920MB)
```
→ RAM kullanımı düşük, 128 MB geri alındı

```
ERROR - Command 'pct status' failed: pct: not found
```
→ SSH bağlantısı sorunu! SSH key'i kontrol edin

---

## 🎛️ Sizin Config'iniz İçin Öneriler

Şu anki ayarlarınız:

```yaml
DEFAULT:
  reserve_memory_mb: 256      # ✅ İyi (küçük sistem için)
  max_cores: 6                # ✅ İyi
  min_memory: 256             # ⚠️ Biraz düşük
  max_memory: 4096            # ✅ İyi

TIER_DEFAULT:
  min_memory: 128             # ❌ ÇOK DÜŞÜK! Container çökebilir
  max_memory: 4096            # ✅ İyi
```

### Önerilen Config:

```yaml
DEFAULT:
  reserve_memory_mb: 512      # Host için biraz daha fazla
  cpu_upper_threshold: 75     # Biraz daha erken tepki
  cpu_lower_threshold: 20
  memory_upper_threshold: 70
  memory_lower_threshold: 20
  min_cores: 1
  max_cores: 6
  min_memory: 512             # Daha güvenli
  max_memory: 4096
  check_interval: 300
  
TIER_DEFAULT:
  min_memory: 512             # 256'dan 512'ye çıkarın!
  max_memory: 4096
  lxc_containers: [1002, 1011, 1012, 1013, 1017, 1020, 1022, 1025]
```

---

## 📈 İlk Kurulumdan Sonra

### 1. İlk 24 Saat - İzleme

```bash
# Sürekli log izleyin
tail -f /var/log/lxc_autoscale.log

# Container'ların kaynak kullanımını izleyin
pct list
```

**Neye dikkat edin:**
- Container'lar min_memory'e çok mu sık iniyor?
- RAM sürekli artıp azalıyor mu? (oscillation)
- Container'lar yavaş mı?

### 2. İlk Hafta - Fine-tuning

Logları analiz edin:
```bash
# En çok RAM değişikliği yapılan container
grep "Increasing memory\|Decreasing memory" /var/log/lxc_autoscale.log | \
  awk '{print $7}' | sort | uniq -c | sort -rn
```

**Sonuçlara göre:**
- Sürekli RAM artan container → `max_memory` arttırın
- Sürekli RAM azalan container → `min_memory` azaltın (dikkatli!)
- Hiç değişmeyen container → threshold'ları ayarlayın

### 3. Aylık Bakım

```bash
# Log dosyası büyüklüğünü kontrol edin
du -h /var/log/lxc_autoscale.log

# Gerekirse temizleyin (>100MB ise)
tail -10000 /var/log/lxc_autoscale.log > /tmp/log_new
mv /tmp/log_new /var/log/lxc_autoscale.log
```

---

## 🆘 Sorun Giderme

### Container Çöküyor

**Olası sebep:** `min_memory` çok düşük

**Çözüm:**
```yaml
min_memory: 512  # 128'den 512'ye çıkarın
```

### RAM Sürekli Artıp Azalıyor

**Olası sebep:** Threshold'lar çok yakın

**Çözüm:**
```yaml
memory_upper_threshold: 75
memory_lower_threshold: 20  # Farkı büyütün
```

### AutoScale Hiç Aksiyon Almıyor

**Kontrol edin:**
```bash
# 1. Servis çalışıyor mu?
systemctl status lxc_autoscale

# 2. SSH bağlantısı var mı?
ssh root@PROXMOX_IP "pct list"

# 3. Container'lar config'de mi?
grep lxc_containers /etc/lxc_autoscale/lxc_autoscale.yaml
```

---

**Bu kılavuz yeterli mi yoksa başka bir konu ekleyelim mi?**
