class EpaperIssue {
  const EpaperIssue({
    required this.id,
    required this.title,
    required this.edition,
    required this.date,
    required this.totalPages,
    this.coverImage,
    this.downloadAvailable = true,
    this.isSamplePreview = false,
    required this.pages,
    required this.articles,
  });

  final String id;
  final String title;
  final String edition;
  final String date;
  final int totalPages;
  final String? coverImage;
  final bool downloadAvailable;
  final bool isSamplePreview;
  final List<EpaperPage> pages;
  final List<EpaperArticle> articles;
}

class EpaperPage {
  const EpaperPage({
    required this.pageNumber,
    required this.label,
    required this.accentColor,
    this.image,
    this.previewImage,
    required this.articleIds,
  });

  final int pageNumber;
  final String label;
  final int accentColor;
  final String? image;
  final String? previewImage;
  final List<String> articleIds;
}

class EpaperArticle {
  const EpaperArticle({
    required this.id,
    required this.title,
    required this.category,
    required this.pageNumber,
    required this.isPremium,
    this.thumbnail,
    this.pageImage,
    this.excerpt = '',
    this.socialLinks = const {},
    this.isLocked,
    required this.content,
  });

  final String id;
  final String title;
  final String category;
  final int pageNumber;
  final bool isPremium;
  final String? thumbnail;
  final String? pageImage;
  final String excerpt;
  final Map<String, String> socialLinks;
  final bool? isLocked;
  final String content;
}
