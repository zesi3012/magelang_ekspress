class Article {
  const Article({
    required this.id,
    required this.title,
    required this.category,
    required this.isPremium,
    required this.body,
    required this.excerpt,
    this.imageUrl,
    this.imageAltText,
    this.author,
    this.publishedAt,
    this.updatedAt,
    this.slug,
    this.seoTitle,
    this.seoDescription,
    this.socialLinks = const {},
  });

  final String id;
  final String title;
  final String category;
  final bool isPremium;
  final String body;
  final String excerpt;
  final String? imageUrl;
  final String? imageAltText;
  final String? author;
  final String? publishedAt;
  final String? updatedAt;
  final String? slug;
  final String? seoTitle;
  final String? seoDescription;
  final Map<String, String> socialLinks;
}
