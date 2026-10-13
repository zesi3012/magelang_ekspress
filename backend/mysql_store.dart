import 'dart:convert';
import 'dart:io';

import 'package:mysql1/mysql1.dart';

abstract interface class Store {
  Map<String, dynamic> get data;
  Future<void> load();
  Future<void> save();
  Future<void> persistPasswordHash(
    String email,
    String passwordHash, {
    required bool admin,
  });
  Future<void> persistSession(Map<String, dynamic> session);
  Future<void> revokeSession(String tokenHash);
}

class MysqlStore implements Store {
  MysqlStore(this.connection);

  final MySqlConnection connection;
  @override
  final data = <String, dynamic>{};
  int _persistedDownloadLogCount = 0;
  int _persistedAuditLogCount = 0;
  int _persistedArticleRevisionCount = 0;

  Future<void> removeLegacyDemoContent({
    required Set<String> articleIds,
    required Set<String> epaperIds,
  }) async {
    await connection.transaction((transaction) async {
      final articlePlaceholders = List.filled(
        articleIds.length,
        '?',
      ).join(', ');
      await transaction.query(
        'DELETE FROM articles WHERE id IN ($articlePlaceholders)',
        articleIds.toList(),
      );
      final epaperPlaceholders = List.filled(epaperIds.length, '?').join(', ');
      await transaction.query(
        'DELETE FROM epapers WHERE id IN ($epaperPlaceholders)',
        epaperIds.toList(),
      );
    });
  }

  Future<void> disableKnownWeakSeedAccounts(
    String passwordHash,
    String legacyPassword,
  ) async {
    await connection.query(
      "UPDATE admin_users SET status = 'disabled' WHERE password_hash = ? OR password_hash = ?",
      [passwordHash, legacyPassword],
    );
    await connection.query(
      "UPDATE users SET password_hash = '', email_verified = FALSE WHERE password_hash = ? OR password_hash = ?",
      [passwordHash, legacyPassword],
    );
  }

  @override
  Future<void> persistPasswordHash(
    String email,
    String passwordHash, {
    required bool admin,
  }) async {
    await connection.query(
      admin
          ? 'UPDATE admin_users SET password_hash = ? WHERE email = ?'
          : 'UPDATE users SET password_hash = ? WHERE email = ?',
      [passwordHash, email],
    );
  }

  static Future<MysqlStore> fromEnvironment() async {
    final connection = await MySqlConnection.connect(
      ConnectionSettings(
        host: Platform.environment['DB_HOST'] ?? '127.0.0.1',
        port: int.tryParse(Platform.environment['DB_PORT'] ?? '3306') ?? 3306,
        user: Platform.environment['DB_USER'] ?? 'root',
        password: Platform.environment['DB_PASSWORD'] ?? '',
        db: Platform.environment['DB_NAME'] ?? 'magelang_express',
      ),
    );
    return MysqlStore(connection);
  }

