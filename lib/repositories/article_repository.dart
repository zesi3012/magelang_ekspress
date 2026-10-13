import '../models/article_model.dart';

abstract interface class ArticleRepository {
  Future<List<Article>> getArticles();
  Future<List<Article>> searchArticles(String query);
}
