import 'package:flutter/material.dart';

import '../../models/epaper_model.dart';
import '../../repositories/epaper_repository.dart';
import 'epaper_viewer_screen.dart';

class EpaperDetailScreen extends StatefulWidget {
  const EpaperDetailScreen({
    super.key,
    required this.repository,
    required this.issueId,
  });
  final EpaperRepository repository;
  final String issueId;
  @override
  State<EpaperDetailScreen> createState() => _EpaperDetailScreenState();
}

class _EpaperDetailScreenState extends State<EpaperDetailScreen> {
  late Future<EpaperIssue?> _issueFuture;
  int _bottomIndex = 1; // E-Paper aktif

  @override
  void initState() {
    super.initState();
    _issueFuture = widget.repository.getEpaperById(widget.issueId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xfffffefa),
        body: SafeArea(
          child: FutureBuilder<EpaperIssue?>(
            future: _issueFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Column(
                  children: [
                    _buildHeader(),
                    _buildTabs(),
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                );
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    _buildHeader(),
                    _buildTabs(),
                    const Expanded(
                      child: Center(
                        child: Text('Detail e-paper belum dapat dimuat.'),
                      ),
                    ),
                  ],
                );
              }
              final issue = snapshot.data;
              if (issue == null) {
                return Column(
                  children: [
                    _buildHeader(),
                    _buildTabs(),
                    const Expanded(
                      child: Center(child: Text('Edisi tidak ditemukan.')),
                    ),
                  ],
                );
              }
              final bookmarked = widget.repository.isBookmarked(issue.id);
              return Column(
                children: [
                  _buildHeader(),
                  _buildTabs(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // ===== ARSIP HEADER =====
                        _buildArchiveHeader(issue),
                        const SizedBox(height: 20),

                        // ===== HERO CARD (GRADIENT NAVY) =====
                        _buildHeroCard(issue),
                        const SizedBox(height: 20),

                        // ===== INFO EDISI =====
                        _buildEditionInfo(issue),
                        const SizedBox(height: 16),

                        // ===== PREVIEW HALAMAN LABEL =====
                        _buildPreviewLabel(),
                        const SizedBox(height: 12),

                        // ===== DAFTAR ARTIKEL DI EDISI =====
                        _buildArticleList(issue),
                        const SizedBox(height: 20),

                        // ===== TOMBOL AKSI =====
                        _buildActionButtons(issue),
                        const SizedBox(height: 16),

                        // ===== BOOKMARK =====
                        _buildBookmarkRow(issue, bookmarked),
                        const SizedBox(height: 20),

                        // ===== PANEL UNDUH E-PAPER =====
                        _buildDownloadPanel(issue),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: _buildBottomNav(),
      );

  // ===== HEADER =====
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xfffffefa),
        border: Border(bottom: BorderSide(color: Color(0xffe8e4dd))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            color: const Color(0xff272521),
            tooltip: 'Kembali',
            onPressed: () => Navigator.pop(context),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xff2563eb), Color(0xff7c3aed)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Text(
              'ME',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MAGELANG EKSPRES',
                  style: TextStyle(
                    color: Color(0xffb91c1c),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Akurat, Terpercaya, dan Menginspirasi',
                  style: TextStyle(
                    color: Color(0xff77736d),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== TAB NAVIGASI =====
  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xfffffefa),
        border: Border(bottom: BorderSide(color: Color(0xffe8e4dd))),
      ),
      child: Row(
        children: [
          _tabItem('Beranda'),
          _tabItem('Lokal'),
          _tabItem('Terbaru'),
          _tabItem('E-Paper', active: true),
          _tabItem('Tersimpan'),
        ],
      ),
    );
  }

  Widget _tabItem(String label, {bool active = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xff272521) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xff77736d),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  // ===== ARSIP HEADER =====
  Widget _buildArchiveHeader(EpaperIssue issue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Arsip E-Paper Magelang Ekspres',
          style: TextStyle(
            color: Color(0xff272521),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Koleksi e-paper harian',
          style: TextStyle(
            color: Color(0xff77736d),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xfff5f3ee),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xffe8e4dd)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today,
                size: 14,
                color: Color(0xff272521),
              ),
              const SizedBox(width: 8),
              Text(
                issue.date,
                style: const TextStyle(
                  color: Color(0xff272521),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.arrow_drop_down,
                color: Color(0xff77736d),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===== HERO CARD (GRADIENT NAVY) =====
  Widget _buildHeroCard(EpaperIssue issue) {
    return Container(
      constraints: const BoxConstraints(minHeight: 340),
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff112b55), Color(0xff274d7d)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MAGELANG EKSPRES',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const Text(
            'Koran Warga Kita',
            style: TextStyle(
              color: Color(0xffffc0a0),
              fontStyle: FontStyle.italic,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: issue.coverImage == null
                ? Container(
                    decoration: BoxDecoration(
                      color: const Color(0xffd9b277),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.landscape_outlined,
                        size: 64,
                        color: Color(0xff112b55),
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _coverImage(issue.coverImage!),
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            issue.edition.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            issue.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  // ===== INFO EDISI =====
  Widget _buildEditionInfo(EpaperIssue issue) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfff5f3ee),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffe8e4dd)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xff272521),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.menu_book,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.edition,
                  style: const TextStyle(
                    color: Color(0xff272521),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${issue.date} • ${issue.totalPages} halaman',
                  style: const TextStyle(
                    color: Color(0xff77736d),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (issue.isSamplePreview)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xffb91c1c),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'PREVIEW',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===== PREVIEW HALAMAN LABEL =====
  Widget _buildPreviewLabel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xfff5f3ee),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe8e4dd)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_outlined,
            size: 16,
            color: Color(0xff272521),
          ),
          const SizedBox(width: 8),
          const Text(
            'PREVIEW HALAMAN',
            style: TextStyle(
              color: Color(0xff272521),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            '1/${_issueTotalPages()}',
            style: const TextStyle(
              color: Color(0xff77736d),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  int _issueTotalPages() {
    // fallback jika field tidak tersedia
    return 20;
  }

  // ===== DAFTAR ARTIKEL =====
  Widget _buildArticleList(EpaperIssue issue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Daftar Artikel',
                style: TextStyle(
                  color: Color(0xff272521),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            Text(
              issue.date,
              style: const TextStyle(
                color: Color(0xff77736d),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _articleRow(
          category: 'HEADLINE',
          title: issue.title.isNotEmpty
              ? issue.title
              : 'Edisi ${issue.edition}',
          time: issue.date,
        ),
        if (issue.isSamplePreview)
          _articleRow(
            category: 'INFO',
            title: 'Pratinjau halaman beresolusi rendah. Scan penuh tersedia untuk pelanggan aktif.',
            time: '',
          ),
      ],
    );
  }

  Widget _articleRow({
    required String category,
    required String title,
    required String time,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffe8e4dd)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xff112b55), Color(0xff274d7d)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: const Text(
              'ME',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: const TextStyle(
                    color: Color(0xffb91c1c),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff272521),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                if (time.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: const TextStyle(
                      color: Color(0xff77736d),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== TOMBOL AKSI =====
  Widget _buildActionButtons(EpaperIssue issue) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => EpaperViewerScreen(
                  repository: widget.repository,
                  issue: issue,
                ),
              ),
            ),
            icon: const Icon(Icons.menu_book, size: 18),
            label: const Text(
              'Baca versi e-paper',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff272521),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => EpaperViewerScreen(
                  repository: widget.repository,
                  issue: issue,
                ),
              ),
            ),
            icon: const Icon(Icons.grid_view, size: 18),
            label: const Text(
              'Grid E-Paper',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Color(0xff272521)),
              foregroundColor: const Color(0xff272521),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===== BOOKMARK ROW =====
  Widget _buildBookmarkRow(EpaperIssue issue, bool bookmarked) {
    return InkWell(
      onTap: () {
        setState(() {
          if (bookmarked) {
            widget.repository.removeBookmark(issue.id);
          } else {
            widget.repository.bookmarkEpaper(issue.id);
          }
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bookmarked
              ? const Color(0xff272521)
              : const Color(0xfff5f3ee),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xffe8e4dd)),
        ),
        child: Row(
          children: [
            Icon(
              bookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: bookmarked ? Colors.white : const Color(0xff272521),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                bookmarked ? 'Tersimpan di koleksi Anda' : 'Simpan e-paper ini',
                style: TextStyle(
                  color: bookmarked ? Colors.white : const Color(0xff272521),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== PANEL UNDUH E-PAPER =====
  Widget _buildDownloadPanel(EpaperIssue issue) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff112b55), Color(0xff274d7d)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.download_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unduh E-Paper (PDF)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Terlindungi & Berwatermark',
                      style: TextStyle(
                        color: Color(0xffffc0a0),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Unduh e-paper dalam format PDF berkualitas tinggi untuk dibaca kapan saja secara offline. Setiap e-paper dilindungi watermark dinamis berisi email dan waktu unduh untuk keamanan konten.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                // trigger download
              },
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text(
                'Unduh PDF',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffd9b277),
                foregroundColor: const Color(0xff112b55),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== BOTTOM NAV =====
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xfffffefa),
        border: Border(top: BorderSide(color: Color(0xffe8e4dd))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _bottomItem(Icons.home_outlined, 'Beranda', 0),
            _bottomItem(Icons.menu_book_outlined, 'E-Paper', 1),
            _bottomItem(Icons.bookmark_border, 'Tersimpan', 2),
            _bottomItem(Icons.person_outline, 'Akun', 3),
          ],
        ),
      ),
    );
  }

  Widget _bottomItem(IconData icon, String label, int index) {
    final active = _bottomIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _bottomIndex = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: active ? const Color(0xffb91c1c) : const Color(0xff77736d),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? const Color(0xffb91c1c)
                      : const Color(0xff77736d),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverImage(String source) {
    const fallback = ColoredBox(color: Color(0xffd9b277));
    return source.startsWith('assets/')
        ? Image.asset(
            source,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.network(
            source,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
  }
}