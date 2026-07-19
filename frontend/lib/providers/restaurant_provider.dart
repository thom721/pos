import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';

final restaurantRepositoryProvider = Provider((_) => RestaurantRepository());

// Liste des tables — rechargée via invalidate
final tablesProvider = FutureProvider<List<RestaurantTableModel>>((ref) async {
  return ref.read(restaurantRepositoryProvider).getTables();
});

// Commande ouverte pour une table donnée
final tableOrderProvider = FutureProvider.family<RestaurantOrderModel?, String>(
  (ref, tableId) async {
    return ref.read(restaurantRepositoryProvider).getTableOrder(tableId);
  },
);

// Toutes les commandes ouvertes (vue cuisine)
final openOrdersProvider = FutureProvider<List<RestaurantOrderModel>>((ref) async {
  return ref.read(restaurantRepositoryProvider).getOpenOrders();
});
