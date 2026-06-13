import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';

class ProductRepository {
  Future<PaginatedResponse<ProductModel>> getProducts({
    int page = 1,
    int limit = 20,
    String? search,
    String? categoryId,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'per_page': limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (categoryId != null) 'category_id': categoryId,
    };
    final res = await dio.get('/api/products/', queryParameters: params);
    return PaginatedResponse.fromJson(res.data, ProductModel.fromJson);
  }

  Future<List<CategoryModel>> getCategories() async {
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

  /// Upload d'image cross-platform (Web + Android + iOS).
  /// Le token JWT est injecté automatiquement par l'AuthInterceptor de dio.
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

  // Used by POS cashier screen
  Future<PaginatedResponse<ProductModel>> searchForSale({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final res =
        await dio.get('/api/sales/products/search', queryParameters: params);
    return PaginatedResponse.fromJson(res.data, ProductModel.fromJson);
  }
}
