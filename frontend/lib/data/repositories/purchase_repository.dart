import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/purchase_model.dart';

class PurchaseRepository {
  Future<PaginatedResponse<PurchaseModel>> getPurchases({
    int page = 1,
    int limit = 15,
    String? search,
    String? status,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (status != null) 'status': status,
    };
    final res = await dio.get('/api/purchases/', queryParameters: params);
    return PaginatedResponse.fromJson(res.data, PurchaseModel.fromJson);
  }

  Future<PurchaseModel> getPurchase(String id) async {
    final res = await dio.get('/api/purchases/$id');
    return PurchaseModel.fromJson(res.data);
  }

  Future<Map<String, dynamic>> createPurchase(Map<String, dynamic> data) async {
    final res = await dio.post('/api/purchases/', data: data);
    return res.data;
  }
}
