import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/purchase_model.dart';
import 'package:pos_connect/services/local_db_service.dart';
import 'package:pos_connect/services/offline_queue_service.dart';

bool _isOffline(Object e) =>
    e is DioException &&
    (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.unknown) ||
    e is SocketException;

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

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

    // Android : source de vérité = SQLite
    if (_isAndroid) {
      return LocalDbService.instance.getPurchases(
        search: search, status: status, page: page, limit: limit,
      );
    }

    final res = await dio.get('/api/purchases/', queryParameters: params);
    return PaginatedResponse.fromJson(res.data, PurchaseModel.fromJson);
  }

  Future<PurchaseModel> getPurchase(String id) async {
    final res = await dio.get('/api/purchases/$id');
    return PurchaseModel.fromJson(res.data);
  }

  /// Crée un achat.
  ///
  /// Sur Android : SQLite d'abord → API cloud avec `client_id`.
  /// Hors-ligne : enfile pour sync ultérieure, retourne `{offline: true}`.
  Future<Map<String, dynamic>> createPurchase(Map<String, dynamic> data) async {
    if (!_isAndroid) {
      final res = await dio.post('/api/purchases/', data: data);
      return res.data as Map<String, dynamic>;
    }

    // Incrémenter le stock local immédiatement
    for (final item in (data['items'] as List? ?? [])) {
      final productId = item['product_id'] as String?;
      final qty       = (item['quantity'] as num?)?.toDouble() ?? 0;
      if (productId != null) {
        await LocalDbService.instance.incrementStock(productId, qty);
      }
    }

    final localId = await LocalDbService.instance.insertLocalPurchase(payload: data);

    try {
      final res = await dio.post(
        '/api/purchases/',
        data: {...data, 'client_id': localId},
      );
      final responseData = res.data as Map<String, dynamic>;
      final reference = responseData['reference'] as String? ?? '';
      await LocalDbService.instance.markPurchaseSynced(localId, reference);
      return {...responseData, 'purchase_id': responseData['id'] ?? localId, 'offline': false};
    } catch (e) {
      if (_isOffline(e)) {
        await OfflineQueueService.instance.enqueue(
          RequestOptions(
            path: '/api/purchases/',
            method: 'POST',
            data: {...data, 'client_id': localId},
          ),
        );
        return {'purchase_id': localId, 'offline': true};
      }
      // Erreur serveur : annuler le stock local
      for (final item in (data['items'] as List? ?? [])) {
        final productId = item['product_id'] as String?;
        final qty       = (item['quantity'] as num?)?.toDouble() ?? 0;
        if (productId != null) {
          await LocalDbService.instance.decrementStock(productId, qty);
        }
      }
      rethrow;
    }
  }
}
