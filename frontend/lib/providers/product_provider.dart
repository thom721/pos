import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/repositories/product_repository.dart';
import 'package:pos_connect/providers/sync_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

final productRepositoryProvider = Provider((ref) => ProductRepository());

final productSearchProvider = StateProvider<String>((ref) => '');

final productsProvider =
    FutureProvider.autoDispose<PaginatedResponse<ProductModel>>((ref) async {
  ref.watch(syncEpochProvider); // rebuild après chaque sync SQLite
  final search = ref.watch(productSearchProvider);
  // Le stock affiché reflète le dépôt actif ("Tous les business" = global).
  final warehouseId = ref.watch(activeWarehouseProvider)?.id;
  final repo = ref.read(productRepositoryProvider);
  return repo.getProducts(
    search: search.isEmpty ? null : search,
    warehouseId: warehouseId,
  );
});

// Pour la recherche POS (caisse)
final posProductSearchProvider = StateProvider<String>((ref) => '');

final posProductsProvider =
    FutureProvider.autoDispose<PaginatedResponse<ProductModel>>((ref) async {
  ref.watch(syncEpochProvider); // rebuild après chaque sync SQLite
  final search = ref.watch(posProductSearchProvider);
  // Le prix affiché/vendu reflète le dépôt actif s'il a un prix spécifique.
  final warehouseId = ref.watch(activeWarehouseProvider)?.id;
  final repo = ref.read(productRepositoryProvider);
  return repo.searchForSale(
    search: search.isEmpty ? null : search,
    perPage: 20,
    warehouseId: warehouseId,
  );
});
