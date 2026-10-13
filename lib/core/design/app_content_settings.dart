import 'package:flutter/foundation.dart';

const _defaultPaymentMethods = <Map<String, dynamic>>[
  {
    'id': 'bank-transfer',
    'name': 'Transfer Bank',
    'instructions': '',
    'enabled': false,
  },
  {'id': 'qris', 'name': 'QRIS', 'instructions': '', 'enabled': false},
];

@immutable
class AppContentSettings {
  const AppContentSettings({
    this.brandName = 'MAGELANG EKSPRES',
    this.tagline = 'Akurat, Terpercaya, dan Menginspirasi',
    this.logoUrl = '',
    this.heroLabel = 'HEADLINE',
    this.heroTitle = '',
    this.heroExcerpt = '',
    this.heroImageUrl = '',
    this.hotTopics = const [
      'Pilkada Magelang',
      'Infrastruktur',
      'Lingkungan',
      'Ekonomi',
    ],
    this.epaperTitle = 'E-Paper Magelang Ekspres',
    this.epaperCoverImageUrl = '',
    this.subscriptionTitle = 'Baca berita lengkap tanpa batas',
    this.subscriptionDescription =
        'Nikmati akses artikel premium, e-paper harian, dan arsip edisi.',
    this.paymentMethods = _defaultPaymentMethods,
  });

  static const defaults = AppContentSettings();

  final String brandName;
  final String tagline;
  final String logoUrl;
  final String heroLabel;
  final String heroTitle;
  final String heroExcerpt;
  final String heroImageUrl;
  final List<String> hotTopics;
  final String epaperTitle;
  final String epaperCoverImageUrl;
  final String subscriptionTitle;
  final String subscriptionDescription;
  final List<Map<String, dynamic>> paymentMethods;

  factory AppContentSettings.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return defaults;
    String read(String key, String fallback) =>
        value[key]?.toString().trim().isNotEmpty == true
        ? value[key].toString().trim()
        : fallback;
    final topics = value['hotTopics'];
    return AppContentSettings(
      brandName: read('brandName', defaults.brandName),
      tagline: read('tagline', defaults.tagline),
      logoUrl: value['logoUrl']?.toString() ?? '',
      heroLabel: read('heroLabel', defaults.heroLabel),
      heroTitle: value['heroTitle']?.toString() ?? '',
      heroExcerpt: value['heroExcerpt']?.toString() ?? '',
      heroImageUrl: value['heroImageUrl']?.toString() ?? '',
      hotTopics: topics is List
          ? topics
                .map((topic) => topic.toString().trim())
                .where((topic) => topic.isNotEmpty)
                .toList()
          : defaults.hotTopics,
      epaperTitle: read('epaperTitle', defaults.epaperTitle),
      epaperCoverImageUrl: value['epaperCoverImageUrl']?.toString() ?? '',
      subscriptionTitle: read('subscriptionTitle', defaults.subscriptionTitle),
      subscriptionDescription: read(
        'subscriptionDescription',
        defaults.subscriptionDescription,
      ),
      paymentMethods: value['paymentMethods'] is List
          ? (value['paymentMethods'] as List)
                .whereType<Map>()
                .map((method) => Map<String, dynamic>.from(method))
                .toList()
          : defaults.paymentMethods,
    );
  }

  Map<String, dynamic> toJson() => {
    'brandName': brandName,
    'tagline': tagline,
    'logoUrl': logoUrl,
    'heroLabel': heroLabel,
    'heroTitle': heroTitle,
    'heroExcerpt': heroExcerpt,
    'heroImageUrl': heroImageUrl,
    'hotTopics': hotTopics,
    'epaperTitle': epaperTitle,
    'epaperCoverImageUrl': epaperCoverImageUrl,
    'subscriptionTitle': subscriptionTitle,
    'subscriptionDescription': subscriptionDescription,
    'paymentMethods': paymentMethods,
  };
}

final appContentSettings = ValueNotifier<AppContentSettings>(
  AppContentSettings.defaults,
);
