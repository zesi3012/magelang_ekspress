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
}
