# Magelang Express API

Backend Dart `dart:io` dengan dua pilihan storage:

- MySQL/MariaDB untuk penggunaan utama.
- `backend/data/store.json` sebagai fallback development.

## Membuat database lewat phpMyAdmin

1. Install dan jalankan XAMPP atau Laragon.
2. Nyalakan **Apache** dan **MySQL**.
3. Buka `http://localhost/phpmyadmin`.
4. Pilih menu **Import**.
5. Pilih `backend/database/magelang_express.sql`.
6. Klik **Go**.

File SQL membuat database `magelang_express`, tabel pengguna, artikel,
kategori, e-paper, paket langganan, subscription, saved items, audit log, dan
`admin_users` khusus akun CMS.

## Migrasi data lama

Setelah schema selesai di-import, jalankan dari root project:

```powershell
$env:APP_ENV='development'
$env:API_BIND_HOST='127.0.0.1'
$env:ADMIN_2FA_CODE='ganti-dengan-kode-pribadi-minimal-6-karakter'
$env:DOWNLOAD_SIGNING_SECRET='isi-secret-acak-minimal-32-karakter'
$env:DB_DRIVER='mysql'
$env:DB_HOST='127.0.0.1'
$env:DB_PORT='3306'
$env:DB_NAME='magelang_express'
$env:DB_USER='magelang_app'
$env:DB_PASSWORD='gunakan-password-database-yang-kuat'
$env:DB_IMPORT_JSON='true'
$env:APP_ENV='development'
$env:ADMIN_2FA_CODE='ganti-dengan-kode-pribadi-minimal-6-karakter'
$env:DOWNLOAD_SIGNING_SECRET='isi-secret-acak-minimal-32-karakter'
dart run backend/server.dart
```

`DB_IMPORT_JSON=true` mengimpor data JSON ketika tabel artikel MySQL kosong.
Gunakan hanya pada basis data baru yang belum berisi data bisnis lain; salin
cadangan sebelum migrasi. Setelah berhasil, matikan flag tersebut:

```powershell
$env:DB_IMPORT_JSON='false'
dart run backend/server.dart
```

## Menjalankan API

```powershell
$env:DB_DRIVER='mysql'
$env:DB_HOST='127.0.0.1'
$env:DB_PORT='3306'
$env:DB_NAME='magelang_express'
$env:DB_USER='magelang_app'
$env:DB_PASSWORD='gunakan-password-database-yang-kuat'
dart run backend/server.dart
```

API berjalan di `http://localhost:8787` secara default. Atur `API_PORT` untuk
memakai port lokal yang berbeda. Tes koneksi:

```powershell
Invoke-RestMethod http://localhost:8787/health
```

Untuk menyalakan API lokal dengan konfigurasi pengembangan yang aman, jalankan
dari PowerShell di root proyek:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\start_local_api.ps1
```

Skrip memakai penyimpanan JSON lokal, hanya bind ke `127.0.0.1`, dan membuat
secret signing acak di memori setiap kali server dimulai. Biarkan jendela
PowerShell tetap terbuka selama menggunakan website; sesi API akan berakhir
ketika server dihentikan. Kode verifikasi lokalnya adalah kode yang dibagikan
oleh pemilik situs untuk verifikasi pembaca. Login CMS mengirim OTP unik ke
email akun admin dan memerlukan konfigurasi Gmail SMTP di bawah ini.

Sebelum menjalankan server, buat App Password dari akun Google pengirim
(jangan gunakan kata sandi Gmail biasa). Skrip lokal akan meminta alamat Gmail
dan membaca App Password secara tersembunyi jika environment belum diisi:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\start_local_api.ps1
```

Untuk server hosting, isi variabel environment berikut:

```powershell
$env:SMTP_HOST='smtp.gmail.com'
$env:SMTP_PORT='587'
$env:SMTP_USERNAME='pengirim@gmail.com'
$env:SMTP_APP_PASSWORD='app-password-google'
$env:SMTP_FROM_EMAIL='pengirim@gmail.com'
$env:SMTP_FROM_NAME='Magelang Ekspres'
```

