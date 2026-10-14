import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as crypto_lib;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'mysql_store.dart';

int get _port {
  final configured = Platform.environment['API_PORT']?.trim();
  if (configured == null || configured.isEmpty) return 8787;
  final port = int.tryParse(configured);
  if (port == null || port < 1 || port > 65535) {
    throw StateError('API_PORT harus berupa nomor port valid (1-65535).');
  }
  return port;
}

const _storePath = 'backend/data/store.json';
const _publicMediaDirectory = 'backend/data/uploads/public';
const _privateMediaDirectory = 'backend/data/uploads/private';
const _passwordHashIterations = 210000;
final _passwordHasher = crypto_lib.Pbkdf2(
  macAlgorithm: crypto_lib.Hmac.sha256(),
  iterations: _passwordHashIterations,
  bits: 256,
);
final _authAttempts = <String, _AuthAttemptWindow>{};
final _knownWeakPasswordHash = crypto.sha256
    .convert(utf8.encode('ubah-password-development'))
    .toString();
const _defaultSiteSettings = <String, dynamic>{
  'brandName': 'MAGELANG EKSPRES',
  'tagline': 'Akurat, Terpercaya, dan Menginspirasi',
  'logoUrl': '',
  'heroLabel': 'HEADLINE',
  'heroTitle': '',
  'heroExcerpt': '',
  'heroImageUrl': '',
  'hotTopics': ['Pilkada Magelang', 'Infrastruktur', 'Lingkungan', 'Ekonomi'],
  'epaperTitle': 'E-Paper Magelang Ekspres',
  'epaperCoverImageUrl': '',
  'subscriptionTitle': 'Baca berita lengkap tanpa batas',
  'subscriptionDescription':
      'Nikmati akses artikel premium, e-paper harian, dan arsip edisi.',
  'paymentMethods': [
    {
      'id': 'bank-transfer',
      'name': 'Transfer Bank',
      'instructions': '',
      'enabled': false,
    },
    {'id': 'qris', 'name': 'QRIS', 'instructions': '', 'enabled': false},
  ],
};

Map<String, dynamic> _siteSettings(Store store) {
  final configured = Platform.environment['MIDTRANS_SERVER_KEY']?.trim() ?? '';
  return {
    ..._defaultSiteSettings,
    if (store.data['siteSettings'] is Map)
      ...Map<String, dynamic>.from(store.data['siteSettings'] as Map),
    'paymentMethods': configured.isEmpty
        ? const <Map<String, dynamic>>[]
        : const [
            {
              'id': 'midtrans',
              'name': 'Pembayaran online',
              'instructions':
                  'Lanjutkan pembayaran melalui halaman aman Midtrans.',
              'enabled': true,
            },
          ],
  };
}

bool _validArticleSeo(Map<String, dynamic> body) {
  final seoTitle = body['seoTitle'];
  final seoDescription = body['seoDescription'];
  final slug = body['slug'];
  return (seoTitle == null || seoTitle is String && seoTitle.length <= 70) &&
      (seoDescription == null ||
          seoDescription is String && seoDescription.length <= 160) &&
      (slug == null ||
          slug is String &&
              slug.length <= 140 &&
              (slug.trim().isEmpty ||
                  RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)));
}

