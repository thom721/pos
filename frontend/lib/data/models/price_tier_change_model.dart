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
}
