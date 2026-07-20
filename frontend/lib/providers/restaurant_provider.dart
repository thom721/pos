import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

final restaurantRepositoryProvider = Provider((_) => RestaurantRepository());

// Liste des tables — rechargée via invalidate
final tablesProvider = FutureProvider<List<RestaurantTableModel>>((ref) async {
  final warehouseId = ref.watch(activeWarehouseProvider)?.id;
  return ref.read(restaurantRepositoryProvider).getTables(warehouseId: warehouseId);
});

// Commande ouverte pour une table donnée
final tableOrderProvider = FutureProvider.family<RestaurantOrderModel?, String>(
  (ref, tableId) async {
    return ref.read(restaurantRepositoryProvider).getTableOrder(tableId);
  },
);

// Toutes les commandes ouvertes (vue cuisine / commandes) — filtrées par dépôt actif
final openOrdersProvider = FutureProvider<List<RestaurantOrderModel>>((ref) async {
  final warehouseId = ref.watch(activeWarehouseProvider)?.id;
  return ref.read(restaurantRepositoryProvider).getOpenOrders(warehouseId: warehouseId);
});
