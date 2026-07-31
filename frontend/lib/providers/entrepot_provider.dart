import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/stock_movement_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/repositories/entrepot_repository.dart';

final entrepotRepositoryProvider = Provider((ref) => EntrepotRepository());

final entrepotProvider =
    FutureProvider.autoDispose<WarehouseModel?>((ref) async {
  return ref.read(entrepotRepositoryProvider).getEntrepot();
});

final entrepotProductSearchProvider = StateProvider<String>((ref) => '');

final entrepotProductsProvider =
    FutureProvider.autoDispose<PaginatedResponse<ProductModel>>((ref) async {
  final entrepot = await ref.watch(entrepotProvider.future);
  if (entrepot == null) {
    return PaginatedResponse<ProductModel>(
      data: const [],
      meta: PaginationMeta(page: 1, limit: 20, total: 0, pages: 1),
    );
  }
  final search = ref.watch(entrepotProductSearchProvider);
  return ref.read(entrepotRepositoryProvider).getProducts(
        search: search.isEmpty ? null : search,
      );
});

final entrepotMovementsProvider =
    FutureProvider.autoDispose<PaginatedResponse<StockMovementModel>>((ref) async {
  final entrepot = await ref.watch(entrepotProvider.future);
  if (entrepot == null) {
    return PaginatedResponse<StockMovementModel>(
      data: const [],
      meta: PaginationMeta(page: 1, limit: 20, total: 0, pages: 1),
    );
  }
  return ref.read(entrepotRepositoryProvider).getMovements(warehouseId: entrepot.id);
});
