import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/customer_model.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/repositories/customer_repository.dart';
import 'package:pos_connect/providers/sync_provider.dart';
import 'package:pos_connect/providers/warehouse_provider.dart';

final customerRepositoryProvider = Provider((ref) => CustomerRepository());

final customerSearchProvider = StateProvider<String>((ref) => '');

final customersProvider =
    FutureProvider.autoDispose<PaginatedResponse<CustomerModel>>((ref) async {
  ref.watch(syncEpochProvider); // rebuild après chaque sync SQLite
  final search = ref.watch(customerSearchProvider);
  // Clients du dépôt actif + clients partagés (warehouse_id NULL).
  final warehouseId = ref.watch(activeWarehouseProvider)?.id;
  final repo = ref.read(customerRepositoryProvider);
  return repo.getCustomers(
    search: search.isEmpty ? null : search,
    warehouseId: warehouseId,
  );
});
