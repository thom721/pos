import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/return_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/data/models/purchase_model.dart';
import 'package:pos_connect/data/models/paginated_response.dart';

class ReturnRepository {
  Future<List<ReturnModel>> getReturns({
    String? returnType,
    int page = 1,
    int limit = 50,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (returnType != null) 'return_type': returnType,
    };
    final res = await dio.get('/api/returns/', queryParameters: params);
    final data = res.data as Map<String, dynamic>;
    return (data['data'] as List? ?? [])
        .map((e) => ReturnModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createSaleReturn({
    required String saleId,
    required List<Map<String, dynamic>> items,
    required double refundAmount,
    String? reason,
  }) async {
    await dio.post('/api/returns/sale', data: {
      'sale_id': saleId,
      'items': items,
      'refund_amount': refundAmount,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  Future<void> createPurchaseReturn({
    required String purchaseId,
    required List<Map<String, dynamic>> items,
    String? reason,
  }) async {
    await dio.post('/api/returns/purchase', data: {
      'purchase_id': purchaseId,
      'items': items,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  Future<PaginatedResponse<SaleModel>> searchSales(String query) async {
    final res = await dio.get('/api/sales/', queryParameters: {
      'search': query,
      'limit': 5,
    });
    return PaginatedResponse.fromJson(res.data, SaleModel.fromJson);
  }

  Future<PaginatedResponse<PurchaseModel>> searchPurchases(String query) async {
    final res = await dio.get('/api/purchases/', queryParameters: {
      'search': query,
      'limit': 5,
    });
    return PaginatedResponse.fromJson(res.data, PurchaseModel.fromJson);
  }
}
