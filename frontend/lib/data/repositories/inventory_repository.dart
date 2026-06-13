import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/inventory_model.dart';

class InventoryRepository {
  Future<List<CategoryItem>> getCategories() async {
    final res = await dio.get('/api/categories/');
    final data = res.data['data'] as List? ?? [];
    return data.map((e) => CategoryItem.fromJson(e)).toList();
  }

  Future<List<InventoryPreviewItem>> getPreview({
    List<String>? categoryIds,
  }) async {
    final params = <String, dynamic>{};
    if (categoryIds != null && categoryIds.isNotEmpty) {
      params['category_ids'] = categoryIds;
    }
    final res =
        await dio.get('/api/inventory/preview', queryParameters: params);
    final data = res.data['data'] as List? ?? [];
    return data.map((e) => InventoryPreviewItem.fromJson(e)).toList();
  }

  Future<List<InventoryModel>> listInventories({
    int page = 1,
    int limit = 20,
  }) async {
    final res = await dio.get('/api/inventory/',
        queryParameters: {'page': page, 'limit': limit});
    final data = res.data['data'] as List? ?? [];
    // List view doesn't include items_json parsing, items = []
    return data.map((e) => InventoryModel.fromJson({...e, 'items': []})).toList();
  }

  Future<InventoryModel> getInventory(String id) async {
    final res = await dio.get('/api/inventory/$id');
    return InventoryModel.fromJson(res.data);
  }

  Future<Map<String, dynamic>> createInventory({
    required String inventoryType,
    List<String>? categoryIds,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await dio.post('/api/inventory/', data: {
      'inventory_type': inventoryType,
      if (categoryIds != null && categoryIds.isNotEmpty)
        'category_ids': categoryIds,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'items': items,
    });
    return res.data;
  }
}
