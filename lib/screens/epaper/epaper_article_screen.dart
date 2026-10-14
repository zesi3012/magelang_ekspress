import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/epaper_model.dart';
import '../../repositories/epaper_repository.dart';
import '../../services/share_service.dart';

class EpaperArticleScreen extends StatefulWidget {
  const EpaperArticleScreen({
    super.key,
    required this.repository,
    required this.article,
  });
  final EpaperRepository repository;
  final EpaperArticle article;
  @override
  State<EpaperArticleScreen> createState() => _EpaperArticleScreenState();
}

class _EpaperArticleScreenState extends State<EpaperArticleScreen> {
  late bool saved;
  int _bottomIndex = 1; // E-Paper aktif

  @override
  void initState() {
    super.initState();
    saved = widget.repository.isArticleBookmarked(widget.article.id);
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.article.isPremium &&
        (widget.article.isLocked ??
            (widget.article.content.isEmpty ||
                !widget.repository.canDownloadEpaper()));

    return Scaffold(
      backgroundColor: const Color(0xfffffefa),
      body: SafeArea(
        child: Column(
          children: [
            // ===== HEADER STICKY =====
            _buildHeader(),

            // ===== TAB NAVIGASI =====
            _buildTabs(),

            // ===== MODE LABEL =====
            _buildModeLabel(),

            // ===== KONTEN ARTIKEL =====
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Kategori + tanggal
                  Text(
                    '${widget.article.category.toUpperCase()} · Halaman ${widget.article.pageNumber}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Judul
                  Text(
                    widget.article.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                      color: Color(0xff272521),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Gambar
                  if (widget.article.pageImage != null ||
                      widget.article.thumbnail != null)
                    _buildImage(locked),

                  const SizedBox(height: 20),

                  // Konten atau Preview
                  if (locked)
                    _buildLockedContent()
                  else
                    Text(
                      widget.article.content,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.7,
                        color: Color(0xff272521),
                      ),
                    ),

                  // Social links
                  if (!locked && widget.article.socialLinks.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Divider(color: Color(0xffe8e4dd)),
                    const SizedBox(height: 16),
                    const Text(
                      'Tautan Terkait',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff272521),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in widget.article.socialLinks.entries)
                          _buildSocialChip(entry.key, entry.value),
                      ],
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Tombol aksi
                  _buildActionButtons(),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

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
          IconButton(
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            color: const Color(0xff272521),
            tooltip: saved ? 'Hapus bookmark' : 'Simpan artikel',
            onPressed: () {
              setState(() {
                saved = !saved;
                if (saved) {
                  widget.repository.bookmarkArticle(widget.article.id);
                } else {
                  widget.repository.removeArticleBookmark(widget.article.id);
                }
              });
            },
          ),
          IconButton(
            tooltip: 'Bagikan artikel',
            icon: const Icon(Icons.share_outlined),
            color: const Color(0xff272521),
            onPressed: () => ShareService.shareArticle(
              title: widget.article.title,
              id: widget.article.id,
              destination: 'Lainnya',
              epaperArticle: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xfffffefa),
        border: Border(bottom: BorderSide(color: Color(0xffe8e4dd))),
      ),
      child: Row(
        children: [
          _tabItem('Beranda', 0),
          _tabItem('Lokal', 2),
          _tabItem('Terbaru', 3),
          _tabItem('E-Paper', 1),
          _tabItem('Tersimpan', 4),
        ],
      ),
    );
  }

  Widget _tabItem(String label, int index) {
    final active = index == 1; // E-Paper aktif
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

  Widget _buildModeLabel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: const Color(0xfff5f3ee),
      child: Row(
        children: [
          const Icon(
            Icons.article_outlined,
            size: 18,
            color: Color(0xff272521),
          ),
          const SizedBox(width: 8),
          const Text(
            'MODE ARTIKEL',
            style: TextStyle(
              color: Color(0xff272521),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            '${widget.article.pageNumber}/20',
            style: const TextStyle(
              color: Color(0xff77736d),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(bool locked) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              widget.article.thumbnail ?? widget.article.pageImage!,
              fit: BoxFit.cover,
            ),
            if (!locked && widget.article.pageImage != null)
              Image.network(
                widget.article.pageImage!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            if (locked)
              Container(
                color: const Color(0xff171717).withOpacity(0.5),
                child: const Center(
                  child: Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: Colors.white,
                  ),
                ),
              ),
            if (locked)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff171717),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Premium',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedContent() {
    final previewText = widget.article.excerpt.isNotEmpty
        ? widget.article.excerpt
        : widget.article.content;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xfff5f3ee),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffe8e4dd)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            previewText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              height: 1.5,
              fontSize: 14,
              color: Color(0xff272521),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffe8e4dd)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Color(0xff272521),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Pratinjau artikel • Berlangganan untuk membuka scan dan artikel lengkap.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff272521),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialChip(String label, String value) {
    final uri = _safeSocialUri(value);
    if (uri == null) return const SizedBox.shrink();
    return ActionChip(
      avatar: Icon(
        Icons.open_in_new,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text(
              'Baca versi e-paper',
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
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
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
        onTap: () {
          setState(() => _bottomIndex = index);
        },
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

  Uri? _safeSocialUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }
}