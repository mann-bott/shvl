# 🚀 SHVL: Next-Generation Native Tunneling Stack

**SHVL** adalah stack tunneling VPN modern, ringan, dan berperforma tinggi yang dirancang khusus untuk **Ubuntu 24.04 LTS (Noble Numbat)** dan **Debian 13 (Trixie)** dengan sistem init murni **systemd**.

Project ini menggabungkan:
- **Arsitektur & TUI Workflow dari [William Old]**: Struktur layanan terorganisir, tata letak port fleksibel, dan slip informasi akun yang rapi dan mudah disalin.
- **Fitur Standar & Engine dari [Alpine-SSH]**: Pure C WebSocket Proxy, multi-login IP limiter dengan sistem **5-minute cooldown auto-unlock**, penyimpanan database SQLite3 terintegrasi, dan notifikasi Bot Telegram otomatis.
- **100% Binary Statis (Zero Compilation)**: Semua komponen utama (`Dropbear 2019`, `ssh-ws`, `Xray Core`, dan `shvl`) telah dikompilasi secara statis (static binary), sehingga instalasi di VPS berlangsung instan (5 - 10 detik) tanpa perlu menginstal compiler `gcc` atau build tools!

---

## ⚡ 6 Protokol Utama yang Didukung

SHVL difokuskan secara khusus hanya pada 6 protokol tunneling esensial dengan performa maksimal:

| No | Protokol | Port | Transport / Keterangan |
|---|---|---|---|
| 1 | **SSH Over WebSocket HTTP** | `80, 8080, 8880, 2082` | HTTP WebSocket (CDN / Cloudflare / Bug Host), Path: `/` atau `/ssh` |
| 2 | **SSH SSL/TLS/SNI** | `443, 8443, 2053, 2083` | Direct SSH dibungkus TLS/SNI langsung ke Dropbear via HAProxy Inspection |
| 3 | **SSH Over WebSocket TLS/SSL/SNI** | `443, 8443, 2053, 2083` | HTTPS WebSocket (WSS) dengan terminasi TLS & ALPN (`h2, http/1.1`) |
| 4 | **OpenVPN TCP** | `1194` & `443` | OpenVPN TCP Server (Direct Port 1194 & Multiplexed Port 443 via HAProxy) |
| 5 | **Squid / HTTP Proxy** | `3128, 8080` & `80` | HTTP CONNECT Proxy untuk injector/payload (Port 80 via HAProxy CONNECT Mux) |
| 6 | **VLESS WebSocket** | `80` (HTTP) & `443` (TLS) | VLESS over WebSocket, Path: `/vless-ws` |
| 7 | **VLESS HttpUpgrade** | `80` (HTTP) & `443` (TLS) | VLESS over HTTPUpgrade, Path: `/vless-hu` |
| 8 | **VLESS XHTTP** | `80` (HTTP) & `443` (TLS) | VLESS over XHTTP (SplitHTTP H2/H3 mode), Path: `/vless-xhttp` |

> Ditambah layanan pendukung:
> - **Dropbear SSH Direct**: Port `109, 143` (Dropbear v2019.78 Static)
> - **OpenSSH Standard**: Port `22`
> - **BadVPN UDPGW**: Port `7300` (Multiplexer terintegrasi untuk VoIP WhatsApp & Gaming)
> - **Internal REST API**: Port `8081` (Loopback monitoring sesi aktif)

---

## 🏗️ Arsitektur Multiplexing (HAProxy Dual-Port)

Semua lalu lintas masuk dimultipleks oleh **HAProxy** secara transparan dalam mode TCP berkecepatan tinggi:

