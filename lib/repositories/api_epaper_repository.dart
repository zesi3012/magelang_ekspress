import '../models/epaper_model.dart';
import '../services/reader_api_client.dart';
import 'epaper_repository.dart';

class ApiEpaperRepository implements EpaperRepository {
  ApiEpaperRepository({ReaderApiClient? client})
    : client = client ?? ReaderApiClient();

  final ReaderApiClient client;
  final _bookmarks = <String>{};
  final _articleBookmarks = <String>{};
  bool _subscriptionActive = false;

  @override
  Future<List<EpaperIssue>> getEpaperIssues() => client.getEpaperIssues();

  @override
  Future<EpaperIssue?> getEpaperById(String id) => client.getEpaperById(id);

  @override
  Future<EpaperPage?> getEpaperPage(String issueId, int pageNumber) async {
    final issue = await getEpaperById(issueId);
    return issue?.pages
        .where((page) => page.pageNumber == pageNumber)
        .firstOrNull;
  }

  @override
  Future<List<EpaperArticle>> getEpaperArticles(
    String issueId,
    int pageNumber,
  ) async {
    final issue = await getEpaperById(issueId);
    return issue?.articles
            .where((article) => article.pageNumber == pageNumber)
            .toList() ??
        [];
  }

  @override
  Future<Map<String, dynamic>> requestDownload(String issueId) async {
    final result = await client.requestEpaperDownload(issueId);
    _subscriptionActive = true;
    final url = result['url']?.toString() ?? '';
    if (url.isEmpty) return result;
    final bytes = await client.downloadEpaperPdf(url);
    return {...result, 'bytes': bytes};
  }

  @override
  bool canDownloadEpaper() => _subscriptionActive;

  @override
  void setMockSubscriptionActive(bool active) => _subscriptionActive = active;

  @override
  bool isBookmarked(String issueId) => _bookmarks.contains(issueId);

  @override
  void bookmarkEpaper(String issueId) => _bookmarks.add(issueId);

  @override
  void removeBookmark(String issueId) => _bookmarks.remove(issueId);

  @override
  bool isArticleBookmarked(String articleId) =>
      _articleBookmarks.contains(articleId);

  @override
  void bookmarkArticle(String articleId) => _articleBookmarks.add(articleId);

  @override
  void removeArticleBookmark(String articleId) =>
      _articleBookmarks.remove(articleId);
}

extension on Iterable<EpaperPage> {
  EpaperPage? get firstOrNull => isEmpty ? null : first;
}
