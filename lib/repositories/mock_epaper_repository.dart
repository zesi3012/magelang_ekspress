import '../data/mock_epaper_data.dart';
import '../models/epaper_model.dart';
import 'epaper_repository.dart';

// TEMPORARY LOCAL IMPLEMENTATION. WILL BE REPLACED BY API REPOSITORY.
class MockEpaperRepository implements EpaperRepository {
  bool _subscriptionActive = false;
  final Set<String> _bookmarks = <String>{};
  final Set<String> _articleBookmarks = <String>{};

  @override
  Future<List<EpaperIssue>> getEpaperIssues() async => mockEpaperIssues;

  @override
  Future<EpaperIssue?> getEpaperById(String id) async =>
      mockEpaperIssues.where((issue) => issue.id == id).firstOrNull;

  @override
  Future<EpaperPage?> getEpaperPage(String issueId, int pageNumber) async {
    final issue = await getEpaperById(issueId);
    if (issue == null || pageNumber < 1 || pageNumber > issue.totalPages) {
      return null;
    }
    return issue.pages[pageNumber - 1];
  }

  @override
  Future<List<EpaperArticle>> getEpaperArticles(
    String issueId,
    int pageNumber,
  ) async {
    final issue = await getEpaperById(issueId);
    final page = await getEpaperPage(issueId, pageNumber);
    if (issue == null || page == null) return [];
    return issue.articles
        .where((article) => page.articleIds.contains(article.id))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> requestDownload(String issueId) async {
    if (!canDownloadEpaper()) {
      throw Exception('Download terkunci. Silakan berlangganan.');
    }
    return {'issueId': issueId};
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

extension on Iterable<EpaperIssue> {
  EpaperIssue? get firstOrNull => isEmpty ? null : first;
}
