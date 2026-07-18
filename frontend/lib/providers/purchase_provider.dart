import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/purchase_model.dart';
import 'package:pos_connect/data/repositories/purchase_repository.dart';
import 'package:pos_connect/providers/sync_provider.dart';

final purchaseRepositoryProvider = Provider((ref) => PurchaseRepository());

class PurchaseListParams {
  final int page;
  final String? search;
  final String? status;

  const PurchaseListParams({this.page = 1, this.search, this.status});

  @override
  bool operator ==(Object other) =>
      other is PurchaseListParams &&
      page == other.page &&
      search == other.search &&
      status == other.status;

  @override
  int get hashCode => Object.hash(page, search, status);
}

final purchaseListParamsProvider =
    StateProvider((ref) => const PurchaseListParams());

final purchasesProvider =
    FutureProvider.autoDispose<PaginatedResponse<PurchaseModel>>((ref) async {
  ref.watch(syncEpochProvider); // rebuild après chaque sync SQLite
  final params = ref.watch(purchaseListParamsProvider);
  final repo = ref.read(purchaseRepositoryProvider);
  return repo.getPurchases(
    page: params.page,
    search: params.search,
    status: params.status,
  );
});
