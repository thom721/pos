import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/supplier_model.dart';
import 'package:pos_connect/data/repositories/supplier_repository.dart';

final supplierRepositoryProvider = Provider((ref) => SupplierRepository());

final supplierSearchProvider = StateProvider<String>((ref) => '');

final suppliersProvider =
    FutureProvider.autoDispose<PaginatedResponse<SupplierModel>>((ref) async {
  final search = ref.watch(supplierSearchProvider);
  final repo = ref.read(supplierRepositoryProvider);
  return repo.getSuppliers(search: search.isEmpty ? null : search);
});
