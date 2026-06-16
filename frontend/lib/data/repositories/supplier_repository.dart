import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/supplier_model.dart';

class SupplierRepository {
  Future<PaginatedResponse<SupplierModel>> getSuppliers({
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final res = await dio.get('/api/suppliers/', queryParameters: params);
    // API returns a plain list
    if (res.data is List) {
      final list = (res.data as List)
          .map((e) => SupplierModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return PaginatedResponse(
        data: list,
        meta: PaginationMeta(page: 1, limit: limit, total: list.length, pages: 1),
      );
    }
    return PaginatedResponse.fromJson(res.data, SupplierModel.fromJson);
  }

  Future<SupplierModel> createSupplier(Map<String, dynamic> data) async {
    final res = await dio.post('/api/suppliers/', data: data);
    return SupplierModel.fromJson(res.data);
  }

  Future<SupplierModel> updateSupplier(String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/suppliers/$id', data: data);
    return SupplierModel.fromJson(res.data);
  }

  Future<void> deleteSupplier(String id) async {
    await dio.delete('/api/suppliers/$id');
  }
}
