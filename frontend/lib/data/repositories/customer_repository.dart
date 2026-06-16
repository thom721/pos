import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/customer_model.dart';

class CustomerRepository {
  Future<PaginatedResponse<CustomerModel>> getCustomers({
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final res = await dio.get('/api/customers/', queryParameters: params);
    // API returns a plain list
    if (res.data is List) {
      final list = (res.data as List)
          .map((e) => CustomerModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return PaginatedResponse(
        data: list,
        meta: PaginationMeta(page: 1, limit: limit, total: list.length, pages: 1),
      );
    }
    return PaginatedResponse.fromJson(res.data, CustomerModel.fromJson);
  }

  Future<CustomerModel> createCustomer(Map<String, dynamic> data) async {
    final res = await dio.post('/api/customers/', data: data);
    return CustomerModel.fromJson(res.data);
  }

  Future<CustomerModel> updateCustomer(String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/customers/$id', data: data);
    return CustomerModel.fromJson(res.data);
  }

  Future<void> deleteCustomer(String id) async {
    await dio.delete('/api/customers/$id');
  }
}