bool _validSocialLinks(Map<String, dynamic> body) {
  final links = body['socialLinks'];
  if (links == null) return true;
  if (links is! Map || links.length > 8) return false;
  for (final entry in links.entries) {
    final label = entry.key;
    final value = entry.value;
    if (label is! String ||
        label.trim().isEmpty ||
        label.length > 32 ||
        value is! String ||
        value.length > 2048) {
      return false;
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
  }
  return true;
}

String _articleSlug(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

bool _articleSlugTaken(
  List<Map<String, dynamic>> articles,
  String slug, {
  String? exceptId,
}) => articles.any((article) {
  if (article['id'] == exceptId) return false;
  final currentSlug = article['slug']?.toString().trim() ?? '';
  return _articleSlug(
        currentSlug.isEmpty ? article['title']?.toString() ?? '' : currentSlug,
      ) ==
      slug;
});

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String? get _configuredPublicSiteUrl {
  final value = Platform.environment['PUBLIC_SITE_URL']?.trim() ?? '';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return value.replaceFirst(RegExp(r'/+$'), '');
}

Future<void> main() async {
  _validateSecurityConfiguration();
  final store = Platform.environment['DB_DRIVER'] == 'mysql'
      ? await MysqlStore.fromEnvironment()
      : JsonStore(File(Platform.environment['STORE_PATH'] ?? _storePath));
  await store.load();
  await _removeLegacyDemoContent(store);
  await _disableUnsafeSeedAccounts(store);
  await _seedSampleContent(store);
  final sessions = <String, Session>{};
  final adminLoginChallenges = <String, _AdminLoginChallenge>{};
  for (final item in (store.data['authSessions'] as List<dynamic>)) {
    if (item is! Map) continue;
    final tokenHash = item['tokenHash']?.toString() ?? '';
    final expiry = DateTime.tryParse(item['expiresAt']?.toString() ?? '');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(tokenHash) ||
        expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      continue;
    }
    sessions[tokenHash] = Session(
      email: item['email']?.toString() ?? '',
      role: item['role']?.toString() ?? 'Reader',
      verified: true,
      expiresAt: expiry,
      admin: item['admin'] == true,
      subscriber: item['subscriber'] == true,
    );
  }
  final bindHost = Platform.environment['API_BIND_HOST'] ?? '127.0.0.1';
  final server = await HttpServer.bind(InternetAddress(bindHost), _port);
  stdout.writeln('Magelang Express API listening on $bindHost:$_port');
  await for (final request in server) {
    await _handle(request, store, sessions, adminLoginChallenges);
  }
}

void _validateSecurityConfiguration() {
  final isProduction =
      (Platform.environment['APP_ENV'] ?? '').toLowerCase() == 'production';
  final requiredSecrets = <String>['ADMIN_2FA_CODE', 'DOWNLOAD_SIGNING_SECRET'];
  for (final name in requiredSecrets) {
    final value = Platform.environment[name]?.trim() ?? '';
    if (value.isEmpty ||
        value.startsWith('change-this') ||
        value.startsWith('development-') ||
        value.toUpperCase().contains('REPLACE') ||
        value.toUpperCase().contains('GENERATE') ||
        (name == 'ADMIN_2FA_CODE' && (value.length < 6 || value == '123456')) ||
        (name != 'ADMIN_2FA_CODE' && value.length < 32)) {
      throw StateError(
        '$name must be configured with a unique secret before the API starts.',
      );
    }
  }
  if (isProduction) {
    final origins = _allowedOrigins;
    if (origins.isEmpty || origins.any((origin) => !_isHttpsOrigin(origin))) {
      throw StateError(
        'Production requires ALLOWED_ORIGINS with HTTPS origins only.',
      );
    }
    if (Platform.environment['DB_DRIVER'] != 'mysql') {
      throw StateError('Production requires DB_DRIVER=mysql.');
    }
    if (Platform.environment['API_BIND_HOST']?.isNotEmpty != true) {
      throw StateError('Production requires an explicit API_BIND_HOST.');
    }
    if ((Platform.environment['DB_USER'] ?? '').trim().isEmpty ||
        (Platform.environment['DB_USER'] ?? '').trim().toLowerCase() ==
            'root' ||
        (Platform.environment['DB_PASSWORD'] ?? '').length < 20) {
      throw StateError(
        'Production requires a dedicated database user and strong DB_PASSWORD.',
      );
    }
    if ((Platform.environment['MIDTRANS_SERVER_KEY'] ?? '').trim().isEmpty ||
        Platform.environment['MIDTRANS_IS_PRODUCTION'] != 'true') {
      throw StateError(
        'Production requires a production Midtrans server key and MIDTRANS_IS_PRODUCTION=true.',
      );
    }
    if ((Platform.environment['PAYMENT_CALLBACK_SECRET'] ?? '')
        .trim()
        .isNotEmpty) {
      throw StateError(
        'PAYMENT_CALLBACK_SECRET is obsolete; remove it and use verified Midtrans notifications.',
      );
    }
    throw StateError(
      'Production is blocked until per-user email verification, password recovery, and non-shared MFA delivery are configured.',
    );
  }
}

Set<String> get _allowedOrigins =>
    (Platform.environment['ALLOWED_ORIGINS'] ?? '')
        .split(',')
        .map((origin) => origin.trim())
        .where((origin) => origin.isNotEmpty)
        .map((origin) => origin.replaceFirst(RegExp(r'/$'), ''))
        .toSet();

bool _isHttpsOrigin(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      (uri.path.isEmpty || uri.path == '/') &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

bool _originAllowed(String? origin) {
  if (origin == null) return true;
  if (_allowedOrigins.contains(origin)) return true;
  if ((Platform.environment['APP_ENV'] ?? '').toLowerCase() == 'production') {
    return false;
  }
  final uri = Uri.tryParse(origin);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      (uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1');
}

bool _isRateLimited(HttpRequest request) {
  final path = request.uri.path;
  const authPaths = {
    '/api/auth/login',
    '/api/v1/auth/login',
    '/api/auth/verify',
    '/api/v1/auth/verify',
    '/api/admin/auth/login',
    '/api/admin/auth/verify',
    '/api/admin/auth/register',
    '/api/auth/register',
    '/api/v1/auth/register',
    '/api/payment/callback',
    '/api/v1/payment/callback',
    '/api/payment/webhook',
    '/api/v1/payment/webhook',
  };
  if (!authPaths.contains(path)) return false;
  final address =
      request.connectionInfo?.remoteAddress.address ?? 'unknown-client';
  final key = '$address|$path';
  final now = DateTime.now().toUtc();
  final window = _authAttempts.putIfAbsent(key, () => _AuthAttemptWindow(now));
  if (now.difference(window.startedAt) >= const Duration(minutes: 1)) {
    window
      ..startedAt = now
      ..count = 0;
  }
  final limit = path.endsWith('/verify')
      ? 8
      : path.endsWith('/payment/webhook')
      ? 300
      : 20;
  window.count++;
  if (_authAttempts.length > 4096) {
    _authAttempts.removeWhere(
      (_, attempt) =>
          now.difference(attempt.startedAt) > const Duration(minutes: 5),
    );
  }
  return window.count > limit;
}

Future<void> _disableUnsafeSeedAccounts(Store store) async {
  var changed = false;
  for (final key in ['adminUsers', 'users']) {
    final accounts = (store.data[key] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    for (final account in accounts) {
      if (account['password'] != 'ubah-password-development' &&
          account['passwordHash'] != _knownWeakPasswordHash) {
        continue;
      }
      if (key == 'adminUsers') {
        account['status'] = 'disabled';
      } else {
        account
          ..['passwordHash'] = ''
          ..remove('password');
      }
      changed = true;
    }
  }
  if (store is MysqlStore) {
    await store.disableKnownWeakSeedAccounts(
      _knownWeakPasswordHash,
      'ubah-password-development',
    );
  } else if (changed) {
    await store.save();
  }
}

Future<void> _handle(
  HttpRequest request,
  Store store,
  Map<String, Session> sessions,
  Map<String, _AdminLoginChallenge> adminLoginChallenges,
) async {
  request.response.headers
    ..set('content-type', 'application/json; charset=utf-8')
    ..set('x-content-type-options', 'nosniff')
    ..set('x-frame-options', 'DENY')
    ..set('referrer-policy', 'no-referrer')
    ..set('cache-control', 'no-store');
  if ((Platform.environment['APP_ENV'] ?? '').toLowerCase() == 'production') {
    request.response.headers.set(
      'strict-transport-security',
      'max-age=31536000; includeSubDomains',
    );
  }
  final origin = request.headers.value('origin');
  if (origin != null && _originAllowed(origin)) {
    request.response.headers
      ..set('access-control-allow-origin', origin)
      ..set('vary', 'Origin')
      ..set(
        'access-control-allow-headers',
        'Content-Type, Authorization, X-Admin-Bootstrap-Key',
      )
      ..set(
        'access-control-allow-methods',
        'GET, POST, PUT, PATCH, DELETE, OPTIONS',
      );
  }
  if (request.method == 'OPTIONS') {
    request.response.statusCode = origin == null || _originAllowed(origin)
        ? HttpStatus.noContent
        : HttpStatus.forbidden;
    await request.response.close();
    return;
  }
  if (_isRateLimited(request)) {
    request.response
      ..statusCode = HttpStatus.tooManyRequests
      ..headers.set('retry-after', '60')
      ..write(jsonEncode({'error': 'Terlalu banyak permintaan. Coba lagi.'}));
    await request.response.close();
    return;
  }

  try {
    final rawPath = request.uri.path;
    final isV1 = rawPath == '/api/v1' || rawPath.startsWith('/api/v1/');
    final path = isV1 ? rawPath.replaceFirst('/api/v1', '/api') : rawPath;
    await _publishScheduledArticles(store);
    if (request.method == 'GET' && path == '/robots.txt') {
      final siteUrl = _configuredPublicSiteUrl;
      final sitemap = siteUrl == null ? '' : 'Sitemap: $siteUrl/sitemap.xml\n';
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('content-type', 'text/plain; charset=utf-8')
        ..headers.set('cache-control', 'public, max-age=3600')
        ..write('User-agent: *\nDisallow: /admin\n$sitemap');
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && path == '/sitemap.xml') {
      final siteUrl = _configuredPublicSiteUrl;
      if (siteUrl == null) {
        return _send(request, 503, {
          'error': 'PUBLIC_SITE_URL wajib dikonfigurasi untuk sitemap.',
        });
      }

      final articles = (store.data['articles'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((article) => article['status'] == 'published');
      final urls = articles.map((article) {
        final slug = _articleSlug(
          article['slug']?.toString().trim().isNotEmpty == true
              ? article['slug'].toString()
              : article['title']?.toString() ?? '',
        );
        final location = Uri.parse(
          '$siteUrl/',
        ).replace(queryParameters: {'article': slug});
        final updatedAt =
            article['publishedAt']?.toString() ??
            article['updatedAt']?.toString();
        final lastModified = DateTime.tryParse(updatedAt ?? '');
        return '<url><loc>${_xmlEscape(location.toString())}</loc>'
            '${lastModified == null ? '' : '<lastmod>${lastModified.toUtc().toIso8601String()}</lastmod>'}'
            '<changefreq>daily</changefreq></url>';
      }).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set('content-type', 'application/xml; charset=utf-8')
        ..headers.set('cache-control', 'public, max-age=900')
        ..write(
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">$urls</urlset>',
        );
      await request.response.close();
      return;
    }
    if (request.method == 'GET' &&
        path != '/health' &&
        !path.startsWith('/api/admin/') &&
        !path.startsWith('/private/') &&
        !path.startsWith('/media/')) {
      _recordVisit(store, path);
    }
    final privateDownloadMatch = RegExp(
      r'^/private/epapers/([^/]+)/([^/]+)\.pdf$',
    ).firstMatch(path);
    if (request.method == 'GET' && privateDownloadMatch != null) {
      final issueId = privateDownloadMatch.group(1)!;
      final email = Uri.decodeComponent(privateDownloadMatch.group(2)!);
      final expires = int.tryParse(
        request.uri.queryParameters['expires'] ?? '',
      );
      final signature = request.uri.queryParameters['signature'] ?? '';
      final expiresAt = expires == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true);
      if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
        return _send(request, 403, {'error': 'Signed URL sudah kedaluwarsa.'});
      }
      if (!_constantTimeEquals(
        signature,
        _signDownload(issueId, email, expiresAt),
      )) {
        return _send(request, 403, {'error': 'Signed URL tidak valid.'});
      }
      if (!_hasActiveSubscription(store, email)) {
        return _send(request, 403, {'error': 'Langganan aktif diperlukan.'});
      }
      final issue = (store.data['epapers'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == issueId)
          .firstOrNull;
      final pdfName = issue?['privateFileName']?.toString() ?? '';
      final file = _epaperPdfFile(pdfName);
      if (issue == null || pdfName.isEmpty || !await file.exists()) {
        return _send(request, 404, {'error': 'File e-paper tidak ditemukan.'});
      }
      request.response.headers
        ..set('content-type', 'application/pdf')
        ..set('content-disposition', 'attachment; filename="$issueId.pdf"')
        ..set('cache-control', 'private, no-store');
      await request.response.addStream(file.openRead());
      await request.response.close();
      return;
    }
    final privatePageMatch = RegExp(
      r'^/private/epapers/([^/]+)/pages/([0-9]+)/([^/]+)\.jpg$',
    ).firstMatch(path);
    if (request.method == 'GET' && privatePageMatch != null) {
      final issueId = privatePageMatch.group(1)!;
      final pageNumber = int.tryParse(privatePageMatch.group(2)!);
      final email = Uri.decodeComponent(privatePageMatch.group(3)!);
      final expires = int.tryParse(
        request.uri.queryParameters['expires'] ?? '',
      );
      final signature = request.uri.queryParameters['signature'] ?? '';
      final expiresAt = expires == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true);
      if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
        return _send(request, 403, {'error': 'Signed URL sudah kedaluwarsa.'});
      }
      if (pageNumber == null ||
          !_constantTimeEquals(
            signature,
            _signPage(issueId, pageNumber, email, expiresAt),
          )) {
        return _send(request, 403, {'error': 'Signed URL tidak valid.'});
      }
      if (!_hasActiveSubscription(store, email)) {
        return _send(request, 403, {'error': 'Langganan aktif diperlukan.'});
      }
      final issue = (store.data['epapers'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == issueId)
          .firstOrNull;
      if (issue == null ||
          !_isSampleIssueId(issueId) ||
          pageNumber < 1 ||
          pageNumber > 8) {
        return _send(request, 404, {
          'error': 'Halaman e-paper tidak ditemukan.',
        });
      }
      final file = File(
        '$_privateMediaDirectory/$issueId-p${pageNumber.toString().padLeft(2, '0')}.jpg',
      );
      if (!await file.exists()) {
        return _send(request, 404, {
          'error': 'Halaman e-paper tidak ditemukan.',
        });
      }
      request.response.headers
        ..set('content-type', 'image/jpeg')
        ..set('cache-control', 'private, max-age=600')
        ..set('cross-origin-resource-policy', 'cross-origin');
      await request.response.addStream(file.openRead());
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && path == '/health') {
      final health = {
        'ok': true,
        'service': 'magelang-express-api',
        'storage': store is MysqlStore ? 'mysql' : 'json-file',
      };
      return isV1
          ? _sendV1(request, 200, 'OK', health)
          : _send(request, 200, health);
    }
    final publicMediaMatch = RegExp(
      r'^/media/(media-[A-Za-z0-9_-]+\.(?:jpg|jpeg|png|webp))$',
    ).firstMatch(path);
    if (request.method == 'GET' && publicMediaMatch != null) {
      final file = File('$_publicMediaDirectory/${publicMediaMatch.group(1)}');
      if (!await file.exists()) {
        return _send(request, 404, {'error': 'Media tidak ditemukan.'});
      }
      final extension = publicMediaMatch.group(1)!.split('.').last;
      request.response.headers
        ..set('content-type', _imageContentType(extension))
        ..set('cache-control', 'public, max-age=86400')
        ..set('access-control-allow-origin', '*')
        ..set('cross-origin-resource-policy', 'cross-origin');
      await request.response.addStream(file.openRead());
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && path == '/api/site-settings') {
      return isV1
          ? _sendV1(request, 200, 'OK', _siteSettings(store))
          : _send(request, 200, _siteSettings(store));
    }
    if (request.method == 'POST' && path == '/api/admin/auth/register') {
      final currentSession = _authorized(request, sessions);
      final existingAdmins = (store.data['adminUsers'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final bootstrapToken =
          Platform.environment['ADMIN_BOOTSTRAP_TOKEN']?.trim() ?? '';
      final isBootstrap =
          existingAdmins.isEmpty &&
          bootstrapToken.length >= 32 &&
          !bootstrapToken.toUpperCase().contains('REPLACE') &&
          !bootstrapToken.toUpperCase().contains('GENERATE') &&
          _constantTimeEquals(
            request.headers.value('x-admin-bootstrap-key') ?? '',
            bootstrapToken,
          );
      if (!isBootstrap &&
          (currentSession == null ||
              !currentSession.admin ||
              currentSession.role != 'Super Admin')) {
        return _send(request, 403, {
          'error':
              'Hanya Super Admin atau bootstrap token sekali pakai yang dapat membuat akun admin.',
        });
      }
      final body = await _body(request);
      final email = _required(body, 'email').toLowerCase();
      final password = _required(body, 'password');
      final requestedRole = body['role']?.toString() ?? 'Author';
      final role = switch (requestedRole) {
        'Super Admin' => 'Super Admin',
        'Admin' || 'Editor' => 'Editor',
        _ => 'Author',
      };
      if (role == 'Super Admin' &&
          !isBootstrap &&
          currentSession?.role != 'Super Admin') {
        return _send(request, 403, {
          'error':
              'Hanya Super Admin yang dapat membuat akun Super Admin baru.',
        });
      }
      if (password.length < 8) {
        return _send(request, 422, {'error': 'Kata sandi minimal 8 karakter.'});
      }
      if (existingAdmins.any((item) => item['email'] == email)) {
        return _send(request, 422, {'error': 'Email admin sudah terdaftar.'});
      }
      final admin = {
        'email': email,
        'passwordHash': await _hashPassword(password),
        'role': role,
        'status': 'active',
      };
      existingAdmins.add(admin);
      _audit(
        store,
        currentSession ??
            const Session(
              email: 'bootstrap',
              role: 'Super Admin',
              verified: true,
            ),
        isBootstrap ? 'admin.bootstrapped' : 'admin.registered',
        email,
      );
      await store.save();
      return _send(request, 201, {'email': email, 'role': role});
    }
    if (request.method == 'POST' && path == '/api/admin/auth/login') {
      final body = await _body(request);
      final email = body['email']?.toString().trim().toLowerCase() ?? '';
      final password = body['password']?.toString() ?? '';
      final admins = (store.data['adminUsers'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      Map<String, dynamic>? admin;
      for (final item in admins) {
        final previousHash = item['passwordHash'];
        if (item['email'] == email &&
            item['status'] != 'disabled' &&
            await _verifyAndUpgradePassword(item, password)) {
          admin = item;
          if (item['passwordHash'] != previousHash) {
            await store.persistPasswordHash(
              email,
              item['passwordHash'].toString(),
              admin: true,
            );
          }
          break;
        }
      }
      if (admin == null) {
        return _send(request, 401, {
          'error': 'Email atau kata sandi admin salah.',
        });
      }
      final mailConfiguration = _smtpConfiguration();
      if (mailConfiguration == null) {
        return _send(request, HttpStatus.serviceUnavailable, {
          'error':
              'Pengiriman kode OTP email belum dikonfigurasi. Hubungi pengelola server.',
        });
      }
      final challenge = _randomToken();
      final verificationCode = _newAdminVerificationCode();
      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 5));
      try {
        await _sendAdminVerificationEmail(
          mailConfiguration,
          email,
          verificationCode,
        );
      } on MailerException catch (error) {
        stderr.writeln(
          'Admin OTP email delivery failed (${error.runtimeType}).',
        );
        return _send(request, HttpStatus.serviceUnavailable, {
          'error':
              'Email kode OTP gagal dikirim. Periksa konfigurasi email server dan coba lagi.',
        });
      } on IOException catch (error) {
        stderr.writeln(
          'Admin OTP email delivery failed (${error.runtimeType}).',
        );
        return _send(request, HttpStatus.serviceUnavailable, {
          'error':
              'Email kode OTP gagal dikirim. Periksa koneksi email server dan coba lagi.',
        });
      } on TimeoutException {
        stderr.writeln('Admin OTP email delivery timed out.');
        return _send(request, HttpStatus.serviceUnavailable, {
          'error': 'Pengiriman email OTP melewati batas waktu. Coba lagi.',
        });
      }
      final previousChallenges = adminLoginChallenges.keys
          .where((token) => sessions[token]?.email == email)
          .toList();
      for (final token in previousChallenges) {
        adminLoginChallenges.remove(token);
        sessions.remove(token);
      }
      sessions[challenge] = Session(
        email: email,
        role: admin['role']?.toString() ?? 'Author',
        verified: false,
        expiresAt: expiresAt,
        admin: true,
        subscriber: false,
      );
      adminLoginChallenges[challenge] = _AdminLoginChallenge(
        codeHash: _adminVerificationCodeHash(verificationCode),
        expiresAt: expiresAt,
      );
      return _send(request, 200, {
        'challengeToken': challenge,
        'requiresTwoFactor': true,
        'message': 'Kode verifikasi dikirim ke email akun admin.',
      });
    }
    if (request.method == 'POST' && path == '/api/auth/login') {
      final body = await _body(request);
      final email = body['email']?.toString().trim().toLowerCase() ?? '';
      final password = body['password']?.toString() ?? '';
      final users = (store.data['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      Map<String, dynamic>? validUser;
      for (final item in users) {
        final previousHash = item['passwordHash'];
        if (item['email'] == email &&
            await _verifyAndUpgradePassword(item, password)) {
          validUser = item;
          if (item['passwordHash'] != previousHash) {
            await store.persistPasswordHash(
              email,
              item['passwordHash'].toString(),
              admin: false,
            );
          }
          break;
        }
      }
      if (validUser != null && validUser['role'] != 'Reader') {
        return _send(request, 403, {
          'error': 'Gunakan login CMS untuk akun administrator.',
        });
      }
      if (validUser == null) {
        return _send(request, 401, {'error': 'Email atau kata sandi salah.'});
      }
      final challenge = _randomToken();
      sessions[challenge] = Session(
        email: email,
        role: validUser['role'] as String,
        verified: false,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        subscriber: validUser['subscriber'] == true,
      );
      final response = {
        'challengeToken': challenge,
        'requiresTwoFactor': true,
        'message': 'Kode verifikasi diperlukan.',
      };
      return isV1
          ? _sendV1(request, 200, 'Kode verifikasi diperlukan.', response)
          : _send(request, 200, response);
    }
    if (request.method == 'POST' && path == '/api/auth/register') {
      final body = await _body(request);
      final email = _required(body, 'email').toLowerCase();
      final password = _required(body, 'password');
      if (password.length < 8) {
        return isV1
            ? _sendV1(
                request,
                422,
                'Kata sandi minimal 8 karakter.',
                null,
                errors: ['weak_password'],
              )
            : _send(request, 422, {'error': 'Kata sandi minimal 8 karakter.'});
      }
      final users = (store.data['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (users.any((user) => user['email'] == email)) {
        return isV1
            ? _sendV1(
                request,
                422,
                'Email sudah terdaftar.',
                null,
                errors: ['email_taken'],
              )
            : _send(request, 422, {'error': 'Email sudah terdaftar.'});
      }
      users.add({
        'email': email,
        'passwordHash': await _hashPassword(password),
        'role': 'Reader',
        'subscriber': false,
        'emailVerified': false,
      });
      _notify(
        store,
        type: 'user',
        title: 'Pelanggan baru terdaftar',
        message: '$email membuat akun pembaca dari frontend.',
        actor: email,
        resourceId: email,
      );
      await store.save();
      final response = {'email': email, 'emailVerified': false};
      return isV1
          ? _sendV1(request, 201, 'Registrasi berhasil.', response)
          : _send(request, 201, response);
    }
    if (request.method == 'POST' && path == '/api/auth/forgot-password') {
      const error = {
        'error':
            'Pemulihan kata sandi belum tersedia karena layanan email belum dikonfigurasi.',
      };
      return isV1
          ? _sendV1(
              request,
              HttpStatus.serviceUnavailable,
              error['error']!,
              null,
              errors: ['password_reset_unavailable'],
            )
          : _send(request, HttpStatus.serviceUnavailable, error);
    }
    if (request.method == 'POST' &&
        (path == '/api/auth/verify' || path == '/api/admin/auth/verify')) {
      final body = await _body(request);
      final token = body['challengeToken']?.toString() ?? '';
      final code = body['code']?.toString() ?? '';
      final session = sessions[token];
      final now = DateTime.now().toUtc();
      if (session == null || session.expiresAt?.isAfter(now) != true) {
        sessions.remove(token);
        adminLoginChallenges.remove(token);
        return _send(request, 401, {'error': 'Kode verifikasi tidak valid.'});
      }
      if (session.admin) {
        final challenge = adminLoginChallenges[token];
        if (challenge == null || !challenge.expiresAt.isAfter(now)) {
          sessions.remove(token);
          adminLoginChallenges.remove(token);
          return _send(request, 401, {
            'error': 'Kode verifikasi tidak valid atau sudah kedaluwarsa.',
          });
        }
        if (!_constantTimeEquals(
          _adminVerificationCodeHash(code),
          challenge.codeHash,
        )) {
          challenge.attempts++;
          if (challenge.attempts >= _maxAdminOtpAttempts) {
            sessions.remove(token);
            adminLoginChallenges.remove(token);
          }
          return _send(request, 401, {
            'error': challenge.attempts >= _maxAdminOtpAttempts
                ? 'Batas percobaan tercapai. Silakan masuk kembali.'
                : 'Kode verifikasi tidak valid.',
          });
        }
        adminLoginChallenges.remove(token);
      } else {
        final challenge = adminLoginChallenges[token];
        if (challenge == null || !challenge.expiresAt.isAfter(now)) {
          sessions.remove(token);
          adminLoginChallenges.remove(token);
          return _send(request, 401, {
            'error': 'Kode verifikasi tidak valid atau sudah kedaluwarsa.',
          });
        }
        if (!_constantTimeEquals(
          _adminVerificationCodeHash(code),
          challenge.codeHash,
        )) {
          challenge.attempts++;
          if (challenge.attempts >= _maxAdminOtpAttempts) {
            sessions.remove(token);
            adminLoginChallenges.remove(token);
          }
          return _send(request, 401, {
            'error': challenge.attempts >= _maxAdminOtpAttempts
                ? 'Batas percobaan tercapai. Silakan masuk kembali.'
                : 'Kode verifikasi tidak valid.',
          });
        }
        adminLoginChallenges.remove(token);
      }
      final accessToken = _randomToken();
      final accessSession = Session(
        email: session.email,
        role: session.role,
        verified: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 8)),
        admin: session.admin,
        subscriber: session.subscriber,
      );
      final accessSessionRecord = _sessionRecord(accessToken, accessSession);
      sessions[accessSessionRecord['tokenHash'] as String] = accessSession;
      await store.persistSession(accessSessionRecord);
      sessions.remove(token);
      final response = {
        'accessToken': accessToken,
        'role': session.role,
        'expiresInSeconds': 28800,
      };
      return isV1
          ? _sendV1(request, 200, 'Login berhasil.', response)
          : _send(request, 200, response);
    }

    final session = _authorized(request, sessions);
    final hasActiveSubscription =
        session != null && _hasActiveSubscription(store, session.email);
    if (request.method == 'POST' && path == '/api/auth/logout') {
      final token = (request.headers.value('authorization') ?? '').replaceFirst(
        'Bearer ',
        '',
      );
      if (token.isNotEmpty) {
        final tokenHash = _tokenHash(token);
        sessions.remove(tokenHash);
        await store.revokeSession(tokenHash);
      }
      return isV1
          ? _sendV1(request, 200, 'Logout berhasil.', null)
          : _send(request, 200, {'loggedOut': true});
    }
    if (request.method == 'POST' && path == '/api/auth/refresh') {
      if (session == null) {
        return isV1
            ? _sendV1(
                request,
                401,
                'Token tidak valid.',
                null,
                errors: ['unauthorized'],
              )
            : _send(request, 401, {'error': 'Token tidak valid.'});
      }
      final token = _randomToken();
      final refreshedSession = Session(
        email: session.email,
        role: session.role,
        verified: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 8)),
        admin: session.admin,
        subscriber: session.subscriber,
      );
      final tokenHash = _tokenHash(token);
      sessions[tokenHash] = refreshedSession;
      await store.persistSession(_sessionRecord(token, refreshedSession));
      final oldToken = (request.headers.value('authorization') ?? '').substring(
        7,
      );
      final oldTokenHash = _tokenHash(oldToken);
      sessions.remove(oldTokenHash);
      await store.revokeSession(oldTokenHash);
      return isV1
          ? _sendV1(request, 200, 'Token diperbarui.', {
              'accessToken': token,
              'expiresInSeconds': 28800,
            })
          : _send(request, 200, {
              'accessToken': token,
              'expiresInSeconds': 28800,
            });
    }
    if (request.method == 'GET' && path == '/api/home') {
      final articles = (store.data['articles'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((article) => _publicArticle(article, hasActiveSubscription))
          .toList();
      final home = <String, dynamic>{
        'headline': articles
            .where((article) => article['status'] == 'published')
            .take(1)
            .toList(),
        'latest': articles
            .where((article) => article['status'] == 'published')
            .toList(),
        'categories': store.data['categories'] ?? const <dynamic>[],
        'epapers': (store.data['epapers'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(
              (issue) => _publicEpaper(
                issue,
                hasActiveSubscription: hasActiveSubscription,
                email: session?.email,
                requestUri: request.uri,
              ),
            )
            .toList(),
      };
      return isV1
          ? _sendV1(request, 200, 'OK', home)
          : _send(request, 200, home);
    }
    if (request.method == 'GET' && path == '/api/categories') {
      final categories = store.data['categories'] ?? const <dynamic>[];
      return isV1
          ? _sendV1(request, 200, 'OK', categories)
          : _send(request, 200, {'items': categories});
    }
    if (request.method == 'GET' && path == '/api/search') {
      final query =
          request.uri.queryParameters['q']?.trim().toLowerCase() ?? '';
      final articles = (store.data['articles'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where(
            (article) =>
                article['status'] == 'published' &&
                '${article['title']} ${article['excerpt']}'
                    .toLowerCase()
                    .contains(query),
          )
          .map((article) => _publicArticle(article, hasActiveSubscription))
          .toList();
      return isV1
          ? _sendV1(request, 200, 'OK', articles)
          : _send(request, 200, {'items': articles});
    }
    if (request.method == 'GET' && path == '/api/articles') {
      final premium = request.uri.queryParameters['premium'];
      final articles = (store.data['articles'] as List<dynamic>)
          .where((item) => item['status'] == 'published')
          .toList();
      final filtered =
          (premium == null
                  ? articles
                  : articles
                        .where(
                          (item) => item['isPremium'].toString() == premium,
                        )
                        .toList())
              .cast<Map<String, dynamic>>()
              .map((article) => _publicArticle(article, hasActiveSubscription))
              .toList();
      return isV1
          ? _sendV1(request, 200, 'OK', filtered)
          : _send(request, 200, {'items': filtered});
    }
    final articleMatch = RegExp(r'^/api/articles/([^/]+)$').firstMatch(path);
    if (request.method == 'GET' && articleMatch != null) {
      final slug = articleMatch.group(1) ?? '';
      final article = (store.data['articles'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['slug'] == slug || item['id'] == slug)
          .firstOrNull;
      if (article == null) {
        return isV1
            ? _sendV1(
                request,
                404,
                'Artikel tidak ditemukan.',
                null,
                errors: ['article_not_found'],
              )
            : _send(request, 404, {'error': 'Artikel tidak ditemukan.'});
      }
      final data = _publicArticle(article, hasActiveSubscription);
      return isV1
          ? _sendV1(request, 200, 'OK', data)
          : _send(request, 200, data);
    }
    if (request.method == 'GET' && path == '/api/epapers') {
      final issues = (store.data['epapers'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (issue) => _publicEpaper(
              issue,
              hasActiveSubscription: hasActiveSubscription,
              email: session?.email,
              requestUri: request.uri,
            ),
          )
          .toList();
      final response = {'items': issues};
      return isV1
          ? _sendV1(request, 200, 'OK', response['items'])
          : _send(request, 200, response);
    }
    final epaperMatch = RegExp(r'^/api/epapers/([^/]+)$').firstMatch(path);
    if (request.method == 'GET' && epaperMatch != null) {
      final issueId = epaperMatch.group(1)!;
      final issue = (store.data['epapers'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == issueId)
          .firstOrNull;
      if (issue == null) {
        return isV1
            ? _sendV1(
                request,
                404,
                'E-paper tidak ditemukan.',
                null,
                errors: ['epaper_not_found'],
              )
            : _send(request, 404, {'error': 'E-paper tidak ditemukan.'});
      }
      final response = _publicEpaper(
        issue,
        hasActiveSubscription: hasActiveSubscription,
        email: session?.email,
        requestUri: request.uri,
      );
      return isV1
          ? _sendV1(request, 200, 'OK', response)
          : _send(request, 200, response);
    }
    if (request.method == 'GET' &&
        (path == '/api/subscription-plans' ||
            path == '/api/subscription/packages')) {
      final plans = store.data['subscriptionPlans'];
      return isV1
          ? _sendV1(request, 200, 'OK', plans)
          : _send(request, 200, {'items': plans});
    }
    if (request.method == 'POST' && path == '/api/subscription/checkout') {
      if (session == null) {
        return _send(request, 401, {'error': 'Login diperlukan.'});
      }
      final body = await _body(request);
      final packageId = _required(body, 'packageId');
      final plan = (store.data['subscriptionPlans'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == packageId)
          .firstOrNull;
      if (plan == null) {
        return _send(request, 422, {'error': 'Paket tidak ditemukan.'});
      }
      final paymentMethodId = body['paymentMethod']?.toString() ?? '';
      final paymentMethod = (_siteSettings(store)['paymentMethods'] as List)
          .whereType<Map>()
          .where((method) => method['enabled'] == true)
          .where((method) => method['id'] == paymentMethodId)
          .firstOrNull;
      if (paymentMethod == null || paymentMethodId != 'midtrans') {
        return _send(request, 422, {
          'error': 'Metode pembayaran tidak tersedia.',
        });
      }
      if ((Platform.environment['MIDTRANS_SERVER_KEY']?.trim() ?? '').isEmpty) {
        return _send(request, HttpStatus.serviceUnavailable, {
          'error': 'Pembayaran online belum dikonfigurasi oleh pengelola.',
        });
      }
      final invoiceId =
          'inv-${DateTime.now().millisecondsSinceEpoch}-${_randomToken().substring(0, 8)}';
      final invoice = <String, dynamic>{
        'id': invoiceId,
        'userId': session.email,
        'packageId': packageId,
        'packageName': plan['name'],
        'baseAmount': plan['price'],
        'amount': (plan['price'] as num).toInt(),
        'status': 'pending',
        'paymentMethod': paymentMethodId,
        'paymentMethodName': paymentMethod['name'],
        'paymentInstructions': paymentMethod['instructions'],
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        final payment = await _createMidtransCheckout(invoice);
        invoice
          ..['paymentUrl'] = payment['redirect_url']
          ..['gatewayToken'] = payment['token'];
      } on MidtransException catch (error) {
        stderr.writeln('Midtrans checkout failed: ${error.message}');
        return _send(request, HttpStatus.badGateway, {
          'error': 'Halaman pembayaran gagal dibuat. Silakan coba kembali.',
        });
      }
      (store.data['invoices'] as List<dynamic>).add(invoice);
      _audit(store, session, 'payment.checkout_created', invoice['id']);
      _notify(
        store,
        type: 'payment',
        title: 'Transaksi baru',
        message: '${session.email} membuat checkout ${invoice['id']}.',
        actor: session.email,
        resourceId: invoice['id'].toString(),
      );
      await store.save();
      return isV1
          ? _sendV1(request, 201, 'Checkout dibuat.', invoice)
          : _send(request, 201, invoice);
    }
    if (request.method == 'POST' &&
        (path == '/api/payment/callback' ||
            path == '/api/v1/payment/callback')) {
      return _send(request, HttpStatus.gone, {
        'error':
            'Callback internal dinonaktifkan. Gunakan notifikasi Midtrans.',
      });
    }
    if (request.method == 'POST' &&
        (path == '/api/payment/webhook' || path == '/api/v1/payment/webhook')) {
      final body = await _body(request);
      final orderId = body['order_id']?.toString() ?? '';
      final statusCode = body['status_code']?.toString() ?? '';
      final grossAmount = body['gross_amount']?.toString() ?? '';
      final receivedSignature = body['signature_key']?.toString() ?? '';
      final serverKey =
          Platform.environment['MIDTRANS_SERVER_KEY']?.trim() ?? '';
      if (serverKey.isEmpty) {
        return _send(request, HttpStatus.serviceUnavailable, {
          'error': 'Notifikasi pembayaran belum dikonfigurasi.',
        });
      }
      final expectedSignature = crypto.sha512
          .convert(utf8.encode('$orderId$statusCode$grossAmount$serverKey'))
          .toString();
      if (!_constantTimeEquals(receivedSignature, expectedSignature)) {
        return _send(request, HttpStatus.unauthorized, {
          'error': 'Signature notifikasi Midtrans tidak valid.',
        });
      }
      final invoice = (store.data['invoices'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == orderId)
          .firstOrNull;
      final notifiedAmount = double.tryParse(grossAmount);
      final invoiceAmount = (invoice?['amount'] as num?)?.toDouble();
      if (invoice == null ||
          notifiedAmount == null ||
          invoiceAmount == null ||
          notifiedAmount != invoiceAmount) {
        return _send(request, HttpStatus.unprocessableEntity, {
          'error': 'Invoice atau nominal notifikasi tidak cocok.',
        });
      }
      final transactionStatus =
          body['transaction_status']?.toString().toLowerCase() ?? '';
      final fraudStatus = body['fraud_status']?.toString().toLowerCase() ?? '';
      final status = switch (transactionStatus) {
        'settlement' => 'paid',
        'capture' when fraudStatus == 'accept' => 'paid',
        'deny' || 'cancel' || 'expire' || 'failure' => 'failed',
        'refund' || 'partial_refund' || 'chargeback' => 'refunded',
        'pending' || 'capture' => 'pending',
        _ => '',
      };
      if (status.isEmpty) {
        return _send(request, HttpStatus.unprocessableEntity, {
          'error': 'Status transaksi Midtrans tidak dikenal.',
        });
      }
      final reference = body['transaction_id']?.toString() ?? '';
      if (status == 'paid' && reference.isEmpty) {
        return _send(request, HttpStatus.unprocessableEntity, {
          'error': 'Referensi transaksi Midtrans tidak tersedia.',
        });
      }
      if (invoice['status'] != 'pending') {
        final duplicate =
            invoice['status'] == status &&
            invoice['transactionReference'] == reference;
        return duplicate
            ? _send(request, HttpStatus.ok, {'ok': true, 'idempotent': true})
            : _send(request, HttpStatus.conflict, {
                'error': 'Invoice sudah diproses dengan status berbeda.',
              });
      }
      invoice
        ..['status'] = status
        ..['transactionReference'] = reference
        ..['paidAt'] = status == 'paid'
            ? DateTime.now().toUtc().toIso8601String()
            : null;
      if (status == 'paid') _activateSubscription(store, invoice);
      await store.save();
      return _send(request, HttpStatus.ok, {'ok': true});
    }
    if (request.method == 'GET' && path == '/api/subscription/invoices') {
      if (session == null) {
        return _send(request, 401, {'error': 'Login diperlukan.'});
      }
      final items = (store.data['invoices'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['userId'] == session.email)
          .toList()
          .reversed
          .toList();
      return isV1
          ? _sendV1(request, 200, 'OK', items)
          : _send(request, 200, {'items': items});
    }
    if (request.method == 'GET' && path == '/api/subscription/status') {
      final subscription = session == null
          ? null
          : (store.data['subscriptions'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .where((item) => item['userId'] == session.email)
                .where((item) => item['status'] == 'active')
                .firstOrNull;
      final active = _hasActiveSubscription(store, session?.email);
      final response = {'active': active, 'subscription': subscription};
      return isV1
          ? _sendV1(request, 200, 'OK', response)
          : _send(request, 200, response);
    }
    final downloadMatch = RegExp(
      r'^/api/epapers/([^/]+)/download$',
    ).firstMatch(path);
    if (request.method == 'POST' && downloadMatch != null) {
      if (session == null || !_hasActiveSubscription(store, session.email)) {
        return isV1
            ? _sendV1(
                request,
                403,
                'Langganan aktif diperlukan.',
                null,
                errors: ['subscription_required'],
              )
            : _send(request, 403, {'error': 'Langganan aktif diperlukan.'});
      }
      final issueId = downloadMatch.group(1)!;
      final issue = (store.data['epapers'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == issueId)
          .firstOrNull;
      if (issue == null) {
        return isV1
            ? _sendV1(
                request,
                404,
                'E-paper tidak ditemukan.',
                null,
                errors: ['epaper_not_found'],
              )
            : _send(request, 404, {'error': 'E-paper tidak ditemukan.'});
      }
      final pdfName = issue['privateFileName']?.toString() ?? '';
      if (pdfName.isEmpty || !await _epaperPdfFile(pdfName).exists()) {
        return _send(request, 409, {
          'error': 'PDF edisi belum diunggah oleh redaksi.',
        });
      }
      if (issue['downloadAllowed'] != true && !_isSampleIssueId(issueId)) {
        return _send(request, 403, {
          'error': 'Download e-paper ini tidak diizinkan.',
        });
      }
      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 10));
      final signature = _signDownload(issueId, session.email, expiresAt);
      final signedUrl =
          '${_publicMediaBaseUrl(request)}/private/epapers/$issueId/${Uri.encodeComponent(session.email)}.pdf?expires=${expiresAt.millisecondsSinceEpoch}&signature=$signature';
      (store.data['downloadLogs'] as List<dynamic>).add({
        'userId': session.email,
        'epaperEditionId': issueId,
        'fileUrl': signedUrl,
        'downloadedAt': DateTime.now().toUtc().toIso8601String(),
      });
      _audit(store, session, 'epaper.download_requested', issueId);
      await store.save();
      final response = {
        'url': signedUrl,
        'expiresAt': expiresAt.toIso8601String(),
        'watermark': {
          'email': session.email,
          'downloadedAt': DateTime.now().toUtc().toIso8601String(),
        },
      };
      return isV1
          ? _sendV1(request, 200, 'Download siap.', response)
          : _send(request, 200, response);
    }
    if (request.method == 'POST' && path == '/api/saved-items') {
      if (session == null) {
        return isV1
            ? _sendV1(
                request,
                401,
                'Login diperlukan.',
                null,
                errors: ['unauthorized'],
              )
            : _send(request, 401, {'error': 'Login diperlukan.'});
      }
      final body = await _body(request);
      final itemType = _required(body, 'itemType');
      final itemId = _required(body, 'itemId');
      final savedItems = (store.data['savedItems'] as List<dynamic>);
      final exists = savedItems.any(
        (item) =>
            item['userId'] == session.email &&
            item['itemType'] == itemType &&
            item['itemId'] == itemId,
      );
      if (!exists) {
        savedItems.add({
          'userId': session.email,
          'itemType': itemType,
          'itemId': itemId,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
        await store.save();
      }
      return isV1
          ? _sendV1(request, 201, 'Tersimpan.', {
              'itemType': itemType,
              'itemId': itemId,
            })
          : _send(request, 201, {'itemType': itemType, 'itemId': itemId});
    }
    if (request.method == 'GET' && path == '/api/saved-items') {
      if (session == null) {
        return _send(request, 401, {'error': 'Login diperlukan.'});
      }
      final items = (store.data['savedItems'] as List<dynamic>)
          .where((item) => item['userId'] == session.email)
          .toList();
      return isV1
          ? _sendV1(request, 200, 'OK', items)
          : _send(request, 200, {'items': items});
    }
    final savedItemMatch = RegExp(
      r'^/api/saved-items/([^/]+)/([^/]+)$',
    ).firstMatch(path);
    if (request.method == 'DELETE' && savedItemMatch != null) {
      if (session == null) {
        return _send(request, 401, {'error': 'Login diperlukan.'});
      }
      final itemType = Uri.decodeComponent(savedItemMatch.group(1)!);
      final itemId = Uri.decodeComponent(savedItemMatch.group(2)!);
      final savedItems = (store.data['savedItems'] as List<dynamic>);
      savedItems.removeWhere(
        (item) =>
            item['userId'] == session.email &&
            item['itemType'] == itemType &&
            item['itemId'] == itemId,
      );
      await store.save();
      return isV1
          ? _sendV1(request, 200, 'Dihapus.', null)
          : _send(request, 200, {'deleted': true});
    }
    if (request.method == 'GET' && path == '/api/admin/dashboard') {
      if (session == null || !session.admin) {
        return _send(request, 401, {'error': 'Authorization diperlukan.'});
      }
      return _send(request, 200, _dashboard(store, session));
    }
    if (path.startsWith('/api/admin/') && (session == null || !session.admin)) {
      return _send(request, 401, {'error': 'Authorization diperlukan.'});
    }
    if (path == '/api/admin/account' || path == '/api/admin/account/password') {
      final admins = (store.data['adminUsers'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final current = admins
          .where((item) => item['email'] == session!.email)
          .firstOrNull;
      if (current == null) {
        return _send(request, 404, {'error': 'Akun tidak ditemukan.'});
      }
      if (path == '/api/admin/account' && request.method == 'GET') {
        return _send(request, 200, {
          'email': current['email'],
          'role': current['role'],
          'status': current['status'] ?? 'active',
        });
      }
      if (path == '/api/admin/account' && request.method == 'PATCH') {
        final body = await _body(request);
        final newEmail = _required(body, 'email').toLowerCase();
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(newEmail)) {
          return _send(request, 422, {'error': 'Format email tidak valid.'});
        }
        if (!await _verifyAndUpgradePassword(
          current,
          body['currentPassword']?.toString() ?? '',
        )) {
          return _send(request, 403, {'error': 'Kata sandi saat ini salah.'});
        }
        final oldEmail = current['email'].toString();
        if (newEmail != oldEmail) {
          if (admins.any((item) => item['email'] == newEmail)) {
            return _send(request, 422, {'error': 'Email sudah digunakan.'});
          }
          current['email'] = newEmail;
          for (final article
              in (store.data['articles'] as List<dynamic>)
                  .cast<Map<String, dynamic>>()) {
            if (article['author'] == oldEmail) article['author'] = newEmail;
          }
          for (final entry in sessions.entries.toList()) {
            final old = entry.value;
            if (old.email != oldEmail || !old.admin) continue;
            sessions[entry.key] = Session(
              email: newEmail,
              role: old.role,
              verified: old.verified,
              expiresAt: old.expiresAt,
              admin: old.admin,
              subscriber: old.subscriber,
            );
          }
          _audit(
            store,
            Session(
              email: newEmail,
              role: current['role'].toString(),
              verified: true,
              admin: true,
            ),
            'account.email_changed',
            oldEmail,
          );
          await store.save();
        }
        return _send(request, 200, {
          'email': current['email'],
          'role': current['role'],
        });
      }
      if (path == '/api/admin/account/password' && request.method == 'POST') {
        final body = await _body(request);
        final newPassword = body['newPassword']?.toString() ?? '';
        if (!await _verifyAndUpgradePassword(
          current,
          body['currentPassword']?.toString() ?? '',
        )) {
          return _send(request, 403, {'error': 'Kata sandi saat ini salah.'});
        }
        if (newPassword.length < 8) {
          return _send(request, 422, {
            'error': 'Kata sandi baru minimal 8 karakter.',
          });
        }
        current['passwordHash'] = await _hashPassword(newPassword);
        current.remove('password');
        _audit(store, session!, 'account.password_changed', session.email);
        await store.save();
        return _send(request, 200, {'changed': true});
      }
    }
    if (request.method == 'GET' && path == '/api/admin/customers') {
      final customers = (store.data['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((user) {
            final email = user['email']?.toString() ?? '';
            final name = email
                .split('@')
                .first
                .replaceAll(RegExp(r'[._-]+'), ' ')
                .split(' ')
                .where((part) => part.isNotEmpty)
                .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
                .join(' ');
            return {
              'name': name,
              'email': email,
              'role': user['role']?.toString() ?? 'Reader',
              'status': user['subscriber'] == true ? 'Aktif' : 'Terdaftar',
              'verified': user['emailVerified'] == true,
            };
          })
          .toList();
      return _send(request, 200, {'items': customers});
    }
    final customerMatch = RegExp(
      r'^/api/admin/customers/(.+)$',
    ).firstMatch(path);
    if (customerMatch != null && request.method == 'GET') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat melihat detail pelanggan.',
        });
      }
      final email = Uri.decodeComponent(customerMatch.group(1)!).toLowerCase();
      final user = (store.data['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['email'] == email)
          .firstOrNull;
      if (user == null) {
        return _send(request, 404, {'error': 'Pelanggan tidak ditemukan.'});
      }
      return _send(request, 200, _customerView(user));
    }
    if (path == '/api/admin/customers' && request.method == 'POST') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat menambahkan pelanggan.',
        });
      }
      final body = await _body(request);
      final email = _required(body, 'email').toLowerCase();
      final password = _required(body, 'password');
      if (password.length < 8) {
        return _send(request, 422, {'error': 'Kata sandi minimal 8 karakter.'});
      }
      final users = (store.data['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (users.any((item) => item['email'] == email)) {
        return _send(request, 422, {
          'error': 'Email pelanggan sudah terdaftar.',
        });
      }
      final user = {
        'email': email,
        'passwordHash': await _hashPassword(password),
        'role': 'Reader',
        'subscriber': body['subscriber'] == true,
        'emailVerified': body['emailVerified'] == true,
      };
      users.add(user);
      await store.save();
      return _send(request, 201, _customerView(user));
    }
    if (customerMatch != null && request.method == 'PATCH') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat mengedit pelanggan.',
        });
      }
      final email = Uri.decodeComponent(customerMatch.group(1)!).toLowerCase();
      final users = (store.data['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final user = users.where((item) => item['email'] == email).firstOrNull;
      if (user == null) {
        return _send(request, 404, {'error': 'Pelanggan tidak ditemukan.'});
      }
      final body = await _body(request);
      if (body['password']?.toString().isNotEmpty == true) {
        final password = body['password'].toString();
        if (password.length < 8) {
          return _send(request, 422, {
            'error': 'Kata sandi minimal 8 karakter.',
          });
        }
        user['passwordHash'] = await _hashPassword(password);
      }
      if (body.containsKey('subscriber')) {
        user['subscriber'] = body['subscriber'] == true;
      }
      if (body.containsKey('emailVerified')) {
        user['emailVerified'] = body['emailVerified'] == true;
      }
      await store.save();
      return _send(request, 200, _customerView(user));
    }
    if (customerMatch != null && request.method == 'DELETE') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat menghapus pelanggan.',
        });
      }
      final email = Uri.decodeComponent(customerMatch.group(1)!).toLowerCase();
      final users = (store.data['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final removed = users.where((item) => item['email'] == email).firstOrNull;
      if (removed == null) {
        return _send(request, 404, {'error': 'Pelanggan tidak ditemukan.'});
      }
      users.remove(removed);
      await store.save();
      return _send(request, 200, {'deleted': true});
    }
    if (path == '/api/admin/media' && request.method == 'POST') {
      final body = await _body(request);
      final kind = _required(body, 'kind');
      final originalName = _required(body, 'name');
      if (originalName.length > 180 || kind != 'image' && kind != 'pdf') {
        return _send(request, 422, {
          'error': 'Jenis media atau nama file tidak valid.',
        });
      }
      if (!_canWrite(session!)) {
        return _send(request, 403, {
          'error': 'Role tidak boleh mengunggah media.',
        });
      }
      late final List<int> bytes;
      try {
        bytes = base64Decode(_required(body, 'data'));
      } on FormatException {
        return _send(request, 422, {'error': 'Data file bukan Base64 valid.'});
      }
      final extension = _mediaExtension(kind, bytes);
      final maxBytes = kind == 'pdf' ? 50 * 1024 * 1024 : 5 * 1024 * 1024;
      if (extension == null || bytes.isEmpty || bytes.length > maxBytes) {
        return _send(request, 422, {
          'error': kind == 'pdf'
              ? 'File harus berupa PDF valid maksimal 50 MB.'
              : 'Gambar harus JPG, PNG, atau WebP valid maksimal 5 MB.',
        });
      }
      final mediaName =
          'media-${DateTime.now().millisecondsSinceEpoch}-${_randomToken().substring(0, 8)}.$extension';
      final directory = Directory(
        kind == 'pdf' ? _privateMediaDirectory : _publicMediaDirectory,
      );
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$mediaName',
      ).writeAsBytes(bytes, flush: true);
      _audit(store, session, 'media.uploaded', mediaName);
      await store.save();
      final publicBaseUrl = _publicMediaBaseUrl(request);
      return _send(request, 201, {
        'fileName': mediaName,
        'originalName': originalName,
        'size': bytes.length,
        if (kind == 'image') 'url': '$publicBaseUrl/media/$mediaName',
      });
    }
    final deleteMediaMatch = RegExp(
      r'^/api/admin/media/(media-[A-Za-z0-9_-]+\.(?:jpg|jpeg|png|webp|pdf))$',
    ).firstMatch(path);
    if (request.method == 'DELETE' && deleteMediaMatch != null) {
      final mediaName = deleteMediaMatch.group(1)!;
      final isPrivatePdf = mediaName.endsWith('.pdf');
      if (session!.role != 'Super Admin' &&
          !(isPrivatePdf && _canWrite(session))) {
        return _send(request, 403, {
          'error': isPrivatePdf
              ? 'Role tidak boleh menghapus PDF e-paper.'
              : 'Hanya Super Admin yang dapat menghapus gambar.',
        });
      }
      if (_referencesMedia(store, mediaName)) {
        return _send(request, 409, {
          'error':
              'Media masih digunakan oleh konten. Hapus referensinya dahulu.',
        });
      }
      final file = File(
        '${isPrivatePdf ? _privateMediaDirectory : _publicMediaDirectory}/$mediaName',
      );
      if (!await file.exists()) {
        return _send(request, 404, {'error': 'Media tidak ditemukan.'});
      }
      await file.delete();
      _audit(store, session, 'media.deleted', mediaName);
      await store.save();
      return _send(request, 200, {'deleted': mediaName});
    }
    if (path == '/api/admin/site-settings' && request.method == 'GET') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat melihat pengaturan aplikasi.',
        });
      }
      return _send(request, 200, _siteSettings(store));
    }
    if (path == '/api/admin/site-settings' && request.method == 'PATCH') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat mengubah pengaturan aplikasi.',
        });
      }
      final body = await _body(request);
      final settings = _siteSettings(store);
      const stringLimits = <String, int>{
        'brandName': 60,
        'tagline': 120,
        'logoUrl': 2048,
        'heroLabel': 24,
        'heroTitle': 160,
        'heroExcerpt': 360,
        'heroImageUrl': 2048,
        'epaperTitle': 160,
        'epaperCoverImageUrl': 2048,
        'subscriptionTitle': 120,
        'subscriptionDescription': 360,
      };
      for (final entry in stringLimits.entries) {
        if (!body.containsKey(entry.key)) continue;
        final value = body[entry.key];
        if (value is! String || value.length > entry.value) {
          return _send(request, 422, {
            'error': 'Nilai ${entry.key} tidak valid atau terlalu panjang.',
          });
        }
        settings[entry.key] = value.trim();
      }
      if (body.containsKey('hotTopics')) {
        final topics = body['hotTopics'];
        if (topics is! List ||
            topics.length > 8 ||
            topics.any((topic) => topic is! String || topic.length > 48)) {
          return _send(request, 422, {
            'error': 'Topik hangat harus berisi maksimal 8 teks (48 karakter).',
          });
        }
        settings['hotTopics'] = topics
            .map((topic) => topic.toString().trim())
            .where((topic) => topic.isNotEmpty)
            .toList();
      }
      if (body.containsKey('paymentMethods')) {
        final methods = body['paymentMethods'];
        final ids = <String>{};
        if (methods is! List || methods.length > 8) {
          return _send(request, 422, {
            'error': 'Maksimal 8 metode pembayaran dapat disimpan.',
          });
        }
        for (final method in methods) {
          if (method is! Map ||
              method['id'] is! String ||
              !RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(method['id'] as String) ||
              !ids.add(method['id'] as String) ||
              method['name'] is! String ||
              (method['name'] as String).trim().isEmpty ||
              (method['name'] as String).length > 48 ||
              method['instructions'] is! String ||
              (method['instructions'] as String).length > 500 ||
              method['enabled'] is! bool) {
            return _send(request, 422, {
              'error': 'Data metode pembayaran tidak valid.',
            });
          }
        }
        settings['paymentMethods'] = methods
            .map((method) => Map<String, dynamic>.from(method as Map))
            .toList();
      }
      store.data['siteSettings'] = settings;
      _audit(store, session, 'site_settings.updated', 'site');
      await store.save();
      return _send(request, 200, settings);
    }
    if (path == '/api/admin/payments' && request.method == 'GET') {
      if (session == null || session.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat mengelola pembayaran.',
        });
      }
      final users = (store.data['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final plans = (store.data['subscriptionPlans'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final items = (store.data['invoices'] as List<dynamic>).reversed.map((
        invoice,
      ) {
        final item = Map<String, dynamic>.from(invoice as Map);
        final email = item['userId']?.toString() ?? '';
        final name = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
        final plan = plans
            .where((entry) => entry['id'] == item['packageId'])
            .firstOrNull;
        item['customerName'] = name
            .split(' ')
            .where((part) => part.isNotEmpty)
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' ');
        item['packageName'] = plan?['name'] ?? item['packageId'];
        item['customerExists'] = users.any((user) => user['email'] == email);
        return item;
      }).toList();
      return _send(request, 200, {'items': items});
    }
    if (path == '/api/admin/notifications' && request.method == 'GET') {
      if (session == null || !session.admin) {
        return _send(request, 401, {'error': 'Authorization diperlukan.'});
      }
      final notifications = (store.data['notifications'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      return _send(request, 200, {
        'items': notifications,
        'unread': notifications.where((item) => item['read'] != true).length,
      });
    }
    if (path == '/api/admin/notifications/read-all' &&
        request.method == 'PATCH') {
      if (session == null || !session.admin) {
        return _send(request, 401, {'error': 'Authorization diperlukan.'});
      }
      for (final notification
          in (store.data['notifications'] as List<dynamic>)) {
        (notification as Map<String, dynamic>)['read'] = true;
      }
      await store.save();
      return _send(request, 200, {'updated': true});
    }
    final paymentConfirmation = RegExp(
      r'^/api/admin/payments/([^/]+)/confirm$',
    ).firstMatch(path);
    if (request.method == 'POST' && paymentConfirmation != null) {
      return _send(request, HttpStatus.gone, {
        'error':
            'Konfirmasi manual dinonaktifkan. Status langganan hanya berubah dari notifikasi gateway terverifikasi.',
      });
    }
    if (path == '/api/admin/epapers' && request.method == 'GET') {
      return _send(request, 200, {'items': store.data['epapers']});
    }
    if (path == '/api/admin/epapers' && request.method == 'POST') {
      if (!_canWrite(session!)) {
        return _send(request, 403, {
          'error': 'Role tidak boleh mengelola e-paper.',
        });
      }
      final body = await _body(request);
      final privateFileName = body['privateFileName']?.toString() ?? '';
      if (privateFileName.isNotEmpty &&
          !RegExp(r'^media-[A-Za-z0-9_-]+\.pdf$').hasMatch(privateFileName)) {
        return _send(request, 422, {'error': 'File PDF edisi tidak valid.'});
      }
      final issue = <String, dynamic>{
        'id': body['id'] ?? 'epaper-${DateTime.now().millisecondsSinceEpoch}',
        'title': _required(body, 'title'),
        'edition': _required(body, 'edition'),
        'date': _required(body, 'date'),
        'totalPages': body['totalPages'] is num
            ? (body['totalPages'] as num).round()
            : 0,
        'status': session.role == 'Author'
            ? 'draft'
            : body['status'] ?? 'draft',
        'createdBy': session.email,
        'downloadAllowed': body['downloadAllowed'] == true,
        if (privateFileName.isNotEmpty) 'privateFileName': privateFileName,
      };
      (store.data['epapers'] as List<dynamic>).add(issue);
      _audit(store, session, 'epaper.created', issue['id']);
      await store.save();
      return _send(request, 201, issue);
    }
    final adminEpaperMatch = RegExp(
      r'^/api/admin/epapers/([^/]+)$',
    ).firstMatch(path);
    if (adminEpaperMatch != null && request.method == 'PATCH') {
      if (!_canWrite(session!)) {
        return _send(request, 403, {
          'error': 'Role tidak boleh mengubah e-paper.',
        });
      }
      final id = adminEpaperMatch.group(1)!;
      final issue = (store.data['epapers'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == id)
          .firstOrNull;
      if (issue == null) {
        return _send(request, 404, {'error': 'E-paper tidak ditemukan.'});
      }
      if (session.role == 'Author' &&
          (issue['createdBy'] != session.email ||
              issue['status'] == 'published')) {
        return _send(request, 403, {
          'error': 'Author hanya dapat mengubah draft e-paper milik sendiri.',
        });
      }
      final body = await _body(request);
      for (final key in ['title', 'edition', 'date']) {
        if (body.containsKey(key)) issue[key] = _required(body, key);
      }
      if (body['totalPages'] is num) {
        issue['totalPages'] = (body['totalPages'] as num).round();
      }
      if (body.containsKey('downloadAllowed')) {
        issue['downloadAllowed'] = body['downloadAllowed'] == true;
      }
      if (body.containsKey('privateFileName')) {
        final fileName = body['privateFileName']?.toString() ?? '';
        if (fileName.isNotEmpty &&
            !RegExp(r'^media-[A-Za-z0-9_-]+\.pdf$').hasMatch(fileName)) {
          return _send(request, 422, {'error': 'File PDF edisi tidak valid.'});
        }
        issue['privateFileName'] = fileName;
      }
      if (body.containsKey('status') && session.role != 'Author') {
        issue['status'] = body['status'];
      }
      _audit(store, session, 'epaper.updated', id);
      await store.save();
      return _send(request, 200, issue);
    }
    final publishEpaperMatch = RegExp(
      r'^/api/admin/epapers/([^/]+)/publish$',
    ).firstMatch(path);
    if (publishEpaperMatch != null && request.method == 'POST') {
      if (!_canPublish(session!)) {
        return _send(request, 403, {
          'error':
              'Hanya Editor atau Super Admin yang dapat menerbitkan e-paper.',
        });
      }
      final id = publishEpaperMatch.group(1)!;
      final issue = (store.data['epapers'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == id)
          .firstOrNull;
      if (issue == null) {
        return _send(request, 404, {'error': 'E-paper tidak ditemukan.'});
      }
      final pdfName = issue['privateFileName']?.toString() ?? '';
      if (pdfName.isEmpty ||
          !await File('$_privateMediaDirectory/$pdfName').exists()) {
        return _send(request, 422, {
          'error': 'Unggah file PDF sebelum menerbitkan e-paper.',
        });
      }
      issue['status'] = 'published';
      _audit(store, session, 'epaper.published', id);
      await store.save();
      return _send(request, 200, issue);
    }
    if (adminEpaperMatch != null && request.method == 'DELETE') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat menghapus e-paper.',
        });
      }
      final id = adminEpaperMatch.group(1)!;
      final epapers = (store.data['epapers'] as List<dynamic>);
      final issue = epapers
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == id)
          .firstOrNull;
      if (issue == null) {
        return _send(request, 404, {'error': 'E-paper tidak ditemukan.'});
      }
      epapers.remove(issue);
      _audit(store, session, 'epaper.deleted', id);
      await store.save();
      final privateFileName = issue['privateFileName']?.toString() ?? '';
      if (privateFileName.isNotEmpty) {
        final pdf = File('$_privateMediaDirectory/$privateFileName');
        if (await pdf.exists()) await pdf.delete();
      }
      return _send(request, 200, issue);
    }
    if (path == '/api/admin/categories' && request.method == 'GET') {
      return _send(request, 200, {'items': store.data['categories']});
    }
    if (path == '/api/admin/categories' && request.method == 'POST') {
      if (session!.role != 'Editor' && session.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Role tidak boleh mengelola kategori.',
        });
      }
      final body = await _body(request);
      final name = _required(body, 'name').toUpperCase();
      final slug = (body['slug']?.toString().trim().isNotEmpty == true
          ? body['slug'].toString().trim().toLowerCase()
          : name
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
                .replaceAll(RegExp(r'^-|-$'), ''));
      final categories = (store.data['categories'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (categories.any((item) => item['slug'] == slug)) {
        return _send(request, 422, {'error': 'Slug kategori sudah digunakan.'});
      }
      final category = {'slug': slug, 'name': name, 'public': true};
      categories.add(category);
      _audit(store, session, 'category.created', slug);
      await store.save();
      return _send(request, 201, category);
    }
    final categoryMatch = RegExp(
      r'^/api/admin/categories/([^/]+)$',
    ).firstMatch(path);
    if (categoryMatch != null && request.method == 'DELETE') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat menghapus kategori.',
        });
      }
      final slug = categoryMatch.group(1)!;
      final categories = (store.data['categories'] as List<dynamic>);
      final removed = categories
          .cast<Map<String, dynamic>>()
          .where((item) => item['slug'] == slug)
          .firstOrNull;
      if (removed == null) {
        return _send(request, 404, {'error': 'Kategori tidak ditemukan.'});
      }
      categories.remove(removed);
      _audit(store, session, 'category.deleted', slug);
      await store.save();
      return _send(request, 200, removed);
    }
    if (path == '/api/admin/articles' && request.method == 'GET') {
      final all = store.data['articles'] as List<dynamic>;
      return _send(request, 200, {
        'items': session!.role == 'Author'
            ? all.where((item) => item['author'] == session.email).toList()
            : all,
      });
    }
    if (path == '/api/admin/articles' && request.method == 'POST') {
      if (!_canWrite(session!)) {
        return _send(request, 403, {
          'error': 'Role tidak boleh membuat artikel.',
        });
      }
      final body = await _body(request);
      if (!_validArticleMedia(body) ||
          !_validArticleSeo(body) ||
          !_validSocialLinks(body)) {
        return _send(request, 422, {
          'error': 'URL media, SEO, atau tautan sosial artikel tidak valid.',
        });
      }
      final articles = (store.data['articles'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final title = _required(body, 'title');
      final requestedSlug = _articleSlug(
        body['slug']?.toString().trim().isNotEmpty == true
            ? body['slug'].toString()
            : title,
      );
      if (_articleSlugTaken(articles, requestedSlug)) {
        return _send(request, 409, {'error': 'Slug artikel sudah digunakan.'});
      }
      final article = <String, dynamic>{
        'id': body['id'] ?? 'article-${DateTime.now().millisecondsSinceEpoch}',
        'title': title,
        'slug': requestedSlug,
        'seoTitle': body['seoTitle']?.toString().trim() ?? '',
        'seoDescription': body['seoDescription']?.toString().trim() ?? '',
        'category': _required(body, 'category'),
        'excerpt': body['excerpt'] ?? '',
        'body': _required(body, 'body'),
        'isPremium': body['isPremium'] == true,
        'mainImageUrl': body['mainImageUrl']?.toString().trim(),
        'mainImageBlurUrl': body['mainImageBlurUrl']?.toString().trim(),
        'mainImageAltText': body['mainImageAltText']?.toString().trim(),
        'socialLinks': Map<String, String>.from(
          body['socialLinks'] as Map? ?? const {},
        ),
        'status': 'draft',
        'author': session.email,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
      articles.add(article);
      _recordArticleRevision(store, article, session, note: 'Artikel dibuat.');
      _audit(store, session, 'article.created', article['id']);
      await store.save();
      return _send(request, 201, article);
    }
    final updateArticleMatch = RegExp(
      r'^/api/admin/articles/([^/]+)$',
    ).firstMatch(path);
    if (updateArticleMatch != null && request.method == 'PATCH') {
      if (!_canWrite(session!)) {
        return _send(request, 403, {
          'error': 'Role tidak boleh mengubah artikel.',
        });
      }
      final id = updateArticleMatch.group(1)!;
      final article = (store.data['articles'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == id)
          .firstOrNull;
      if (article == null) {
        return _send(request, 404, {'error': 'Artikel tidak ditemukan.'});
      }
      if (session.role == 'Author' &&
          (article['author'] != session.email ||
              article['status'] != 'draft' &&
                  article['status'] != 'rejected')) {
        return _send(request, 403, {
          'error': 'Author hanya dapat mengubah draft milik sendiri.',
        });
      }
      final body = await _body(request);
      if (!_validArticleMedia(body) ||
          !_validArticleSeo(body) ||
          !_validSocialLinks(body)) {
        return _send(request, 422, {
          'error': 'URL media, SEO, atau tautan sosial artikel tidak valid.',
        });
      }
      if (body.containsKey('slug')) {
        final newSlug = _articleSlug(body['slug']?.toString() ?? '');
        if (newSlug.isEmpty) {
          return _send(request, 422, {'error': 'Slug artikel tidak valid.'});
        }
        final duplicate = _articleSlugTaken(
          (store.data['articles'] as List<dynamic>)
              .cast<Map<String, dynamic>>(),
          newSlug,
          exceptId: id,
        );
        if (duplicate) {
          return _send(request, 409, {
            'error': 'Slug artikel sudah digunakan.',
          });
        }
        article['slug'] = newSlug;
      }
      for (final key in ['title', 'category', 'excerpt', 'body']) {
        if (body.containsKey(key)) article[key] = _required(body, key);
      }
      for (final key in ['seoTitle', 'seoDescription']) {
        if (body.containsKey(key)) {
          article[key] = body[key]?.toString().trim() ?? '';
        }
      }
      for (final key in [
        'mainImageUrl',
        'mainImageBlurUrl',
        'mainImageAltText',
      ]) {
        if (body.containsKey(key)) {
          article[key] = body[key]?.toString().trim() ?? '';
        }
      }
      if (body.containsKey('socialLinks')) {
        article['socialLinks'] = Map<String, String>.from(
          body['socialLinks'] as Map? ?? const {},
        );
      }
      if (body.containsKey('isPremium')) {
        article['isPremium'] = body['isPremium'] == true;
      }
      article['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      _recordArticleRevision(
        store,
        article,
        session,
        note: body['revisionNote']?.toString().trim() ?? 'Perubahan artikel.',
      );
      _audit(store, session, 'article.updated', id);
      await store.save();
      return _send(request, 200, article);
    }
    final articleRevisionsMatch = RegExp(
      r'^/api/admin/articles/([^/]+)/revisions$',
    ).firstMatch(path);
    if (articleRevisionsMatch != null && request.method == 'GET') {
      final id = articleRevisionsMatch.group(1)!;
      final article = (store.data['articles'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == id)
          .firstOrNull;
      if (article == null) {
        return _send(request, 404, {'error': 'Artikel tidak ditemukan.'});
      }
      final revisions =
          (store.data['articleRevisions'] as List<dynamic>)
              .where((item) => item['articleId'] == id)
              .toList()
            ..sort((left, right) {
              final leftDate = DateTime.tryParse(
                left['createdAt']?.toString() ?? '',
              );
              final rightDate = DateTime.tryParse(
                right['createdAt']?.toString() ?? '',
              );
              return (rightDate ?? DateTime(1970)).compareTo(
                leftDate ?? DateTime(1970),
              );
            });
      return _send(request, 200, {'items': revisions});
    }
    final submitReviewMatch = RegExp(
      r'^/api/admin/articles/([^/]+)/submit-review$',
    ).firstMatch(path);
    if (submitReviewMatch != null && request.method == 'POST') {
      final id = submitReviewMatch.group(1)!;
      final article = _findAdminArticle(store, id);
      if (article == null) {
        return _send(request, 404, {'error': 'Artikel tidak ditemukan.'});
      }
      if (session!.role != 'Author' ||
          article['author'] != session.email ||
          !{'draft', 'rejected'}.contains(article['status'])) {
        return _send(request, 403, {
          'error':
              'Hanya penulis artikel draft miliknya yang dapat mengirim review.',
        });
      }
      await _transitionArticle(
        store,
        article,
        session,
        status: 'review',
        action: 'article.submitted_for_review',
      );
      return _send(request, 200, article);
    }
    final approveArticleMatch = RegExp(
      r'^/api/admin/articles/([^/]+)/approve$',
    ).firstMatch(path);
    if (approveArticleMatch != null && request.method == 'POST') {
      if (!_canPublish(session!)) {
        return _send(request, 403, {
          'error':
              'Hanya Editor atau Super Admin yang dapat menyetujui artikel.',
        });
      }
      final id = approveArticleMatch.group(1)!;
      final article = _findAdminArticle(store, id);
      if (article == null) {
        return _send(request, 404, {'error': 'Artikel tidak ditemukan.'});
      }
      // Super Admin bisa approve dari draft/review/ready
      final isSuperAdmin = session!.role == 'Super Admin';
      if (article['status'] != 'review' && !isSuperAdmin) {
        return _send(request, 409, {
          'error': 'Hanya artikel berstatus review yang dapat disetujui.',
        });
      }
      await _transitionArticle(
        store,
        article,
        session,
        status: 'ready',
        action: 'article.approved',
      );
      return _send(request, 200, article);
    }
    final rejectArticleMatch = RegExp(
      r'^/api/admin/articles/([^/]+)/reject$',
    ).firstMatch(path);
    if (rejectArticleMatch != null && request.method == 'POST') {
      if (!_canPublish(session!)) {
        return _send(request, 403, {
          'error': 'Hanya Editor atau Super Admin yang dapat menolak artikel.',
        });
      }
      final id = rejectArticleMatch.group(1)!;
      final article = _findAdminArticle(store, id);
      if (article == null) {
        return _send(request, 404, {'error': 'Artikel tidak ditemukan.'});
      }
      if (article['status'] != 'review') {
        return _send(request, 409, {
          'error': 'Hanya artikel berstatus review yang dapat ditolak.',
        });
      }
      final body = await _body(request);
      final note = body['note']?.toString().trim() ?? '';
      if (note.isEmpty || note.length > 500) {
        return _send(request, 422, {
          'error': 'Catatan penolakan wajib diisi, maksimal 500 karakter.',
        });
      }
      await _transitionArticle(
        store,
        article,
        session,
        status: 'rejected',
        action: 'article.rejected',
        note: note,
      );
      return _send(request, 200, article);
    }
    final scheduleArticleMatch = RegExp(
      r'^/api/admin/articles/([^/]+)/schedule$',
    ).firstMatch(path);
    if (scheduleArticleMatch != null && request.method == 'POST') {
      if (!_canPublish(session!)) {
        return _send(request, 403, {
          'error':
              'Hanya Editor atau Super Admin yang dapat menjadwalkan artikel.',
        });
      }
      final id = scheduleArticleMatch.group(1)!;
      final article = _findAdminArticle(store, id);
      if (article == null) {
        return _send(request, 404, {'error': 'Artikel tidak ditemukan.'});
      }
      if (article['status'] != 'ready') {
        return _send(request, 409, {
          'error': 'Setujui artikel sebelum menjadwalkan publikasi.',
        });
      }
      final body = await _body(request);
      final scheduledAt = DateTime.tryParse(
        body['scheduledAt']?.toString() ?? '',
      )?.toUtc();
      if (scheduledAt == null || !scheduledAt.isAfter(DateTime.now().toUtc())) {
        return _send(request, 422, {
          'error': 'Waktu publikasi harus berupa tanggal mendatang yang valid.',
        });
      }
      article['scheduledAt'] = scheduledAt.toIso8601String();
      await _transitionArticle(
        store,
        article,
        session,
        status: 'scheduled',
        action: 'article.scheduled',
        note: 'Dijadwalkan untuk ${scheduledAt.toIso8601String()}.',
        save: false,
      );
      return _send(request, 200, article);
    }
    final archiveArticleMatch = RegExp(
      r'^/api/admin/articles/([^/]+)/archive$',
    ).firstMatch(path);
    if (archiveArticleMatch != null && request.method == 'POST') {
      if (!_canPublish(session!)) {
        return _send(request, 403, {
          'error':
              'Hanya Editor atau Super Admin yang dapat mengarsipkan artikel.',
        });
      }
      final id = archiveArticleMatch.group(1)!;
      final article = _findAdminArticle(store, id);
      if (article == null) {
        return _send(request, 404, {'error': 'Artikel tidak ditemukan.'});
      }
      if (article['status'] != 'published') {
        return _send(request, 409, {
          'error': 'Hanya artikel terbit yang dapat diarsipkan.',
        });
      }
      await _transitionArticle(
        store,
        article,
        session,
        status: 'archived',
        action: 'article.archived',
      );
      return _send(request, 200, article);
    }
    if (updateArticleMatch != null && request.method == 'DELETE') {
      if (session!.role != 'Editor' && session.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Role tidak boleh menghapus artikel.',
        });
      }
      final id = updateArticleMatch.group(1)!;
      final articles = (store.data['articles'] as List<dynamic>);
      final article = articles
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == id)
          .firstOrNull;
      if (article == null) {
        return _send(request, 404, {'error': 'Artikel tidak ditemukan.'});
      }
      if (article['status'] == 'published' && session.role != 'Super Admin') {
        return _send(request, 409, {
          'error': 'Arsipkan artikel terbit sebelum menghapusnya.',
        });
      }
      articles.remove(article);
      _audit(store, session, 'article.deleted', id);
      await store.save();
      return _send(request, 200, article);
    }
    final publishMatch = RegExp(
      r'^/api/admin/articles/([^/]+)/publish$',
    ).firstMatch(path);
    if (publishMatch != null && request.method == 'POST') {
      if (!_canPublish(session!)) {
        return _send(request, 403, {
          'error': 'Hanya Editor atau Super Admin yang dapat publish.',
        });
      }
      final id = publishMatch.group(1) ?? '';
      final article = (store.data['articles'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == id)
          .firstOrNull;
      if (article == null) {
        return _send(request, 404, {'error': 'Artikel tidak ditemukan.'});
      }
      if (article['status'] == 'published') {
        return _send(request, 200, article);
      }
      // Super Admin bisa langsung publish dari draft/review/ready
      final isSuperAdmin = session!.role == 'Super Admin';
      if (!isSuperAdmin &&
          !{'ready', 'scheduled'}.contains(article['status'])) {
        return _send(request, 409, {
          'error': 'Setujui artikel sebelum menerbitkannya.',
        });
      }
      final scheduledAt = DateTime.tryParse(
        article['scheduledAt']?.toString() ?? '',
      );
      if (article['status'] == 'scheduled' &&
          scheduledAt != null &&
          scheduledAt.isAfter(DateTime.now().toUtc())) {
        return _send(request, 409, {
          'error': 'Artikel belum mencapai waktu publikasi terjadwal.',
        });
      }
      article.remove('scheduledAt');
      article['publishedAt'] = DateTime.now().toUtc().toIso8601String();
      await _transitionArticle(
        store,
        article,
        session,
        status: 'published',
        action: 'article.published',
        save: false,
      );
      _notify(
        store,
        type: 'editorial',
        title: 'Artikel diterbitkan',
        message: article['title']?.toString() ?? '',
        actor: session.email,
        resourceId: id,
      );
      await store.save();
      return _send(request, 200, article);
    }
    final planMatch = RegExp(
      r'^/api/admin/subscription-plans/([^/]+)$',
    ).firstMatch(path);
    if (path == '/api/admin/subscription-plans' && request.method == 'POST') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat menambah paket.',
        });
      }
      final body = await _body(request);
      final id = _required(body, 'id').toLowerCase();
      final name = _required(body, 'name');
      final durationDays = body['durationDays'];
      final price = body['price'];
      if (durationDays is! num ||
          durationDays <= 0 ||
          price is! num ||
          price <= 0) {
        return _send(request, 422, {
          'error': 'Durasi dan harga harus berupa angka positif.',
        });
      }
      final plans = (store.data['subscriptionPlans'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (plans.any((item) => item['id'] == id)) {
        return _send(request, 422, {'error': 'ID paket sudah digunakan.'});
      }
      final plan = <String, dynamic>{
        'id': id,
        'name': name,
        'durationDays': durationDays.round(),
        'price': price.round(),
        'benefits': (body['benefits'] as List? ?? const [])
            .map((benefit) => benefit.toString())
            .toList(),
      };
      plans.add(plan);
      _audit(store, session, 'subscription.package_created', id);
      await store.save();
      return _send(request, 201, plan);
    }
    if (planMatch != null && request.method == 'PATCH') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat mengubah harga.',
        });
      }
      final body = await _body(request);
      final id = planMatch.group(1) ?? '';
      final plan = (store.data['subscriptionPlans'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['id'] == id)
          .firstOrNull;
      if (plan == null) {
        return _send(request, 404, {'error': 'Paket tidak ditemukan.'});
      }
      if (body['price'] is! num ||
          (body['price'] as num) <= 0 ||
          body['durationDays'] is! num ||
          (body['durationDays'] as num) <= 0 ||
          body['name']?.toString().trim().isEmpty == true) {
        return _send(request, 422, {
          'error': 'Nama, durasi, dan harga paket wajib valid.',
        });
      }
      plan['name'] = body['name'].toString().trim();
      plan['durationDays'] = (body['durationDays'] as num).round();
      plan['price'] = (body['price'] as num).round();
      if (body['benefits'] is List) {
        plan['benefits'] = (body['benefits'] as List)
            .map((benefit) => benefit.toString())
            .toList();
      }
      _audit(store, session, 'subscription.price_updated', id);
      await store.save();
      return _send(request, 200, plan);
    }
    if (planMatch != null && request.method == 'DELETE') {
      if (session!.role != 'Super Admin') {
        return _send(request, 403, {
          'error': 'Hanya Super Admin yang dapat menghapus paket.',
        });
      }
      final id = planMatch.group(1)!;
      final plans = (store.data['subscriptionPlans'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final plan = plans.where((item) => item['id'] == id).firstOrNull;
      if (plan == null) {
        return _send(request, 404, {'error': 'Paket tidak ditemukan.'});
      }
      final used = (store.data['invoices'] as List<dynamic>).any(
        (invoice) => invoice['packageId'] == id,
      );
      if (used) {
        return _send(request, 409, {
          'error': 'Paket sudah memiliki transaksi dan tidak dapat dihapus.',
        });
      }
      plans.remove(plan);
      _audit(store, session, 'subscription.package_deleted', id);
      await store.save();
      return _send(request, 200, {'deleted': id});
    }
    return _send(request, 404, {'error': 'Route tidak ditemukan.'});
  } on _RequestBodyTooLarge {
    return _send(request, HttpStatus.requestEntityTooLarge, {
      'error': 'Ukuran body permintaan melebihi batas.',
    });
  } on FormatException catch (error) {
    return _send(request, HttpStatus.badRequest, {'error': error.message});
  } catch (error, stackTrace) {
    stderr.writeln('Request failed: $error\n$stackTrace');
    return _send(request, 500, {'error': 'Kesalahan server.'});
  }
}

