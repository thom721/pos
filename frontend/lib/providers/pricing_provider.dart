import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/api/api_client.dart';

class PricingInfo {
  final double monthlyPriceHtg;
  final double monthlyPriceUsd;
  final int trialDays;
  final double extraCaisseHtg;
  final double extraCaisseUsd;
  final String statBusinesses;
  final String statTransactionsDay;
  final String statUptime;

  const PricingInfo({
    required this.monthlyPriceHtg,
    required this.monthlyPriceUsd,
    required this.trialDays,
    required this.extraCaisseHtg,
    required this.extraCaisseUsd,
    this.statBusinesses      = '500+',
    this.statTransactionsDay = '10k+',
    this.statUptime          = '99.9%',
  });

  factory PricingInfo.fromJson(Map<String, dynamic> j) => PricingInfo(
        monthlyPriceHtg:     (j['monthly_price_htg'] as num).toDouble(),
        monthlyPriceUsd:     (j['monthly_price_usd'] as num).toDouble(),
        trialDays:           (j['trial_days'] as num).toInt(),
        extraCaisseHtg:      (j['price_per_extra_caisse_htg'] as num).toDouble(),
        extraCaisseUsd:      (j['price_per_extra_caisse_usd'] as num).toDouble(),
        statBusinesses:      j['stat_businesses']?.toString()       ?? '500+',
        statTransactionsDay: j['stat_transactions_day']?.toString() ?? '10k+',
        statUptime:          j['stat_uptime']?.toString()           ?? '99.9%',
      );

  static const fallback = PricingInfo(
    monthlyPriceHtg: 2500,
    monthlyPriceUsd: 20,
    trialDays:       30,
    extraCaisseHtg:  500,
    extraCaisseUsd:  4,
  );
}

final pricingProvider = FutureProvider<PricingInfo>((ref) async {
  try {
    final res = await dio.get('/api/public/pricing');
    return PricingInfo.fromJson(res.data as Map<String, dynamic>);
  } catch (_) {
    return PricingInfo.fallback;
  }
});
