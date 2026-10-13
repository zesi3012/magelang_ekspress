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

  @override
  void initState() {
    super.initState();
    _issueFuture = widget.repository.getEpaperById(widget.issueId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DETAIL E-PAPER')),
    body: FutureBuilder<EpaperIssue?>(
      future: _issueFuture,
      builder: (context, snapshot) {
        final issue = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('Detail e-paper belum dapat dimuat.'),
          );
        }
        if (issue == null) {
          return const Center(child: Text('Edisi tidak ditemukan.'));
        }
        final bookmarked = widget.repository.isBookmarked(issue.id);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 340),
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff112b55), Color(0xff274d7d)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MAGELANG EKSPRES',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'Koran Warga Kita',
                    style: TextStyle(
                      color: Color(0xffffc0a0),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: issue.coverImage == null
                        ? const ColoredBox(
                            color: Color(0xffd9b277),
                            child: Center(
                              child: Icon(
                                Icons.landscape_outlined,
                                size: 64,
                                color: Color(0xff112b55),
                              ),
                            ),
                          )
                        : _coverImage(issue.coverImage!),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    issue.edition.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    issue.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              issue.edition,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text('${issue.date} • ${issue.totalPages} halaman'),
            if (issue.isSamplePreview) ...[
              const SizedBox(height: 12),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.preview_outlined),
                title: Text('Pratinjau edisi koran'),
                subtitle: Text(
                  'Preview halaman beresolusi rendah. Scan penuh tersedia untuk pelanggan aktif.',
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
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
                    icon: const Icon(Icons.menu_book),
                    label: const Text('BUKA E-PAPER'),
                  ),
                ),
                IconButton(
                  tooltip: 'Bookmark e-paper',
                  icon: Icon(
                    bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  ),
                  onPressed: () {
                    setState(() {
                      if (bookmarked) {
                        widget.repository.removeBookmark(issue.id);
                      } else {
                        widget.repository.bookmarkEpaper(issue.id);
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        );
      },
    ),
  );

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