bool _hasActiveSubscription(Store store, String? email) {
  if (email == null) return false;
  final now = DateTime.now().toUtc();
  return (store.data['subscriptions'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .any((subscription) {
        final endDate = DateTime.tryParse(
          subscription['endDate']?.toString() ?? '',
        );
        return subscription['userId'] == email &&
            subscription['status'] == 'active' &&
            endDate != null &&
            endDate.isAfter(now);
      });
}

void _activateSubscription(Store store, Map<String, dynamic> invoice) {
  final plans = (store.data['subscriptionPlans'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final plan = plans
      .where((item) => item['id'] == invoice['packageId'])
      .firstOrNull;
  if (plan == null) return;
  final now = DateTime.now().toUtc();
  final subscriptions = (store.data['subscriptions'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final current = subscriptions
      .where((item) => item['userId'] == invoice['userId'])
      .where((item) => item['status'] == 'active')
      .where((item) {
        final end = DateTime.tryParse(item['endDate']?.toString() ?? '');
        return end != null && end.isAfter(now);
      })
      .firstOrNull;
  final start = current == null
      ? now
      : DateTime.parse(current['endDate'].toString()).toUtc();
  final end = start.add(Duration(days: (plan['durationDays'] as num).toInt()));
  if (current != null) current['status'] = 'extended';
  subscriptions.add({
    'userId': invoice['userId'],
    'packageId': invoice['packageId'],
    'startDate': start.toIso8601String(),
    'endDate': end.toIso8601String(),
    'status': 'active',
    'source': invoice['paymentMethod'] ?? 'gateway',
  });
}

String _signDownload(String issueId, String email, DateTime expiresAt) {
  final secret = Platform.environment['DOWNLOAD_SIGNING_SECRET']!;
  final payload = '$issueId|$email|${expiresAt.millisecondsSinceEpoch}';
  return crypto.Hmac(
    crypto.sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(payload)).toString();
}

String _signPage(
  String issueId,
  int pageNumber,
  String email,
  DateTime expiresAt,
) {
  final secret = Platform.environment['DOWNLOAD_SIGNING_SECRET']!;
  final payload =
      '$issueId|$pageNumber|$email|${expiresAt.millisecondsSinceEpoch}';
  return crypto.Hmac(
    crypto.sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(payload)).toString();
}

Future<Map<String, dynamic>> _createMidtransCheckout(
  Map<String, dynamic> invoice,
) async {
  final serverKey = Platform.environment['MIDTRANS_SERVER_KEY']?.trim() ?? '';
  final production = Platform.environment['MIDTRANS_IS_PRODUCTION'] == 'true';
  if (serverKey.isEmpty) {
    throw const MidtransException('server key is not configured');
  }
  final endpoint = Uri.https(
    production ? 'app.midtrans.com' : 'app.sandbox.midtrans.com',
    '/snap/v1/transactions',
  );
  final siteUrl = _configuredPublicSiteUrl;
  final packageName = invoice['packageName']?.toString() ?? 'Langganan';
  final requestBody = <String, dynamic>{
    'transaction_details': {
      'order_id': invoice['id'],
      'gross_amount': invoice['amount'],
    },
    'item_details': [
      {
        'id': invoice['packageId'],
        'price': invoice['amount'],
        'quantity': 1,
        'name': packageName.substring(0, min(50, packageName.length)),
      },
    ],
    'customer_details': {'email': invoice['userId']},
    if (siteUrl != null) 'callbacks': {'finish': '$siteUrl/?payment=finish'},
  };
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.postUrl(endpoint);
    request.headers
      ..set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('$serverKey:'))}',
      )
      ..contentType = ContentType.json;
    request.write(jsonEncode(requestBody));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final responseBody = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MidtransException('gateway returned HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic> ||
        decoded['token'] is! String ||
        decoded['redirect_url'] is! String) {
      throw const MidtransException('gateway response is incomplete');
    }
    final redirect = Uri.tryParse(decoded['redirect_url'] as String);
    if (redirect == null ||
        redirect.scheme != 'https' ||
        !{
          'app.midtrans.com',
          'app.sandbox.midtrans.com',
        }.contains(redirect.host)) {
      throw const MidtransException('gateway redirect URL is invalid');
    }
    return decoded;
  } on MidtransException {
    rethrow;
  } on TimeoutException {
    throw const MidtransException('gateway request timed out');
  } on FormatException {
    throw const MidtransException('gateway returned invalid JSON');
  } on SocketException {
    throw const MidtransException('gateway is unreachable');
  } finally {
    client.close(force: true);
  }
}

class MidtransException implements Exception {
  const MidtransException(this.message);
  final String message;
}

Future<String> _hashPassword(String password) async {
  final random = Random.secure();
  final salt = List<int>.generate(16, (_) => random.nextInt(256));
  final key = await _passwordHasher.deriveKey(
    secretKey: crypto_lib.SecretKey(utf8.encode(password)),
    nonce: salt,
  );
  return 'pbkdf2-sha256:$_passwordHashIterations:'
      '${base64UrlEncode(salt)}:${base64UrlEncode(await key.extractBytes())}';
}

Future<bool> _verifyAndUpgradePassword(
  Map<String, dynamic> user,
  String password,
) async {
  final value = user['passwordHash']?.toString() ?? '';
  if (value.startsWith('pbkdf2-sha256:')) {
    final parts = value.split(':');
    if (parts.length != 4) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 100000 || iterations > 1000000) {
      return false;
    }
    try {
      final salt = base64Url.decode(base64Url.normalize(parts[2]));
      final expected = base64Url.decode(base64Url.normalize(parts[3]));
      if (salt.length != 16 || expected.length != 32) return false;
      final hasher = crypto_lib.Pbkdf2(
        macAlgorithm: crypto_lib.Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      );
      final actual = await hasher.deriveKey(
        secretKey: crypto_lib.SecretKey(utf8.encode(password)),
        nonce: salt,
      );
      final verified = _constantTimeBytesEqual(
        await actual.extractBytes(),
        expected,
      );
      if (verified && iterations < _passwordHashIterations) {
        user['passwordHash'] = await _hashPassword(password);
      }
      return verified;
    } on FormatException {
      return false;
    }
  }

  final legacyHash = crypto.sha256.convert(utf8.encode(password)).toString();
  final legacyMatch =
      (value.isNotEmpty && _constantTimeEquals(legacyHash, value)) ||
      (value.isEmpty && user['password'] == password && password.isNotEmpty);
  if (!legacyMatch) return false;
  user['passwordHash'] = await _hashPassword(password);
  user.remove('password');
  return true;
}

bool _constantTimeEquals(String first, String second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first.codeUnitAt(index) ^ second.codeUnitAt(index);
  }
  return difference == 0;
}

