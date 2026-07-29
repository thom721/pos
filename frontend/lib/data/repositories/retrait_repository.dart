import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/retrait_model.dart';
import 'package:pos_connect/services/local_db_service.dart';

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

class RetraitRepository {
  Future<List<RetraitModel>> getRetraits({String? clientId}) async {
    if (_isAndroid) return LocalDbService.instance.getRetraits(clientId: clientId);

    final res = await dio.get('/api/retraits/', queryParameters: {
      if (clientId != null) 'client_id': clientId,
    });
    final raw = res.data is Map
        ? (res.data['data'] as List? ?? [])
        : (res.data as List? ?? []);
    return raw.map((e) => RetraitModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RetraitModel> createRetrait(Map<String, dynamic> data) async {
    final res = await dio.post('/api/retraits/', data: data);
    return RetraitModel.fromJson(res.data as Map<String, dynamic>);
  }
}
