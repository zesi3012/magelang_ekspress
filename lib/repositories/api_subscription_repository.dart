import '../models/subscription_plan_model.dart';
import '../services/reader_api_client.dart';
import 'subscription_repository.dart';

class ApiSubscriptionRepository implements SubscriptionRepository {
  ApiSubscriptionRepository({ReaderApiClient? client})
    : client = client ?? ReaderApiClient();

  final ReaderApiClient client;

  @override
  Future<List<SubscriptionPlan>> getActivePlans() =>
      client.getSubscriptionPlans();
}
