import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/repositories/product_repository.dart';

final productRepositoryProvider = Provider((ref) => ProductRepository());

final productSearchProvider = StateProvider<String>((ref) => '');

final productsProvider =
    FutureProvider.autoDispose<PaginatedResponse<ProductModel>>((ref) async {
  final search = ref.watch(productSearchProvider);
  final repo = ref.read(productRepositoryProvider);
  return repo.getProducts(search: search.isEmpty ? null : search);
});

// Pour la recherche POS (caisse)
final posProductSearchProvider = StateProvider<String>((ref) => '');

final posProductsProvider =
    FutureProvider.autoDispose<PaginatedResponse<ProductModel>>((ref) async {
  final search = ref.watch(posProductSearchProvider);
  final repo = ref.read(productRepositoryProvider);
  return repo.searchForSale(search: search.isEmpty ? null : search, perPage: 20);
});
