import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription_plan_model.dart';
import '../models/article_model.dart';
import '../models/epaper_model.dart';

String _readerDefaultApiBaseUrl() {
  const configured = String.fromEnvironment('API_BASE_URL');
  if (configured.isNotEmpty) return configured;
  return defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8787'
      : 'http://localhost:8787';
}

class ReaderApiClient {
  ReaderApiClient({String? baseUrl})
    : baseUrl = baseUrl ?? _readerDefaultApiBaseUrl();

  final String baseUrl;
  String? accessToken;
  String? currentUserEmail;
  String? currentUserRole;
  String? _pendingLoginEmail;
  static const _timeout = Duration(seconds: 8);
  static const _savedTokenKey = 'readerAccessToken';
  static const _savedEmailKey = 'readerEmail';
  static const _savedRoleKey = 'readerRole';

  Future<void> restoreSavedSession() async {
    final preferences = await SharedPreferences.getInstance();
    accessToken = preferences.getString(_savedTokenKey);
    currentUserEmail = preferences.getString(_savedEmailKey);
    currentUserRole = preferences.getString(_savedRoleKey);
  }

  String get accountDisplayName {
    final email = currentUserEmail?.trim() ?? '';
    final localPart = email.split('@').first;
    if (localPart.isEmpty) return 'Akun Pembaca';
    return localPart
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String resolveMediaUrl(String? value) {
    final mediaPath = value?.trim() ?? '';
    if (mediaPath.isEmpty) return '';
    final uri = Uri.tryParse(mediaPath);
    if (uri != null && uri.hasScheme) return mediaPath;
    return Uri.parse(baseUrl).resolve(mediaPath).toString();
  }

  String? _resolveOptionalMedia(Object? value) {
    final path = value?.toString().trim() ?? '';
    return path.isEmpty ? null : resolveMediaUrl(path);
  }

  Future<void> register(String email, String password) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/register'),
          headers: _headers,
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);
    _data(response);
  }

  Future<void> forgotPassword(String email) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/forgot-password'),
          headers: _headers,
          body: jsonEncode({'email': email}),
        )
        .timeout(_timeout);
    _data(response);
  }

  Future<String> login(String email, String password) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: _headers,
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ReaderApiException(body['error']?.toString() ?? 'Login gagal.');
    }
    _pendingLoginEmail = email.trim();
    return body['challengeToken'] as String;
  }

  Future<String> verify(
    String challengeToken,
    String code, {
    bool rememberMe = false,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/verify'),
          headers: _headers,
          body: jsonEncode({'challengeToken': challengeToken, 'code': code}),
        )
        .timeout(_timeout);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ReaderApiException(
        body['error']?.toString() ?? 'Verifikasi gagal.',
      );
    }
    accessToken = body['accessToken'] as String;
    currentUserEmail = _pendingLoginEmail;
    currentUserRole = body['role']?.toString();
    _pendingLoginEmail = null;
    final preferences = await SharedPreferences.getInstance();
    if (rememberMe) {
      await preferences.setString(_savedTokenKey, accessToken!);
      await preferences.setString(_savedEmailKey, currentUserEmail ?? '');
      await preferences.setString(_savedRoleKey, currentUserRole ?? '');
    } else {
      await preferences.remove(_savedTokenKey);
      await preferences.remove(_savedEmailKey);
      await preferences.remove(_savedRoleKey);
    }
    return body['role'] as String;
  }

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (accessToken != null) 'authorization': 'Bearer $accessToken',
  };

  Future<Map<String, dynamic>> getSiteSettings() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/v1/site-settings'), headers: _headers)
        .timeout(_timeout);
    return Map<String, dynamic>.from(_data(response) as Map);
  }

  Future<List<SubscriptionPlan>> getSubscriptionPlans() async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/v1/subscription/packages'),
          headers: _headers,
        )
        .timeout(_timeout);
    final data = _data(response);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(
          (item) => SubscriptionPlan(
            id: item['id'].toString(),
            name: item['name'].toString(),
            durationDays: (item['durationDays'] as num).toInt(),
            price: (item['price'] as num).toInt(),
            benefits: (item['benefits'] as List? ?? const [])
                .map((benefit) => benefit.toString())
                .toList(),
          ),
        )
        .toList();
  }

  Future<List<Article>> getArticles() async {
    final data = _data(
      await http
          .get(Uri.parse('$baseUrl/api/v1/articles'), headers: _headers)
          .timeout(_timeout),
    );
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(_articleFromJson)
        .toList();
  }

  Future<List<Article>> searchArticles(String query) async {
    final data = _data(
      await http
          .get(
            Uri.parse(
              '$baseUrl/api/v1/search?q=${Uri.encodeQueryComponent(query)}',
            ),
            headers: _headers,
          )
          .timeout(_timeout),
    );
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(_articleFromJson)
        .toList();
  }

  Future<List<EpaperIssue>> getEpaperIssues() async {
    final data = _data(
      await http
          .get(Uri.parse('$baseUrl/api/v1/epapers'), headers: _headers)
          .timeout(_timeout),
    );
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(_epaperFromJson)
        .toList();
  }

  Future<EpaperIssue?> getEpaperById(String id) async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/v1/epapers/$id'), headers: _headers)
        .timeout(_timeout);
    if (response.statusCode == 404) return null;
    return _epaperFromJson(_data(response) as Map<String, dynamic>);
  }

  Article _articleFromJson(Map<String, dynamic> item) => Article(
    id: item['id'].toString(),
    title: item['title'].toString(),
    category: item['category'].toString(),
    isPremium: item['isPremium'] == true,
    body: item['body']?.toString() ?? '',
    excerpt:
        item['excerpt']?.toString() ?? item['teaserContent']?.toString() ?? '',
    imageUrl: resolveMediaUrl(
      item['isLocked'] == true
          ? item['mainImageBlurUrl']?.toString()
          : item['mainImageUrl']?.toString(),
    ),
    imageAltText: item['mainImageAltText']?.toString(),
    author: item['author']?.toString(),
    publishedAt: item['publishedAt']?.toString(),
    updatedAt: item['updatedAt']?.toString(),
    slug: item['slug']?.toString(),
    seoTitle: item['seoTitle']?.toString(),
    seoDescription: item['seoDescription']?.toString(),
    socialLinks: item['socialLinks'] is Map
        ? (item['socialLinks'] as Map).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : const {},
  );

  EpaperIssue _epaperFromJson(Map<String, dynamic> item) {
    final pages = (item['pages'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (page) => EpaperPage(
            pageNumber: (page['pageNumber'] as num).toInt(),
            label: page['label']?.toString() ?? '',
            accentColor: (page['accentColor'] as num?)?.toInt() ?? 0xffb51f2a,
            image: _resolveOptionalMedia(page['image']),
            previewImage: _resolveOptionalMedia(page['previewImage']),
            articleIds: (page['articleIds'] as List? ?? const [])
                .map((id) => id.toString())
                .toList(),
          ),
        )
        .toList();
    final articles = (item['articles'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (article) => EpaperArticle(
            id: article['id'].toString(),
            title: article['title'].toString(),
            category: article['category'].toString(),
            pageNumber: (article['pageNumber'] as num).toInt(),
            isPremium: article['isPremium'] == true,
            thumbnail: _resolveOptionalMedia(article['thumbnail']),
            pageImage: _resolveOptionalMedia(article['pageImage']),
            excerpt: article['excerpt']?.toString() ?? '',
            socialLinks: article['socialLinks'] is Map
                ? (article['socialLinks'] as Map).map(
                    (key, value) => MapEntry(key.toString(), value.toString()),
                  )
                : const {},
            isLocked: article['isLocked'] is bool
                ? article['isLocked'] as bool
                : null,
            content: article['content']?.toString() ?? '',
          ),
        )
        .toList();
    return EpaperIssue(
      id: item['id'].toString(),
      title: item['title'].toString(),
      edition: item['edition']?.toString() ?? '',
      date: item['date']?.toString() ?? '',
      totalPages: (item['totalPages'] as num?)?.toInt() ?? pages.length,
      coverImage: _resolveOptionalMedia(item['coverImage']),
      downloadAvailable: item['downloadAvailable'] == true,
      isSamplePreview: item['isSamplePreview'] == true,
      pages: pages,
      articles: articles,
    );
  }

  Future<Map<String, dynamic>> subscriptionStatus() async =>
      (_data(
            await http
                .get(
                  Uri.parse('$baseUrl/api/v1/subscription/status'),
                  headers: _headers,
                )
                .timeout(_timeout),
          )
          as Map<String, dynamic>);

  Future<Map<String, dynamic>> requestEpaperDownload(String issueId) async =>
      (_data(
            await http
                .post(
                  Uri.parse('$baseUrl/api/v1/epapers/$issueId/download'),
                  headers: _headers,
                )
                .timeout(_timeout),
          )
          as Map<String, dynamic>);

  Future<Uint8List> downloadEpaperPdf(String signedUrl) async {
    final response = await http.get(Uri.parse(signedUrl)).timeout(_timeout);
    if (response.statusCode != 200) {
      throw ReaderApiException('PDF e-paper gagal diunduh.');
    }
    if (response.bodyBytes.length < 5 ||
        response.bodyBytes[0] != 0x25 ||
        response.bodyBytes[1] != 0x50 ||
        response.bodyBytes[2] != 0x44 ||
        response.bodyBytes[3] != 0x46 ||
        response.bodyBytes[4] != 0x2d) {
      throw const ReaderApiException('File yang diterima bukan PDF valid.');
    }
    return response.bodyBytes;
  }

  Future<void> saveItem({
    required String itemType,
    required String itemId,
  }) async {
    _data(
      await http
          .post(
            Uri.parse('$baseUrl/api/v1/saved-items'),
            headers: _headers,
            body: jsonEncode({'itemType': itemType, 'itemId': itemId}),
          )
          .timeout(_timeout),
    );
  }

  Future<void> removeSavedItem({
    required String itemType,
    required String itemId,
  }) async {
    _data(
      await http
          .delete(
            Uri.parse(
              '$baseUrl/api/v1/saved-items/${Uri.encodeComponent(itemType)}/${Uri.encodeComponent(itemId)}',
            ),
            headers: _headers,
          )
          .timeout(_timeout),
    );
  }

  Future<List<Map<String, dynamic>>> getSavedItems() async {
    final data = _data(
      await http
          .get(Uri.parse('$baseUrl/api/v1/saved-items'), headers: _headers)
          .timeout(_timeout),
    );
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getInvoices() async {
    final data = _data(
      await http
          .get(
            Uri.parse('$baseUrl/api/v1/subscription/invoices'),
            headers: _headers,
          )
          .timeout(_timeout),
    );
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> checkout(
    String packageId, {
    required String paymentMethod,
  }) async {
    return (_data(
          await http
              .post(
                Uri.parse('$baseUrl/api/v1/subscription/checkout'),
                headers: _headers,
                body: jsonEncode({
                  'packageId': packageId,
                  'paymentMethod': paymentMethod,
                }),
              )
              .timeout(_timeout),
        )
        as Map<String, dynamic>);
  }

  dynamic _data(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReaderApiException(
        body['message']?.toString() ??
            body['error']?.toString() ??
            'Permintaan gagal.',
      );
    }
    return body['data'];
  }
}

class ReaderApiException implements Exception {
  const ReaderApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
