import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/customer_model.dart';
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

class CustomerRepository {
  Future<PaginatedResponse<CustomerModel>> getCustomers({
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    // Android : source de vérité = SQLite
    if (_isAndroid) {
      return LocalDbService.instance.getCustomers(
        search: search, page: page, limit: limit,
      );
    }

    final res = await dio.get('/api/customers/', queryParameters: params);
    if (res.data is List) {
      final list = (res.data as List)
          .map((e) => CustomerModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return PaginatedResponse(
        data: list,
        meta: PaginationMeta(page: 1, limit: limit, total: list.length, pages: 1),
      );
    }
    return PaginatedResponse.fromJson(res.data, CustomerModel.fromJson);
  }

  /// Crée un client.
  ///
  /// Sur Android hors-ligne : enregistre en SQLite avec UUID local,
  /// met en file pour sync ultérieure. Retourne un [CustomerModel] local.
  Future<CustomerModel> createCustomer(Map<String, dynamic> data) async {
    if (_isAndroid) {
      try {
        final res = await dio.post('/api/customers/', data: data);
        final customer = CustomerModel.fromJson(res.data);
        await LocalDbService.instance.upsertCustomers([customer]);
        return customer;
      } catch (e) {
        if (_isOffline(e)) {
          final localId = await LocalDbService.instance.insertLocalCustomer(
            name:        data['name'] as String,
            phone:       data['phone'] as String? ?? '',
            nif:         data['nif'] as String?,
            email:       data['email'] as String?,
            address:     data['address'] as String?,
            creditLimit: (data['credit_limit'] as num?)?.toDouble() ?? 0,
          );
          await OfflineQueueService.instance.enqueue(
            RequestOptions(
              path: '/api/customers/',
              method: 'POST',
              data: {...data, 'local_id': localId},
            ),
          );
          return CustomerModel(
            id:          localId,
            name:        data['name'] as String,
            phone:       data['phone'] as String? ?? '',
            nif:         data['nif'] as String?,
            email:       data['email'] as String?,
            address:     data['address'] as String? ?? '',
            creditLimit: (data['credit_limit'] as num?)?.toDouble() ?? 0,
          );
        }
        rethrow;
      }
    }

    // Web / macOS : direct API
    final res = await dio.post('/api/customers/', data: data);
    return CustomerModel.fromJson(res.data);
  }

  Future<CustomerModel> updateCustomer(String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/customers/$id', data: data);
    return CustomerModel.fromJson(res.data);
  }

  Future<void> deleteCustomer(String id) async {
    await dio.delete('/api/customers/$id');
  }
}
