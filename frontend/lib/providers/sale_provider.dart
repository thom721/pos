import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/data/repositories/sale_repository.dart';

final saleRepositoryProvider = Provider((ref) => SaleRepository());

class SaleListParams {
  final int page;
  final String? search;
  final String? status;

  const SaleListParams({this.page = 1, this.search, this.status});

  @override
  bool operator ==(Object other) =>
      other is SaleListParams &&
      page == other.page &&
      search == other.search &&
      status == other.status;

  @override
  int get hashCode => Object.hash(page, search, status);
}

final saleListParamsProvider =
    StateProvider((ref) => const SaleListParams());

final salesProvider =
    FutureProvider.autoDispose<PaginatedResponse<SaleModel>>((ref) async {
  final params = ref.watch(saleListParamsProvider);
  final repo = ref.read(saleRepositoryProvider);
  return repo.getSales(
    page: params.page,
    search: params.search,
    status: params.status,
  );
});

final saleDetailProvider =
    FutureProvider.autoDispose.family<SaleModel, String>((ref, id) async {
  final repo = ref.read(saleRepositoryProvider);
  return repo.getSale(id);
});
