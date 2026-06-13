import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/customer_model.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/repositories/customer_repository.dart';

final customerRepositoryProvider = Provider((ref) => CustomerRepository());

final customerSearchProvider = StateProvider<String>((ref) => '');

final customersProvider =
    FutureProvider.autoDispose<PaginatedResponse<CustomerModel>>((ref) async {
  final search = ref.watch(customerSearchProvider);
  final repo = ref.read(customerRepositoryProvider);
  return repo.getCustomers(search: search.isEmpty ? null : search);
});
