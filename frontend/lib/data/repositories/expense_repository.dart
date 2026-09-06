import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/expense_model.dart';
import 'package:pos_connect/data/models/paginated_response.dart';

class ExpenseRepository {
  Future<PaginatedResponse<ExpenseModel>> getExpenses({
    int page = 1,
    int limit = 20,
    String? search,
    String? category,
    String? warehouseId,
  }) async {
    final res = await dio.get('/api/expenses/', queryParameters: {
      'page': page,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (category != null && category.isNotEmpty) 'category': category,
      if (warehouseId != null && warehouseId.isNotEmpty) 'warehouse_id': warehouseId,
    });
    return PaginatedResponse.fromJson(res.data, ExpenseModel.fromJson);
  }

  Future<ExpenseModel> createExpense(Map<String, dynamic> data) async {
    final res = await dio.post('/api/expenses/', data: data);
    return ExpenseModel.fromJson(res.data);
  }

  Future<ExpenseModel> updateExpense(String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/expenses/$id', data: data);
    return ExpenseModel.fromJson(res.data);
  }

  Future<void> deleteExpense(String id) async {
    await dio.delete('/api/expenses/$id');
  }
}
