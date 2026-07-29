import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/depot_model.dart';
import 'package:pos_connect/services/local_db_service.dart';

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

class DepotRepository {
  Future<List<DepotModel>> getDepots({String? clientId}) async {
    if (_isAndroid) return LocalDbService.instance.getDepots(clientId: clientId);

    final res = await dio.get('/api/depots/', queryParameters: {
      if (clientId != null) 'client_id': clientId,
    });
    final raw = res.data is Map
        ? (res.data['data'] as List? ?? [])
        : (res.data as List? ?? []);
    return raw.map((e) => DepotModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DepotModel> createDepot(Map<String, dynamic> data) async {
    final res = await dio.post('/api/depots/', data: data);
    return DepotModel.fromJson(res.data as Map<String, dynamic>);
  }
}
