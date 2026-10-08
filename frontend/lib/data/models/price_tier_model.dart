/// Palier de prix d'un produit dans un dépôt : à partir de [minQuantity]
/// (unités de vente), le prix unitaire est [price] (HTG, source de vérité).
class PriceTier {
  final String productId;
  final double minQuantity;
  final double price;

  const PriceTier({
    required this.productId,
    required this.minQuantity,
    required this.price,
  });

  // double.tryParse(...toString()), pas `as num` — un backend plus ancien
  // (Decimal sérialisé en chaîne JSON par Pydantic, ex: "3.00") planterait
  // sinon sur un simple cast de type.
  factory PriceTier.fromJson(Map<String, dynamic> json) => PriceTier(
        productId: json['product_id']?.toString() ?? '',
        minQuantity: double.tryParse(json['min_quantity']?.toString() ?? '') ?? 0,
        price: double.tryParse(json['price']?.toString() ?? '') ?? 0,
      );

  /// Regroupe les paliers par produit, triés par seuil croissant.
  static Map<String, List<PriceTier>> groupByProduct(Iterable<PriceTier> tiers) {
    final map = <String, List<PriceTier>>{};
    for (final t in tiers) {
      map.putIfAbsent(t.productId, () => []).add(t);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.minQuantity.compareTo(b.minQuantity));
    }
    return map;
  }
}