bool _constantTimeBytesEqual(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}

class _RequestBodyTooLarge implements Exception {}

Future<Map<String, dynamic>> _body(HttpRequest request) async {
  const maxBytes = 72 * 1024 * 1024;
  if (request.contentLength > maxBytes) throw _RequestBodyTooLarge();
  final bytes = BytesBuilder();
  var received = 0;
  await for (final chunk in request) {
    received += chunk.length;
    if (received > maxBytes) throw _RequestBodyTooLarge();
    bytes.add(chunk);
  }
  final raw = utf8.decode(bytes.takeBytes());
  if (raw.trim().isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Body JSON harus object.');
  }
  return decoded;
}

String _required(Map<String, dynamic> body, String key) {
  final value = body[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('$key wajib diisi.');
  return value;
}

Session? _authorized(HttpRequest request, Map<String, Session> sessions) {
  final header = request.headers.value('authorization') ?? '';
  if (!header.startsWith('Bearer ')) return null;
  final token = header.substring(7);
  final key = sessions.containsKey(token) ? token : _tokenHash(token);
  final session = sessions[key];
  if (session?.expiresAt?.isAfter(DateTime.now().toUtc()) != true) {
    sessions.remove(key);
    return null;
  }
  return session?.verified == true ? session : null;
}

String _tokenHash(String token) =>
    crypto.sha256.convert(utf8.encode(token)).toString();

Map<String, dynamic> _sessionRecord(String token, Session session) => {
  'tokenHash': _tokenHash(token),
  'email': session.email,
  'role': session.role,
  'expiresAt': session.expiresAt!.toUtc().toIso8601String(),
  'admin': session.admin,
  'subscriber': session.subscriber,
};

bool _canWrite(Session session) =>
    session.role == 'Author' ||
    session.role == 'Editor' ||
    session.role == 'Super Admin';
bool _canPublish(Session session) =>
    session.role == 'Editor' || session.role == 'Super Admin';

Map<String, dynamic> _customerView(Map<String, dynamic> user) {
  final email = user['email']?.toString() ?? '';
  final name = email
      .split('@')
      .first
      .replaceAll(RegExp(r'[._-]+'), ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
  return {
    'name': name,
    'email': email,
    'role': user['role']?.toString() ?? 'Reader',
    'status': user['subscriber'] == true ? 'Aktif' : 'Terdaftar',
    'verified': user['emailVerified'] == true,
  };
}

Map<String, dynamic> _dashboard(Store store, Session session) {
  final allArticles = store.data['articles'] as List<dynamic>;
  final articles = session.role == 'Author'
      ? allArticles.where((item) => item['author'] == session.email).toList()
      : allArticles;
  final now = DateTime.now().toUtc();
  final published = articles
      .where((item) => item['status'] == 'published')
      .toList();
  final activeSubscribers = (store.data['subscriptions'] as List<dynamic>)
      .where((item) {
        final endDate = DateTime.tryParse(item['endDate']?.toString() ?? '');
        return item['status'] == 'active' &&
            endDate != null &&
            endDate.isAfter(now);
      })
      .map((item) => item['userId']?.toString())
      .whereType<String>()
      .toSet()
      .length;
  final readers = (store.data['users'] as List<dynamic>)
      .where((item) => item['role'] == 'Reader')
      .length;
  final today = _dateKey(now);
  final publishedToday = published.where((item) {
    final publishedAt = DateTime.tryParse(
      (item['publishedAt'] ?? item['updatedAt'])?.toString() ?? '',
    );
    return publishedAt != null && _dateKey(publishedAt.toUtc()) == today;
  }).length;
  final visits = (store.data['visitLog'] as List<dynamic>?) ?? const [];
  final traffic = List.generate(7, (index) {
    final date = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: 6 - index));
    final key = _dateKey(date);
    return {
      'date': key,
      'visits': visits.where((item) => item['date'] == key).length,
    };
  });
  return {
    'role': session.role,
    'counts': {
      'articles': articles.length,
      'drafts': articles.where((item) => item['status'] == 'draft').length,
      'reviews': articles.where((item) => item['status'] == 'review').length,
      'ready': articles.where((item) => item['status'] == 'ready').length,
      'scheduled': articles
          .where((item) => item['status'] == 'scheduled')
          .length,
      'published': published.length,
      'archived': articles.where((item) => item['status'] == 'archived').length,
      'publishedToday': publishedToday,
      'epapers': (store.data['epapers'] as List<dynamic>)
          .where((item) => item['status'] == 'published')
          .length,
      'activeSubscribers': activeSubscribers,
      'conversionRate': readers == 0 ? 0 : activeSubscribers / readers * 100,
    },
    'traffic': traffic,
    'auditLog': (store.data['auditLog'] as List<dynamic>).toList()
      ..sort((left, right) {
        final leftDate = DateTime.tryParse(left['at']?.toString() ?? '');
        final rightDate = DateTime.tryParse(right['at']?.toString() ?? '');
        return (rightDate ?? DateTime(1970)).compareTo(
          leftDate ?? DateTime(1970),
        );
      }),
  };
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void _recordVisit(Store store, String path) {
  final visits = (store.data['visitLog'] as List<dynamic>);
  visits.add({'date': _dateKey(DateTime.now().toUtc()), 'path': path});
  if (visits.length > 5000) {
    visits.removeRange(0, visits.length - 5000);
  }
  unawaited(store.save());
}

void _audit(Store store, Session session, String action, String id) {
  (store.data['auditLog'] as List<dynamic>).add({
    'action': action,
    'resourceId': id,
    'actor': session.email,
    'at': DateTime.now().toUtc().toIso8601String(),
  });
}

Map<String, dynamic>? _findAdminArticle(Store store, String id) =>
    (store.data['articles'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((item) => item['id'] == id)
        .firstOrNull;

Map<String, dynamic> _articleRevisionSnapshot(Map<String, dynamic> article) => {
  for (final key in [
    'title',
    'slug',
    'seoTitle',
    'seoDescription',
    'category',
    'excerpt',
    'body',
    'mainImageUrl',
    'mainImageBlurUrl',
    'mainImageAltText',
    'socialLinks',
    'isPremium',
    'status',
    'scheduledAt',
    'publishedAt',
  ])
    if (article.containsKey(key)) key: article[key],
};

void _recordArticleRevision(
  Store store,
  Map<String, dynamic> article,
  Session session, {
  required String note,
}) {
  (store.data['articleRevisions'] as List<dynamic>).add({
    'id': 'article-revision-${DateTime.now().microsecondsSinceEpoch}',
    'articleId': article['id'],
    'actor': session.email,
    'status': article['status'],
    'note': note,
    'snapshot': _articleRevisionSnapshot(article),
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<void> _transitionArticle(
  Store store,
  Map<String, dynamic> article,
  Session session, {
  required String status,
  required String action,
  String? note,
  bool save = true,
}) async {
  article['status'] = status;
  article['updatedAt'] = DateTime.now().toUtc().toIso8601String();
  _recordArticleRevision(
    store,
    article,
    session,
    note: note ?? 'Status diubah menjadi $status.',
  );
  _audit(store, session, action, article['id'].toString());
  if (save) await store.save();
}

Future<void> _publishScheduledArticles(Store store) async {
  final now = DateTime.now().toUtc();
  final dueArticles = (store.data['articles'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((article) {
        final scheduledAt = DateTime.tryParse(
          article['scheduledAt']?.toString() ?? '',
        );
        return article['status'] == 'scheduled' &&
            scheduledAt != null &&
            !scheduledAt.isAfter(now);
      })
      .toList();
  if (dueArticles.isEmpty) return;
  const scheduler = Session(
    email: 'system:scheduler',
    role: 'System',
    verified: true,
  );
  for (final article in dueArticles) {
    article.remove('scheduledAt');
    article['publishedAt'] = now.toIso8601String();
    await _transitionArticle(
      store,
      article,
      scheduler,
      status: 'published',
      action: 'article.scheduled_publication_completed',
      note: 'Publikasi terjadwal dijalankan.',
      save: false,
    );
  }
  await store.save();
}

void _notify(
  Store store, {
  required String type,
  required String title,
  required String message,
  String? actor,
  String? resourceId,
}) {
  final notifications = (store.data['notifications'] as List<dynamic>);
  notifications.insert(0, {
    'id': 'notification-${DateTime.now().microsecondsSinceEpoch}',
    'type': type,
    'title': title,
    'message': message,
    'actor': actor,
    'resourceId': resourceId,
    'read': false,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });
  if (notifications.length > 100) {
    notifications.removeRange(100, notifications.length);
  }
}

String _randomToken() => base64UrlEncode(
  List<int>.generate(32, (_) => Random.secure().nextInt(256)),
);

const _maxAdminOtpAttempts = 5;

String _newAdminVerificationCode() =>
    Random.secure().nextInt(1000000).toString().padLeft(6, '0');

String _adminVerificationCodeHash(String code) => crypto.Hmac(
  crypto.sha256,
  utf8.encode(Platform.environment['DOWNLOAD_SIGNING_SECRET']!),
).convert(utf8.encode(code)).toString();

_SmtpConfiguration? _smtpConfiguration() {
  // ===== PATCH DEVELOPMENT =====
  final appEnv =
      Platform.environment['APP_ENV']?.trim().toLowerCase() ?? 'development';
  if (appEnv != 'production') {
    return _SmtpConfiguration(
      host: 'localhost',
      port: 25,
      username: 'dev@localhost',
      password: 'dev',
      sender: 'dev@localhost',
      senderName: 'Development',
    );
  }
  // ===== END PATCH =====

  final username = Platform.environment['SMTP_USERNAME']?.trim() ?? '';
  final password = Platform.environment['SMTP_APP_PASSWORD']?.trim() ?? '';
  final host = Platform.environment['SMTP_HOST']?.trim() ?? 'smtp.gmail.com';
  final port = int.tryParse(Platform.environment['SMTP_PORT']?.trim() ?? '587');
  final sender = Platform.environment['SMTP_FROM_EMAIL']?.trim() ?? username;
  if (!_looksLikeEmail(username) ||
      password.isEmpty ||
      host.isEmpty ||
      host.contains(RegExp(r'\s')) ||
      port == null ||
      port < 1 ||
      port > 65535 ||
      !_looksLikeEmail(sender)) {
    return null;
  }
  return _SmtpConfiguration(
    host: host,
    port: port,
    username: username,
    password: password.replaceAll(' ', ''),
    sender: sender,
    senderName:
        Platform.environment['SMTP_FROM_NAME']?.trim() ?? 'Magelang Ekspres',
  );
}

bool _looksLikeEmail(String value) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

Future<void> _sendAdminVerificationEmail(
  _SmtpConfiguration configuration,
  String recipient,
  String code,
) async {
  // ===== PATCH DEVELOPMENT =====
  final appEnv =
      Platform.environment['APP_ENV']?.trim().toLowerCase() ?? 'development';
  if (appEnv != 'production') {
    stdout.writeln('');
    stdout.writeln('╔══════════════════════════════════════════╗');
    stdout.writeln('║       OTP LOGIN ADMIN (DEVELOPMENT)      ║');
    stdout.writeln('╠══════════════════════════════════════════╣');
    stdout.writeln('║ Email : $recipient');
    stdout.writeln('║ OTP   : $code');
    stdout.writeln('║ Berlaku 5 menit, sekali pakai.');
    stdout.writeln('╚══════════════════════════════════════════╝');
    stdout.writeln('');
    return;
  }
  // ===== END PATCH =====

  final message = Message()
    ..from = Address(configuration.sender, configuration.senderName)
    ..recipients.add(recipient)
    ..subject = 'Kode verifikasi admin Magelang Ekspres'
    ..text =
        'Kode verifikasi login CMS Magelang Ekspres Anda adalah $code.\n\n'
        'Kode berlaku selama 5 menit dan hanya dapat digunakan satu kali. '
        'Jangan bagikan kode ini kepada siapa pun.';
  final smtpServer = SmtpServer(
    configuration.host,
    port: configuration.port,
    ssl: configuration.port == 465,
    allowInsecure: false,
    username: configuration.username,
    password: configuration.password,
  );
  await send(message, smtpServer, timeout: const Duration(seconds: 15));
}

Future<void> _removeLegacyDemoContent(Store store) async {
  const demoArticleIds = {
    'welcome',
    'koran-sekolah-sample',
    'article-1788704071746',
    'article-1788838433073',
  };
  const demoEpaperIds = {'edisi-2026-09-06'};
  final articles = (store.data['articles'] as List<dynamic>);
  final epapers = (store.data['epapers'] as List<dynamic>);
  final previousArticleCount = articles.length;
  final previousEpaperCount = epapers.length;
  articles.removeWhere(
    (item) => item is Map && demoArticleIds.contains(item['id']),
  );
  epapers.removeWhere(
    (item) => item is Map && demoEpaperIds.contains(item['id']),
  );
  if (articles.length != previousArticleCount ||
      epapers.length != previousEpaperCount) {
    if (store is MysqlStore) {
      await store.removeLegacyDemoContent(
        articleIds: demoArticleIds,
        epaperIds: demoEpaperIds,
      );
    } else {
      await store.save();
    }
  }
}

Future<void> _seedSampleContent(Store store) async {
  var changed = false;
  final categories = (store.data['categories'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  for (final category in categories) {
    if (category['slug'] == 'olahraga') {
      category
        ..['slug'] = 'kampung-inovatif'
        ..['name'] = 'KAMPUNG INOVATIF';
      changed = true;
    } else if (category['slug'] == 'pendidikan') {
      category
        ..['slug'] = 'koran-sekolah'
        ..['name'] = 'KORAN SEKOLAH';
      changed = true;
    }
  }
  for (final category in [
    {'slug': 'kampung-inovatif', 'name': 'KAMPUNG INOVATIF', 'public': true},
    {'slug': 'koran-sekolah', 'name': 'KORAN SEKOLAH', 'public': true},
  ]) {
    if (!categories.any((item) => item['slug'] == category['slug'])) {
      categories.add(category);
      changed = true;
    }
  }

  final articles = (store.data['articles'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final sampleArticles = [
    {
      'id': 'kampung-inovatif-2026-08-13',
      'slug': 'budidaya-maggot-jambon-kampung-inovatif',
      'title': 'Budidaya Maggot di Jambon, Cara Kurangi Sampah Organik',
      'category': 'KAMPUNG INOVATIF',
      'excerpt':
          'Edisi 13 Agustus 2026, halaman 6. Baca ringkasan dua baris; scan koran dan isi lengkap tersedia untuk pelanggan.',
      'body':
          'Sorotan Kampung Inovatif dari edisi 13 Agustus 2026. Buka halaman 6 untuk membaca versi koran lengkap.',
      'isPremium': true,
      'status': 'published',
      'author': 'system',
      'publishedAt': '2026-08-13T00:00:00.000Z',
      'isSample': true,
      'epaperId': 'epaper-2026-08-13',
      'pageNumber': 6,
      'socialLinks': <String, String>{},
    },
    {
      'id': 'kampung-inovatif-meteseh-2026-08-13',
      'slug': 'kampung-meteseh-hut-ri-2026',
      'title': 'Kampung Meteseh Semarakkan HUT RI dengan Beragam Lomba',
      'category': 'KAMPUNG INOVATIF',
      'excerpt':
          'Edisi 13 Agustus 2026, halaman 6. Cuplikan gratis dua baris; scan halaman penuh terkunci untuk pelanggan.',
      'body':
          'Berita Kampung Inovatif dari halaman 6 edisi 13 Agustus 2026. Buka scan halaman untuk versi cetak lengkap.',
      'isPremium': true,
      'status': 'published',
      'author': 'system',
      'publishedAt': '2026-08-13T00:00:00.000Z',
      'isSample': true,
      'epaperId': 'epaper-2026-08-13',
      'pageNumber': 6,
      'socialLinks': <String, String>{},
    },
  ];
  for (final article in sampleArticles) {
    if (!articles.any((item) => item['id'] == article['id'])) {
      articles.add(article);
      changed = true;
    }
  }

  final epapers = (store.data['epapers'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final sampleIssues = [
    _sampleIssue(
      date: '13 Agustus 2026',
      isoDate: '2026-08-13',
      featured: true,
      labels: const [
        'PURWOREJO - TEMANGGUNG',
        'KABUPATEN MAGELANG',
        'MAGELANG',
        'METROPOLIS',
        'WONOSOBO EKSPRES',
        'KAMPUNG INOVATIF',
        'WONOSOBO / PURWOREJO',
        'MAGELANG / METROPOLIS',
      ],
      articleIds: const {
        6: [
          'kampung-inovatif-2026-08-13',
          'kampung-inovatif-meteseh-2026-08-13',
        ],
      },
    ),
    _sampleIssue(
      date: '1 Oktober 2026',
      isoDate: '2026-10-01',
      featured: false,
      labels: const [
        'BERITA UTAMA',
        'KABUPATEN MAGELANG',
        'WONOSOBO EKSPRES',
        'METROPOLIS',
        'MAGELANG',
        'WONOSOBO',
        'KABUPATEN MAGELANG',
        'MAGELANG / METROPOLIS',
      ],
      articleIds: const {},
    ),
  ];
  for (final issue in sampleIssues.reversed) {
    if (!epapers.any((item) => item['id'] == issue['id'])) {
      epapers.insert(0, issue);
      changed = true;
    }
  }
  if (changed) await store.save();
}

Map<String, dynamic> _sampleIssue({
  required String date,
  required String isoDate,
  required bool featured,
  required List<String> labels,
  required Map<int, List<String>> articleIds,
}) {
  final id = 'epaper-$isoDate';
  final pages = [
    for (var pageNumber = 1; pageNumber <= 8; pageNumber++)
      <String, dynamic>{
        'pageNumber': pageNumber,
        'label': labels[pageNumber - 1],
        'accentColor': pageNumber == 6 ? 0xff4b9b46 : 0xffb51f2a,
        'articleIds': articleIds[pageNumber] ?? <String>[],
      },
  ];
  final articles = [
    if (isoDate == '2026-08-13')
      <String, dynamic>{
        'id': 'kampung-inovatif-2026-08-13',
        'title': 'Budidaya Maggot di Jambon, Cara Kurangi Sampah Organik',
        'category': 'KAMPUNG INOVATIF',
        'pageNumber': 6,
        'isPremium': true,
        'excerpt':
            'Edisi 13 Agustus 2026, halaman 6. Baca scan lengkap dengan langganan.',
        'content':
            'Sorotan Kampung Inovatif dari halaman 6. Scan halaman koran memuat artikel lengkap.',
        'socialLinks': <String, String>{},
      },
    if (isoDate == '2026-08-13')
      <String, dynamic>{
        'id': 'kampung-inovatif-meteseh-2026-08-13',
        'title': 'Kampung Meteseh Semarakkan HUT RI dengan Beragam Lomba',
        'category': 'KAMPUNG INOVATIF',
        'pageNumber': 6,
        'isPremium': true,
        'excerpt':
            'Kampung Meteseh mengisi peringatan HUT RI dengan beragam lomba.',
        'content':
            'Berita Kampung Inovatif pada halaman 6 edisi 13 Agustus 2026. Scan halaman koran memuat artikel lengkap.',
        'socialLinks': <String, String>{},
      },
  ];
  return {
    'id': id,
    'title': 'MAGELANG EKSPRES',
    'edition': 'Edisi $date',
    'date': date,
    'totalPages': 8,
    'status': 'published',
    'featured': featured,
    'isSample': true,
    'coverImage': '/media/media-$id-p01.jpg',
    'privateFileName': 'sample-$isoDate.pdf',
    'downloadAllowed': true,
    'pages': pages,
    'articles': articles,
  };
}

File _epaperPdfFile(String fileName) {
  final samplePdf = switch (fileName) {
    'sample-2026-08-13.pdf' => 'docx_pdf/Magelang Ekspres 13-08-2026-01.pdf',
    'sample-2026-10-01.pdf' => 'docx_pdf/Magelang Ekspres 01-10-2026-01.pdf',
    _ => '$_privateMediaDirectory/$fileName',
  };
  return File(samplePdf);
}

Future<void> _send(HttpRequest request, int status, Object body) async {
  request.response.statusCode = status;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<void> _sendV1(
  HttpRequest request,
  int status,
  String message,
  Object? data, {
  List<String>? errors,
}) async {
  await _send(request, status, {
    'success': status >= 200 && status < 300,
    'message': message,
    'data': data,
    'meta': <String, dynamic>{},
    'errors': errors,
  });
}

Map<String, dynamic> _publicArticle(
  Map<String, dynamic> article,
  bool unlocked,
) {
  final result = Map<String, dynamic>.from(article);
  final title = result['title']?.toString() ?? '';
  final excerpt = result['excerpt']?.toString() ?? '';
  result
    ..['slug'] = _articleSlug(
      result['slug']?.toString().trim().isNotEmpty == true
          ? result['slug'].toString()
          : title,
    )
    ..['seoTitle'] = result['seoTitle']?.toString().trim().isNotEmpty == true
        ? result['seoTitle'].toString().trim()
        : _defaultSeoTitle(title)
    ..['seoDescription'] =
        result['seoDescription']?.toString().trim().isNotEmpty == true
        ? result['seoDescription'].toString().trim()
        : excerpt;
  final premium = result['isPremium'] == true;
  if (premium && !unlocked) {
    result.remove('body');
    result.remove('content');
    result.remove('mainImageUrl');
    result.remove('originalAssetUrl');
    result.remove('socialLinks');
    result['teaserContent'] =
        result['teaserContent'] ?? result['excerpt'] ?? '';
    result['isLocked'] = true;
  } else {
    result['isLocked'] = false;
  }
  return result;
}

String _defaultSeoTitle(String title) {
  final suffix = ' | Magelang Ekspres';
  if (title.length + suffix.length <= 70) return '$title$suffix';
  final prefixLength = 70 - suffix.length - 3;
  return '${title.substring(0, prefixLength)}...$suffix';
}

Map<String, dynamic> _publicEpaper(
  Map<String, dynamic> issue, {
  bool hasActiveSubscription = false,
  String? email,
  required Uri requestUri,
}) {
  final result = Map<String, dynamic>.from(issue)..remove('privateFileName');
  final privateFileName = issue['privateFileName']?.toString() ?? '';
  final hasPdf =
      privateFileName.isNotEmpty &&
      _epaperPdfFile(privateFileName).existsSync();
  result['downloadAvailable'] = hasPdf;
  result['downloadAllowed'] =
      (issue['downloadAllowed'] == true ||
          _isSampleIssueId(issue['id']?.toString() ?? '')) &&
      hasPdf;
  final issueId = result['id']?.toString() ?? '';
  final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 10));
  final pages = ((result['pages'] as List<dynamic>?) ?? const []).map((item) {
    final page = Map<String, dynamic>.from(item as Map);
    final pageNumber = (page['pageNumber'] as num?)?.toInt() ?? 0;
    final publicPreview = _publicPageImage(issueId, pageNumber);
    if (publicPreview != null) page['previewImage'] = publicPreview;
    if (hasActiveSubscription &&
        email != null &&
        pageNumber > 0 &&
        _isSampleIssueId(issueId)) {
      page['image'] = _signedPageUrl(
        requestUri,
        issueId,
        pageNumber,
        email,
        expiresAt,
      );
    } else {
      page.remove('image');
    }
    return page;
  }).toList();
  result['pages'] = pages;
  result['coverImage'] ??= _publicPageImage(issueId, 1);
  result['articles'] = ((result['articles'] as List<dynamic>?) ?? const []).map(
    (item) {
      final article = Map<String, dynamic>.from(item as Map);
      final pageNumber = (article['pageNumber'] as num?)?.toInt() ?? 0;
      final publicPreview = _publicPageImage(issueId, pageNumber);
      if (publicPreview != null) {
        article['thumbnail'] ??= publicPreview;
      }
      if (hasActiveSubscription &&
          email != null &&
          pageNumber > 0 &&
          _isSampleIssueId(issueId)) {
        article['pageImage'] = _signedPageUrl(
          requestUri,
          issueId,
          pageNumber,
          email,
          expiresAt,
        );
      } else {
        article.remove('pageImage');
        if (article['isPremium'] == true) article['content'] = '';
      }
      article['isLocked'] =
          article['isPremium'] == true && !hasActiveSubscription;
      return article;
    },
  ).toList();
  return result;
}

String? _publicPageImage(String issueId, int pageNumber) {
  if (!_isSampleIssueId(issueId) || pageNumber < 1 || pageNumber > 8) {
    return null;
  }
  final fileName =
      'media-$issueId-p${pageNumber.toString().padLeft(2, '0')}.jpg';
  if (!File('$_publicMediaDirectory/$fileName').existsSync()) return null;
  return '/media/$fileName?v=2';
}

bool _isSampleIssueId(String issueId) =>
    RegExp(r'^epaper-2026-(08-13|10-01)$').hasMatch(issueId);

String _signedPageUrl(
  Uri requestUri,
  String issueId,
  int pageNumber,
  String email,
  DateTime expiresAt,
) {
  final expires = expiresAt.millisecondsSinceEpoch;
  return requestUri
      .replace(
        path:
            '/private/epapers/$issueId/pages/$pageNumber/${Uri.encodeComponent(email)}.jpg',
        queryParameters: {
          'expires': '$expires',
          'signature': _signPage(issueId, pageNumber, email, expiresAt),
        },
      )
      .toString();
}

bool _validArticleMedia(Map<String, dynamic> body) {
  const limits = <String, int>{
    'mainImageUrl': 2048,
    'mainImageBlurUrl': 2048,
    'mainImageAltText': 180,
  };
  return limits.entries.every((entry) {
    final value = body[entry.key];
    return !body.containsKey(entry.key) ||
        value is String && value.length <= entry.value;
  });
}

String? _mediaExtension(String kind, List<int> bytes) {
  if (kind == 'pdf') {
    return bytes.length >= 5 &&
            bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46 &&
            bytes[4] == 0x2d
        ? 'pdf'
        : null;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'jpg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return null;
}

String _imageContentType(String extension) => switch (extension) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'application/octet-stream',
};

String _publicMediaBaseUrl(HttpRequest request) {
  final configured = Platform.environment['API_PUBLIC_BASE_URL']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return configured.replaceFirst(RegExp(r'/+$'), '');
  }
  final host = request.headers.host;
  final hostUri = Uri.parse('http://$host');
  return 'http://${hostUri.host}:${hostUri.hasPort ? hostUri.port : _port}';
}

bool _referencesMedia(Store store, String mediaName) {
  final reference = '/media/$mediaName';
  final settings = store.data['siteSettings'];
  if (settings is Map &&
      settings.values.any((value) => value.toString().contains(reference))) {
    return true;
  }
  for (final article in (store.data['articles'] as List<dynamic>)) {
    if (article is Map &&
        article.values.any((value) => value.toString().contains(reference))) {
      return true;
    }
  }
  for (final issue in (store.data['epapers'] as List<dynamic>)) {
    if (issue is Map &&
        issue.values.any((value) => value.toString().contains(reference))) {
      return true;
    }
  }
  return false;
}

class Session {
  const Session({
    required this.email,
    required this.role,
    required this.verified,
    this.expiresAt,
    this.admin = false,
    this.subscriber = false,
  });
  final String email;
  final String role;
  final bool verified;
  final DateTime? expiresAt;
  final bool admin;
  final bool subscriber;
}

class _AuthAttemptWindow {
  _AuthAttemptWindow(this.startedAt);
  DateTime startedAt;
  int count = 0;
}

class _AdminLoginChallenge {
  _AdminLoginChallenge({required this.codeHash, required this.expiresAt});

  final String codeHash;
  final DateTime expiresAt;
  int attempts = 0;
}

class _SmtpConfiguration {
  const _SmtpConfiguration({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.sender,
    required this.senderName,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String sender;
  final String senderName;
}

class JsonStore implements Store {
  JsonStore(this.file);
  final File file;
  @override
  late Map<String, dynamic> data;

  @override
  Future<void> load() async {
    if (!await file.exists()) {
      data = _seed();
      await save();
      return;
    }
    data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    data.putIfAbsent('users', () => <dynamic>[]);
    data.putIfAbsent('authSessions', () => <dynamic>[]);
    data.putIfAbsent('categories', () => _defaultCategories());
    data.putIfAbsent('savedItems', () => <dynamic>[]);
    data.putIfAbsent('subscriptions', () => <dynamic>[]);
    data.putIfAbsent('invoices', () => <dynamic>[]);
    data.putIfAbsent('notifications', () => <dynamic>[]);
    data.putIfAbsent('downloadLogs', () => <dynamic>[]);
    data.putIfAbsent('auditLog', () => <dynamic>[]);
    data.putIfAbsent('articleRevisions', () => <dynamic>[]);
    data.putIfAbsent('visitLog', () => <dynamic>[]);
    data.putIfAbsent(
      'adminUsers',
      () => (data['users'] as List<dynamic>)
          .where((user) => user['role'] != 'Reader')
          .map((user) => Map<String, dynamic>.from(user as Map))
          .toList(),
    );
  }

  @override
  Future<void> save() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  @override
  Future<void> persistPasswordHash(
    String email,
    String passwordHash, {
    required bool admin,
  }) async {
    final key = admin ? 'adminUsers' : 'users';
    final account = (data[key] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((item) => item['email'] == email)
        .firstOrNull;
    if (account == null) {
      throw StateError('Akun tidak ditemukan saat menyimpan hash kata sandi.');
    }
    account['passwordHash'] = passwordHash;
    account.remove('password');
    await save();
  }

  @override
  Future<void> persistSession(Map<String, dynamic> session) async {
    final sessions = (data['authSessions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    sessions.removeWhere((item) => item['tokenHash'] == session['tokenHash']);
    sessions.add(session);
    await save();
  }

  @override
  Future<void> revokeSession(String tokenHash) async {
    (data['authSessions'] as List<dynamic>).removeWhere(
      (item) => item['tokenHash'] == tokenHash,
    );
    await save();
  }

  Map<String, dynamic> _seed() => <String, dynamic>{
    'articles': <Map<String, dynamic>>[],
    'users': <Map<String, dynamic>>[],
    'adminUsers': <Map<String, dynamic>>[],
    'authSessions': <Map<String, dynamic>>[],
    'categories': _defaultCategories(),
    'epapers': <Map<String, dynamic>>[],
    'subscriptionPlans': <Map<String, dynamic>>[
      {
        'id': 'premium_1_month',
        'name': 'Premium 1 Bulan',
        'durationDays': 30,
        'price': 49000,
        'benefits': ['Artikel premium', 'E-paper', 'Baca nanti'],
      },
      {
        'id': 'premium_3_month',
        'name': 'Premium 3 Bulan',
        'durationDays': 90,
        'price': 129000,
        'benefits': ['Artikel premium', 'E-paper', 'Baca nanti'],
      },
      {
        'id': 'premium_6_month',
        'name': 'Premium 6 Bulan',
        'durationDays': 180,
        'price': 249000,
        'benefits': ['Artikel premium', 'E-paper', 'Baca nanti'],
      },
      {
        'id': 'premium_1_year',
        'name': 'Premium 1 Tahun',
        'durationDays': 365,
        'price': 499000,
        'benefits': ['Artikel premium', 'E-paper', 'Baca nanti'],
      },
    ],
    'savedItems': <Map<String, dynamic>>[],
    'invoices': <Map<String, dynamic>>[],
    'notifications': <Map<String, dynamic>>[],
    'downloadLogs': <Map<String, dynamic>>[],
    'articleRevisions': <Map<String, dynamic>>[],
    'visitLog': <Map<String, dynamic>>[],
    'auditLog': <Map<String, dynamic>>[],
  };
}

List<Map<String, dynamic>> _defaultCategories() => [
  {'slug': 'berita-utama', 'name': 'BERITA UTAMA', 'public': true},
  {'slug': 'magelang-kota', 'name': 'MAGELANG KOTA', 'public': true},
  {'slug': 'kabupaten-magelang', 'name': 'KABUPATEN MAGELANG', 'public': true},
  {'slug': 'jateng', 'name': 'JATENG', 'public': true},
  {'slug': 'ekonomi', 'name': 'EKONOMI', 'public': true},
  {'slug': 'kampung-inovatif', 'name': 'KAMPUNG INOVATIF', 'public': true},
  {'slug': 'koran-sekolah', 'name': 'KORAN SEKOLAH', 'public': true},
];

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
