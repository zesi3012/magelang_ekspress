import '../models/subscription_plan_model.dart';

// TEMPORARY MOCK DATA. WILL BE REPLACED BY API/BACKEND.
const mockSubscriptionPlans = <SubscriptionPlan>[
  SubscriptionPlan(
    id: 'premium_1_month',
    name: 'Premium 1 Bulan',
    durationDays: 30,
    price: 49000,
    benefits: [
      'Artikel premium',
      'E-paper harian',
      'Mode artikel',
      'Simpan artikel',
    ],
  ),
  SubscriptionPlan(
    id: 'premium_3_month',
    name: 'Premium 3 Bulan',
    durationDays: 90,
    price: 129000,
    benefits: ['Semua fitur 1 bulan', 'Harga lebih hemat', 'Arsip 90 hari'],
  ),
  SubscriptionPlan(
    id: 'premium_6_month',
    name: 'Premium 6 Bulan',
    durationDays: 180,
    price: 249000,
    benefits: [
      'Akses menengah untuk pembaca rutin',
      'Artikel premium',
      'E-paper',
    ],
  ),
  SubscriptionPlan(
    id: 'premium_1_year',
    name: 'Premium 1 Tahun',
    durationDays: 365,
    price: 499000,
    benefits: ['Akses tahunan', 'Arsip lebih panjang', 'Harga terbaik'],
  ),
];
