import 'package:dio/dio.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/customer_model.dart';
import 'package:pos_connect/services/local_db_service.dart';

bool _isOffline(Object e) =>
    e is DioException &&
    (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.unknown);

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
    try {
      final res = await dio.get('/api/customers/', queryParameters: params);
      PaginatedResponse<CustomerModel> result;
      if (res.data is List) {
        final list = (res.data as List)
            .map((e) => CustomerModel.fromJson(e as Map<String, dynamic>))
            .toList();
        result = PaginatedResponse(
          data: list,
          meta: PaginationMeta(page: 1, limit: limit, total: list.length, pages: 1),
        );
      } else {
        result = PaginatedResponse.fromJson(res.data, CustomerModel.fromJson);
      }
      LocalDbService.instance.upsertCustomers(result.data).ignore();
      return result;
    } catch (e) {
      if (_isOffline(e)) {
        return LocalDbService.instance.getCustomers(
          search: search, page: page, limit: limit,
        );
      }
      rethrow;
    }
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
