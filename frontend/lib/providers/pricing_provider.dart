import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/api/api_client.dart';

class PricingPlan {
  final String id;
  final String name;
  final String subtitle;
  final String priceHtg;
  final String priceUsd;
  final String period;
  final bool highlighted;
  final List<String> features;

  const PricingPlan({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.priceHtg,
    required this.priceUsd,
    required this.period,
    required this.highlighted,
    required this.features,
  });

  factory PricingPlan.fromJson(Map<String, dynamic> j) => PricingPlan(
        id:          j['id']?.toString()       ?? '',
        name:        j['name']?.toString()     ?? '',
        subtitle:    j['subtitle']?.toString() ?? '',
        priceHtg:    j['price_htg']?.toString() ?? '',
        priceUsd:    j['price_usd']?.toString() ?? '',
        period:      j['period']?.toString()   ?? '',
        highlighted: j['highlighted'] == true,
        features:    (j['features'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subtitle': subtitle,
        'price_htg': priceHtg.isEmpty ? null : priceHtg,
        'price_usd': priceUsd.isEmpty ? null : priceUsd,
        'period': period,
        'highlighted': highlighted,
        'visible': true,
        'features': features,
      };
}

class PricingInfo {
  final double monthlyPriceHtg;
  final double monthlyPriceUsd;
  final int trialDays;
  final double extraCaisseHtg;
  final double extraCaisseUsd;
  final String statBusinesses;
  final String statTransactionsDay;
  final String statUptime;
  final List<PricingPlan> plans;

  const PricingInfo({
    required this.monthlyPriceHtg,
    required this.monthlyPriceUsd,
    required this.trialDays,
    required this.extraCaisseHtg,
    required this.extraCaisseUsd,
    this.statBusinesses      = '500+',
    this.statTransactionsDay = '10k+',
    this.statUptime          = '99.9%',
    this.plans               = const [],
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
        plans: (j['plans'] as List?)
                ?.map((e) => PricingPlan.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  static final fallback = PricingInfo(
    monthlyPriceHtg: 2500,
    monthlyPriceUsd: 20,
    trialDays:       30,
    extraCaisseHtg:  500,
    extraCaisseUsd:  4,
    plans: [
      PricingPlan(
        id: 'starter', name: 'Starter', subtitle: 'Pour découvrir',
        priceHtg: 'Gratuit', priceUsd: '',
        period: '30 jours d\'essai', highlighted: false,
        features: const ['1 dépôt', '1 caisse', 'Ventes & encaissements', 'Gestion clients', 'Rapports de base', 'Support email', 'Aucune carte requise'],
      ),
      PricingPlan(
        id: 'pro', name: 'Pro', subtitle: 'Basé sur le nombre de caisses',
        priceHtg: '2 500 HTG', priceUsd: '20 USD',
        period: 'par mois · 1 dépôt', highlighted: true,
        features: const ['1 dépôt inclus', '3 caisses incluses', 'Mode restaurant', 'Sync cloud temps réel', 'Rapports avancés', 'Multi-plateformes', 'Support prioritaire'],
      ),
      PricingPlan(
        id: 'enterprise', name: 'Enterprise', subtitle: 'Pour les grandes enseignes',
        priceHtg: 'Sur devis', priceUsd: '',
        period: '', highlighted: false,
        features: const ['Dépôts illimités', 'Caisses illimitées', 'API REST complète', 'White label', 'Formation sur site', 'Gestionnaire dédié', 'SLA 99.9%'],
      ),
    ],
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
