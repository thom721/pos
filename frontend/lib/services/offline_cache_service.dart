import 'package:flutter/foundation.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/customer_model.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/services/local_db_service.dart';

/// Synchronise les données critiques API → SQLite local.
///
/// Appelé :
///  - au login (warm-up initial du cache)
///  - à chaque cycle de sync automatique (toutes les 5 min dans app.dart)
///
/// Ne lève jamais d'exception vers l'appelant : les erreurs sont silencieuses
/// car le cache est un complément, pas un prérequis.
class OfflineCacheService {
  OfflineCacheService._();
  static final OfflineCacheService instance = OfflineCacheService._();

  bool _running = false;

  // ── API publique ──────────────────────────────────────────────────────────

  /// Lance la sync de toutes les entités. Ignoré si déjà en cours.
  Future<void> syncAll() async {
    if (kIsWeb || _running) return;
    _running = true;
    try {
      await Future.wait([
        _syncProducts(),
        _syncCustomers(),
        _syncCategories(),
        _syncWarehouses(),
      ]);
    } catch (e) {
      debugPrint('[OfflineCache] syncAll error: $e');
    } finally {
      _running = false;
    }
  }

  // ── Produits ──────────────────────────────────────────────────────────────

  Future<void> _syncProducts() async {
    try {
      final all = <ProductModel>[];
      int page = 1;
      while (true) {
        final res = await dio.get('/api/products/', queryParameters: {
          'page': page,
          'per_page': 200,
        });
        final data = res.data as Map<String, dynamic>;
        final items = (data['data'] as List)
            .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
            .toList();
        all.addAll(items);

        final totalPages = data['pages'] ?? data['meta']?['pages'] ?? 1;
        if (page >= (totalPages as num).toInt()) break;
        page++;
      }
      await LocalDbService.instance.upsertProducts(all);
      await LocalDbService.instance.setLastSynced('products');
      debugPrint('[OfflineCache] products: ${all.length} mis en cache');
    } catch (e) {
      debugPrint('[OfflineCache] products sync error: $e');
    }
  }

  // ── Clients ───────────────────────────────────────────────────────────────

  Future<void> _syncCustomers() async {
    try {
      final all = <CustomerModel>[];
      int page = 1;
      while (true) {
        final res = await dio.get('/api/customers/', queryParameters: {
          'page': page,
          'limit': 200,
        });
        final raw = res.data;
        List items;
        int totalPages = 1;

        if (raw is List) {
          // API retourne une liste plate
          items = raw;
          totalPages = 1;
        } else {
          items = (raw['data'] as List? ?? []);
          totalPages = (raw['pages'] ?? raw['meta']?['pages'] ?? 1) as int;
        }

        all.addAll(
          items.map((e) => CustomerModel.fromJson(e as Map<String, dynamic>)),
        );
        if (page >= totalPages) break;
        page++;
      }
      await LocalDbService.instance.upsertCustomers(all);
      await LocalDbService.instance.setLastSynced('customers');
      debugPrint('[OfflineCache] customers: ${all.length} mis en cache');
    } catch (e) {
      debugPrint('[OfflineCache] customers sync error: $e');
    }
  }

  // ── Catégories ────────────────────────────────────────────────────────────

  Future<void> _syncCategories() async {
    try {
      final res = await dio.get('/api/categories/');
      final raw = res.data;
      final items = raw is Map
          ? (raw['data'] as List? ?? [])
          : (raw as List? ?? []);
      final cats = items
          .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
      await LocalDbService.instance.upsertCategories(cats);
      await LocalDbService.instance.setLastSynced('categories');
      debugPrint('[OfflineCache] categories: ${cats.length} mis en cache');
    } catch (e) {
      debugPrint('[OfflineCache] categories sync error: $e');
    }
  }

  // ── Dépôts ────────────────────────────────────────────────────────────────

  Future<void> _syncWarehouses() async {
    try {
      final res = await dio.get('/api/warehouses/');
      final raw = res.data;
      final items = raw is Map
          ? (raw['data'] as List? ?? [])
          : (raw as List? ?? []);
      final warehouses = items
          .map((e) => WarehouseModel.fromJson(e as Map<String, dynamic>))
          .toList();
      await LocalDbService.instance.upsertWarehouses(warehouses);
      await LocalDbService.instance.setLastSynced('warehouses');
      debugPrint('[OfflineCache] warehouses: ${warehouses.length} mis en cache');
    } catch (e) {
      debugPrint('[OfflineCache] warehouses sync error: $e');
    }
  }
}
