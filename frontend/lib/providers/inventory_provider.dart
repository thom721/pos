import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/inventory_model.dart';
import 'package:pos_connect/data/repositories/inventory_repository.dart';

final inventoryListProvider = FutureProvider<List<InventoryModel>>((ref) async {
  return InventoryRepository().listInventories();
});

final inventoryDetailProvider =
    FutureProvider.family<InventoryModel, String>((ref, id) async {
  return InventoryRepository().getInventory(id);
});

final categoriesProvider = FutureProvider<List<CategoryItem>>((ref) async {
  return InventoryRepository().getCategories();
});
