import 'package:flutter_test/flutter_test.dart';
import 'package:magelang_express/repositories/mock_article_repository.dart';

void main() {
  late MockArticleRepository repository;

  setUp(() => repository = MockArticleRepository());

  test('returns only the source-verified Kampung Inovatif articles', () async {
    final result = await repository.getArticles();
    expect(
      result.map((article) => article.id),
      orderedEquals([
        'kampung-inovatif-2026-08-13',
        'kampung-inovatif-meteseh-2026-08-13',
      ]),
    );
    expect(result.every((article) => article.isPremium), isTrue);
  });

  test('search matches the supplied newspaper titles and category', () async {
    final titleResult = await repository.searchArticles('Maggot');
    final categoryResult = await repository.searchArticles('Kampung Inovatif');
    expect(titleResult.single.id, 'kampung-inovatif-2026-08-13');
    expect(categoryResult, hasLength(2));
  });
}