  @override
  Future<void> persistSession(Map<String, dynamic> session) async {
    await connection.query(
      'INSERT INTO auth_sessions (token_hash, email, role, expires_at, is_admin, subscriber) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE email = VALUES(email), role = VALUES(role), expires_at = VALUES(expires_at), is_admin = VALUES(is_admin), subscriber = VALUES(subscriber)',
      [
        session['tokenHash'],
        session['email'],
        session['role'],
        _date(session['expiresAt']),
        session['admin'] == true ? 1 : 0,
        session['subscriber'] == true ? 1 : 0,
      ],
    );
    final sessions = (data['authSessions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    sessions.removeWhere((item) => item['tokenHash'] == session['tokenHash']);
    sessions.add(Map<String, dynamic>.from(session));
  }

  @override
  Future<void> revokeSession(String tokenHash) async {
    await connection.query('DELETE FROM auth_sessions WHERE token_hash = ?', [
      tokenHash,
    ]);
    (data['authSessions'] as List<dynamic>).removeWhere(
      (item) => item['tokenHash'] == tokenHash,
    );
  }

  @override
  Future<void> load() async {
    data['adminUsers'] = await _rows(
      'SELECT email, password_hash, role, status FROM admin_users',
      (row) => {
        'email': row['email'],
        'passwordHash': row['password_hash'],
        'role': row['role'],
        'status': row['status'],
      },
    );
    data['users'] = await _rows(
      'SELECT email, password_hash, role, subscriber, email_verified FROM users',
      (row) => {
        'email': row['email'],
        'passwordHash': row['password_hash'],
        'role': row['role'],
        'subscriber': row['subscriber'] == 1,
        'emailVerified': row['email_verified'] == 1,
      },
    );
    data['authSessions'] = await _rows(
      'SELECT token_hash, email, role, expires_at, is_admin, subscriber FROM auth_sessions',
      (row) => {
        'tokenHash': row['token_hash'],
        'email': row['email'],
        'role': row['role'],
        'expiresAt': row['expires_at']?.toString(),
        'admin': row['is_admin'] == 1,
        'subscriber': row['subscriber'] == 1,
      },
    );
    data['categories'] = await _rows(
      'SELECT slug, name, is_public FROM categories ORDER BY name',
      (row) => {
        'slug': row['slug'],
        'name': row['name'],
        'public': row['is_public'] == 1,
      },
    );
    data['articles'] = await _rows(
      'SELECT id, title, slug, seo_title, seo_description, category, excerpt, body, main_image_url, main_image_blur_url, main_image_alt_text, is_premium, status, author, updated_at, published_at FROM articles ORDER BY updated_at DESC',
      (row) => {
        'id': row['id'],
        'title': row['title'],
        'slug': row['slug'],
        'seoTitle': row['seo_title'],
        'seoDescription': row['seo_description'],
        'category': row['category'],
        'excerpt': row['excerpt'],
        'body': row['body'],
        'mainImageUrl': row['main_image_url'],
        'mainImageBlurUrl': row['main_image_blur_url'],
        'mainImageAltText': row['main_image_alt_text'],
        'isPremium': row['is_premium'] == 1,
        'status': row['status'],
        'author': row['author'],
        'updatedAt': row['updated_at']?.toString(),
        'publishedAt': row['published_at']?.toString(),
      },
    );
    data['epapers'] = await _rows(
      'SELECT id, title, edition, edition_date, total_pages, cover_image, private_file_name, status FROM epapers ORDER BY edition_date DESC',
      (row) => {
        'id': row['id'],
        'title': row['title'],
        'edition': row['edition'],
        'date': row['edition_date'],
        'totalPages': row['total_pages'],
        'coverImage': row['cover_image'],
        'privateFileName': row['private_file_name'],
        'status': row['status'],
      },
    );
    data['subscriptionPlans'] = await _rows(
      'SELECT id, name, duration_days, price, benefits FROM subscription_packages ORDER BY duration_days',
      (row) => {
        'id': row['id'],
        'name': row['name'],
        'durationDays': row['duration_days'],
        'price': row['price'],
        'benefits': _jsonList(row['benefits']),
      },
    );
    data['subscriptions'] = await _rows(
      'SELECT user_id, package_id, start_date, end_date, status FROM subscriptions',
      (row) => {
        'userId': row['user_id'],
        'packageId': row['package_id'],
        'startDate': row['start_date'].toString(),
        'endDate': row['end_date'].toString(),
        'status': row['status'],
      },
    );
    data['savedItems'] = await _rows(
      'SELECT user_id, item_type, item_id, created_at FROM saved_items',
      (row) => {
        'userId': row['user_id'],
        'itemType': row['item_type'],
        'itemId': row['item_id'],
        'createdAt': row['created_at'].toString(),
      },
    );
    data['invoices'] = await _rows(
      'SELECT id, user_id, package_id, amount, payment_method, status, transaction_reference, payment_url, gateway_token, created_at, paid_at FROM payments',
      (row) => {
        'id': row['id'],
        'userId': row['user_id'],
        'packageId': row['package_id'],
        'amount': row['amount'],
        'paymentMethod': row['payment_method'],
        'status': row['status'],
        'transactionReference': row['transaction_reference'],
        'paymentUrl': row['payment_url'],
        'gatewayToken': row['gateway_token'],
        'createdAt': row['created_at']?.toString(),
        'paidAt': row['paid_at']?.toString(),
      },
    );
    data['notifications'] = await _rows(
      'SELECT id, type, title, message, actor, resource_id, is_read, created_at FROM notifications ORDER BY created_at DESC',
      (row) => {
        'id': row['id'],
        'type': row['type'],
        'title': row['title'],
        'message': row['message'],
        'actor': row['actor'],
        'resourceId': row['resource_id'],
        'read': row['is_read'] == 1,
        'createdAt': row['created_at']?.toString(),
      },
    );
    data['downloadLogs'] = await _rows(
      'SELECT user_id, epaper_edition_id, file_url, ip_address, user_agent, downloaded_at FROM download_logs ORDER BY downloaded_at DESC',
      (row) => {
        'userId': row['user_id'],
        'epaperEditionId': row['epaper_edition_id'],
        'fileUrl': row['file_url'],
        'ipAddress': row['ip_address'],
        'userAgent': row['user_agent'],
        'downloadedAt': row['downloaded_at']?.toString(),
      },
    );
    data['auditLog'] = await _rows(
      'SELECT action, resource_id, actor, created_at FROM audit_logs ORDER BY id ASC',
      (row) => {
        'action': row['action'],
        'resourceId': row['resource_id'],
        'actor': row['actor'],
        'at': row['created_at'].toString(),
      },
    );
    data['articleRevisions'] = await _rows(
      'SELECT id, article_id, actor, status, note, snapshot, created_at FROM article_revisions ORDER BY created_at DESC',
      (row) => {
        'id': row['id'],
        'articleId': row['article_id'],
        'actor': row['actor'],
        'status': row['status'],
        'note': row['note'],
        'snapshot': _jsonMap(row['snapshot']),
        'createdAt': row['created_at']?.toString(),
      },
    );
    final siteSettingsRows = await _rows(
      'SELECT settings FROM app_settings WHERE id = 1',
      (row) => {'settings': row['settings']},
    );
    data['siteSettings'] = siteSettingsRows.isEmpty
        ? <String, dynamic>{}
        : _jsonMap(siteSettingsRows.first['settings']);
    await _loadEpaperDetails();
    if (Platform.environment['DB_IMPORT_JSON'] == 'true' &&
        (data['articles'] as List<dynamic>).isEmpty) {
      final source = File(
        Platform.environment['DB_JSON_PATH'] ?? 'backend/data/store.json',
      );
      if (await source.exists()) {
        final imported = jsonDecode(await source.readAsString());
        if (imported is Map<String, dynamic>) {
          data
            ..clear()
            ..addAll(imported);
          _persistedDownloadLogCount = 0;
          _persistedAuditLogCount = 0;
          _persistedArticleRevisionCount = 0;
          await save();
        }
      }
    }
    data.putIfAbsent('authSessions', () => <dynamic>[]);
    data.putIfAbsent('articleRevisions', () => <dynamic>[]);
    _persistedDownloadLogCount = (data['downloadLogs'] as List<dynamic>).length;
    _persistedAuditLogCount = (data['auditLog'] as List<dynamic>).length;
    _persistedArticleRevisionCount =
        (data['articleRevisions'] as List<dynamic>).length;
  }

  Future<void> _loadEpaperDetails() async {
    final pages = await _rows(
      'SELECT issue_id, page_number, label, accent_color, image, article_ids FROM epaper_pages ORDER BY issue_id, page_number',
      (row) => {
        'issueId': row['issue_id'],
        'pageNumber': row['page_number'],
        'label': row['label'],
        'accentColor': row['accent_color'],
        'image': row['image'],
        'articleIds': _jsonList(row['article_ids']),
      },
    );
    final articles = await _rows(
      'SELECT id, issue_id, title, category, page_number, is_premium, thumbnail, content FROM epaper_articles',
      (row) => {
        'id': row['id'],
        'issueId': row['issue_id'],
        'title': row['title'],
        'category': row['category'],
        'pageNumber': row['page_number'],
        'isPremium': row['is_premium'] == 1,
        'thumbnail': row['thumbnail'],
        'content': row['content'],
      },
    );
    for (final issue
        in (data['epapers'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      issue['pages'] = pages
          .where((page) => page['issueId'] == issue['id'])
          .map((page) {
            final copy = Map<String, dynamic>.from(page)..remove('issueId');
            return copy;
          })
          .toList();
      issue['articles'] = articles
          .where((article) => article['issueId'] == issue['id'])
          .map((article) {
            final copy = Map<String, dynamic>.from(article)..remove('issueId');
            return copy;
          })
          .toList();
    }
  }

  @override
  Future<void> save() async {
    await connection.transaction((transaction) async {
      final admins = (data['adminUsers'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        _upsertSql(
          'admin_users',
          ['id', 'email', 'password_hash', 'role', 'status'],
          ['id'],
        ),
        admins.map(
          (admin) => [
            admin['email'],
            admin['email'],
            admin['passwordHash'] ?? '',
            admin['role'] ?? 'Author',
            admin['status'] ?? 'active',
          ],
        ),
      );

      final users = (data['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        _upsertSql(
          'users',
          [
            'id',
            'email',
            'password_hash',
            'role',
            'subscriber',
            'email_verified',
          ],
          ['id'],
        ),
        users.map(
          (user) => [
            user['email'],
            user['email'],
            user['passwordHash'] ?? '',
            user['role'] ?? 'Reader',
            user['subscriber'] == true ? 1 : 0,
            user['emailVerified'] == true ? 1 : 0,
          ],
        ),
      );

      final categories = (data['categories'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        _upsertSql('categories', ['slug', 'name', 'is_public'], ['slug']),
        categories.map(
          (category) => [
            category['slug'],
            category['name'],
            category['public'] == true ? 1 : 0,
          ],
        ),
      );

      final articles = (data['articles'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        _upsertSql(
          'articles',
          [
            'id',
            'title',
            'slug',
            'seo_title',
            'seo_description',
            'category',
            'excerpt',
            'body',
            'main_image_url',
            'main_image_blur_url',
            'main_image_alt_text',
            'is_premium',
            'status',
            'author',
            'updated_at',
            'published_at',
          ],
          ['id'],
        ),
        articles.map(
          (article) => [
            article['id'],
            article['title'],
            article['slug'] ?? '',
            article['seoTitle'] ?? '',
            article['seoDescription'] ?? '',
            article['category'],
            article['excerpt'] ?? '',
            article['body'] ?? '',
            article['mainImageUrl'],
            article['mainImageBlurUrl'],
            article['mainImageAltText'],
            article['isPremium'] == true ? 1 : 0,
            article['status'] ?? 'draft',
            article['author'] ?? 'system',
            _date(article['updatedAt']),
            _date(article['publishedAt']),
          ],
        ),
      );

      final epapers = (data['epapers'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        _upsertSql(
          'epapers',
          [
            'id',
            'title',
            'edition',
            'edition_date',
            'total_pages',
            'cover_image',
            'private_file_name',
            'status',
          ],
          ['id'],
        ),
        epapers.map(
          (issue) => [
            issue['id'],
            issue['title'],
            issue['edition'],
            issue['date'] ?? '',
            issue['totalPages'] ?? 0,
            issue['coverImage'],
            issue['privateFileName'],
            issue['status'] ?? 'published',
          ],
        ),
      );
      final pageValues = <List<Object?>>[];
      final articleValues = <List<Object?>>[];
      for (final issue in epapers) {
        for (final page in (issue['pages'] as List<dynamic>? ?? const [])) {
          final item = page as Map<String, dynamic>;
          pageValues.add([
            issue['id'],
            item['pageNumber'],
            item['label'] ?? '',
            item['accentColor'] ?? 0,
            item['image'],
            jsonEncode(item['articleIds'] ?? const []),
          ]);
        }
        for (final article
            in (issue['articles'] as List<dynamic>? ?? const [])) {
          final item = article as Map<String, dynamic>;
          articleValues.add([
            item['id'],
            issue['id'],
            item['title'],
            item['category'],
            item['pageNumber'],
            item['isPremium'] == true ? 1 : 0,
            item['thumbnail'],
            item['content'] ?? '',
          ]);
        }
      }
      await transaction.queryMulti(
        _upsertSql(
          'epaper_pages',
          [
            'issue_id',
            'page_number',
            'label',
            'accent_color',
            'image',
            'article_ids',
          ],
          ['issue_id', 'page_number'],
        ),
        pageValues,
      );
      await transaction.queryMulti(
        _upsertSql(
          'epaper_articles',
          [
            'id',
            'issue_id',
            'title',
            'category',
            'page_number',
            'is_premium',
            'thumbnail',
            'content',
          ],
          ['id'],
        ),
        articleValues,
      );

      final plans = (data['subscriptionPlans'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        _upsertSql(
          'subscription_packages',
          ['id', 'name', 'duration_days', 'price', 'benefits'],
          ['id'],
        ),
        plans.map(
          (plan) => [
            plan['id'],
            plan['name'],
            plan['durationDays'],
            plan['price'],
            jsonEncode(plan['benefits'] ?? const []),
          ],
        ),
      );

      final subscriptions = (data['subscriptions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        _upsertSql(
          'subscriptions',
          ['user_id', 'package_id', 'start_date', 'end_date', 'status'],
          ['user_id', 'package_id', 'start_date'],
        ),
        subscriptions.map(
          (subscription) => [
            subscription['userId'],
            subscription['packageId'],
            _date(subscription['startDate']),
            _date(subscription['endDate']),
            subscription['status'] ?? 'active',
          ],
        ),
      );

      final savedItems = (data['savedItems'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        _upsertSql(
          'saved_items',
          ['user_id', 'item_type', 'item_id'],
          ['user_id', 'item_type', 'item_id'],
        ),
        savedItems.map(
          (item) => [item['userId'], item['itemType'], item['itemId']],
        ),
      );
      final invoices = (data['invoices'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        _upsertSql(
          'payments',
          [
            'id',
            'user_id',
            'package_id',
            'amount',
            'payment_method',
            'status',
            'transaction_reference',
            'payment_url',
            'gateway_token',
            'created_at',
            'paid_at',
          ],
          ['id'],
        ),
        invoices.map(
          (invoice) => [
            invoice['id'],
            invoice['userId'],
            invoice['packageId'],
            invoice['amount'] ?? 0,
            invoice['paymentMethod'] ?? 'gateway',
            invoice['status'] ?? 'pending',
            invoice['transactionReference'],
            invoice['paymentUrl'],
            invoice['gatewayToken'],
            _date(invoice['createdAt']) ?? DateTime.now().toUtc(),
            _date(invoice['paidAt']),
          ],
        ),
      );
      final notifications = (data['notifications'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        _upsertSql(
          'notifications',
          [
            'id',
            'type',
            'title',
            'message',
            'actor',
            'resource_id',
            'is_read',
            'created_at',
          ],
          ['id'],
        ),
        notifications.map(
          (notification) => [
            notification['id'],
            notification['type'] ?? 'activity',
            notification['title'] ?? '',
            notification['message'] ?? '',
            notification['actor'],
            notification['resourceId'],
            notification['read'] == true ? 1 : 0,
            _date(notification['createdAt']) ?? DateTime.now().toUtc(),
          ],
        ),
      );
      final downloadLogs = (data['downloadLogs'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final newDownloadLogs = downloadLogs
          .skip(_persistedDownloadLogCount)
          .toList();
      await transaction.queryMulti(
        'INSERT INTO download_logs (user_id, epaper_edition_id, file_url, ip_address, user_agent, downloaded_at) VALUES (?, ?, ?, ?, ?, ?)',
        newDownloadLogs.map(
          (log) => [
            log['userId'],
            log['epaperEditionId'],
            log['fileUrl'],
            log['ipAddress'],
            log['userAgent'],
            _date(log['downloadedAt']) ?? DateTime.now().toUtc(),
          ],
        ),
      );
      final auditLog = (data['auditLog'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        'INSERT INTO audit_logs (action, resource_id, actor, created_at) VALUES (?, ?, ?, ?)',
        auditLog
            .skip(_persistedAuditLogCount)
            .map(
              (entry) => [
                entry['action'],
                entry['resourceId'],
                entry['actor'],
                _date(entry['at']) ?? DateTime.now().toUtc(),
              ],
            ),
      );
      final articleRevisions = (data['articleRevisions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      await transaction.queryMulti(
        'INSERT INTO article_revisions (id, article_id, actor, status, note, snapshot, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        articleRevisions
            .skip(_persistedArticleRevisionCount)
            .map(
              (revision) => [
                revision['id'],
                revision['articleId'],
                revision['actor'],
                revision['status'],
                revision['note'],
                jsonEncode(revision['snapshot'] ?? const <String, dynamic>{}),
                _date(revision['createdAt']) ?? DateTime.now().toUtc(),
              ],
            ),
      );
      await transaction.query(
        'INSERT INTO app_settings (id, settings) VALUES (1, ?) ON DUPLICATE KEY UPDATE settings = VALUES(settings)',
        [jsonEncode(data['siteSettings'] ?? const <String, dynamic>{})],
      );
    });
    _persistedDownloadLogCount = (data['downloadLogs'] as List<dynamic>).length;
    _persistedAuditLogCount = (data['auditLog'] as List<dynamic>).length;
    _persistedArticleRevisionCount =
        (data['articleRevisions'] as List<dynamic>).length;
  }

  String _upsertSql(
    String table,
    List<String> columns,
    List<String> keyColumns,
  ) {
    final fields = columns.join(', ');
    final placeholders = List.filled(columns.length, '?').join(', ');
    final updates = columns
        .where((column) => !keyColumns.contains(column))
        .map((column) => '$column = VALUES($column)')
        .join(', ');
    final duplicateAction = updates.isEmpty
        ? '${keyColumns.first} = VALUES(${keyColumns.first})'
        : updates;
    return 'INSERT INTO $table ($fields) VALUES ($placeholders) '
        'ON DUPLICATE KEY UPDATE $duplicateAction';
  }

  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();

  Future<List<Map<String, dynamic>>> _rows(
    String sql,
    Map<String, dynamic> Function(ResultRow row) map,
  ) async {
    final result = await connection.query(sql);
    return result.map(map).toList();
  }

  List<dynamic> _jsonList(Object? value) {
    if (value == null) return <dynamic>[];
    final decoded = value is String ? jsonDecode(value) : value;
    return decoded is List ? decoded : <dynamic>[];
  }

  Map<String, dynamic> _jsonMap(Object? value) {
    if (value == null) return <String, dynamic>{};
    final decoded = value is String ? jsonDecode(value) : value;
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }
}
