// Vérifie, contre une vraie base SQLite (sqflite_common_ffi), que
// Customer.warehouseId survit au cycle upsertCustomers → getCustomers, et
// que le filtre par dépôt (dépôt actif + clients partagés, warehouse_id
// NULL) fonctionne hors-ligne sur Android — même convention que les
// paliers de prix / rabais, pas seulement côté serveur.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:pos_connect/data/models/customer_model.dart';
import 'package:pos_connect/services/local_db_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  final String path;
  _FakePathProviderPlatform(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('pos_connect_test_db');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await LocalDbService.instance.init();
  });

  tearDownAll(() async {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('warehouseId survit au cycle upsertCustomers -> getCustomers, filtre dépôt + partagé',
      () async {
    await LocalDbService.instance.upsertCustomers([
      CustomerModel(
        id: 'c-depot-a', name: 'Depot A', phone: '1', address: 'x',
        creditLimit: 0, warehouseId: 'wh-a',
      ),
      CustomerModel(
        id: 'c-depot-b', name: 'Depot B', phone: '2', address: 'x',
        creditLimit: 0, warehouseId: 'wh-b',
      ),
      CustomerModel(
        id: 'c-shared', name: 'Shared', phone: '3', address: 'x',
        creditLimit: 0, warehouseId: null,
      ),
    ]);

    final everyone = await LocalDbService.instance.getCustomers(limit: 50);
    expect(everyone.data.map((c) => c.id).toSet(), {'c-depot-a', 'c-depot-b', 'c-shared'});

    final depotA = await LocalDbService.instance.getCustomers(limit: 50, warehouseId: 'wh-a');
    expect(depotA.data.map((c) => c.id).toSet(), {'c-depot-a', 'c-shared'});

    final depotB = await LocalDbService.instance.getCustomers(limit: 50, warehouseId: 'wh-b');
    expect(depotB.data.map((c) => c.id).toSet(), {'c-depot-b', 'c-shared'});
  });

  test('insertLocalCustomer enregistre le dépôt (création hors-ligne)', () async {
    final id = await LocalDbService.instance.insertLocalCustomer(
      name: 'Offline', phone: '9', warehouseId: 'wh-a',
    );

    final depotA = await LocalDbService.instance.getCustomers(limit: 50, warehouseId: 'wh-a');
    expect(depotA.data.any((c) => c.id == id), isTrue);

    final depotB = await LocalDbService.instance.getCustomers(limit: 50, warehouseId: 'wh-b');
    expect(depotB.data.any((c) => c.id == id), isFalse);
  });
}