```
[ Port 80 (HTTP) ] ──> HAProxy ──┬──> [/.well-known/acme-challenge/] ──> ACME Standalone (:8080)
                                 ├──> [/vless-ws]                     ──> Xray VLESS WS (:10001)
                                 ├──> [/vless-hu]                     ──> Xray VLESS HU (:10002)
                                 ├──> [/vless-xhttp]                  ──> Xray VLESS XHTTP (:10003)
                                 ├──> [Payload "CONNECT ..."]         ──> Squid HTTP Proxy (:3128)
                                 └──> [Default / Static / WS Upgrade] ──> ssh-ws Proxy (:8880)
                                                                            ├──> [Static *.ovpn / openvpn.zip] ──> Direct File Attachment (200 OK)
                                                                            ├──> [/ovpn WebSocket]             ──> OpenVPN TCP (:1194)
                                                                            └──> [SSH WebSocket Upgrade]       ──> Dropbear (:109)

[ Port 443 (TLS) ] ──> HAProxy ──┬──> [Raw OpenVPN (0x38/0x50/0x08)]  ──> OpenVPN TCP (:1194)
                                 ├──> [Raw SSH "SSH-..."]             ──> Dropbear SSH (:109)
                                 └──> [TLS Handshake (0x16)] ─────────> TLS Decryptor (:10443)
                                                                            │
                                                                            ├──> [Decrypted "SSH-..."] ──> Dropbear (:109)
                                                                            ├──> [Decrypted OpenVPN]   ──> OpenVPN (:1194)
                                                                            ├──> [/vless-ws]           ──> Xray WS (:10001)
                                                                            ├──> [/vless-hu]           ──> Xray HU (:10002)
                                                                            ├──> [/vless-xhttp]        ──> Xray XHTTP (:10003)
                                                                            └──> [Default WSS / HTTPS] ──> ssh-ws (:8880)
                                                                                                            ├──> [Static *.ovpn / openvpn.zip] (Direct HTTPS Download)
                                                                                                            └──> [SSH WebSocket TLS] ──> Dropbear (:109)
```

> 💡 **Fitur Direct Download OVPN (HTTPS & HTTP):**
> Klien dapat langsung mengunduh profil `.ovpn` maupun arsip `openvpn.zip` melalui browser pada port standar HTTPS (`https://domain/client-tcp-1194.ovpn`) dan HTTP tanpa perlu port non-standar. Server otomatis mengirim header `Content-Disposition: attachment` dan MIME type `application/x-openvpn-profile` sehingga browser mobile/desktop langsung menyimpan file ke folder Downloads alih-alih merender teks mentah di layar.

---

## 🛡️ Fitur Cerdas Multi-Login IP Limiter

Sistem limiter mengadopsi mekanisme cerdas dari `alpine-ssh`:
1. **Pemeriksaan Berkala**: Daemon background (`shvl-limiter.service`) memantau koneksi aktif setiap 15 detik.
   - Untuk **SSH**: Mengambil sesi aktif dari REST API `ssh-ws` (`http://127.0.0.1:8081/api/sessions`) yang membaca IP asli klien via PROXY Protocol v1.
   - Untuk **VLESS**: Menginspeksi log koneksi Xray (`/var/log/xray/access.log`) dalam window 2 menit terakhir.
2. **Penguncian Otomatis (Lock)**: Jika jumlah IP unik melebihi batas `limit_ip`:
   - Akun dikunci di OS (`usermod -L`) dan sesi aktif dihentikan seketika.
   - Untuk VLESS, klien dinonaktifkan sementara dari konfigurasi Xray.
   - Notifikasi dikirim ke Bot Telegram dengan detail IP yang terdeteksi.
3. **Auto-Unlock 5 Menit**: Setelah masa cooldown 5 menit (300 detik) berakhir:
   - Akun secara otomatis diaktifkan kembali tanpa perlu campur tangan admin!
   - Notifikasi pemulihan dikirim ke Bot Telegram.

---

## 📦 Pilihan Metode Instalasi (Ubuntu 24.04 & Debian 13)

### 🌐 Opsi 1: Online Auto-Install (GitHub / Web Host)
Jalankan satu perintah berikut sebagai `root`:

```bash
wget -qO install.sh https://raw.githubusercontent.com/risqinf/shvl/main/install.sh && bash install.sh
```

### 🚀 Opsi 2: Instalasi Folder Lokal (Super Cepat ~ 10 Detik)
Jika Anda mengunggah folder project ke VPS (via Git, SFTP, atau SCP):

```bash
cd /root/shvl
chmod +x install.sh
./install.sh --local
```

---

## 🛠️ Menu & CLI Commands

### Interactive TUI Dashboards
```bash
menu          # Membuka Dashboard Utama (System info, RAM, status service, opsi sistem)
menu-ssh      # Membuka menu interaktif pengelolaan SSH
menu-vless    # Membuka menu interaktif pengelolaan VLESS (WS, HU, XHTTP)
```

