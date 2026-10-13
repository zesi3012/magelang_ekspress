import '../models/article_model.dart';
import '../services/reader_api_client.dart';
import 'article_repository.dart';

class ApiArticleRepository implements ArticleRepository {
  ApiArticleRepository({ReaderApiClient? client})
    : client = client ?? ReaderApiClient();

  final ReaderApiClient client;

  @override
  Future<List<Article>> getArticles() => client.getArticles();

  @override
  Future<List<Article>> searchArticles(String query) =>
      client.searchArticles(query);
}
