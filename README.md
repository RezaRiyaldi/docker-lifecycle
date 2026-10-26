# Docker Stack (PHP + Node + Nginx + Database)

Dokumen ini ditujukan buat setup di server fisik Ubuntu 22.04 yang masih kosong, khususnya buat uji coba `core-r` (PHP 8.5) dan `core-r-fe` (Node 24).

> **Fokus:** Setup menggunakan **domain** (bukan akses via IP:port). Beli domain untuk proses RnD terlebih dahulu. Nanti kalau mau go public, kamu bisa beli domain baru sesuai kebutuhan aplikasi.

## 1. Struktur Direktori

Dari root workspace (`/home/boy/Documents/project/`):

```text
.
├── docker/        # Stack docker (compose, config terkait)
├── php/           # PHP apps, Dockerfile per versi, nginx vhost, ssl
│   ├── docker/    # Dockerfile per versi PHP
│   ├── nginx/     # vhost nginx yang di-mount ke container nginx
│   ├── ssl/       # sertifikat lokal/wildcard
│   └── www/       # source code PHP (p56/p74/.../p85/...)
└── node/          # Node apps & Dockerfile
    ├── docker/    # Dockerfile per versi Node
    └── www/       # source code Node (n20/n22/n24/...)
```

Stack ini menjalankan `nginx` -> `php-fpm` (per versi PHP) dan `node` container langsung atau via reverse proxy nginx.

## 2. Kondisi Saat Ini (Quick Review)

