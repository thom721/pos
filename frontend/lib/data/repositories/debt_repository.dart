import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/debt_model.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/services/local_db_service.dart';

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

class DebtRepository {
  Future<PaginatedResponse<DebtModel>> getDebts({
    int page = 1,
    int limit = 50,
    String? partnerType,
    String? status,
    String? partnerId,
  }) async {
    // Android : source de vérité = SQLite alimenté par OfflineCacheService
    if (_isAndroid) {
      return LocalDbService.instance.getDebts(
        partnerType: partnerType,
        status: status,
        partnerId: partnerId,
        page: page,
        limit: limit,
      );
    }

    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (partnerType != null) 'partner_type': partnerType,
      if (status != null) 'status': status,
      if (partnerId != null) 'partner_id': partnerId,
    };
    final res = await dio.get('/api/debts/', queryParameters: params);
    return PaginatedResponse.fromJson(res.data, DebtModel.fromJson);
  }
}
