import 'package:flutter_test/flutter_test.dart';
import 'package:magelang_express/repositories/mock_epaper_repository.dart';

void main() {
  late MockEpaperRepository repository;

  setUp(() => repository = MockEpaperRepository());

  test('mock repository includes both supplied newspaper editions', () async {
    final issues = await repository.getEpaperIssues();
    expect(
      issues.map((issue) => issue.id),
      orderedEquals(['epaper-2026-08-13', 'epaper-2026-10-01']),
    );
    for (final issue in issues) {
      expect(issue.totalPages, 8);
      expect(
        issue.pages.map((page) => page.pageNumber),
        orderedEquals([1, 2, 3, 4, 5, 6, 7, 8]),
      );
    }
  });

  test('13 August page six is highlighted as Kampung Inovatif', () async {
    final page = await repository.getEpaperPage('epaper-2026-08-13', 6);
    expect(page?.label, 'KAMPUNG INOVATIF');
    expect(page?.previewImage, contains('epaper-2026-08-13-p06.jpg'));
    expect(
      (await repository.getEpaperArticles(
        'epaper-2026-08-13',
        6,
      )).map((article) => article.category).toSet(),
      {'KAMPUNG INOVATIF'},
    );
  });

  test('page lookup accepts valid pages and rejects invalid pages', () async {
    final issue = (await repository.getEpaperIssues()).first;
    expect((await repository.getEpaperPage(issue.id, 1))?.pageNumber, 1);
    expect((await repository.getEpaperPage(issue.id, 8))?.pageNumber, 8);
    expect(await repository.getEpaperPage(issue.id, 0), isNull);
    expect(await repository.getEpaperPage(issue.id, 9), isNull);
  });

  test('all mock article page numbers are valid', () async {
    final issues = await repository.getEpaperIssues();
    expect(
      issues.every(
        (issue) => issue.articles.every(
          (article) =>
              article.pageNumber >= 1 && article.pageNumber <= issue.totalPages,
        ),
      ),
      isTrue,
    );
  });

  test('bookmark can be added and removed', () async {
    final issue = (await repository.getEpaperIssues()).first;
    expect(repository.isBookmarked(issue.id), isFalse);
    repository.bookmarkEpaper(issue.id);
    expect(repository.isBookmarked(issue.id), isTrue);
    repository.removeBookmark(issue.id);
    expect(repository.isBookmarked(issue.id), isFalse);
  });

  test('article bookmark can be added and removed', () {
    expect(repository.isArticleBookmarked('headline'), isFalse);
    repository.bookmarkArticle('headline');
    expect(repository.isArticleBookmarked('headline'), isTrue);
    repository.removeArticleBookmark('headline');
    expect(repository.isArticleBookmarked('headline'), isFalse);
  });

  test('download follows mock subscription state', () {
    expect(repository.canDownloadEpaper(), isFalse);
    repository.setMockSubscriptionActive(false);
    expect(repository.canDownloadEpaper(), isFalse);
    repository.setMockSubscriptionActive(true);
    expect(repository.canDownloadEpaper(), isTrue);
  });
}
