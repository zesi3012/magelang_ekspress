import '../data/mock_subscription_data.dart';
import '../models/subscription_plan_model.dart';
import 'subscription_repository.dart';

// TEMPORARY LOCAL IMPLEMENTATION. WILL BE REPLACED BY API REPOSITORY.
class MockSubscriptionRepository implements SubscriptionRepository {
  @override
  Future<List<SubscriptionPlan>> getActivePlans() async =>
      mockSubscriptionPlans;
}
