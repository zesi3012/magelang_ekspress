// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

const _siteTitle = 'Magelang Ekspres | Berita Magelang & E-Paper Digital';
const _siteDescription =
    'Berita Magelang dan Jawa Tengah, e-paper harian, serta kisah Kampung Inovatif.';

bool isAdminEntry() {
  final location = Uri.tryParse(html.window.location.href);
  final path = location?.path.replaceAll(RegExp(r'/+$'), '');
  return location?.queryParameters['admin'] == '1' ||
      path?.endsWith('/admin') == true ||
      path?.endsWith('/admin/login') == true;
}

void showArticleMetadata({
  required String title,
  required String description,
  required String articleId,
  String? imageUrl,
}) {
  html.document.title = title;
  _setMeta('name', 'description', description);
  _setMeta('property', 'og:type', 'article');
  _setMeta('property', 'og:title', title);
  _setMeta('property', 'og:description', description);
  if (imageUrl != null && imageUrl.isNotEmpty) {
    _setMeta('property', 'og:image', imageUrl);
  }

  final uri = Uri.base.replace(
    queryParameters: {...Uri.base.queryParameters, 'article': articleId},
    fragment: '',
  );
  var canonical =
      html.document.querySelector('link[rel="canonical"]') as html.LinkElement?;
  if (canonical == null) {
    canonical = html.LinkElement()..rel = 'canonical';
    html.document.head?.append(canonical);
  }
  canonical.href = uri.toString();
  html.window.history.replaceState(null, '', uri.toString());
}

void restoreSiteMetadata() {
  html.document.title = _siteTitle;
  _setMeta('name', 'description', _siteDescription);
  _setMeta('property', 'og:type', 'website');
  _setMeta('property', 'og:title', _siteTitle);
  _setMeta('property', 'og:description', _siteDescription);
  final current = Uri.base;
  final query = Map<String, String>.from(current.queryParameters)
    ..remove('article');
  final uri = current.replace(queryParameters: query, fragment: '');
  html.document.querySelector('link[rel="canonical"]')?.remove();
  html.window.history.replaceState(null, '', uri.toString());
}

void _setMeta(String key, String value, String content) {
  var element =
      html.document.querySelector('meta[$key="$value"]') as html.MetaElement?;
  if (element == null) {
    element = html.MetaElement()..attributes[key] = value;
    html.document.head?.append(element);
  }
  element.content = content;
}
