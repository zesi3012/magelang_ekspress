import '../models/subscription_plan_model.dart';
import '../services/reader_api_client.dart';
import 'subscription_repository.dart';

class ApiSubscriptionRepository implements SubscriptionRepository {
  ApiSubscriptionRepository({required this.client});

  final ReaderApiClient client;
  bool _mockActive = false;

  @override
  void setMockSubscriptionActive(bool value) {
    _mockActive = value;
  }

  @override
  Future<List<SubscriptionPlan>> getActivePlans() async {
    try {
      // Gunakan method yang SUDAH ADA di ReaderApiClient
      // Method ini return List<SubscriptionPlan> langsung
      final plans = await client.getSubscriptionPlans();
      
      if (plans.isEmpty) {
        // Jika backend kosong, pakai default
        return _defaultPlans();
      }
      
      return plans;
    } catch (e) {
      // Jika backend error (offline/404/dll), fallback ke default
      return _defaultPlans();
    }
  }

  @override
  Future<Map<String, dynamic>> checkout(
    String planId, {
    required String paymentMethod,
  }) {
    return client.checkout(planId, paymentMethod: paymentMethod);
  }

  /// Paket default sebagai fallback jika backend belum tersedia
  List<SubscriptionPlan> _defaultPlans() => const [
        SubscriptionPlan(
          id: 'premium_1_month',
          name: 'Premium 1 Bulan',
          durationDays: 30,
          price: 49000,
          benefits: [
            'Artikel Premium Tanpa Batas',
            'E-Paper Harian',
            'Arsip Edisi Lengkap',
          ],
        ),
        SubscriptionPlan(
          id: 'premium_3_months',
          name: 'Premium 3 Bulan',
          durationDays: 90,
          price: 129000,
          benefits: [
            'Artikel Premium Tanpa Batas',
            'E-Paper Harian',
            'Arsip Edisi Lengkap',
            'Tanpa Iklan Mengganggu',
          ],
        ),
        SubscriptionPlan(
          id: 'premium_6_months',
          name: 'Premium 6 Bulan',
          durationDays: 180,
          price: 249000,
          benefits: [
            'Artikel Premium Tanpa Batas',
            'E-Paper Harian',
            'Arsip Edisi Lengkap',
            'Tanpa Iklan Mengganggu',
            'Prioritas Dukungan',
          ],
        ),
        SubscriptionPlan(
          id: 'premium_1_year',
          name: 'Premium 1 Tahun',
          durationDays: 365,
          price: 499000,
          benefits: [
            'Artikel Premium Tanpa Batas',
            'E-Paper Harian',
            'Arsip Edisi Lengkap',
            'Tanpa Iklan Mengganggu',
            'Prioritas Dukungan',
            'Baca di Semua Perangkat',
          ],
        ),
      ];
}