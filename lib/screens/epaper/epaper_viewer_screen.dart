import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_typography.dart';
import '../../models/epaper_model.dart';
import '../../repositories/epaper_repository.dart';
import 'epaper_article_screen.dart';

class EpaperViewerScreen extends StatefulWidget {
  const EpaperViewerScreen({
    super.key,
    required this.repository,
    required this.issue,
  });
  final EpaperRepository repository;
  final EpaperIssue issue;
  @override
  State<EpaperViewerScreen> createState() => _EpaperViewerScreenState();
}

class _EpaperViewerScreenState extends State<EpaperViewerScreen> {
  final ScrollController _scrollController = ScrollController();
  double _pageExtent = 0;
  int _page = 1;
  double _scale = 1;
  int _bottomIndex = 1; // E-Paper aktif

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xfffffefa),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 900;
              return Column(
                children: [
                  // ===== HEADER =====
                  _buildHeader(),

                  // ===== TAB NAVIGASI =====
                  _buildTabs(),

                  // ===== MODE LABEL =====
                  _buildModeLabel(),

                  // ===== KONTEN UTAMA =====
                  Expanded(
                    child: Row(
                      children: [
                        if (desktop) _thumbnailRail(),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, viewport) {
                              _pageExtent =
                                  (viewport.maxWidth - AppSpacing.xl * 2) /
                                          .72 +
                                      AppSpacing.xl * 2;
                              return NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  if (notification is ScrollUpdateNotification ||
                                      notification is UserScrollNotification) {
                                    _updateVisiblePage();
                                  }
                                  return false;
                                },
                                child: ListView.separated(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.md,
                                  ),
                                  itemCount: widget.issue.pages.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: AppSpacing.md),
                                  itemBuilder: (_, index) => InteractiveViewer(
                                    minScale: .8,
                                    maxScale: 3,
                                    panEnabled: false,
                                    scaleEnabled: true,
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(
                                          AppSpacing.lg,
                                        ),
                                        child: _pageCanvas(
                                          widget.issue.pages[index],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ===== MOBILE THUMBNAILS =====
                  if (!desktop) _mobileThumbnails(),

                  // ===== ZOOM CONTROLS =====
                  _buildZoomControls(),

                  // ===== ACTION BUTTONS =====
                  _buildActionButtons(),

                  // ===== DOWNLOAD PANEL =====
                  _buildDownloadPanel(),
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
          IconButton(
            tooltip: widget.issue.downloadAvailable
                ? 'Download e-paper'
                : 'PDF belum tersedia',
            icon: const Icon(Icons.download_outlined),
            color: const Color(0xff272521),
            onPressed: _download,
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

  // ===== MODE LABEL =====
  Widget _buildModeLabel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xfff5f3ee),
      child: Row(
        children: [
          const Icon(
            Icons.menu_book_outlined,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xff272521),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$_page/${widget.issue.totalPages}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== ZOOM CONTROLS =====
  Widget _buildZoomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _zoomButton(Icons.zoom_out, 'Perkecil', () {
            setState(() => _scale = (_scale - .2).clamp(.8, 3.0));
          }),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xfff5f3ee),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xffe8e4dd)),
            ),
            child: Text(
              '${(_scale * 100).round()}%',
              style: const TextStyle(
                color: Color(0xff272521),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _zoomButton(Icons.zoom_in, 'Perbesar', () {
            setState(() => _scale = (_scale + .2).clamp(.8, 3.0));
          }),
          const SizedBox(width: 8),
          _zoomButton(Icons.fit_screen, 'Reset', () {
            setState(() => _scale = 1);
          }),
        ],
      ),
    );
  }

  Widget _zoomButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xffe8e4dd)),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: const Color(0xff272521),
          ),
        ),
      ),
    );
  }

  // ===== ACTION BUTTONS =====
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.grid_view, size: 16),
              label: const Text(
                'Grid E-Paper',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Color(0xff272521)),
                foregroundColor: const Color(0xff272521),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _showArticles,
              icon: const Icon(Icons.list, size: 16),
              label: const Text(
                'Daftar Artikel',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: const Color(0xff272521),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== DOWNLOAD PANEL =====
  Widget _buildDownloadPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff112b55), Color(0xff274d7d)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.picture_as_pdf,
                color: Colors.white,
                size: 18,
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
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Terlindungi & Berwatermark',
                    style: TextStyle(
                      color: Color(0xffffc0a0),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: _download,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffd9b277),
                foregroundColor: const Color(0xff112b55),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Unduh PDF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
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
                color: active
                    ? const Color(0xffb91c1c)
                    : const Color(0xff77736d),
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

  Widget _thumbnailRail() => Container(
        width: 112,
        color: AppColors.navyDeep,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.sm,
        ),
        child: ListView.separated(
          itemCount: widget.issue.pages.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, index) =>
              _thumbnail(widget.issue.pages[index], compact: true),
        ),
      );

  Widget _mobileThumbnails() => SizedBox(
        height: 76,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          scrollDirection: Axis.horizontal,
          itemCount: widget.issue.pages.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, index) => _thumbnail(widget.issue.pages[index]),
        ),
      );

  Widget _thumbnail(EpaperPage page, {bool compact = false}) {
    final selected = page.pageNumber == _page;
    return GestureDetector(
      onTap: () => _scrollToPage(page.pageNumber),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: compact ? 88 : 58,
        height: compact ? 112 : 62,
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.paper,
          border: Border.all(
            color: selected ? const Color(0xffb91c1c) : Colors.white24,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: page.previewImage == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(page.accentColor).withOpacity(.22),
                      ),
                      child: CustomPaint(
                        painter: _MiniPaperPainter(page.accentColor),
                      ),
                    )
                  : _pageImage(
                      page.previewImage!,
                      BoxFit.cover,
                      ColoredBox(
                        color: Color(page.accentColor).withOpacity(.22),
                      ),
                    ),
            ),
            const SizedBox(height: 2),
            Text(
              '${page.pageNumber}',
              textAlign: TextAlign.center,
              style: AppTypography.label.copyWith(
                fontSize: 9,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageCanvas(EpaperPage page) {
    final articles = widget.issue.articles
        .where((item) => page.articleIds.contains(item.id))
        .toList();
    if (page.image != null || page.previewImage != null) {
      return Transform.scale(
        scale: _scale,
        child: GestureDetector(
          onTap: articles.isEmpty
              ? null
              : () => _showArticlePreview(articles.first),
          child: AspectRatio(
            aspectRatio: .72,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (page.previewImage != null)
                  _pageImage(
                    page.previewImage!,
                    BoxFit.contain,
                    const ColoredBox(color: AppColors.paper),
                  ),
                if (page.image != null)
                  _pageImage(
                    page.image!,
                    BoxFit.contain,
                    page.previewImage == null
                        ? const ColoredBox(color: AppColors.paper)
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Transform.scale(
      scale: _scale,
      child: GestureDetector(
        onTap: articles.isEmpty
            ? null
            : () => _showArticlePreview(articles.first),
        child: AspectRatio(
          aspectRatio: .72,
          child: Container(
            color: AppColors.paper,
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MAGELANG EKSPRES',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      '${page.pageNumber} • ${widget.issue.date}',
                      style: AppTypography.label.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(height: 3, color: const Color(0xffb91c1c)),
                const SizedBox(height: AppSpacing.md),
                Text(
                  page.label,
                  style: AppTypography.section.copyWith(
                    color: Color(page.accentColor),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (articles.isNotEmpty)
                  Text(
                    articles.first.title,
                    style: AppTypography.display.copyWith(fontSize: 26),
                  ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _paperImage(page)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(flex: 2, child: _paperColumns(articles)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Container(height: 1, color: AppColors.line),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'KORAN DIGITAL',
                      style: AppTypography.label.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageImage(String source, BoxFit fit, Widget fallback) {
    return source.startsWith('assets/')
        ? Image.asset(source, fit: fit, errorBuilder: (_, __, ___) => fallback)
        : Image.network(
            source,
            fit: fit,
            errorBuilder: (_, __, ___) => fallback,
          );
  }

  void _scrollToPage(int pageNumber) {
    if (!_scrollController.hasClients || _pageExtent == 0) return;
    _scrollController.animateTo(
      AppSpacing.md + (pageNumber - 1) * (_pageExtent + AppSpacing.md),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _updateVisiblePage() {
    if (!_scrollController.hasClients || _pageExtent == 0) return;
    final page = ((_scrollController.offset - AppSpacing.md) /
                (_pageExtent + AppSpacing.md))
            .floor() +
        1;
    final visiblePage = page.clamp(1, widget.issue.totalPages).toInt();
    if (visiblePage != _page) setState(() => _page = visiblePage);
  }

  Widget _paperImage(EpaperPage page) => DecoratedBox(
        decoration: BoxDecoration(
          color: Color(page.accentColor).withOpacity(.22),
          border: Border.all(color: AppColors.line),
        ),
        child: CustomPaint(
          painter: _PaperIllustrationPainter(page.accentColor),
          child: const SizedBox.expand(),
        ),
      );

  Widget _paperColumns(List<EpaperArticle> articles) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            articles.isEmpty ? 'Halaman koran digital' : articles.first.content,
            maxLines: articles.length > 1 ? 4 : 8,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
          if (articles.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            Container(height: 1, color: AppColors.line),
            const SizedBox(height: AppSpacing.sm),
            Text(
              articles[1].title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.headline.copyWith(fontSize: 15),
            ),
          ],
        ],
      );

  void _showArticlePreview(EpaperArticle article) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xfffffefa),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                article.category,
                style: const TextStyle(
                  color: Color(0xffb91c1c),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                article.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xff272521),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                article.isPremium
                    ? 'Artikel premium • pelanggan aktif dapat membaca penuh'
                    : 'Artikel gratis dapat dibaca tanpa berlangganan',
                style: const TextStyle(
                  color: Color(0xff77736d),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => EpaperArticleScreen(
                          repository: widget.repository,
                          article: article,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chrome_reader_mode, size: 16),
                  label: const Text(
                    'MODE ARTIKEL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff272521),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showArticles() async {
    final pageArticles = await widget.repository.getEpaperArticles(
      widget.issue.id,
      _page,
    );
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xfffffefa),
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DAFTAR ARTIKEL',
                style: TextStyle(
                  color: Color(0xff272521),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Edisi ${widget.issue.date}',
                style: const TextStyle(
                  color: Color(0xff77736d),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              ...pageArticles.map(
                (article) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xffe8e4dd)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
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
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    title: Text(
                      article.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff272521),
                      ),
                    ),
                    subtitle: Text(
                      '${article.category} • Halaman ${article.pageNumber}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff77736d),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0xff77736d),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => EpaperArticleScreen(
                            repository: widget.repository,
                            article: article,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _download() async {
    if (!widget.issue.downloadAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF edisi belum diunggah oleh redaksi.'),
        ),
      );
      return;
    }
    if (!widget.repository.canDownloadEpaper()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download terkunci. Silakan berlangganan.'),
        ),
      );
      return;
    }
    try {
      final result = await widget.repository.requestDownload(widget.issue.id);
      if (!mounted) return;
      final bytes = result['bytes'];
      if (bytes is Uint8List) {
        final saved = await FilePicker.saveFile(
          fileName: '${widget.issue.id}.pdf',
          bytes: bytes,
          mimeType: 'application/pdf',
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
          dialogTitle: 'Simpan e-paper',
        );
        if (!mounted || saved == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF e-paper berhasil disimpan.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File PDF belum tersedia untuk edisi contoh.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}

class _MiniPaperPainter extends CustomPainter {
  const _MiniPaperPainter(this.accentColor);
  final int accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = Paint()..color = Color(accentColor).withOpacity(.75);
    final ink = Paint()..color = AppColors.navy.withOpacity(.55);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * .18), accent);
    for (var index = 0; index < 5; index++) {
      final y = size.height * (.3 + index * .12);
      canvas.drawRect(
        Rect.fromLTWH(size.width * .08, y, size.width * (.7 - index * .05), 2),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniPaperPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

class _PaperIllustrationPainter extends CustomPainter {
  const _PaperIllustrationPainter(this.accentColor);
  final int accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = Paint()..color = Color(accentColor).withOpacity(.7);
    final navy = Paint()..color = AppColors.navy.withOpacity(.75);
    canvas.drawCircle(
      Offset(size.width * .7, size.height * .28),
      size.width * .14,
      accent,
    );
    final hills = Path()
      ..moveTo(0, size.height * .7)
      ..lineTo(size.width * .25, size.height * .42)
      ..lineTo(size.width * .45, size.height * .7)
      ..lineTo(size.width * .7, size.height * .35)
      ..lineTo(size.width, size.height * .7)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hills, navy);
    canvas.drawRect(
      Rect.fromLTWH(size.width * .12, size.height * .78, size.width * .76, 2),
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperIllustrationPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}