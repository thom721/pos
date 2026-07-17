import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/models/pos_register_model.dart';

class WarehouseRepository {
  Future<List<WarehouseModel>> listWarehouses() async {
    final res = await dio.get('/api/warehouses/');
    final data = res.data as List? ?? [];
    return data.map((e) => WarehouseModel.fromJson(e)).toList();
  }

  Future<WarehouseModel> createWarehouse(String name,
      {String? description, bool force = false}) async {
    final res = await dio.post('/api/warehouses/', data: {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'force': force,
    });
    return WarehouseModel.fromJson(res.data);
  }

  Future<WarehouseModel> updateWarehouse(
    String id, {
    String? name,
    String? description,
    bool? isActive,
  }) async {
    final res = await dio.put('/api/warehouses/$id', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (isActive != null) 'is_active': isActive,
    });
    return WarehouseModel.fromJson(res.data);
  }

  Future<WarehouseModel> setDefault(String id) async {
    final res = await dio.put('/api/warehouses/$id/set-default');
    return WarehouseModel.fromJson(res.data);
  }

  Future<void> deleteWarehouse(String id) async {
    await dio.delete('/api/warehouses/$id');
  }

  // ── Caisses (PosRegister) ─────────────────────────────────────────────────

  Future<List<PosRegisterModel>> listRegisters(String warehouseId) async {
    final res = await dio.get('/api/warehouses/$warehouseId/registers');
    return (res.data as List? ?? [])
        .map((e) => PosRegisterModel.fromJson(e))
        .toList();
  }

  Future<PosRegisterModel> createRegister(String warehouseId, String name,
      {bool force = false}) async {
    final res = await dio.post('/api/warehouses/$warehouseId/registers',
        data: {'name': name, 'force': force});
    return PosRegisterModel.fromJson(res.data);
  }

  Future<PosRegisterModel> updateRegister(
    String warehouseId,
    String registerId, {
    String? name,
    bool? isActive,
  }) async {
    final res = await dio.put(
        '/api/warehouses/$warehouseId/registers/$registerId',
        data: {
          if (name != null) 'name': name,
          if (isActive != null) 'is_active': isActive,
        });
    return PosRegisterModel.fromJson(res.data);
  }

  Future<void> deleteRegister(String warehouseId, String registerId) async {
    await dio.delete('/api/warehouses/$warehouseId/registers/$registerId');
  }
}
