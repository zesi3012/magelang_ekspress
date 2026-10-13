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

  @override
  void initState() {
    super.initState();
    saved = widget.repository.isArticleBookmarked(widget.article.id);
  }

  @override
  Widget build(BuildContext context) {
    final locked =
        widget.article.isPremium &&
        (widget.article.isLocked ??
            (widget.article.content.isEmpty ||
                !widget.repository.canDownloadEpaper()));
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
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
            onPressed: () => ShareService.shareArticle(
              title: widget.article.title,
              id: widget.article.id,
              destination: 'Lainnya',
              epaperArticle: true,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.article.category,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.article.title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Text('Halaman ${widget.article.pageNumber}'),
          const SizedBox(height: 20),
          if (widget.article.pageImage != null ||
              widget.article.thumbnail != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: .72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      widget.article.thumbnail ?? widget.article.pageImage!,
                      fit: BoxFit.contain,
                    ),
                    if (!locked && widget.article.pageImage != null)
                      Image.network(
                        widget.article.pageImage!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    if (locked)
                      const Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircleAvatar(
                            backgroundColor: Color(0xff171717),
                            child: Icon(Icons.lock, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          const SizedBox(height: 20),
          if (locked)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.article.excerpt.isEmpty
                          ? widget.article.content
                          : widget.article.excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(height: 1.45),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pratinjau dua baris • berlangganan untuk membuka scan dan artikel lengkap.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              widget.article.content,
              style: const TextStyle(fontSize: 17, height: 1.65),
            ),
          if (!locked && widget.article.socialLinks.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in widget.article.socialLinks.entries)
                  if (_safeSocialUri(entry.value) case final uri?)
                    ActionChip(
                      avatar: const Icon(Icons.open_in_new, size: 16),
                      label: Text(entry.key),
                      onPressed: () =>
                          launchUrl(uri, mode: LaunchMode.externalApplication),
                    ),
              ],
            ),
          ],
        ],
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