Jangan commit App Password atau memasukkannya ke Flutter. Kode admin berlaku
5 menit, disimpan sebagai HMAC di memori server, maksimal lima kali percobaan,
dan tidak pernah dikembalikan melalui API/log. Jika SMTP gagal, login admin
ditolak dan server mengembalikan error yang dapat dicoba ulang.

Jika `DB_DRIVER` tidak diisi atau bukan `mysql`, backend menggunakan JSON.
Mode JSON hanya untuk testing lokal; gunakan `DB_DRIVER=mysql` agar seluruh
perubahan CMS tersimpan di database yang dapat dilihat melalui phpMyAdmin.

Untuk basis data yang pernah memakai kredensial admin development yang diketahui,
j alankan `backend/database/migrate_secure_admin_auth.sql` sebelum membuka
layanan kembali. Skrip hanya menonaktifkan akun yang memiliki hash/kata sandi
seed tersebut dan mempertahankan riwayat pelanggan/transaksi. Akun Super Admin
pertama dibuat melalui bootstrap token, bukan kredensial bawaan.

Untuk database lama yang sudah dibuat sebelum pengaturan konten dan foto artikel
ditambahkan, import `backend/database/migrate_site_settings.sql` melalui
phpMyAdmin sebelum menjalankan backend dengan `DB_DRIVER=mysql`. Untuk kolom
slug dan metadata SEO artikel, import `backend/database/migrate_article_seo.sql`
juga.

Untuk database yang sudah ada, import
`backend/database/migrate_article_revisions.sql` sebelum menjalankan workflow
artikel yang menyimpan riwayat revisi. Instalasi baru mendapat tabel tersebut
dari `backend/database/magelang_express.sql`.

Workflow CMS artikel divalidasi server-side: Author mengirim draft untuk review,
Editor atau Super Admin menyetujui atau menolak dengan catatan, artikel siap
terbit dapat diterbitkan atau dijadwalkan, dan artikel terbit dapat diarsipkan.
Publikasi terjadwal dijalankan otomatis pada permintaan API pertama setelah
waktunya tiba. Endpoint workflow tersedia pada
`/api/admin/articles/{id}/submit-review`, `/approve`, `/reject`, `/schedule`,
`/publish`, `/archive`, dan `/revisions`.

Media yang diunggah backend JSON disimpan di `backend/data/uploads/`. Preview
halaman koran berukuran kecil disajikan melalui `/media/...`; scan beresolusi
penuh hanya diberikan melalui URL bertanda tangan selama 10 menit setelah
server memastikan langganan masih aktif. File edisi contoh 13 Agustus dan
1 Oktober 2026 memakai PDF di `docx_pdf/` dan gambar privat di
`backend/data/uploads/private/`. Kedua folder tersebut menolak akses langsung
Apache melalui `.htaccess`; akses penuh tetap melewati API. Backup folder
uploads bersama store JSON sebelum memindahkan server.

Saat startup, backend menambahkan dua edisi contoh tersebut dan kategori
Kampung Inovatif serta Koran Sekolah tanpa menggandakan data yang sudah ada.
Halaman 6 edisi 13 Agustus disorot sebagai Kampung Inovatif. Preview publik
sengaja beresolusi rendah agar isi koran tidak dapat dibaca sebelum login
berlangganan.

Backend juga menghapus entri contoh lama yang diketahui bukan berasal dari
PDF sumber. Untuk instalasi MySQL, perubahan ini dijalankan secara terarah
saat startup; skrip `database/migrate_remove_placeholder_content.sql` dapat
dipakai untuk menerapkannya sebelum deployment.

## Konfigurasi keamanan dan bootstrap admin

```powershell
$env:ADMIN_2FA_CODE='kode-pribadi-bukan-123456'
$env:ADMIN_BOOTSTRAP_TOKEN='secret-acak-minimal-32-karakter'
$env:DOWNLOAD_SIGNING_SECRET='secret-acak-minimal-32-karakter'
$env:MIDTRANS_SERVER_KEY='server-key-dari-akun-merchant'
$env:MIDTRANS_IS_PRODUCTION='false'
$env:ALLOWED_ORIGINS='https://www.domain-anda.id,https://domain-anda.id'
$env:PUBLIC_SITE_URL='https://www.domain-anda.id'
```

