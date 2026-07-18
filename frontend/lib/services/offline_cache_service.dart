import 'package:flutter/foundation.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/customer_model.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/purchase_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
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
        _syncSales(),
        _syncPurchases(),
        _syncUsers(),
        _syncSessions(),
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
        final res = await dio.get('/api/products/',
            queryParameters: {'page': page, 'per_page': 100},
            options: kBackgroundOptions);
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
      // Supprimer les produits supprimés côté serveur
      await LocalDbService.instance.deleteStaleProducts(all.map((p) => p.id).toList());
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
        final res = await dio.get('/api/customers/',
            queryParameters: {'page': page, 'limit': 200},
            options: kBackgroundOptions);
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
      await LocalDbService.instance.deleteStaleCustomers(all.map((c) => c.id).toList());
      await LocalDbService.instance.setLastSynced('customers');
      debugPrint('[OfflineCache] customers: ${all.length} mis en cache');
    } catch (e) {
      debugPrint('[OfflineCache] customers sync error: $e');
    }
  }

  // ── Catégories ────────────────────────────────────────────────────────────

  Future<void> _syncCategories() async {
    try {
      final res = await dio.get('/api/categories/', options: kBackgroundOptions);
      final raw = res.data;
      final items = raw is Map
          ? (raw['data'] as List? ?? [])
          : (raw as List? ?? []);
      final cats = items
          .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
      await LocalDbService.instance.upsertCategories(cats);
      await LocalDbService.instance.deleteStaleCategories(cats.map((c) => c.id).toList());
      await LocalDbService.instance.setLastSynced('categories');
      debugPrint('[OfflineCache] categories: ${cats.length} mis en cache');
    } catch (e) {
      debugPrint('[OfflineCache] categories sync error: $e');
    }
  }

  // ── Ventes ────────────────────────────────────────────────────────────────

  Future<void> _syncSales() async {
    try {
      final all = <SaleModel>[];
      int page = 1;
      while (true) {
        final res = await dio.get('/api/sales/',
            queryParameters: {'page': page, 'limit': 100},
            options: kBackgroundOptions);
        final raw = res.data as Map<String, dynamic>;
        final items = (raw['data'] as List? ?? [])
            .map((e) => SaleModel.fromJson(e as Map<String, dynamic>))
            .toList();
        all.addAll(items);
        final totalPages = (raw['pages'] ?? raw['meta']?['pages'] ?? 1) as int;
        if (page >= totalPages) break;
        page++;
      }
      await LocalDbService.instance.upsertSales(all);
      await LocalDbService.instance.setLastSynced('sales');
      debugPrint('[OfflineCache] sales: ${all.length} mis en cache');
    } catch (e) {
      debugPrint('[OfflineCache] sales sync error: $e');
    }
  }

  // ── Achats ────────────────────────────────────────────────────────────────

  Future<void> _syncPurchases() async {
    try {
      final all = <PurchaseModel>[];
      int page = 1;
      while (true) {
        final res = await dio.get('/api/purchases/',
            queryParameters: {'page': page, 'limit': 100},
            options: kBackgroundOptions);
        final raw = res.data as Map<String, dynamic>;
        final items = (raw['data'] as List? ?? [])
            .map((e) => PurchaseModel.fromJson(e as Map<String, dynamic>))
            .toList();
        all.addAll(items);
        final totalPages = (raw['pages'] ?? raw['meta']?['pages'] ?? 1) as int;
        if (page >= totalPages) break;
        page++;
      }
      await LocalDbService.instance.upsertPurchases(all);
      await LocalDbService.instance.setLastSynced('purchases');
      debugPrint('[OfflineCache] purchases: ${all.length} mis en cache');
    } catch (e) {
      debugPrint('[OfflineCache] purchases sync error: $e');
    }
  }

  // ── Dépôts ────────────────────────────────────────────────────────────────

  Future<void> _syncWarehouses() async {
    try {
      final res = await dio.get('/api/warehouses/', options: kBackgroundOptions);
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

  // ── Utilisateurs (auth hors ligne) ────────────────────────────────────────

  Future<void> _syncUsers() async {
    try {
      final res = await dio.get('/api/users/', options: kBackgroundOptions);
      final raw = res.data;
      final items = raw is List
          ? raw.cast<Map<String, dynamic>>()
          : ((raw['data'] as List? ?? []).cast<Map<String, dynamic>>());
      await LocalDbService.instance.upsertLocalUsers(items);
      debugPrint('[OfflineCache] users: ${items.length} en cache local');
    } catch (e) {
      debugPrint('[OfflineCache] users sync error: $e');
    }
  }

  // ── Sessions caisse ───────────────────────────────────────────────────────

  Future<void> _syncSessions() async {
    try {
      final res = await dio.get(
        '/api/sessions/',
        queryParameters: {'page': 1, 'limit': 100},
        options: kBackgroundOptions,
      );
      final data = res.data as Map<String, dynamic>;
      final items = (data['data'] as List? ?? []).cast<Map<String, dynamic>>();
      await LocalDbService.instance.upsertSessions(items);
      await LocalDbService.instance.setLastSynced('cashier_sessions');
      debugPrint('[OfflineCache] sessions: ${items.length} mis en cache');
    } catch (e) {
      debugPrint('[OfflineCache] sessions sync error: $e');
    }
  }
}
