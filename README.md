# Docker Stack (PHP + Node + Nginx + Caddy + Database)

Dokumen ini ditujukan buat setup di server fisik Ubuntu 22.04 yang masih kosong, khususnya buat uji coba `core-r` (PHP 8.5) dan `core-r-fe` (Node 24).

> **Fokus:** Setup menggunakan **domain** (bukan akses via IP:port). Beli domain untuk proses RnD terlebih dahulu. Nanti kalau mau go public, kamu bisa beli domain baru sesuai kebutuhan aplikasi.
>
> **HTTPS di server diurus oleh Caddy** (sertifikat Let's Encrypt terbit dan diperbarui otomatis). Nginx tetap dipakai untuk PHP seperti di lokal, tapi tidak lagi mengurus sertifikat.

## 1. Struktur Direktori

Dari root workspace (`/home/boy/Documents/project/`):

```text
.
├── docker/        # Stack docker (compose, config terkait)
│   ├── compose/   # server.yml, php.yml, node.yml, database.yml, tools.yml, proxy.yml (Caddy)
│   ├── caddy/     # Caddyfile (reverse proxy + HTTPS otomatis, dipakai di server)
│   └── docker-volumes/   # data persisten (database, caddy-data, dll)
├── php/           # PHP apps, Dockerfile per versi, nginx vhost, ssl
│   ├── docker/    # Dockerfile per versi PHP
│   ├── nginx/     # vhost nginx yang di-mount ke container nginx
│   ├── ssl/       # sertifikat LOKAL (mkcert). Tidak dipakai di server.
│   └── www/       # source code PHP (p56/p74/.../p85/...)
└── node/          # Node apps & Dockerfile
    ├── docker/    # Dockerfile per versi Node
    └── www/       # source code Node (n20/n22/n24/...)
```

Alur request di **server**:

```text
Internet ──443──► Caddy (HTTPS otomatis) ──► nginx ──► php-fpm (php85)    core-r.domainrnd.com
                                         └─► node24 :3000                  app.domainrnd.com
```

Alur request di **lokal** (tanpa Caddy, seperti sebelumnya):

```text
Browser ──80/8443──► nginx ──► php-fpm (per versi)     (sertifikat dari mkcert)
```

## 2. Kondisi Saat Ini (Quick Review)

| Item | Status | Keterangan |
|---|---|---|
| Multi-PHP (5.6 - 8.5) | OK | Tersedia di `compose/php.yml` |
| PHP 8.5 (`php85`) | OK | Cocok buat `p85/core-r`. Ada `custom.ini`, `zzz-custom.conf`, mount `ssl/`. |
| Node (20/22/24) | OK | Tersedia. `node24` expose `3024:3000`. |
| Nginx reverse PHP | OK | `php/nginx/p85.conf` pakai pola subdomain `*.p85.test` + redirect HTTP->HTTPS + fastcgi ke `dev-php85:9000`. Dipakai untuk lokal. |
| Reverse proxy + HTTPS di server | **BARU: Caddy** | `compose/proxy.yml` + `caddy/Caddyfile`. Hanya aktif di server (profil `server`). |
| Nginx reverse Node | Tidak perlu | Di server, Caddy langsung meneruskan ke `node24:3000`. |
| Path Node | PERLU PENYESUAIAN | `node24` di `compose/node.yml` punya `working_dir: /var/www/n24/my-app` padahal project kamu ada di `../node/www/n24/core-r-fe`. Perlu disesuaikan atau dibuat symlink. |
| `.env` | ADA (berisi kredensial OAuth) | Jangan pakai mentah di server publik. Buat `.env` baru dari `.env.example` & isi `UID:GID`. Kosongkan kredensial OAuth jika tidak dipakai. |
| Port database & tools | **BAHAYA di server publik** | `database.yml` dan `tools.yml` mem-publish port ke semua interface (3307, 3308, 5433, 6380, 8080, 8081, 9000, 1080, 1025, 1090, 1091). Lihat bagian 6.4c. |
| Queue/Scheduler | HARDCODE | `queue-worker` & `scheduler` masih hardcode ke `p84/riyerp`. Aman di-disable jika belum dipakai. |
| SSL wildcard (`php/ssl/`) | Lokal saja | Sertifikat mkcert hanya dipercaya laptop yang memasang CA-nya. Di server dipakai Let's Encrypt lewat Caddy. |

## 3. Konsep Singkat: Domain, DNS, dan SSL

Tiga hal ini terpisah dan sering tertukar:

| | Fungsi | Diurus di |
|---|---|---|
| **Domain** | Nama (`core-r.domainrnd.com`) yang kamu beli | Registrar (mis. Rumahweb) |
| **DNS (record A)** | Menunjuk nama itu ke IP publik server | Panel DNS registrar / Cloudflare |
| **Sertifikat SSL** | Bukti bahwa server di balik nama itu milikmu, sekaligus enkripsi HTTPS | **Web server** (di sini: Caddy) |

Membeli domain **tidak** otomatis memberi sertifikat. Sertifikat harus diminta ke penerbit yang dipercaya semua perangkat (Let's Encrypt, gratis). Caddy melakukannya sendiri:

1. Caddy meminta sertifikat untuk tiap nama yang tertulis di `Caddyfile`.
2. Let's Encrypt membuktikan bahwa kamu mengendalikan nama itu dengan membuka port 80 server (karena itu DNS harus sudah mengarah ke server).
3. Sertifikat terpasang dan diperbarui otomatis sebelum habis (sekitar 90 hari).

Kenapa tidak pakai sertifikat mkcert di server: mkcert membuat CA pribadi yang hanya dipercaya mesin yang memasangnya. Perangkat lain (HP, laptop teman, layanan luar seperti webhook) akan menolaknya. Sertifikat Let's Encrypt dipercaya semua perangkat tanpa pemasangan apa pun.

Syarat agar sertifikat berhasil terbit: (1) DNS sudah mengarah ke IP server, (2) port 80 dan 443 terbuka di UFW **dan** di firewall penyedia server (kalau ada), (3) port 80 tidak dipakai proses lain.

## 4. Kebutuhan Server

- OS: Ubuntu 22.04 LTS (fresh)
- Akses root/sudo
- **Domain** yang sudah dibeli untuk RnD (bisa satu domain utama, lalu pakai subdomain untuk tiap aplikasi)
- **DNS Management** (Cloudflare/Registrar panel) buat atur record A/CNAME
- Port yang perlu dibuka: `22` (SSH), `80`, `443`. **Tidak disarankan** mengakses aplikasi langsung via IP:port, semua harus lewat Caddy + domain/subdomain.

## 5. Instalasi di Server Baru

### 5.1 Update & Dependensi
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg git unzip ufw
```

### 5.2 Firewall Dasar (lakukan SEBELUM menjalankan stack)

> **Penting:** izinkan SSH dulu sebelum `ufw enable`. Kalau tidak, kamu terkunci dari server (dan satu-satunya akses ke server ini lewat SSH).

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Catatan penting soal Docker dan UFW: **port yang di-publish Docker bisa menembus UFW**. Artinya `ports: - 5433:5432` di compose membuka Postgres ke internet walaupun UFW tidak mengizinkannya. Itu sebabnya bagian 6.4c mengikat port ke `127.0.0.1`.

### 5.3 Install Docker & Docker Compose Plugin
```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
docker version
docker compose version
```

### 5.4 Pindahkan Project

Pindahkan seluruh folder `docker/`, `php/`, dan `node/` ke server. Pastikan struktur relasinya tetap sama karena `docker-compose.yml` menggunakan relative path.

Contoh target: `/home/<user>/project/`

```bash
mkdir -p ~/project
# rsync/scp/git clone ketiganya ke ~/project/
```

## 6. Konfigurasi Awal

### 6.1 Konfigurasi .env
Masuk ke direktori docker:

```bash
cd ~/project/docker
cp .env.example .env
```

Cek UID & GID user di server:
```bash
id -u && id -g
```

Edit file `.env`:
```env
UID=1000  # sesuaikan
GID=1000  # sesuaikan

# --- Khusus SERVER ---
# Mengaktifkan Caddy (di lokal baris ini dikosongkan)
COMPOSE_PROFILES=server

# Nginx dan Node tidak boleh terbuka ke internet; hanya Caddy yang membuka 80/443.
# Diikat ke localhost supaya masih bisa dites dari server dengan curl.
NGINX_HTTP=127.0.0.1:8080:80
NGINX_HTTPS=127.0.0.1:8443:443
NODE24_PORT=127.0.0.1:3024:3000

# Kosongkan jika tidak dipakai
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
```

Tambahkan juga ketiga variabel server (`COMPOSE_PROFILES`, `NGINX_*`, `NODE24_PORT`) ke `.env.example` sebagai contoh, tapi biarkan kosong di lokal supaya perilaku lokal tidak berubah.

> Hindari menggunakan `.env` yang ada saat ini di repo karena berisi kredensial. Lebih aman buat baru dari `.env.example`.

### 6.2 Atur Permission
Agar file yang dibuat container bisa diedit dari host:

```bash
sudo chown -R $(id -u):$(id -g) ~/project/php/www ~/project/node/www
find ~/project/php/www -type d -exec chmod 775 {} \;
find ~/project/node/www -type d -exec chmod 775 {} \;
find ~/project/php/www -type f -exec chmod 664 {} \;
find ~/project/node/www -type f -exec chmod 664 {} \;
```

> Di bash, variabel `$GID` biasanya kosong. Pakai `$(id -g)` seperti di atas.

Untuk Laravel, pastikan folder `storage/` dan `bootstrap/cache/` writable.

### 6.3 SSL: Lokal vs Server

| | Lokal | Server |
|---|---|---|
| Domain | `*.p85.test` | Domain yang kamu beli |
| Sertifikat | mkcert (file di `php/ssl/`) | Let's Encrypt lewat Caddy (otomatis) |
| Dipercaya oleh | Laptop yang memasang CA mkcert | Semua perangkat |
| File `.pem` yang diurus manual | Ya | **Tidak ada** |

Di server **tidak perlu** menyalin sertifikat ke `php/ssl/`. Folder itu tetap ada karena dipakai vhost lokal, tapi tidak dipakai Caddy. Jangan pernah menyalin `rootCA-key.pem` milik mkcert ke server.

### 6.4 Sesuaikan Compose untuk Server

Perubahan di bawah **tidak mengubah perilaku lokal** karena memakai nilai default.

**a) `compose/server.yml` (nginx): port dari variabel, dan depends_on seperlunya**

```yaml
services:
  nginx:
    image: nginx:latest
    container_name: dev-nginx
    ports:
      - "${NGINX_HTTP:-80:80}"
      - "${NGINX_HTTPS:-8443:443}"
    volumes:
      - ../../php/www:/var/www
      - ../../php/nginx:/etc/nginx/conf.d
      - ../../php/ssl:/etc/nginx/ssl
    restart: always
    depends_on:
      php85:
        condition: service_started
    networks:
      - default
```

Di versi lama, `nginx` bergantung ke php56 sampai php85, jadi menjalankan `nginx` ikut membangun dan menyalakan semua versi PHP. Untuk server, cukup `php85`. Kalau kamu butuh versi lain di server, tambahkan di `depends_on` dan `docker compose up`.

**b) `compose/proxy.yml` (Caddy, file baru)**

```yaml
services:
  caddy:
    image: caddy:2
    container_name: dev-caddy
    profiles: ["server"]
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"   # HTTP/3 (opsional)
    volumes:
      - ../caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ../docker-volumes/caddy-data:/data      # sertifikat; JANGAN dihapus
      - ../docker-volumes/caddy-config:/config
    depends_on:
      - nginx
    networks:
      - default
```

Daftarkan di `docker-compose.yml`:

```yaml
include:
  - compose/server.yml
  - compose/php.yml
  - compose/node.yml
  - compose/database.yml
  - compose/tools.yml
  - compose/proxy.yml
```

`profiles: ["server"]` membuat Caddy **hanya** jalan jika `COMPOSE_PROFILES=server` ada di `.env`. Di lokal Caddy tidak menyala, jadi tidak bentrok dengan nginx di port 80.

> `caddy-data` menyimpan sertifikat dan akun Let's Encrypt. Kalau folder ini terhapus, Caddy meminta ulang sertifikat dan bisa terkena batas percobaan Let's Encrypt. Masukkan ke backup.

**c) Port database dan tools: ikat ke localhost**

Port berikut di-publish ke semua interface oleh file compose yang ada, dan **Docker menembus UFW**:

| File | Service | Port host |
|---|---|---|
| `database.yml` | mysql, mysql57, postgres, redis | 3307, 3308, 5433, 6380 |
| `tools.yml` | adminer, phpmyadmin | 8080, 8081 |
| `tools.yml` | portainer, maildev, minio | 9000, 1080 dan 1025, 1090 dan 1091 |

Dua langkah, lakukan keduanya di salinan **server**:

1. Untuk `database.yml`, ikat ke localhost (aman, tetap bisa diakses dari server atau lewat SSH tunnel):

   ```bash
   cd ~/project/docker/compose
   sed -i.bak -E 's/^(\s*- )([0-9]+:[0-9]+)$/\1127.0.0.1:\2/' database.yml
   grep -n "127.0.0.1" database.yml
   ```

2. Jangan jalankan service di `tools.yml` kecuali memang perlu. Kalau perlu (misalnya Adminer atau Portainer), ikat ke `127.0.0.1` juga, lalu akses lewat SSH tunnel, bukan lewat internet:

   ```bash
   ssh -L 9000:localhost:9000 user@IP_SERVER   # lalu buka http://localhost:9000 di laptop
   ```

**d) Vhost nginx lama**

File vhost PHP lama di `php/nginx/` (p56, p74, p80, dst.) mengarah ke container `dev-php56:9000` dan seterusnya. Jika container itu tidak dijalankan di server, nginx gagal start dengan pesan `host not found in upstream`. Di server, **simpan hanya vhost yang dipakai**:

```bash
cd ~/project/php/nginx
mkdir -p ../nginx-disabled
mv p56.conf p74.conf p80.conf p81.conf p82.conf p83.conf p84.conf ../nginx-disabled/ 2>/dev/null
ls
```

Sesuaikan nama file dengan isi folder kamu. Vhost `p85.conf` dan `core-r.conf` (bagian 9.3) boleh tetap ada.

## 7. Menjalankan Stack

Dari direktori `docker/`. Di server, **jalankan hanya service yang dibutuhkan**, jangan `docker compose up -d` tanpa nama service (itu menyalakan semua versi PHP, Node, database, dan tools).

```bash
cd ~/project/docker

# Build & jalankan (server)
docker compose up -d --build caddy nginx php85 node24 postgres redis
```

Tambah service lain (mis. `mysql`) hanya jika dibutuhkan.

Cek status & log:
```bash
docker compose ps
docker compose logs -f nginx
docker compose logs -f caddy
```

Pastikan hanya port yang diinginkan yang terbuka ke luar:
```bash
sudo ss -tlnp
```
Yang boleh muncul di `0.0.0.0` atau `*` hanya `22`, `80`, dan `443`. Semua port lain harus berawalan `127.0.0.1`. Kalau ada port database atau tools yang muncul di `0.0.0.0`, kembali ke bagian 6.4c.

Untuk menghentikan:
```bash
docker compose down
```

## 8. Setup Project `core-r` (PHP 8.5) & `core-r-fe` (Node 24)

### 8.1 PHP - `p85/core-r`
Project berada di `~/project/php/www/p85/core-r/`

Masuk container dan setup:
```bash
docker exec -it dev-php85 bash
cd /var/www/p85/core-r
cp .env.example .env  # jika belum ada
composer install
php artisan key:generate
php artisan migrate --seed  # sesuaikan kebutuhan
php artisan storage:link
npm install && npm run build  # jika ada asset
exit
```

Di `.env` aplikasi untuk server, pastikan:
```env
APP_ENV=production
APP_DEBUG=false
APP_URL=https://core-r.domainrnd.com
```

Dan baca bagian 9.4 (trusted proxy) supaya Laravel memahami bahwa pengunjung memakai HTTPS.

### 8.2 Node - `n24/core-r-fe`
Project berada di `~/project/node/www/n24/core-r-fe/`

Karena `node24` di `compose/node.yml` saat ini punya `working_dir: /var/www/n24/my-app`, ada 2 opsi:

#### Opsi A: Symlink (cepat, tanpa ubah compose)
```bash
cd ~/project/node/www/n24
ln -s core-r-fe my-app
```

#### Opsi B: Ubah compose (lebih jelas & permanen)
Edit `~/project/docker/compose/node.yml` pada service `node24`:

```yaml
  node24:
    build: ../../node/docker/node24
    container_name: dev-node24
    user: "${UID}:${GID}"
    working_dir: /var/www/n24/core-r-fe
    volumes:
      - ../../node/www:/var/www
    ports:
      - "${NODE24_PORT:-3024:3000}"
    networks:
      - default
    tty: true
    restart: always
```

Lalu rebuild:
```bash
cd ~/project/docker
docker compose up -d --build node24
```

Jalankan development server:
```bash
docker exec -it dev-node24 sh
cd /var/www/n24/core-r-fe
npm ci
cp .env.example .env
npm run dev -- --host 0.0.0.0 --port 3000
exit
```

> Catatan: Setelah Caddy dikonfigurasi (bagian 9), akses lewat domain/subdomain di port 443. Jangan mengandalkan akses langsung `IP_SERVER:3024`. Dengan `NODE24_PORT=127.0.0.1:3024:3000` port itu hanya terbuka dari server sendiri.
>
> Proses `npm run dev` berhenti ketika sesi `docker exec` ditutup. Untuk RnD yang perlu hidup terus, jalankan lewat `command` di service `node24` atau gunakan build produksi. Pengaturan Vite untuk domain ada di bagian 9.5.

## 9. Konfigurasi Domain, Caddy, dan HTTPS

Kamu beli 1 domain untuk RnD (contoh: `domainrnd.com`). Dari domain ini, buat **subdomain terpisah** untuk tiap aplikasi biar tetap rapi dan siap dipindah saat go public.

### 9.1 Atur DNS di Registrar/Cloudflare
Sebelum menyalakan Caddy, arahkan DNS terlebih dahulu ke IP publik server fisik kamu.

| Record | Type | Host | Value | Keterangan |
|---|---|---|---|---|
| Core PHP (core-r) | A | `core-r.domainrnd.com` | `IP_PUBLIK_SERVER` | Untuk aplikasi Laravel/ PHP 8.5 |
| Core FE (core-r-fe) | A | `app.domainrnd.com` | `IP_PUBLIK_SERVER` | Untuk aplikasi Node 24 (bisa diganti sesuai naming kamu) |
| (Opsional) Root | A | `domainrnd.com` | `IP_PUBLIK_SERVER` | Hanya jika ada halaman landing |

> **Cloudflare:** set record ke **DNS Only (grey cloud)** saat pertama kali meminta sertifikat. Kalau record Proxied (orange cloud), pembuktian domain bisa gagal atau menghasilkan redirect berulang. Setelah HTTPS stabil, boleh dialihkan ke Proxied dengan mode SSL `Full (strict)`.

Tunggu propagasi DNS (bisa beberapa menit, bisa lebih). Bisa dicek pakai `dig` atau `nslookup`.

```bash
dig core-r.domainrnd.com +short
dig app.domainrnd.com +short
```

Hasilnya harus IP publik server. Jangan lanjut sebelum benar.

### 9.2 Caddyfile
Buat file `~/project/docker/caddy/Caddyfile`:

```caddy
{
	# Email untuk pemberitahuan dari Let's Encrypt (opsional tapi disarankan)
	email admin@domainrnd.com

	# Saat uji coba, buka komentar baris berikut untuk memakai server STAGING
	# Let's Encrypt (tidak terkena batas percobaan, tapi sertifikatnya tidak dipercaya browser).
	# Hapus lagi setelah semuanya benar, lalu restart Caddy.
	# acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}

core-r.domainrnd.com {
	encode gzip
	reverse_proxy nginx:80
}

app.domainrnd.com {
	encode gzip
	reverse_proxy node24:3000
}
```

Tidak ada `ssl_certificate` di sini: Caddy mengurus sertifikat sendiri untuk setiap nama yang ditulis. WebSocket (misalnya HMR Vite atau Reverb) ikut diteruskan otomatis.

Menambah aplikasi baru di kemudian hari berarti menambah satu blok seperti di atas, lalu:

```bash
docker exec dev-caddy caddy reload --config /etc/caddy/Caddyfile
```

### 9.3 Vhost Nginx untuk PHP (`core-r`) - tanpa SSL
Buat file vhost baru di `~/project/php/nginx/core-r.conf`. Nginx hanya mendengarkan port 80 di dalam Docker (dari Caddy), jadi tidak ada blok SSL:

```nginx
server {
    listen 80;
    server_name core-r.domainrnd.com;
    client_max_body_size 12m;

    root /var/www/p85/core-r/public;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        try_files $uri =404;
        include fastcgi_params;
        fastcgi_pass dev-php85:9000;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
```

Caddy meneruskan header `Host` asli, sehingga nginx tetap mencocokkan `server_name`.

Untuk `core-r-fe` tidak perlu vhost nginx. Caddy langsung meneruskan ke `node24:3000` (lihat Caddyfile di atas).

### 9.4 Laravel di Belakang Proxy
Karena aplikasi diakses lewat Caddy, Laravel perlu diberi tahu agar memercayai header `X-Forwarded-*`. Kalau tidak, URL yang dibuat Laravel bisa berawalan `http://` padahal pengunjung memakai `https://`.

Di `bootstrap/app.php` (cek dulu apakah sudah ada konfigurasi proxy di project):

```php
->withMiddleware(function (Middleware $middleware): void {
    $middleware->trustProxies(at: '*');
})
```

`'*'` aman di sini karena nginx hanya terjangkau dari Caddy (lewat network Docker) atau dari `127.0.0.1` server.

Karena FE (`app.`) dan API (`core-r.`) berbeda subdomain, atur juga CORS agar API menerima origin FE:

```text
allowed_origins: https://app.domainrnd.com
```

(di `config/cors.php`, atau lewat `.env` kalau project sudah menyediakan variabelnya).

### 9.5 Node/Vite di Belakang Proxy
Vite memblokir host yang tidak dikenal dan salah menebak port HMR saat berada di belakang HTTPS. Di `vite.config.*` project FE:

```js
server: {
  host: '0.0.0.0',
  port: 3000,
  allowedHosts: ['app.domainrnd.com'],   // tanpa ini muncul "Blocked request. This host is not allowed"
  hmr: { clientPort: 443 },              // supaya hot reload lewat wss://app.domainrnd.com
},
```

Variabel build seperti `VITE_API_URL` (atau yang setara) diisi `https://core-r.domainrnd.com` di `.env` FE. Nilai ini tertanam saat build, jadi ubah lalu build ulang kalau berganti. Kalau FE memakai framework lain (Nuxt/Next), pengaturan padanannya serupa: izinkan host dan beri tahu port publik.

### 9.6 Reload & Test
```bash
# Tes konfigurasi nginx
docker exec dev-nginx nginx -t

# Reload nginx
docker exec dev-nginx nginx -s reload

# Lihat Caddy meminta sertifikat (cari baris "certificate obtained successfully")
docker logs -f dev-caddy

# Cek akses lewat domain
curl -I https://core-r.domainrnd.com
curl -I https://app.domainrnd.com

# Cek penerbit sertifikat
curl -vI https://core-r.domainrnd.com 2>&1 | grep -E "issuer:|expire date|SSL certificate verify"
```

Hasil yang benar: `issuer` berisi `Let's Encrypt` dan `SSL certificate verify ok`. Uji juga dari HP dengan data seluler (bukan Wi-Fi rumah). Kalau gembok muncul tanpa peringatan, sertifikatnya dipercaya perangkat lain juga.

Buka browser dan test langsung lewat: `https://core-r.domainrnd.com` dan `https://app.domainrnd.com`.

## 10. Kekurangan & Rekomendasi

| Temuan | Risiko | Rekomendasi |
|---|---|---|
| Port database dan tools di-publish ke semua interface | **Tinggi** (Docker menembus UFW) | Ikat ke `127.0.0.1`, jangan jalankan `tools.yml` kecuali perlu (bagian 6.4c). Cek dengan `sudo ss -tlnp`. |
| `ufw enable` tanpa mengizinkan SSH | **Tinggi** (terkunci dari server) | Selalu `sudo ufw allow OpenSSH` dulu (bagian 5.2). |
| Password default di compose (`r3t...`, `admin1234...`) | Tinggi jika terbuka ke internet | Ganti semuanya sebelum dipakai di server publik, walaupun port sudah diikat ke localhost. |
| `nginx` depends_on semua versi PHP | Sedang | Sesuaikan ke `php85` saja untuk server (bagian 6.4a). |
| Vhost nginx lama mengarah ke container yang tidak jalan | Sedang (nginx gagal start) | Pindahkan vhost yang tidak dipakai (bagian 6.4d). |
| `node24` working_dir beda dengan project `core-r-fe` | Sedang | Samakan path (Opsi A atau B di bagian 8.2) |
| `.env` lama berisi kredensial OAuth | Tinggi (jika ter-expose) | Use `.env` baru from `.env.example`, kosongkan kredensial if not needed |
| `caddy-data` hilang | Sedang | Backup folder itu; kalau hilang, sertifikat diminta ulang dan bisa terkena batas percobaan |
| Telescope/Swagger terbuka di domain publik (jika dipakai di `core-r`) | Sedang | Matikan lewat `.env` di server, atau batasi akses |
| `queue-worker` & `scheduler` hardcode `p84/riyerp` | Rendah (jika belum dipakai) | Komentari di `compose/php.yml` atau sesuaikan ke project yang dipakai |

## 11. Checklist Install Cepat (Fokus Domain)

- [ ] **Beli domain** untuk RnD (mis. `domainrnd.com`)
- [ ] **Setup DNS**: A record `core-r.domainrnd.com` & `app.domainrnd.com` -> IP publik server (cek dengan `dig`)
- [ ] Firewall penyedia server (jika ada): buka 22, 80, 443
- [ ] Di server: `ufw allow OpenSSH`, `ufw allow 80/tcp`, `ufw allow 443/tcp`, lalu `ufw enable`
- [ ] Install Docker + Docker Compose Plugin di Ubuntu 22.04
- [ ] Pindahkan `docker/`, `php/`, dan `node/` ke server (`~/project/`)
- [ ] `cp docker/.env.example docker/.env` & isi `UID:GID` (`id -u` / `id -g`), `COMPOSE_PROFILES=server`, `NGINX_HTTP`, `NGINX_HTTPS`, `NODE24_PORT`
- [ ] Edit `compose/server.yml` (port dari variabel, `depends_on` hanya `php85`)
- [ ] Tambah `compose/proxy.yml` dan `caddy/Caddyfile`, daftarkan `proxy.yml` di `include`
- [ ] Ikat port `database.yml` ke `127.0.0.1`, jangan jalankan `tools.yml` kecuali perlu
- [ ] Pindahkan vhost nginx PHP lama yang tidak dipakai ke `php/nginx-disabled/`
- [ ] Sesuaikan `node24` working_dir atau buat symlink ke `core-r-fe`
- [ ] Setup `.env` di `php/www/p85/core-r/` (`APP_URL`, `APP_DEBUG=false`) & `node/www/n24/core-r-fe/` (`VITE_API_URL`)
- [ ] Buat vhost `core-r.conf` di `php/nginx/` (tanpa SSL), atur trusted proxy dan CORS di Laravel
- [ ] Atur `allowedHosts` dan `hmr.clientPort` di Vite
- [ ] `docker compose up -d --build caddy nginx php85 node24 postgres redis`
- [ ] Verifikasi `sudo ss -tlnp`: hanya 22, 80, 443 yang terbuka ke luar
- [ ] Test akses via `https://core-r.domainrnd.com` & `https://app.domainrnd.com`, dan dari HP dengan data seluler

## Troubleshooting Singkat

```bash
# Cek permission user di container
docker exec -it dev-php85 id

# Tes konfigurasi nginx
docker exec dev-nginx nginx -t

# Lihat log
docker compose logs -f php85
docker compose logs -f node24
docker compose logs -f nginx
docker compose logs -f caddy

# Restart service terkait
docker compose restart nginx php85 node24 caddy
```

| Gejala | Penyebab dan solusi |
|---|---|
| Caddy tidak berhasil mendapat sertifikat | Cek berurutan: `dig` (DNS mengarah ke server?), firewall penyedia server (port 80 dan 443), `sudo ss -tlnp` (ada proses lain di port 80?), lalu `docker logs dev-caddy` |
| Browser menampilkan "koneksi tidak privat" | Sertifikat staging masih aktif (hapus baris `acme_ca` dan restart Caddy), atau Caddy belum selesai meminta sertifikat |
| `ERR_TOO_MANY_REDIRECTS` | Record Cloudflare berstatus Proxied dengan mode SSL `Flexible`. Pakai DNS Only, atau ubah mode ke `Full (strict)` |
| Link atau aset Laravel berawalan `http://` | Trusted proxy belum diatur (bagian 9.4) dan `APP_URL` belum `https://...` |
| `Blocked request. This host is not allowed` (Vite) | Tambahkan domain ke `server.allowedHosts` (bagian 9.5) |
| nginx gagal start: `host not found in upstream` | Ada vhost yang mengarah ke container PHP yang tidak berjalan (bagian 6.4d) |
| `502 Bad Gateway` dari Caddy | Container tujuan belum jalan atau nama service salah. Cek `docker compose ps` dan nama di Caddyfile (`nginx`, `node24`) |
| Port 80 sudah dipakai saat `up` | Nginx masih mem-publish `80:80`. Pastikan `NGINX_HTTP=127.0.0.1:8080:80` ada di `.env` |

**Rekomendasi awal:** Mulai hanya dengan service yang dibutuhkan (`caddy`, `nginx`, `php85`, `node24`, dan database yang dipakai). Baru nyalakan service lain setelah core berhasil running.