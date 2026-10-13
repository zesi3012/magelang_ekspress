import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ShareService {
  static Uri _contentUri(String id, String type) {
    const configuredBase = String.fromEnvironment('WEB_BASE_URL');
    final base = configuredBase.isNotEmpty
        ? Uri.parse(configuredBase)
        : kIsWeb
        ? Uri.base
        : Uri.parse('http://localhost:8080');
    return base.replace(queryParameters: {...base.queryParameters, type: id});
  }

  static Future<void> shareArticle({
    required String title,
    required String id,
    required String destination,
    bool epaperArticle = false,
  }) async {
    final uri = _contentUri(id, epaperArticle ? 'epaperArticle' : 'article');
    final text = '$title\n$uri';

    switch (destination) {
      case 'Salin tautan':
        await Clipboard.setData(ClipboardData(text: uri.toString()));
        return;
      case 'WhatsApp':
        await _launch(Uri.https('wa.me', '/', {'text': text}), text, title);
        return;
      case 'Facebook':
        await _launch(
          Uri.https('www.facebook.com', '/sharer/sharer.php', {
            'u': uri.toString(),
          }),
          text,
          title,
        );
        return;
      case 'Twitter':
      case 'X':
        await _launch(
          Uri.https('twitter.com', '/intent/tweet', {
            'text': title,
            'url': uri.toString(),
          }),
          text,
          title,
        );
        return;
      default:
        await SharePlus.instance.share(ShareParams(text: text, subject: title));
    }
  }

  static Future<void> _launch(Uri uri, String text, String title) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await SharePlus.instance.share(ShareParams(text: text, subject: title));
    }
  }
}
