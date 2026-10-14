class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.durationDays,
    required this.price,
    required this.benefits,
  });

  final String id;
  final String name;
  final int durationDays;
  final int price;
  final List<String> benefits;

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id']?.toString() ?? json['planId']?.toString() ?? '',
      name: json['name']?.toString() ?? json['packageName']?.toString() ?? 'Paket',
      durationDays: _parseDuration(json),
      price: _parsePrice(json),
      benefits: _parseBenefits(json),
    );
  }

  static int _parseDuration(Map<String, dynamic> json) {
    if (json['durationDays'] != null) {
      return (json['durationDays'] as num).toInt();
    }
    if (json['durationMonths'] != null) {
      return (json['durationMonths'] as num).toInt() * 30;
    }
    if (json['duration'] != null) {
      final dur = json['duration'];
      if (dur is int) return dur;
      if (dur is String) {
        final match = RegExp(r'(\d+)').firstMatch(dur);
        if (match != null) {
          final value = int.parse(match.group(1)!);
          if (dur.toLowerCase().contains('bulan') || dur.toLowerCase().contains('month')) {
            return value * 30;
          } else if (dur.toLowerCase().contains('tahun') || dur.toLowerCase().contains('year')) {
            return value * 365;
          }
          return value;
        }
      }
    }
    return 30;
  }

  static int _parsePrice(Map<String, dynamic> json) {
    final price = json['price'] ?? json['amount'] ?? 0;
    return price is int ? price : (price as num).toInt();
  }

  static List<String> _parseBenefits(Map<String, dynamic> json) {
    final raw = json['benefits'] ?? json['features'] ?? [];
    if (raw is List) {
      return raw.map((b) => b.toString()).toList();
    }
    if (raw is String) {
      return raw.split(',').map((b) => b.trim()).toList();
    }
    return const [];
  }
}