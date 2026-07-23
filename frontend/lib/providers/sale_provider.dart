import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/date_utils.dart' show haitiTodayStartUtc;
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/data/repositories/sale_repository.dart';
import 'package:pos_connect/providers/auth_provider.dart';
import 'package:pos_connect/providers/sync_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

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
  ref.watch(syncEpochProvider); // rebuild après chaque sync SQLite
  final params = ref.watch(saleListParamsProvider);
  final activeWh = ref.watch(activeWarehouseProvider)?.id;
  final user = ref.watch(authProvider).user;
  final repo = ref.read(saleRepositoryProvider);

  // Les non-admins/managers ne voient que leurs propres ventes (Android: SQLite,
  // web/macOS: filtré côté serveur via JWT).
  final canSeeAll = user == null || user.isAdmin || user.hasRole('manager');
  final cashierId = canSeeAll ? null : user.id;

  // Pour les caissiers : ne pas filtrer par warehouseId — cashierId suffit.
  // Si le dépôt actif a changé (UUID recréé, fallback), les ventes SQLite
  // restent visibles car elles portent l'ancien warehouse_id.
  final warehouseId = canSeeAll ? activeWh : null;

  return repo.getSales(
    page: params.page,
    search: params.search,
    status: params.status,
    warehouseId: warehouseId,
    cashierId: cashierId,
  );
});

final saleDetailProvider =
    FutureProvider.autoDispose.family<SaleModel, String>((ref, id) async {
  final repo = ref.read(saleRepositoryProvider);
  return repo.getSale(id);
});

/// For the dashboard: if isCashier=true, restrict to today (backend already
/// enforces user_id filter for cashiers).
final dashboardSalesProvider =
    FutureProvider.autoDispose.family<PaginatedResponse<SaleModel>, bool>(
        (ref, isCashier) async {
  ref.watch(syncEpochProvider); // rebuild après chaque sync SQLite
  final warehouseId = ref.watch(activeWarehouseProvider)?.id;
  final repo = ref.read(saleRepositoryProvider);
  final todayUtc = haitiTodayStartUtc();
  return repo.getSales(
    limit: 50,
    dateFrom: todayUtc,
    dateTo: todayUtc.add(const Duration(days: 1)),
    warehouseId: warehouseId,
  );
});
