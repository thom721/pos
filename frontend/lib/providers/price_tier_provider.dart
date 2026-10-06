import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/price_tier_model.dart';
import 'package:pos_connect/data/repositories/product_repository.dart';
import 'package:pos_connect/providers/sync_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

/// Paliers du dépôt actif, groupés par produit.
/// En ligne : API (toujours à jour). Hors-ligne : cache local (base SQLite),
/// rempli par la synchro. Le serveur refait le calcul à la vente de toute façon.
final priceTiersProvider = FutureProvider.autoDispose<Map<String, List<PriceTier>>>((ref) async {
  final warehouseId = ref.watch(activeWarehouseProvider)?.id;
  ref.watch(syncEpochProvider);
  if (warehouseId == null) return const {};
  try {
    return PriceTier.groupByProduct(await ProductRepository().getAllPriceTiers(warehouseId));
  } catch (_) {
    return PriceTier.groupByProduct(await ProductRepository().getLocalPriceTiers(warehouseId));
  }
});
