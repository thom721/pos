import 'package:pos_connect/data/models/price_tier_model.dart';

/// Un changement de paliers de prix détecté côté appareil (avant/après),
/// en comparant deux relevés successifs de /api/price-tiers — voir
/// app.dart::_checkPriceTierChangeFiche. Construit directement en Dart,
/// jamais désérialisé depuis l'API (pas de journal serveur : ça doit
/// marcher identiquement avec ou sans serveur local intermédiaire).
class PriceTierChangeModel {
  final String productId;
  final String productName;
  final String warehouseId;
  final List<PriceTier> oldTiers;
  final List<PriceTier> newTiers;
  final DateTime createdAt;

  const PriceTierChangeModel({
    required this.productId,
    required this.productName,
    required this.warehouseId,
    required this.oldTiers,
    required this.newTiers,
    required this.createdAt,
  });

  /// Instantané sérialisable (JSON) des paliers actuels, un par produit —
  /// mémorisé en SharedPreferences et comparé au cycle de synchro suivant
  /// par [diffSnapshots] pour détecter ce qu'il faut imprimer.
  static Map<String, dynamic> buildSnapshot(Iterable<PriceTier> tiers) {
    final byProduct = PriceTier.groupByProduct(tiers);
    return {
      for (final entry in byProduct.entries)
        entry.key: {
          'name': entry.value.first.productName ?? '',
          'tiers': entry.value.map((t) => {'q': t.minQuantity, 'p': t.price}).toList(),
        },
    };
  }

  static List<PriceTier> _tiersOf(String productId, Map<String, dynamic>? entry) {
    if (entry == null) return const [];
    return (entry['tiers'] as List)
        .map((t) => PriceTier(
              productId: productId,
              minQuantity: (t['q'] as num).toDouble(),
              price: (t['p'] as num).toDouble(),
            ))
        .toList();
  }

  static bool _sameTiers(List<PriceTier> a, List<PriceTier> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].minQuantity != b[i].minQuantity || a[i].price != b[i].price) return false;
    }
    return true;
  }

  /// Compare deux instantanés successifs (voir [buildSnapshot]) et renvoie
  /// un changement par produit dont les paliers diffèrent entre les deux.
  static List<PriceTierChangeModel> diffSnapshots(
    Map<String, dynamic> previous,
    Map<String, dynamic> current,
    String warehouseId,
  ) {
    final changes = <PriceTierChangeModel>[];
    for (final pid in {...previous.keys, ...current.keys}) {
      final prevEntry = previous[pid] as Map<String, dynamic>?;
      final curEntry = current[pid] as Map<String, dynamic>?;
      final oldTiers = _tiersOf(pid, prevEntry);
      final newTiers = _tiersOf(pid, curEntry);
      if (_sameTiers(oldTiers, newTiers)) continue;
      final name = (curEntry?['name'] as String?)?.isNotEmpty == true
          ? curEntry!['name'] as String
          : (prevEntry?['name'] as String? ?? '—');
      changes.add(PriceTierChangeModel(
        productId: pid,
        productName: name,
        warehouseId: warehouseId,
        oldTiers: oldTiers,
        newTiers: newTiers,
        createdAt: DateTime.now(),
      ));
    }
    return changes;
  }
}
