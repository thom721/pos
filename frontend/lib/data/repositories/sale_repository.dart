import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/services/local_db_service.dart';
import 'package:pos_connect/services/offline_queue_service.dart';

bool _isOffline(Object e) =>
    e is DioException &&
    (e.type == DioExceptionType.connectionError ||
     e.type == DioExceptionType.connectionTimeout ||
     e.type == DioExceptionType.receiveTimeout) ||
    e is SocketException;

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

class SaleRepository {
  Future<PaginatedResponse<SaleModel>> getSales({
    int page = 1,
    int limit = 15,
    String? search,
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (status != null) 'status': status,
      if (dateFrom != null) 'date_from': dateFrom.toIso8601String(),
      if (dateTo != null) 'date_to': dateTo.toIso8601String(),
    };

    try {
      final res = await dio.get('/api/sales/', queryParameters: params);
      final result = PaginatedResponse.fromJson(res.data, SaleModel.fromJson);
      if (_isAndroid) {
        LocalDbService.instance.upsertSales(result.data).ignore();
      }
      return result;
    } catch (e) {
      if (_isAndroid && _isOffline(e)) {
        return LocalDbService.instance.getSales(
          search: search,
          status: status,
          page: page,
          limit: limit,
        );
      }
      rethrow;
    }
  }

  Future<SaleModel> getSale(String id) async {
    try {
      final res = await dio.get('/api/sales/$id');
      return SaleModel.fromJson(res.data);
    } catch (e) {
      if (_isAndroid && _isOffline(e)) {
        final local = await LocalDbService.instance.getLocalSale(id);
        if (local != null) return local;
      }
      rethrow;
    }
  }

  /// Crée une vente.
  ///
  /// Sur Android : écrit en SQLite d'abord (offline-first), tente l'API,
  /// et met en file d'attente si hors-ligne.
  /// Retourne `{'sale_id': id, 'reference': ref, 'offline': bool}`.
  Future<Map<String, dynamic>> createSale(
    Map<String, dynamic> data, {
    String? customerName,
  }) async {
    if (_isAndroid) {
      // 1. Écriture locale immédiate
      final localId = await LocalDbService.instance.insertLocalSale(
        payload: data,
        customerName: customerName,
      );

      // 2. Déduction stock local pour éviter la survente
      for (final item in data['items'] as List) {
        await LocalDbService.instance.decrementStock(
          item['product_id'] as String,
          (item['quantity'] as num).toDouble(),
        );
      }

      // 3. Envoi cloud avec l'UUID client
      try {
        final res = await dio.post('/api/sales/', data: {
          ...data,
          'client_id': localId,
        });
        final serverId  = res.data['sale_id']?.toString() ?? localId;
        final reference = res.data['reference']?.toString() ?? '';
        await LocalDbService.instance.markSaleSynced(localId, reference);
        return {'sale_id': serverId, 'reference': reference, 'offline': false};
      } catch (e) {
        if (_isOffline(e)) {
          // 4. Hors-ligne : mettre en file pour sync ultérieure
          await OfflineQueueService.instance.enqueue(
            RequestOptions(
              path: '/api/sales/',
              method: 'POST',
              data: {...data, 'client_id': localId},
            ),
          );
          return {'sale_id': localId, 'reference': null, 'offline': true};
        }
        // Erreur serveur (stock, validation…) : annuler le SQLite local
        await _rollbackLocalSale(localId, data);
        rethrow;
      }
    }

    // Web / macOS : direct API
    final res = await dio.post('/api/sales/', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<void> _rollbackLocalSale(
      String localId, Map<String, dynamic> data) async {
    final db = LocalDbService.instance;
    for (final item in data['items'] as List) {
      await db.decrementStock(
        item['product_id'] as String,
        -((item['quantity'] as num).toDouble()), // remettre le stock
      );
    }
    // Supprimer l'enregistrement local erroné
    final rawDb = LocalDbService.instance;
    await rawDb.deleteSale(localId);
  }

  Future<void> cancelSale(String id) async {
    await dio.patch('/api/sales/$id/cancel');
  }

  Future<Map<String, dynamic>> updateSale(
      String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/sales/$id', data: data);
    return res.data;
  }

  Future<void> addPayment({
    required String referenceType,
    required String referenceId,
    required double amount,
    required String method,
  }) async {
    await dio.post('/api/payments/', data: {
      'reference_type': referenceType,
      'reference_id':   referenceId,
      'amount':         amount,
      'method':         method,
    });
  }
}
