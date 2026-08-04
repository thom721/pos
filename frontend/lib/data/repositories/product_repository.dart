import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/services/local_db_service.dart';

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

class ProductRepository {
  Future<PaginatedResponse<ProductModel>> getProducts({
    int page = 1,
    int limit = 20,
    String? search,
    String? categoryId,
    String? warehouseId,
  }) async {
    // Le cache local (offline Android) stocke stock/prix déjà scopés au dépôt
    // actif — c'est offline_cache_service.dart::_syncProducts qui les peuple
    // ainsi en arrière-plan (une caisse Android est dédiée à un seul dépôt).
    // Le repli ci-dessous (cache vide, premier lancement) fait pareil.
    if (_isAndroid) {
      final cached = await LocalDbService.instance.getProducts(
        search: search, page: page, limit: limit, categoryId: categoryId,
      );
      // Cache vide sans filtre actif → fallback API avec pagination + peuplement du cache
      if (cached.data.isEmpty && search == null && categoryId == null) {
        try {
          final all = <ProductModel>[];
          int p = 1;
          while (true) {
            if (p > 200) break;
            final res = await dio.get('/api/products/', queryParameters: {
              'page': p,
              'per_page': 100,
              if (warehouseId != null) 'warehouse_id': warehouseId,
            });
            final data = res.data as Map<String, dynamic>;
            final raw = (data['data'] as List? ?? []);
            all.addAll(raw.map((e) => ProductModel.fromJson(e as Map<String, dynamic>)));
            final totalPages = data['pages'] ?? data['meta']?['pages'] ?? 1;
            if (p >= (totalPages as num).toInt()) break;
            p++;
          }
          if (all.isNotEmpty) await LocalDbService.instance.upsertProducts(all);
          return LocalDbService.instance.getProducts(
            search: search, page: page, limit: limit, categoryId: categoryId,
          );
        } catch (_) {
          return cached;
        }
      }
      return cached;
    }

    final params = <String, dynamic>{
      'page': page,
      'per_page': limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (categoryId != null) 'category_id': categoryId,
      if (warehouseId != null) 'warehouse_id': warehouseId,
    };
    final res = await dio.get('/api/products/', queryParameters: params);
    return PaginatedResponse.fromJson(res.data, ProductModel.fromJson);
  }

  Future<List<CategoryModel>> getCategories() async {
    if (_isAndroid) return LocalDbService.instance.getCategories();

    final res = await dio.get('/api/categories/');
    final raw = res.data is Map
        ? (res.data['data'] as List? ?? [])
        : (res.data as List? ?? []);
    return raw
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CategoryModel> createCategory(Map<String, dynamic> data) async {
    final res = await dio.post('/api/categories/', data: data);
    return CategoryModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CategoryModel> updateCategory(
      String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/categories/$id', data: data);
    return CategoryModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteCategory(String id) async {
    await dio.delete('/api/categories/$id');
  }

  Future<ProductModel> createProduct(Map<String, dynamic> data) async {
    final res = await dio.post('/api/products/', data: data);
    return ProductModel.fromJson(res.data);
  }

  Future<ProductModel> updateProduct(String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/products/$id', data: data);
    return ProductModel.fromJson(res.data);
  }

  Future<void> deleteProduct(String id) async {
    await dio.delete('/api/products/$id');
  }

  Future<String?> uploadProductImage(
    String productId,
    Uint8List bytes,
    String filename,
  ) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: _mimeType(filename),
      ),
    });
    final res = await dio.post(
      '/api/products/$productId/image',
      data: formData,
    );
    return res.data['image_url']?.toString();
  }

  DioMediaType _mimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'png'  => DioMediaType('image', 'png'),
      'webp' => DioMediaType('image', 'webp'),
      _      => DioMediaType('image', 'jpeg'),
    };
  }

  Future<ProductModel> adjustStock(String id, double quantity, {String? reason, String? warehouseId}) async {
    final res = await dio.post('/api/products/$id/adjust-stock', data: {
      'quantity': quantity,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      if (warehouseId != null) 'warehouse_id': warehouseId,
    });
    return ProductModel.fromJson(res.data);
  }

  Future<List<WarehousePriceModel>> getWarehousePrices(String productId) async {
    final res = await dio.get('/api/products/$productId/warehouse-prices');
    return (res.data as List)
        .map((e) => WarehousePriceModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setWarehousePrice(String productId, String warehouseId, double salePrice) async {
    await dio.put('/api/products/$productId/warehouse-prices/$warehouseId',
        data: {'sale_price': salePrice});
  }

  Future<void> deleteWarehousePrice(String productId, String warehouseId) async {
    await dio.delete('/api/products/$productId/warehouse-prices/$warehouseId');
  }

  Future<PaginatedResponse<ProductModel>> searchForSale({
    String? search,
    int page = 1,
    int perPage = 20,
    String? warehouseId,
  }) async {
    if (_isAndroid) {
      // Cache local (offline) : pas encore de prix par dépôt — reste sur le
      // prix par défaut, comme pour le stock (voir getProducts ci-dessus).
      return LocalDbService.instance.searchForSale(
        search: search, page: page, perPage: perPage,
      );
    }

    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      if (search != null && search.isNotEmpty) 'search': search,
      if (warehouseId != null) 'warehouse_id': warehouseId,
    };
    final res = await dio.get('/api/sales/products/search', queryParameters: params);
    return PaginatedResponse.fromJson(res.data, ProductModel.fromJson);
  }

  /// Résout un code scanné (douchette ou caméra) vers le produit exact.
  /// Réutilise la recherche existante (name OR barcode ilike) puis ne
  /// retient que la correspondance exacte du code-barres — évite un faux
  /// positif si le code scanné apparaît comme sous-chaîne d'un nom produit.
  Future<ProductModel?> findByBarcode(String code, {String? warehouseId}) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    final res = await searchForSale(
      search: trimmed, perPage: 20, warehouseId: warehouseId,
    );
    for (final p in res.data) {
      if (p.barcode != null && p.barcode!.trim() == trimmed) return p;
    }
    return null;
  }
}
