// Vérifie, contre une vraie base SQLite (sqflite_common_ffi), que le champ
// is_service survit au cycle upsertProducts → getProducts, et que le
// filtre "Produit"/"Service" de getSales (jointure sale_items → products)
// fonctionne hors-ligne sur Android — pas seulement côté serveur.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:pos_connect/data/models/product_model.dart';
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
    tz_data.initializeTimeZones(); // requis par haitiNow() (insertLocalSale)
    tempDir = Directory.systemTemp.createTempSync('pos_connect_test_db');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await LocalDbService.instance.init();
  });

  tearDownAll(() async {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('cache local SQLite — onglet Produit/Service', () {
    test('is_service survit au cycle upsertProducts -> getProducts', () async {
      await LocalDbService.instance.upsertProducts([
        ProductModel(
          id: 'p-produit',
          name: 'Produit A',
          salePrice: 10,
          purchasePrice: 5,
          alertStock: 2,
        ),
        ProductModel(
          id: 'p-service',
          name: 'Pressing',
          salePrice: 20,
          purchasePrice: 0,
          alertStock: 0,
          isService: true,
        ),
      ]);

      final all = await LocalDbService.instance.getProducts(limit: 50);
      final byId = {for (final p in all.data) p.id: p};
      expect(byId['p-produit']!.isService, false);
      expect(byId['p-service']!.isService, true);

      final onlyProducts =
          await LocalDbService.instance.getProducts(limit: 50, itemType: 'product');
      expect(onlyProducts.data.map((p) => p.id), ['p-produit']);

      final onlyServices =
          await LocalDbService.instance.getProducts(limit: 50, itemType: 'service');
      expect(onlyServices.data.map((p) => p.id), ['p-service']);
    });

    test('getSales(itemType:) classe correctement produit / service / vente mixte',
        () async {
      // Sales créées offline (insertLocalSale) référencent les produits
      // déjà upsertés ci-dessus.
      final productOnlyId = await LocalDbService.instance.insertLocalSale(
        payload: {
          'items': [
            {
              'product_id': 'p-produit',
              'product_name': 'Produit A',
              'quantity': 1,
              'unit_price': 10,
              'subtotal': 10,
            },
          ],
          'paid_amount': 10,
        },
        customerName: null,
      );
      final serviceOnlyId = await LocalDbService.instance.insertLocalSale(
        payload: {
          'items': [
            {
              'product_id': 'p-service',
              'product_name': 'Pressing',
              'quantity': 1,
              'unit_price': 20,
              'subtotal': 20,
            },
          ],
          'paid_amount': 20,
        },
        customerName: null,
      );
      final mixedId = await LocalDbService.instance.insertLocalSale(
        payload: {
          'items': [
            {
              'product_id': 'p-produit',
              'product_name': 'Produit A',
              'quantity': 1,
              'unit_price': 10,
              'subtotal': 10,
            },
            {
              'product_id': 'p-service',
              'product_name': 'Pressing',
              'quantity': 1,
              'unit_price': 20,
              'subtotal': 20,
            },
          ],
          'paid_amount': 30,
        },
        customerName: null,
      );

      final productTab =
          (await LocalDbService.instance.getSales(limit: 50, itemType: 'product'))
              .data
              .map((s) => s.id)
              .toSet();
      final serviceTab =
          (await LocalDbService.instance.getSales(limit: 50, itemType: 'service'))
              .data
              .map((s) => s.id)
              .toSet();

      expect(productTab.contains(productOnlyId), true);
      expect(productTab.contains(serviceOnlyId), false);
      expect(productTab.contains(mixedId), true,
          reason: 'vente mixte doit apparaître sous Produit aussi');

      expect(serviceTab.contains(serviceOnlyId), true);
      expect(serviceTab.contains(productOnlyId), false);
      expect(serviceTab.contains(mixedId), true,
          reason: 'vente mixte doit apparaître sous Service aussi');

      // getLocalSale doit aussi exposer isService par article (utilisé par
      // la section Services du PDF et le préfixe SER-).
      final mixedSale = await LocalDbService.instance.getLocalSale(mixedId);
      expect(mixedSale, isNotNull);
      final serviceItems = mixedSale!.items.where((i) => i.isService).toList();
      expect(serviceItems.length, 1);
      expect(serviceItems.first.productId, 'p-service');
    });
  });
}
