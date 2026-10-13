# Magelang Ekspres — blueprint CMS SEO dan Google Play

**Target kesiapan internal:** 20 Oktober 2026  
**Status:** prototipe lokal; belum diterbitkan ke Play Store.

## Produk dan arsitektur

- **Pembaca:** Flutter Web dan Android dengan satu desain responsif.
- **API/CMS:** Dart API pada `backend/server.dart`; JSON lokal untuk prototipe,
  MySQL melalui `MysqlStore` untuk instalasi yang dikonfigurasi.
- **Berita:** artikel, kategori, gambar, status premium, slug, judul SEO, dan
  deskripsi SEO.
- **E-paper:** arsip dua edisi contoh. Preview halaman berukuran rendah dapat
  dilihat publik; pelanggan aktif mendapat scan/PDF melalui tautan sementara.
- **Rubrik warga:** Kampung Inovatif dan Koran Sekolah adalah kategori editorial
  tersendiri. Isi dari PDF pindai belum ditranskripsikan; jangan mengarang
  kutipan sebagai laporan koran.

## Alur redaksi dan SEO

1. Author menulis judul, kategori, ringkasan, isi, gambar, slug, judul SEO, dan
   deskripsi SEO pada editor CMS.
2. API memeriksa panjang metadata dan format slug, mencegah penggunaan slug
   duplikat, lalu menyimpan nilai pada JSON atau kolom MySQL.
3. Jika metadata SEO kosong, API memakai judul dan ringkasan artikel sebagai
   fallback. Untuk artikel premium, isi dan gambar asli tetap disensor bagi
   pengunjung tanpa langganan.
4. Flutter Web memperbarui title, description, Open Graph, dan canonical ketika
   artikel dibuka. Untuk mesin pencari yang memerlukan HTML server-rendered,
   rencanakan website SSR terpisah/proxy SEO; Flutter Web tetap sebuah SPA.
5. Set `PUBLIC_SITE_URL` ke URL HTTPS produksi sebelum mendaftarkan
   `/sitemap.xml` di Google Search Console. Jangan gunakan alamat localhost.

## Listing Google Play — draf

- **Nama aplikasi:** Magelang Ekspres
- **Short description:** Berita Magelang, Jawa Tengah, e-paper, dan kisah warga.
- **Kategori:** News & Magazines
- **Bahasa utama:** Bahasa Indonesia
- **Long description:**

  Baca kabar terbaru dari Magelang dan Jawa Tengah bersama Magelang Ekspres.
  Ikuti berita daerah, jelajahi Kampung Inovatif dan Koran Sekolah, serta buka
  arsip e-paper dalam satu aplikasi.

  **Fitur**
  - Berita daerah dan pilihan kategori redaksi.
  - E-paper edisi pilihan dengan preview yang ringan.
  - Akses halaman koran lengkap bagi pelanggan aktif.
  - Simpan berita untuk dibaca kembali.
  - Bagikan artikel dan tautan edisi.

  Ketersediaan artikel, arsip, dan fitur pelanggan mengikuti konten serta paket
  yang disediakan Magelang Ekspres.

- **Package ID:** belum ditetapkan. `com.example.magelang_express` adalah
  placeholder pengembangan dan tidak boleh dipakai untuk publikasi.
- **Signing:** wajib memakai upload keystore yang dikuasai pemilik penerbit.
- **Aset listing:** siapkan ikon 512×512, feature graphic 1024×500, minimal dua
  screenshot ponsel, serta screenshot tablet bila mendukung perangkat tablet.
  Semua gambar harus menangkap build final, tanpa data akun nyata.

## Persiapan rilis

1. Pemilik memilih dan memastikan package ID belum pernah dipakai atau
   dipublikasikan. Package ID tidak dapat diganti setelah publikasi.
2. Siapkan upload keystore dan simpan salinan cadangan aman. Buat
   `android/key.properties` secara lokal; file ini dikecualikan dari Git.
3. Set `MAGELANG_APPLICATION_ID` dan `API_BASE_URL` ke endpoint produksi HTTPS,
   lalu build dengan `flutter build appbundle --release`.
4. Uji login, pemulihan pembelian/langganan, tautan bertanda tangan yang
   kedaluwarsa, aksesibilitas, dan aplikasi pada perangkat Android nyata.
5. Lengkapi akun Google Play Console, privacy policy URL, Data safety form,
   content rating, target audience, negara, harga, dan deklarasi langganan.
6. Unggah AAB ke internal testing, undang tester, perbaiki hasil pre-launch
   report, lalu ajukan production release.

Build rilis Android sengaja menolak konfigurasi package ID atau signing yang
belum lengkap. Tidak ada signing key atau kredensial Play Console di proyek ini.
Publikasi memerlukan pemilik akun Play Console dan persetujuan daftar data/
privasi aplikasi yang sebenarnya.
