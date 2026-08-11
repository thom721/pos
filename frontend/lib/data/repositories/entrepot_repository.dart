import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/models/stock_movement_model.dart';
import 'package:pos_connect/data/models/transfer_receipt_model.dart';

class EntrepotRepository {
  Future<List<WarehouseModel>> listEntrepots() async {
    final res = await dio.get('/api/entrepot/');
    return (res.data as List)
        .map((e) => WarehouseModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WarehouseModel> createEntrepot({
    String name = 'Entrepôt',
    String? address,
    String? linkedWarehouseId,
  }) async {
    final res = await dio.post('/api/entrepot/', data: {
      'name': name,
      if (address != null && address.isNotEmpty) 'address': address,
      if (linkedWarehouseId != null) 'linked_warehouse_id': linkedWarehouseId,
    });
    return WarehouseModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// [linkedWarehouseId] : passer une chaîne vide pour détacher l'entrepôt
  /// (le repasse cloud-only) — omettre le champ pour ne pas y toucher.
  Future<WarehouseModel> updateEntrepot(
    String entrepotId, {
    String? name,
    String? address,
    String? linkedWarehouseId,
    bool unlink = false,
  }) async {
    final res = await dio.patch('/api/entrepot/$entrepotId', data: {
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (unlink) 'linked_warehouse_id': null
      else if (linkedWarehouseId != null) 'linked_warehouse_id': linkedWarehouseId,
    });
    return WarehouseModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<ProductModel>> getProducts({
    required String entrepotId,
    int page = 1,
    int perPage = 20,
    String? search,
  }) async {
    final res = await dio.get('/api/entrepot/$entrepotId/products', queryParameters: {
      'page': page,
      'per_page': perPage,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return PaginatedResponse.fromJson(res.data, ProductModel.fromJson);
  }

  Future<ProductModel> adjustStock(
    String entrepotId,
    String productId,
    double quantity, {
    String? reason,
  }) async {
    final res = await dio.post('/api/entrepot/$entrepotId/products/$productId/adjust', data: {
      'quantity': quantity,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return ProductModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> distribute(
    String entrepotId,
    String productId,
    List<Map<String, dynamic>> allocations,
  ) async {
    await dio.post('/api/entrepot/$entrepotId/products/$productId/distribute', data: {
      'allocations': allocations,
    });
  }

  /// Envoie du stock VERS un entrepôt, depuis un dépôt classique
  /// (« retourner à l'entrepôt ») ou un autre entrepôt (transfert).
  Future<TransferReceiptModel> transferIn(
    String entrepotId,
    String productId,
    String sourceWarehouseId,
    double quantity, {
    String? reason,
  }) async {
    final res = await dio.post(
      '/api/entrepot/$entrepotId/products/$productId/transfer-in',
      data: {
        'source_warehouse_id': sourceWarehouseId,
        'quantity': quantity,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return TransferReceiptModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// [warehouseId] optionnel — omis, l'historique couvre tous les dépôts du
  /// tenant (utilisé pour l'historique produit depuis la page Produits, hors
  /// contexte Entrepôt qui filtre toujours sur un warehouseId précis).
  Future<PaginatedResponse<StockMovementModel>> getMovements({
    String? warehouseId,
    String? productId,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await dio.get('/api/stock-movements/', queryParameters: {
      if (warehouseId != null && warehouseId.isNotEmpty) 'warehouse_id': warehouseId,
      if (productId != null && productId.isNotEmpty) 'product_id': productId,
      'page': page,
      'limit': limit,
    });
    return PaginatedResponse.fromJson(res.data, StockMovementModel.fromJson);
  }
}