API menolak nilai contoh dan rahasia lemah. Buat kredensial bootstrap pertama
dengan header `X-Admin-Bootstrap-Key` saat belum ada akun admin; setelah itu
token tidak lagi dapat mendaftarkan admin dan harus dihapus dari environment.
Pendaftaran admin biasa hanya boleh dilakukan Super Admin. Login saat ini masih memakai challenge bersama; autentikasi pelanggan melalui
email dan sesi persisten belum siap produksi.

Pada produksi, `APP_ENV=production` mewajibkan HTTPS origin allowlist,
`DB_DRIVER=mysql`, bind host eksplisit, user database khusus (bukan `root`),
password database kuat, dan kredensial merchant Midtrans produksi. Terapkan
`database/migrate_midtrans.sql` sebelum mengaktifkan pembayaran di MySQL.
Tempatkan API di belakang TLS proxy yang
terkonfigurasi benar, batasi jaringan database, jangan menyimpan secret di
repository, dan lakukan rotasi secret.

## Menjalankan Flutter dengan API

```powershell
flutter run --dart-define=USE_API=true --dart-define=API_BASE_URL=http://localhost:8787
```

Untuk Android emulator, gunakan `http://10.0.2.2:8787`. Untuk perangkat fisik,
gunakan IP komputer di jaringan lokal, misalnya `http://192.168.1.10:8787`.

## Endpoint utama

- `GET /health`
- `GET /api/v1/articles`
- `GET /api/v1/search?q=...`
- `GET /api/v1/epapers`
- `GET /api/v1/epapers/:id`
- `GET /robots.txt`
- `GET /sitemap.xml`
- `GET /api/v1/subscription/packages`
- `POST /api/v1/subscription/checkout`
- `POST /api/v1/payment/webhook`
- `GET /api/v1/saved-items`
- `DELETE /api/v1/saved-items/:itemType/:itemId`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `POST /api/admin/auth/register`
- `POST /api/admin/auth/login`
- `POST /api/admin/auth/verify`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/verify`
- `GET /api/admin/dashboard`
- `POST /api/admin/articles`
- `POST /api/admin/articles/:id/publish`
- `PATCH /api/admin/subscription-plans/:id`

Checkout membuat transaksi Snap menggunakan server key Midtrans; server key
tidak pernah dikirim ke aplikasi. Notifikasi Midtrans memeriksa `signature_key`
(SHA-512) dan jumlah invoice, kemudian memproses status secara idempoten.
Endpoint callback internal dan konfirmasi pembayaran manual dinonaktifkan.
Gunakan URL publik `https://domain-anda/api/v1/payment/webhook` pada dashboard
merchant setelah domain/API HTTPS tersedia. Tanpa server key merchant, metode
pembayaran tidak ditampilkan dan checkout menolak pembayaran.
URL download e-paper berlaku 10 menit dan setiap permintaan dicatat ke
`download_logs`. Gambar halaman penuh menggunakan signature HMAC yang memuat
ID edisi, nomor halaman, email, dan waktu kedaluwarsa. Ganti
`DOWNLOAD_SIGNING_SECRET` sebelum deploy.
Atur `PUBLIC_SITE_URL` ke origin HTTPS produksi agar sitemap menghasilkan URL
kanonis; tanpa pengaturan itu, endpoint sitemap menolak membuat URL localhost.

Email reset kata sandi, verifikasi email, dan pengiriman kode 2FA individual
belum terintegrasi. Sesi akses kini menyimpan hash token dan dapat dipulihkan
dari JSON/MySQL setelah restart; challenge login singkat tetap berada di memori.
Mode `APP_ENV=production` sengaja menolak startup sampai email verifikasi,
pemulihan kata sandi, dan MFA per pengguna tersedia. Jangan mengiklankan alur
pemulihan akun atau menyatakan sistem siap produksi sampai semua integrasi dan
uji deployment selesai.
