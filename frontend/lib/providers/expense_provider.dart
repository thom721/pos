import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/models/expense_model.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/repositories/expense_repository.dart';

final expenseRepositoryProvider = Provider((ref) => ExpenseRepository());

final expenseSearchProvider = StateProvider<String>((ref) => '');

final expensesProvider =
    FutureProvider.autoDispose<PaginatedResponse<ExpenseModel>>((ref) async {
  final search = ref.watch(expenseSearchProvider);
  final repo = ref.read(expenseRepositoryProvider);
  return repo.getExpenses(search: search.isEmpty ? null : search);
});
