import '../models/subscription_plan_model.dart';

abstract interface class SubscriptionRepository {
  Future<List<SubscriptionPlan>> getActivePlans();
}
