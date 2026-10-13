import '../data/mock_article_data.dart';
import '../models/article_model.dart';
import 'article_repository.dart';

// TEMPORARY LOCAL IMPLEMENTATION. WILL BE REPLACED BY API REPOSITORY.
class MockArticleRepository implements ArticleRepository {
  @override
  Future<List<Article>> getArticles() async => mockArticles;

  @override
  Future<List<Article>> searchArticles(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return mockArticles;
    return mockArticles
        .where(
          (article) => '${article.title} ${article.category}'
              .toLowerCase()
              .contains(normalizedQuery),
        )
        .toList();
  }
}