### Quick CLI Commands
```bash
# SSH Management
shvl add-ssh alice Secret123 30 2 0    # Buat user: user pass hari limit_ip quota_gb
shvl trial-ssh                         # Buat akun trial SSH 1 hari
shvl del-ssh alice                     # Hapus akun SSH
shvl renew-ssh alice 30                # Perpanjang 30 hari
shvl list-ssh                          # Tampilkan daftar akun SSH
shvl slip-ssh alice                    # Tampilkan slip info akun SSH

# VLESS Management
shvl add-vless bob 30 2 0              # Buat akun VLESS: user hari limit_ip quota_gb
shvl trial-vless                       # Buat akun trial VLESS 1 hari
shvl del-vless bob                     # Hapus akun VLESS
shvl renew-vless bob 30                # Perpanjang 30 hari
shvl list-vless                        # Tampilkan daftar akun VLESS
shvl slip-vless bob                    # Cetak link VLESS WS, HU, XHTTP

# System Operations
shvl limit                             # Cek status multi-login limiter
shvl xp                                # Bersihkan akun expired
shvl domain vpn.example.com            # Ganti domain & terbitkan SSL
shvl cert renew                        # Perbarui sertifikat SSL
shvl backup                            # Backup sistem & kirim ke Telegram
shvl restore /path/to/backup.tar.gz    # Restore sistem
shvl telegram                          # Setup Bot Token & Chat ID Telegram
shvl restart                           # Restart seluruh service
```

---

## 📂 Struktur Direktori Project

```
shvl/
├── bin/                         # Binary statis siap pakai (x86_64)
│   ├── amd64/
│   │   ├── dropbear             # Dropbear SSH v2019.78 (Static)
│   │   ├── dropbearkey          # DropbearKey (Static)
│   │   ├── dropbearconvert      # DropbearConvert (Static)
│   │   ├── ssh-ws               # Pure C WebSocket Proxy & UDPGW (Static)
│   │   ├── xray                 # Xray Core v26+ (Static)
│   │   └── shvl                 # SHVL Core Manager with SQLite3 (Static)
│   ├── geoip.dat                # Xray GeoIP database
│   └── geosite.dat              # Xray GeoSite database
├── conf/                        # Template konfigurasi layanan
│   ├── haproxy.cfg              # Dual-port 80 & 443 multiplexer
│   ├── xray.json                # Inbound VLESS WS, HttpUpgrade, XHTTP
│   ├── dropbear.conf            # Konfigurasi port 109 & 143 Dropbear
│   ├── issue.net                # Banner SSH
│   └── shvl.conf                # Konfigurasi master sistem
├── systemd/                     # Service units systemd
│   ├── dropbear.service         # Service Dropbear
│   ├── ssh-ws.service           # Service WebSocket Proxy
│   ├── xray.service             # Service Xray Core
│   ├── shvl-limiter.service     # Service Multi-login Limiter Daemon
│   ├── shvl-xp.service          # Service pembersih akun expired
│   └── shvl-xp.timer            # Timer harian jam 00:00
├── menu/                        # Script antarmuka TUI
│   ├── menu                     # Dashboard utama
│   ├── menu-ssh                 # Submenu SSH
│   └── menu-vless               # Submenu VLESS
├── scripts/                     # CLI wrapper commands
│   ├── add-ssh, trial-ssh, del-ssh, renew-ssh, cek-ssh
│   ├── add-vless, trial-vless, del-vless, renew-vless, cek-vless
│   └── restart
├── include/                     # Header file C
├── src/                         # Source code C Core & SQLite3
├── c-websocket-proxy/           # Source code Pure C WebSocket Proxy
├── Makefile                     # Build system
├── build-static.sh              # Script kompilasi & pengemas rilis
├── install.sh                   # Script instalasi otomatis Ubuntu/Debian
└── README.md                    # Dokumentasi lengkap
```

---

## 📜 Lisensi
Dikembangkan untuk komunitas VPN & tunneling dengan standar kualitas tinggi, keamanan, dan kehandalan performa.
Didistribusikan di bawah lisensi MIT / Apache 2.0.