| Item | Status | Keterangan |
|---|---|---|
| Multi-PHP (5.6 - 8.5) | OK | Tersedia di `compose/php.yml` |
| PHP 8.5 (`php85`) | OK | Cocok buat `p85/core-r`. Ada `custom.ini`, `zzz-custom.conf`, mount `ssl/`. |
| Node (20/22/24) | OK | Tersedia. `node24` expose `3024:3000`. |
| Nginx reverse PHP | OK | `php/nginx/p85.conf` pakai pola subdomain `*.p85.test` + redirect HTTP->HTTPS + fastcgi ke `dev-php85:9000`. |
| Nginx reverse Node | PERLU DITAMBAH | Belum ada vhost untuk Node. Saat ini hanya bisa diakses via `IP_SERVER:3024`. Lebih rapi jika lewat subdomain + nginx di port 80/443. |
| Path Node | PERLU PENYESUAIAN | `node24` di `compose/node.yml` punya `working_dir: /var/www/n24/my-app` padahal project kamu ada di `../node/www/n24/core-r-fe`. Perlu disesuaikan atau dibuat symlink. |
| `.env` | ADA (berisi kredensial OAuth) | Jangan pakai mentah di server publik. Buat `.env` baru dari `.env.example` & isi `UID:GID`. Kosongkan kredensial OAuth jika tidak dipakai. |
| Queue/Scheduler | HARDCORE | `queue-worker` & `scheduler` masih hardcode ke `p84/riyerp`. Aman di-disable jika belum dipakai. |
| SSL wildcard | ADA | Terdapat file SSL di `php/ssl/`. Untuk RnD bisa pakai mkcert, untuk domain real wajib pakai sertifikat valid (Let's Encrypt/Cloudflare). |

## 3. Kebutuhan Server

- OS: Ubuntu 22.04 LTS (fresh)
- Akses root/sudo
- **Domain** yang sudah dibeli untuk RnD (bisa satu domain utama, lalu pakai subdomain untuk tiap aplikasi)
- **DNS Management** (Cloudflare/Registrar panel) buat atur record A/CNAME
- Port yang perlu dibuka: `80`, `443` (utama). **Tidak disarankan** mengakses aplikasi langsung via IP:port, semua harus lewat Nginx + domain/subdomain.

## 4. Instalasi di Server Baru

### 4.1 Update & Dependensi
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg git unzip ufw
```

### 4.2 Install Docker & Docker Compose Plugin
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

### 4.3 Pindahkan Project

Pindahkan seluruh folder `docker/`, `php/`, dan `node/` ke server. Pastikan struktur relasinya tetap sama karena `docker-compose.yml` menggunakan relative path.

Contoh target: `/home/<user>/project/`

```bash
mkdir -p ~/project
# rsync/scp/git clone ketiganya ke ~/project/
```

## 5. Konfigurasi Awal

### 5.1 Konfigurasi .env
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

# Kosongkan jika tidak dipakai
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
```

> Hindari menggunakan `.env` yang ada saat ini di repo karena berisi kredensial. Lebih aman buat baru dari `.env.example`.

### 5.2 Atur Permission
Agar file yang dibuat container bisa diedit dari host:

```bash
sudo chown -R $UID:$GID ~/project/php/www ~/project/node/www
find ~/project/php/www -type d -exec chmod 775 {} \;
find ~/project/node/www -type d -exec chmod 775 {} \;
find ~/project/php/www -type f -exec chmod 664 {} \;
find ~/project/node/www -type f -exec chmod 664 {} \;
```

Untuk Laravel, pastikan folder `storage/` dan `bootstrap/cache/` writable.

### 5.3 SSL untuk RnD
Cek isi `php/ssl/`:
```bash
ls -la ~/project/php/ssl/
```

- **Untuk testing lokal-like:** Bisa pakai [mkcert](https://github.com/FiloSottile/mkcert) dan sesuaikan nama file dengan yang dipanggil di `p85.conf` (`_wildcard.pxx.test.pem` / `-key.pem`).
- **Untuk domain real RnD:** Lebih disarankan pakai Let's Encrypt (via Certbot) atau Cloudflare Origin Certificate.

## 6. Menjalankan Stack

Dari direktori `docker/`:

```bash
cd ~/project/docker

# Build & jalankan
docker compose build
docker compose up -d
```

Cek status & log:
```bash
docker compose ps
docker compose logs -f nginx
```

Untuk menghentikan:
```bash
docker compose down
```

## 7. Setup Project `core-r` (PHP 8.5) & `core-r-fe` (Node 24)

### 7.1 PHP - `p85/core-r`
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

### 7.2 Node - `n24/core-r-fe`
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
      - "3024:3000"
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

> Catatan: Setelah reverse proxy dikonfigurasi (section 8), akses via domain/subdomain di port 80/443. Jangan mengandalkan akses langsung `IP_SERVER:3024` untuk RnD. Hanya dipakai untuk pengecekan internal sebelum setup Nginx.

## 8. Konfigurasi Domain & Subdomain (RnD)

### 8.1 Untuk PHP (`core-r`) via subdomain
Buat vhost baru di `~/project/php/nginx/core-r.conf`:

```nginx
# HTTP -> HTTPS
server {
    listen 80;
    server_name core-r.rnd.domainkamu.com;
    return 301 https://$host$request_uri;
}

# HTTPS
server {
    listen 443 ssl;
    server_name core-r.rnd.domainkamu.com;
    client_max_body_size 12m;

    ssl_certificate     /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

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

### 8.2 Untuk Node (`core-r-fe`) via reverse proxy
Buat vhost baru di `~/project/php/nginx/core-r-fe.conf`:

```nginx
# HTTP -> HTTPS
server {
    listen 80;
    server_name app.rnd.domainkamu.com;
    return 301 https://$host$request_uri;
}

# HTTPS
server {
    listen 443 ssl;
    server_name app.rnd.domainkamu.com;
    client_max_body_size 12m;

    ssl_certificate     /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    location / {
        proxy_pass http://node24:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

Reload nginx setelah menambah vhost:
```bash
docker exec dev-nginx nginx -t && docker exec dev-nginx nginx -s reload
```

### 8.3 Setup DNS & SSL
1. Arahkan DNS A record (subdomain) ke IP publik server
2. Pasang sertifikat di `php/ssl/` (`fullchain.pem` & `privkey.pem`) atau sesuaikan path di vhost
3. Untuk production-like, disarankan pakai Let's Encrypt

## 9. Kekurangan & Rekomendasi

| Temuan | Risiko | Rekomendasi |
|---|---|---|
| `node24` working_dir beda dengan project `core-r-fe` | Sedang | Samakan path (Opsi A atau B di section 7.2) |
| Belum ada nginx vhost untuk Node | Sedang | Tambahkan vhost reverse proxy (section 8.2) agar konsisten pakai domain + 80/443 |
| `queue-worker` & `scheduler` hardcode `p84/riyerp` | Rendah (jika belum dipakai) | Komentari di `docker-compose.yml` atau sesuaikan ke project yang dipakai |
| `.env` lama berisi kredensial OAuth | Tinggi (jika ter-expose) | Gunakan `.env` baru dari `.env.example`, kosongkan kredensial jika tidak dipakai |
| Port Node di-expose langsung | Sedang | Tutup akses langsung setelah reverse proxy berjalan, atau batasi dengan firewall |
| SSL masih pakai wildcard contoh | Sedang | Ganti dengan sertifikat sesuai domain RnD yang akan dipakai |

## 10. Checklist Install Cepat

- [ ] Install Docker + Docker Compose Plugin di Ubuntu 22.04
- [ ] Pindahkan `docker/`, `php/`, `node/` ke server (`~/project/`)
- [ ] `cp docker/.env.example docker/.env` & isi `UID:GID` sesuai `id -u/id -g`
- [ ] Sesuaikan `node24` working_dir atau buat symlink ke `core-r-fe`
- [ ] Setup `.env` di `php/www/p85/core-r/` & `node/www/n24/core-r-fe/`
- [ ] Pasang sertifikat ke `php/ssl/`
- [ ] Tambah DNS A record + vhost nginx untuk `core-r` & `core-r-fe`
- [ ] `docker compose up -d --build`
- [ ] Setup firewall: `sudo ufw allow 80,443 && sudo ufw enable`
- [ ] Test akses via subdomain HTTPS

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

# Restart service terkait
docker compose restart nginx php85 node24
```

**Rekomendasi awal:** Mulai hanya dengan service yang dibutuhkan (`nginx`, `php85`, `node24`, dan database yang dipakai). Baru nyalakan service lain setelah core berhasil running.