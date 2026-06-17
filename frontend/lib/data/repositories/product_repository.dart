import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/services/local_db_service.dart';

bool _isOffline(Object e) =>
    e is DioException &&
    (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.unknown);

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
    try {
      final res = await dio.get('/api/products/', queryParameters: params);
      final result = PaginatedResponse.fromJson(res.data, ProductModel.fromJson);
      // Met à jour le cache en arrière-plan
      LocalDbService.instance.upsertProducts(result.data).ignore();
      return result;
    } catch (e) {
      if (_isOffline(e)) {
        return LocalDbService.instance.getProducts(
          search: search, page: page, limit: limit, categoryId: categoryId,
        );
      }
      rethrow;
    }
  }

  Future<List<CategoryModel>> getCategories() async {
    try {
      final res = await dio.get('/api/categories/');
      final raw = res.data is Map
          ? (res.data['data'] as List? ?? [])
          : (res.data as List? ?? []);
      final cats = raw
          .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
      LocalDbService.instance.upsertCategories(cats).ignore();
      return cats;
    } catch (e) {
      if (_isOffline(e)) return LocalDbService.instance.getCategories();
      rethrow;
    }
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
    try {
      final res =
          await dio.get('/api/sales/products/search', queryParameters: params);
      final result = PaginatedResponse.fromJson(res.data, ProductModel.fromJson);
      LocalDbService.instance.upsertProducts(result.data).ignore();
      return result;
    } catch (e) {
      if (_isOffline(e)) {
        return LocalDbService.instance.searchForSale(
          search: search, page: page, perPage: perPage,
        );
      }
      rethrow;
    }
  }
}
