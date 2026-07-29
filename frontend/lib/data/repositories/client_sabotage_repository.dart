import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/client_sabotage_model.dart';
import 'package:pos_connect/services/local_db_service.dart';

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

class ClientSabotageRepository {
  Future<List<ClientSabotageModel>> getClients() async {
    if (_isAndroid) return LocalDbService.instance.getClientsSabotage();

    final res = await dio.get('/api/clients-sabotage/');
    final raw = res.data is Map
        ? (res.data['data'] as List? ?? [])
        : (res.data as List? ?? []);
    return raw
        .map((e) => ClientSabotageModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ClientSabotageModel> createClient(Map<String, dynamic> data) async {
    final res = await dio.post('/api/clients-sabotage/', data: data);
    return ClientSabotageModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ClientSabotageModel> updateClient(String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/clients-sabotage/$id', data: data);
    return ClientSabotageModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteClient(String id) async {
    await dio.delete('/api/clients-sabotage/$id');
  }
}
