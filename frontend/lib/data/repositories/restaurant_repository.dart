import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';

class RestaurantRepository {
  // ── Waiters ─────────────────────────────────────────────────────────────────

  Future<List<RestaurantWaiterModel>> getWaiters() async {
    final res = await dio.get('/api/restaurant/waiters/');
    return (res.data as List)
        .map((e) => RestaurantWaiterModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RestaurantTableModel> assignWaiter(String tableId, String? waiterId) async {
    final res = await dio.put('/api/restaurant/tables/$tableId/assign', data: {
      'waiter_id': waiterId,
    });
    return RestaurantTableModel.fromJson(res.data as Map<String, dynamic>);
  }

  // ── Tables ──────────────────────────────────────────────────────────────────

  Future<List<RestaurantTableModel>> getTables() async {
    final res = await dio.get('/api/restaurant/tables/');
    return (res.data as List)
        .map((e) => RestaurantTableModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RestaurantTableModel> createTable({
    required String name,
    int capacity = 4,
  }) async {
    final res = await dio.post('/api/restaurant/tables/', data: {
      'name': name,
      'capacity': capacity,
    });
    return RestaurantTableModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<RestaurantTableModel> updateTable(
    String tableId, {
    String? name,
    int? capacity,
    String? status,
  }) async {
    final res = await dio.put('/api/restaurant/tables/$tableId', data: {
      if (name != null) 'name': name,
      if (capacity != null) 'capacity': capacity,
      if (status != null) 'status': status,
    });
    return RestaurantTableModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteTable(String tableId) async {
    await dio.delete('/api/restaurant/tables/$tableId');
  }

  // ── Orders ──────────────────────────────────────────────────────────────────

  Future<List<RestaurantOrderModel>> getOpenOrders() async {
    final res = await dio.get('/api/restaurant/orders/');
    return (res.data as List)
        .map((e) => RestaurantOrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RestaurantOrderModel?> getTableOrder(String tableId) async {
    final res = await dio.get('/api/restaurant/orders/table/$tableId');
    if (res.data == null) return null;
    return RestaurantOrderModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<RestaurantOrderModel> getOrder(String orderId) async {
    final res = await dio.get('/api/restaurant/orders/$orderId');
    return RestaurantOrderModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<RestaurantOrderModel> openOrder({
    String? tableId,
    int covers = 1,
    String? notes,
  }) async {
    final res = await dio.post(
      '/api/restaurant/orders/',
      queryParameters: {if (tableId != null) 'table_id': tableId},
      data: {'covers': covers, if (notes != null) 'notes': notes},
    );
    return RestaurantOrderModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<RestaurantOrderModel> addItem(
    String orderId, {
    required String productId,
    double quantity = 1.0,
    String? notes,
  }) async {
    final res = await dio.post('/api/restaurant/orders/$orderId/items', data: {
      'product_id': productId,
      'quantity': quantity,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return RestaurantOrderModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> removeItem(String orderId, String itemId) async {
    await dio.delete('/api/restaurant/orders/$orderId/items/$itemId');
  }

  Future<RestaurantOrderModel> updateItemQuantity(
      String orderId, String itemId, double quantity) async {
    final res = await dio.put(
        '/api/restaurant/orders/$orderId/items/$itemId',
        data: {'quantity': quantity});
    return RestaurantOrderModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<RestaurantOrderModel> sendToKitchen(String orderId) async {
    final res = await dio.put('/api/restaurant/orders/$orderId/kitchen');
    return RestaurantOrderModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<RestaurantOrderModel> markReady(String orderId) async {
    final res = await dio.put('/api/restaurant/orders/$orderId/ready');
    return RestaurantOrderModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<ProductModel>> searchProducts(String query) async {
    final res = await dio.get('/api/products/', queryParameters: {
      'search': query,
      'per_page': 10,
    });
    final data = res.data as Map<String, dynamic>;
    return (data['data'] as List? ?? [])
        .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Ingredients ─────────────────────────────────────────────────────────────

  Future<List<IngredientModel>> getIngredients({
    String? productId,
    String? categoryId,
  }) async {
    final res = await dio.get('/api/restaurant/ingredients/', queryParameters: {
      if (productId != null) 'product_id': productId,
      if (categoryId != null) 'category_id': categoryId,
    });
    return (res.data as List)
        .map((e) => IngredientModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<IngredientModel> createIngredient({
    required String name,
    String? productId,
    String? categoryId,
  }) async {
    final res = await dio.post('/api/restaurant/ingredients/', data: {
      'name': name,
      if (productId != null) 'product_id': productId,
      if (categoryId != null) 'category_id': categoryId,
    });
    return IngredientModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<IngredientModel> updateIngredient(
    String id, {
    String? name,
    String? productId,
    String? categoryId,
  }) async {
    final res = await dio.put('/api/restaurant/ingredients/$id', data: {
      if (name != null) 'name': name,
      'product_id': productId,
      'category_id': categoryId,
    });
    return IngredientModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteIngredient(String id) async {
    await dio.delete('/api/restaurant/ingredients/$id');
  }

  Future<Map<String, dynamic>> checkout(
    String orderId, {
    required double paidAmount,
    String paymentMethod = 'CASH',
    String? customerId,
    double discount = 0.0,
    double tip = 0.0,
  }) async {
    final res = await dio.post('/api/restaurant/orders/$orderId/checkout', data: {
      'paid_amount': paidAmount,
      'payment_method': paymentMethod,
      if (customerId != null) 'customer_id': customerId,
      'discount': discount,
      'tip': tip,
    });
    return res.data as Map<String, dynamic>;
  }
}
