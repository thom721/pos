import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/models/stock_movement_model.dart';

class EntrepotRepository {
  Future<WarehouseModel?> getEntrepot() async {
    final res = await dio.get('/api/entrepot/');
    if (res.data == null) return null;
    return WarehouseModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<WarehouseModel> createEntrepot({String name = 'Entrepôt'}) async {
    final res = await dio.post('/api/entrepot/', data: {'name': name});
    return WarehouseModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<ProductModel>> getProducts({
    int page = 1,
    int perPage = 20,
    String? search,
  }) async {
    final res = await dio.get('/api/entrepot/products', queryParameters: {
      'page': page,
      'per_page': perPage,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return PaginatedResponse.fromJson(res.data, ProductModel.fromJson);
  }

  Future<ProductModel> adjustStock(String productId, double quantity, {String? reason}) async {
    final res = await dio.post('/api/entrepot/products/$productId/adjust', data: {
      'quantity': quantity,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return ProductModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> distribute(
    String productId,
    List<Map<String, dynamic>> allocations,
  ) async {
    await dio.post('/api/entrepot/products/$productId/distribute', data: {
      'allocations': allocations,
    });
  }

  Future<PaginatedResponse<StockMovementModel>> getMovements({
    required String warehouseId,
    String? productId,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await dio.get('/api/stock-movements/', queryParameters: {
      'warehouse_id': warehouseId,
      if (productId != null && productId.isNotEmpty) 'product_id': productId,
      'page': page,
      'limit': limit,
    });
    return PaginatedResponse.fromJson(res.data, StockMovementModel.fromJson);
  }
}
