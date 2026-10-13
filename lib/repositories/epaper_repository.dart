import '../models/epaper_model.dart';

abstract interface class EpaperRepository {
  Future<List<EpaperIssue>> getEpaperIssues();
  Future<EpaperIssue?> getEpaperById(String id);
  Future<EpaperPage?> getEpaperPage(String issueId, int pageNumber);
  Future<List<EpaperArticle>> getEpaperArticles(String issueId, int pageNumber);
  Future<Map<String, dynamic>> requestDownload(String issueId);
  bool canDownloadEpaper();
  void setMockSubscriptionActive(bool active);
  bool isBookmarked(String issueId);
  void bookmarkEpaper(String issueId);
  void removeBookmark(String issueId);
  bool isArticleBookmarked(String articleId);
  void bookmarkArticle(String articleId);
  void removeArticleBookmark(String articleId);
}
