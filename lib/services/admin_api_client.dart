import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String _defaultApiBaseUrl() {
  const configured = String.fromEnvironment('API_BASE_URL');
  if (configured.isNotEmpty) return configured;
  return defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8787'
      : 'http://localhost:8787';
}

class AdminApiClient {
  AdminApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultApiBaseUrl();
  final String baseUrl;
  String? accessToken;

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (accessToken != null) 'authorization': 'Bearer $accessToken',
  };

  Future<String> login(String email, String password) async {
    late final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/auth/login'),
            headers: _headers,
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw ApiException('Koneksi ke server timeout: $baseUrl');
    } on http.ClientException catch (exception) {
      throw ApiException(
        'Tidak dapat terhubung ke server: ${exception.message}',
      );
    }
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Login gagal.');
    }
    return body['challengeToken'] as String;
  }

  Future<String> verify(String challengeToken, String code) async {
    late final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/auth/verify'),
            headers: _headers,
            body: jsonEncode({'challengeToken': challengeToken, 'code': code}),
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw ApiException('Koneksi ke server timeout: $baseUrl');
    } on http.ClientException catch (exception) {
      throw ApiException(
        'Tidak dapat terhubung ke server: ${exception.message}',
      );
    }
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Verifikasi gagal.');
    }
    accessToken = body['accessToken'] as String;
    return body['role'] as String;
  }

  Future<void> registerAdmin({
    required String email,
    required String password,
    String role = 'Author',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/auth/register'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password, 'role': role}),
    );
    final body = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(
        body['error']?.toString() ?? 'Registrasi admin gagal.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> articles({bool? premium}) async {
    final query = premium == null ? '' : '?premium=$premium';
    final response = await http.get(
      Uri.parse('$baseUrl/api/articles$query'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Artikel gagal dimuat.');
    }
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> adminArticles() async {
    late final http.Response response;
    try {
      response = await http
          .get(Uri.parse('$baseUrl/api/admin/articles'), headers: _headers)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException('Koneksi ke server timeout: $baseUrl');
    } on http.ClientException catch (exception) {
      throw ApiException(
        'Tidak dapat terhubung ke server: ${exception.message}',
      );
    }
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Artikel gagal dimuat.');
    }
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> categories() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/categories'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Kategori gagal dimuat.');
    }
    final items = body['items'] ?? body['data'];
    return (items as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> adminCategories() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/categories'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Kategori gagal dimuat.');
    }
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> createCategory(String name, {String? slug}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/categories'),
      headers: _headers,
      body: jsonEncode({'name': name, 'slug': ?slug}),
    );
    final body = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(body['error']?.toString() ?? 'Kategori gagal dibuat.');
    }
  }

  Future<void> deleteCategory(String slug) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/admin/categories/$slug'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Kategori gagal dihapus.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> subscriptionPlans() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/subscription-plans'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Paket gagal dimuat.');
    }
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> payments() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/payments'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Pembayaran gagal dimuat.',
      );
    }
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> confirmPayment(String invoiceId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/payments/$invoiceId/confirm'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Pembayaran gagal dikonfirmasi.',
      );
    }
  }

  Future<Map<String, dynamic>> account() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/account'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Akun gagal dimuat.');
    }
    return body;
  }

  Future<void> updateAccountEmail({
    required String email,
    required String currentPassword,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/admin/account'),
      headers: _headers,
      body: jsonEncode({'email': email, 'currentPassword': currentPassword}),
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Email gagal diubah.');
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/account/password'),
      headers: _headers,
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Kata sandi gagal diubah.',
      );
    }
  }

  Future<Map<String, dynamic>> notifications() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/notifications'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Notifikasi gagal dimuat.',
      );
    }
    return body;
  }

  Future<void> markNotificationsRead() async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/admin/notifications/read-all'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Notifikasi gagal diperbarui.',
      );
    }
  }

  Future<Map<String, dynamic>> dashboard() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/dashboard'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Dashboard gagal dimuat.',
      );
    }
    return body;
  }

  Future<List<Map<String, dynamic>>> customers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/customers'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Data pelanggan gagal dimuat.',
      );
    }
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> customer(String email) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/customers/${Uri.encodeComponent(email)}'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Detail pelanggan gagal dimuat.',
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> createCustomer({
    required String email,
    required String password,
    required bool subscriber,
    required bool emailVerified,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/customers'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'subscriber': subscriber,
        'emailVerified': emailVerified,
      }),
    );
    final body = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(
        body['error']?.toString() ?? 'Pelanggan gagal ditambahkan.',
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> updateCustomer({
    required String email,
    String? password,
    required bool subscriber,
    required bool emailVerified,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/admin/customers/${Uri.encodeComponent(email)}'),
      headers: _headers,
      body: jsonEncode({
        if (password != null && password.isNotEmpty) 'password': password,
        'subscriber': subscriber,
        'emailVerified': emailVerified,
      }),
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Pelanggan gagal diperbarui.',
      );
    }
    return body;
  }

  Future<void> deleteCustomer(String email) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/admin/customers/${Uri.encodeComponent(email)}'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Pelanggan gagal dihapus.',
      );
    }
  }

  Future<Map<String, dynamic>> createArticle({
    required String title,
    required String category,
    required String excerpt,
    required String body,
    required bool premium,
    String imageUrl = '',
    String blurredImageUrl = '',
    String imageAltText = '',
    String slug = '',
    String seoTitle = '',
    String seoDescription = '',
    Map<String, String> socialLinks = const {},
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/articles'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'category': category,
        'excerpt': excerpt,
        'body': body,
        'isPremium': premium,
        'mainImageUrl': imageUrl,
        'mainImageBlurUrl': blurredImageUrl,
        'mainImageAltText': imageAltText,
        'slug': slug,
        'seoTitle': seoTitle,
        'seoDescription': seoDescription,
        'socialLinks': socialLinks,
      }),
    );
    final result = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(
        result['error']?.toString() ?? 'Artikel gagal disimpan.',
      );
    }
    return result;
  }

  Future<void> publishArticle(String id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/articles/$id/publish'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw ApiException(
        _decode(response)['error']?.toString() ?? 'Artikel gagal dipublish.',
      );
    }
  }

  Future<void> submitArticleForReview(String id) =>
      _articleWorkflowAction(id, 'submit-review');

  Future<void> approveArticle(String id) =>
      _articleWorkflowAction(id, 'approve');

  Future<void> rejectArticle(String id, {required String note}) =>
      _articleWorkflowAction(id, 'reject', body: {'note': note});

  Future<void> scheduleArticle(String id, DateTime scheduledAt) =>
      _articleWorkflowAction(
        id,
        'schedule',
        body: {'scheduledAt': scheduledAt.toUtc().toIso8601String()},
      );

  Future<void> archiveArticle(String id) =>
      _articleWorkflowAction(id, 'archive');

  Future<void> _articleWorkflowAction(
    String id,
    String action, {
    Map<String, Object?> body = const {},
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/articles/$id/$action'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final result = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        result['error']?.toString() ?? 'Workflow artikel gagal diperbarui.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> articleRevisions(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/articles/$id/revisions'),
      headers: _headers,
    );
    final result = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        result['error']?.toString() ?? 'Riwayat artikel gagal dimuat.',
      );
    }
    return (result['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> updateArticle(
    String id, {
    required String title,
    required String category,
    required String excerpt,
    required String body,
    required bool premium,
    String imageUrl = '',
    String blurredImageUrl = '',
    String imageAltText = '',
    String slug = '',
    String seoTitle = '',
    String seoDescription = '',
    Map<String, String> socialLinks = const {},
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/admin/articles/$id'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'category': category,
        'excerpt': excerpt,
        'body': body,
        'isPremium': premium,
        'mainImageUrl': imageUrl,
        'mainImageBlurUrl': blurredImageUrl,
        'mainImageAltText': imageAltText,
        'slug': slug,
        'seoTitle': seoTitle,
        'seoDescription': seoDescription,
        'socialLinks': socialLinks,
      }),
    );
    final result = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        result['error']?.toString() ?? 'Artikel gagal diubah.',
      );
    }
    return result;
  }

  Future<void> deleteArticle(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/admin/articles/$id'),
      headers: _headers,
    );
    final result = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        result['error']?.toString() ?? 'Artikel gagal dihapus.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> adminEpapers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/epapers'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'E-paper gagal dimuat.');
    }
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createEpaper({
    required String title,
    required String edition,
    required String date,
    required int totalPages,
    required bool downloadAllowed,
    String? privateFileName,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/epapers'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'edition': edition,
        'date': date,
        'totalPages': totalPages,
        'downloadAllowed': downloadAllowed,
        'privateFileName': ?privateFileName,
      }),
    );
    final body = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(body['error']?.toString() ?? 'E-paper gagal dibuat.');
    }
    return body;
  }

  Future<void> updateEpaper(
    String id, {
    required String title,
    required String edition,
    required String date,
    required int totalPages,
    required bool downloadAllowed,
    String? privateFileName,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/admin/epapers/$id'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'edition': edition,
        'date': date,
        'totalPages': totalPages,
        'downloadAllowed': downloadAllowed,
        'privateFileName': ?privateFileName,
      }),
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'E-paper gagal diubah.');
    }
  }

  Future<void> deleteEpaper(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/admin/epapers/$id'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'E-paper gagal dihapus.');
    }
  }

  Future<void> publishEpaper(String id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/epapers/$id/publish'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'E-paper gagal diterbitkan.',
      );
    }
  }

  Future<void> updatePrice(String planId, int price) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/admin/subscription-plans/$planId'),
      headers: _headers,
      body: jsonEncode({'price': price}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        _decode(response)['error']?.toString() ?? 'Harga gagal disimpan.',
      );
    }
  }

  Future<Map<String, dynamic>> createSubscriptionPlan({
    required String id,
    required String name,
    required int durationDays,
    required int price,
    required List<String> benefits,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/subscription-plans'),
      headers: _headers,
      body: jsonEncode({
        'id': id,
        'name': name,
        'durationDays': durationDays,
        'price': price,
        'benefits': benefits,
      }),
    );
    final body = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(
        body['error']?.toString() ?? 'Paket gagal ditambahkan.',
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> updateSubscriptionPlan({
    required String id,
    required String name,
    required int durationDays,
    required int price,
    required List<String> benefits,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/admin/subscription-plans/$id'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'durationDays': durationDays,
        'price': price,
        'benefits': benefits,
      }),
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        body['error']?.toString() ?? 'Paket gagal diperbarui.',
      );
    }
    return body;
  }

  Future<void> deleteSubscriptionPlan(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/admin/subscription-plans/$id'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Paket gagal dihapus.');
    }
  }

  Future<Map<String, dynamic>> siteSettings() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/site-settings'),
      headers: _headers,
    );
    final result = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        result['error']?.toString() ?? 'Pengaturan gagal dimuat.',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> saveSiteSettings(
    Map<String, dynamic> settings,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/admin/site-settings'),
      headers: _headers,
      body: jsonEncode(settings),
    );
    final result = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(
        result['error']?.toString() ?? 'Pengaturan gagal disimpan.',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> uploadMedia({
    required Uint8List bytes,
    required String fileName,
    required String kind,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/media'),
      headers: _headers,
      body: jsonEncode({
        'name': fileName,
        'kind': kind,
        'data': base64Encode(bytes),
      }),
    );
    final result = _decode(response);
    if (response.statusCode != 201) {
      throw ApiException(result['error']?.toString() ?? 'Upload gagal.');
    }
    return result;
  }

  Future<void> deleteMedia(String fileName) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/admin/media/$fileName'),
      headers: _headers,
    );
    final result = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(result['error']?.toString() ?? 'Media gagal dihapus.');
    }
  }

  Map<String, dynamic> _decode(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
