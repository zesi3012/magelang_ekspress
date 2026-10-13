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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.issue.title}  $_page/${widget.issue.totalPages}'),
      actions: [
        IconButton(
          tooltip: 'Perkecil',
          icon: const Icon(Icons.zoom_out),
          onPressed: () =>
              setState(() => _scale = (_scale - .2).clamp(.8, 3.0)),
        ),
        IconButton(
          tooltip: 'Perbesar',
          icon: const Icon(Icons.zoom_in),
          onPressed: () =>
              setState(() => _scale = (_scale + .2).clamp(.8, 3.0)),
        ),
        IconButton(
          tooltip: 'Reset zoom',
          icon: const Icon(Icons.fit_screen),
          onPressed: () => setState(() => _scale = 1),
        ),
        IconButton(
          tooltip: widget.issue.downloadAvailable
              ? 'Download e-paper'
              : 'PDF belum tersedia',
          icon: const Icon(Icons.download_outlined),
          onPressed: _download,
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (desktop) _thumbnailRail(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, viewport) {
                        _pageExtent =
                            (viewport.maxWidth - AppSpacing.xl * 2) / .72 +
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
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.md),
                            itemBuilder: (_, index) => InteractiveViewer(
                              minScale: .8,
                              maxScale: 3,
                              panEnabled: false,
                              scaleEnabled: true,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  child: _pageCanvas(widget.issue.pages[index]),
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
            if (!desktop) _mobileThumbnails(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'HALAMAN $_page / ${widget.issue.totalPages}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _showArticles,
                    icon: const Icon(Icons.list),
                    label: const Text('DAFTAR ARTIKEL', maxLines: 1),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _thumbnailRail() => Container(
    width: 112,
    color: AppColors.navyDeep,
    padding: const EdgeInsets.symmetric(
      vertical: AppSpacing.md,
      horizontal: AppSpacing.sm,
    ),
    child: ListView.separated(
      itemCount: widget.issue.pages.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
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
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
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
            color: selected ? AppColors.red : Colors.white24,
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
                        color: Color(page.accentColor).withValues(alpha: .22),
                      ),
                      child: CustomPaint(
                        painter: _MiniPaperPainter(page.accentColor),
                      ),
                    )
                  : _pageImage(
                      page.previewImage!,
                      BoxFit.cover,
                      ColoredBox(
                        color: Color(page.accentColor).withValues(alpha: .22),
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
                Container(height: 3, color: AppColors.red),
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
        ? Image.asset(source, fit: fit, errorBuilder: (_, _, _) => fallback)
        : Image.network(source, fit: fit, errorBuilder: (_, _, _) => fallback);
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
    final page =
        ((_scrollController.offset - AppSpacing.md) /
                (_pageExtent + AppSpacing.md))
            .floor() +
        1;
    final visiblePage = page.clamp(1, widget.issue.totalPages).toInt();
    if (visiblePage != _page) setState(() => _page = visiblePage);
  }

  Widget _paperImage(EpaperPage page) => DecoratedBox(
    decoration: BoxDecoration(
      color: Color(page.accentColor).withValues(alpha: .22),
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
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                article.category,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                article.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                article.isPremium
                    ? 'Artikel premium • pelanggan aktif dapat membaca penuh'
                    : 'Artikel gratis dapat dibaca tanpa berlangganan',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
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
                icon: const Icon(Icons.chrome_reader_mode),
                label: const Text('MODE ARTIKEL'),
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
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'ARTIKEL DI E-PAPER',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            ...pageArticles.map(
              (article) => ListTile(
                title: Text(article.title),
                subtitle: Text(
                  '${article.category} • Halaman ${article.pageNumber}',
                ),
                trailing: const Icon(Icons.chevron_right),
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
          ],
        ),
      ),
    );
  }

  Future<void> _download() async {
    if (!widget.issue.downloadAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF edisi belum diunggah oleh redaksi.')),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _MiniPaperPainter extends CustomPainter {
  const _MiniPaperPainter(this.accentColor);
  final int accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = Paint()..color = Color(accentColor).withValues(alpha: .75);
    final ink = Paint()..color = AppColors.navy.withValues(alpha: .55);
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
    final accent = Paint()..color = Color(accentColor).withValues(alpha: .7);
    final navy = Paint()..color = AppColors.navy.withValues(alpha: .75);
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
