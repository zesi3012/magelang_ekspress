import 'package:flutter_test/flutter_test.dart';
import 'package:magelang_express/repositories/mock_subscription_repository.dart';

void main() {
  test(
    'returns the four configured local plans without UI hardcoding',
    () async {
      final plans = await MockSubscriptionRepository().getActivePlans();
      expect(plans.length, 4);
      expect(
        plans.map((plan) => plan.price),
        orderedEquals([49000, 129000, 249000, 499000]),
      );
      expect(plans.every((plan) => plan.benefits.isNotEmpty), isTrue);
    },
  );
}
