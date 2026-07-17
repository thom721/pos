import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/sale_model.dart';

class SaleRepository {
  Future<PaginatedResponse<SaleModel>> getSales({
    int page = 1,
    int limit = 15,
    String? search,
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (status != null) 'status': status,
      if (dateFrom != null) 'date_from': dateFrom.toIso8601String(),
      if (dateTo != null) 'date_to': dateTo.toIso8601String(),
    };
    final res = await dio.get('/api/sales/', queryParameters: params);
    return PaginatedResponse.fromJson(res.data, SaleModel.fromJson);
  }

  Future<SaleModel> getSale(String id) async {
    final res = await dio.get('/api/sales/$id');
    return SaleModel.fromJson(res.data);
  }

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> data) async {
    final res = await dio.post('/api/sales/', data: data);
    return res.data;
  }

  Future<void> cancelSale(String id) async {
    await dio.patch('/api/sales/$id/cancel');
  }

  Future<Map<String, dynamic>> updateSale(
      String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/sales/$id', data: data);
    return res.data;
  }

  Future<void> addPayment({
    required String referenceType,
    required String referenceId,
    required double amount,
    required String method,
  }) async {
    await dio.post('/api/payments/', data: {
      'reference_type': referenceType,
      'reference_id': referenceId,
      'amount': amount,
      'method': method,
    });
  }
}
