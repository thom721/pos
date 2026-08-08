import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/stock_movement_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/repositories/entrepot_repository.dart';

final entrepotRepositoryProvider = Provider((ref) => EntrepotRepository());

// Un tenant peut avoir plusieurs entrepôts — liste complète.
final entrepotsProvider =
    FutureProvider.autoDispose<List<WarehouseModel>>((ref) async {
  return ref.read(entrepotRepositoryProvider).listEntrepots();
});

// Entrepôt actuellement sélectionné dans l'écran Entrepôt — pas de
// persistance (contrairement à activeWarehouseProvider) : chaque ouverture
// de l'écran repart du premier entrepôt de la liste (voir entrepot_screen.dart).
final activeEntrepotProvider = StateProvider<WarehouseModel?>((ref) => null);

final entrepotProductSearchProvider = StateProvider<String>((ref) => '');

final entrepotProductsProvider =
    FutureProvider.autoDispose<PaginatedResponse<ProductModel>>((ref) async {
  final entrepot = ref.watch(activeEntrepotProvider);
  if (entrepot == null) {
    return PaginatedResponse<ProductModel>(
      data: const [],
      meta: PaginationMeta(page: 1, limit: 20, total: 0, pages: 1),
    );
  }
  final search = ref.watch(entrepotProductSearchProvider);
  return ref.read(entrepotRepositoryProvider).getProducts(
        entrepotId: entrepot.id,
        search: search.isEmpty ? null : search,
      );
});

// Filtre produit optionnel pour l'onglet Historique — porte id + nom pour
// affichage du chip de filtre actif sans requête supplémentaire.
// Pas de autoDispose : la valeur est écrite via ref.read() juste avant la
// navigation (aucun watcher actif à cet instant), un autoDispose la
// réinitialiserait avant même que l'écran cible n'ait pu la lire.
final entrepotMovementProductFilterProvider =
    StateProvider<ProductModel?>((ref) => null);

// Onglet à ouvrir à l'arrivée sur l'écran Entrepôt (0 = Produits, 1 =
// Historique) — utilisé par la page Produits pour arriver directement sur
// l'historique d'un produit donné (voir aussi le filtre ci-dessus).
// Remis à 0 par _EntrepotContent une fois consommé (voir son initState).
final entrepotInitialTabProvider = StateProvider<int>((ref) => 0);

final entrepotMovementsProvider =
    FutureProvider.autoDispose<PaginatedResponse<StockMovementModel>>((ref) async {
  final entrepot = ref.watch(activeEntrepotProvider);
  if (entrepot == null) {
    return PaginatedResponse<StockMovementModel>(
      data: const [],
      meta: PaginationMeta(page: 1, limit: 20, total: 0, pages: 1),
    );
  }
  final productFilter = ref.watch(entrepotMovementProductFilterProvider);
  return ref.read(entrepotRepositoryProvider).getMovements(
        warehouseId: entrepot.id,
        productId: productFilter?.id,
      );
});
