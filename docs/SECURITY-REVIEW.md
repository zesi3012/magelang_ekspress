# Ringkasan Tinjauan Keamanan

## Temuan dan perbaikan

| # | Severity | File | Lines | Vulnerability | Confidence |
|---|----------|------|-------|---------------|------------|
| 1 | 🟠 HIGH | `backend/server.dart` | 319-354, 515-525 | Endpoint pendaftaran admin sebelumnya dapat dipakai publik dan kode 2FA memiliki nilai bawaan yang diketahui. Pendaftaran kini memerlukan Super Admin atau bootstrap token acak sekali pakai saat belum ada admin; startup menolak kode bawaan/lemah. | 9/10 |
| 2 | 🟠 HIGH | `backend/server.dart`, `backend/database/magelang_express.sql` | 2792-2798; 176-177 | Akun Super Admin seed memakai hash SHA-256 untuk kata sandi development yang diketahui. Seed dihapus; akun lama dengan kredensial seed dinonaktifkan tanpa menghapus transaksi/riwayat; login password legacy yang sah di-upgrade ke PBKDF2-HMAC-SHA256. | 9/10 |
| 3 | 🟠 HIGH | `backend/server.dart` | 779-805, 1991-1998 | Secret callback pembayaran memiliki fallback development yang dapat diprediksi. Secret kini wajib dikonfigurasi, minimal 32 karakter, dan signature dibandingkan secara constant-time. | 9/10 |
| 4 | 🟠 HIGH | `backend/server.dart` | 195-255, 1963-1987 | Secret URL scan e-paper memiliki fallback development yang dapat diprediksi. Secret kini wajib dikonfigurasi dan URL tetap bertanda tangan dengan masa berlaku serta pemeriksaan langganan aktif. | 9/10 |

## Mitigasi tambahan yang diterapkan

- CORS produksi memakai allowlist origin HTTPS; request tanpa `Origin` tetap bisa digunakan oleh klien server-ke-server.
- Header keamanan, HSTS produksi, batas ukuran body, respons error tanpa rincian internal, dan rate limit endpoint autentikasi/callback diterapkan.
- Penyimpanan hash password saat login tidak lagi memanggil rewrite penuh tabel MySQL; MySQL hanya memperbarui hash akun yang sedang login.
- Callback tidak menerima status `refunded` yang belum didukung oleh alur pembatalan langganan.
- Endpoint lupa kata sandi kini melaporkan `503` sampai provider email nyata dikonfigurasi; tidak lagi memberikan respons sukses seolah email telah dikirim.

## Batasan yang belum diselesaikan

- Challenge 2FA masih memakai satu kode konfigurasi bersama, bukan TOTP atau kode per pengguna yang dikirim melalui provider.
- Sesi disimpan dalam memori proses; restart API membatalkan semua sesi. Refresh token tidak persisten.
- Email verifikasi dan reset kata sandi belum mempunyai provider email.
- Callback HMAC adalah kontrak lokal, bukan adapter gateway pembayaran produksi. Belum ada verifikasi langsung terhadap provider, refund, atau rekonsiliasi.
- Belum ada pengujian integrasi backend otomatis untuk seluruh alur di atas. Sebelum produksi, jalankan migrasi SQL, konfigurasi TLS/proxy serta allowlist, rotasi seluruh secret, uji dari jaringan deployment, dan integrasikan provider nyata.

Perubahan dibuat di workspace yang tidak memiliki metadata Git, sehingga tidak dapat dibuat commit.
