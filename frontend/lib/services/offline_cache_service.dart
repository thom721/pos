import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/customer_model.dart';
import 'package:pos_connect/data/models/debt_model.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/purchase_model.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/data/models/supplier_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/services/local_db_service.dart';

bool _isPermissionDenied(Object e) =>
    e is DioException && e.response?.statusCode == 403;

/// Sur bureau (Windows/Linux/macOS) on cache tout sans filtre type.
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Synchronise les données critiques API → SQLite local.
///
/// Appelé :
///  - au login (warm-up initial du cache)
///  - à chaque cycle de sync automatique (toutes les 5 min dans app.dart)
///
/// [businessType] : 'commerce' | 'restaurant' | 'depot' | 'hotel'
/// Sur desktop, tout est caché indépendamment du type.
///
/// Ne lève jamais d'exception vers l'appelant.
class OfflineCacheService {
  OfflineCacheService._();
  static final OfflineCacheService instance = OfflineCacheService._();

  bool _running = false;

  // ── API publique ──────────────────────────────────────────────────────────

  Future<void> syncAll({
    String? warehouseId,
    String? tenantId,
    String businessType = 'commerce',
  }) async {
    if (kIsWeb || _running) return;
    _running = true;
    try {
      if (tenantId != null) {
        final prefs = await SharedPreferences.getInstance();
        final cachedTenant    = prefs.getString('_cache_tenant_id');
        final cachedWarehouse = prefs.getString('_cache_warehouse_id');
        // Ne vider que si le TENANT change, ou si le warehouse passe d'une valeur
        // connue à une valeur DIFFÉRENTE. Le passage null→valeur (premier chargement
        // du warehouse actif) ne doit PAS déclencher un vidage — c'est la cause
        // des disparitions de ventes après la première sync.
        final warehouseChanged = cachedWarehouse != null && cachedWarehouse != warehouseId;
        final changed = cachedTenant != null &&
            (cachedTenant != tenantId || warehouseChanged);
        if (changed) {
          await LocalDbService.instance.clearAllCachedData();
          debugPrint('[OfflineCache] tenant/warehouse changé ($cachedTenant→$tenantId'
              ' / $cachedWarehouse→$warehouseId) → cache vidé');
        }
        await prefs.setString('_cache_tenant_id', tenantId);
        if (warehouseId != null) {
          await prefs.setString('_cache_warehouse_id', warehouseId);
        } else {
          await prefs.remove('_cache_warehouse_id');
        }
      }
      // ── Base commune — tous les types ──────────────────────────────────
      await Future.wait([
        _syncProducts(),
        _syncCustomers(),
        _syncCategories(),
        _syncWarehouses(),
        _syncSales(warehouseId: warehouseId),
        _syncPurchases(warehouseId: warehouseId),
        _syncDebts(),
        _syncUsers(warehouseId: warehouseId),
        _syncSessions(warehouseId: warehouseId),
        _syncSuppliers(),               // fournisseurs utiles partout
      ]);

      // ── Tables métier — selon type ou desktop ──────────────────────────
      final syncRestaurant = _isDesktop ||
          businessType == 'restaurant' ||
          businessType == 'hotel';
      final syncHotel      = _isDesktop || businessType == 'hotel';
      final syncMenu       = _isDesktop || businessType == 'restaurant';

      if (syncRestaurant) {
        await Future.wait([
          _syncRestaurantTables(warehouseId: warehouseId),
          _syncRestaurantOrders(warehouseId: warehouseId),
        ]);
      }
      if (syncMenu) {
        await _syncMenuItems(warehouseId: warehouseId);
      }
      if (syncHotel) {
        await _syncHousekeepingTasks(warehouseId: warehouseId);
      }
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
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] products sync error: $e');
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
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] customers sync error: $e');
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
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] categories sync error: $e');
    }
  }

  // ── Ventes ────────────────────────────────────────────────────────────────

  Future<void> _syncSales({String? warehouseId}) async {
    try {
      final all = <SaleModel>[];
      int page = 1;
      while (true) {
        final res = await dio.get('/api/sales/',
            queryParameters: {
              'page': page,
              'limit': 100,
              if (warehouseId != null) 'warehouse_id': warehouseId,
            },
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
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] sales sync error: $e');
    }
  }

  // ── Achats ────────────────────────────────────────────────────────────────

  Future<void> _syncPurchases({String? warehouseId}) async {
    try {
      final all = <PurchaseModel>[];
      int page = 1;
      while (true) {
        final res = await dio.get('/api/purchases/',
            queryParameters: {
              'page': page,
              'limit': 100,
              if (warehouseId != null) 'warehouse_id': warehouseId,
            },
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
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] purchases sync error: $e');
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
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] warehouses sync error: $e');
    }
  }

  // ── Utilisateurs (auth hors ligne) ────────────────────────────────────────

  Future<void> _syncUsers({String? warehouseId}) async {
    try {
      final res = await dio.get('/api/users/offline-sync',
          queryParameters: {
            if (warehouseId != null) 'warehouse_id': warehouseId,
          },
          options: kBackgroundOptions);
      final raw = res.data;
      final items = raw is List
          ? raw.cast<Map<String, dynamic>>()
          : ((raw['data'] as List? ?? []).cast<Map<String, dynamic>>());
      await LocalDbService.instance.upsertLocalUsers(items);
      debugPrint('[OfflineCache] users: ${items.length} en cache local');
    } catch (e) {
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] users sync error: $e');
    }
  }

  // ── Dettes ───────────────────────────────────────────────────────────────

  Future<void> _syncDebts() async {
    try {
      final all = <DebtModel>[];
      int page = 1;
      while (true) {
        final res = await dio.get(
          '/api/debts/',
          queryParameters: {'page': page, 'limit': 100},
          options: kBackgroundOptions,
        );
        final data = res.data as Map<String, dynamic>;
        final items = (data['data'] as List? ?? [])
            .map((e) => DebtModel.fromJson(e as Map<String, dynamic>))
            .toList();
        all.addAll(items);
        final totalPages = (data['meta']?['pages'] ?? data['pages'] ?? 1) as int;
        if (page >= totalPages) break;
        page++;
      }
      await LocalDbService.instance.upsertDebts(all);
      await LocalDbService.instance.setLastSynced('debts');
      debugPrint('[OfflineCache] debts: ${all.length} mis en cache');
    } catch (e) {
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] debts sync error: $e');
    }
  }

  // ── Sessions caisse ───────────────────────────────────────────────────────

  Future<void> _syncSessions({String? warehouseId}) async {
    try {
      final res = await dio.get(
        '/api/sessions/',
        queryParameters: {
          'page': 1,
          'limit': 100,
          if (warehouseId != null) 'warehouse_id': warehouseId,
        },
        options: kBackgroundOptions,
      );
      final data = res.data as Map<String, dynamic>;
      final items = (data['data'] as List? ?? []).cast<Map<String, dynamic>>();
      await LocalDbService.instance.upsertSessions(items);
      await LocalDbService.instance.setLastSynced('cashier_sessions');
      debugPrint('[OfflineCache] sessions: ${items.length} mis en cache');
    } catch (e) {
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] sessions sync error: $e');
    }
  }

  // ── Fournisseurs ──────────────────────────────────────────────────────────

  Future<void> _syncSuppliers() async {
    try {
      final res = await dio.get('/api/suppliers/', options: kBackgroundOptions);
      final raw = res.data;
      final items = (raw is Map
              ? (raw['data'] as List? ?? [])
              : (raw as List? ?? []))
          .map((e) => SupplierModel.fromJson(e as Map<String, dynamic>))
          .toList();
      await LocalDbService.instance.upsertSuppliers(items);
      await LocalDbService.instance.deleteStaleSuppliers(
          items.map((s) => s.id).toList());
      await LocalDbService.instance.setLastSynced('suppliers');
      debugPrint('[OfflineCache] suppliers: ${items.length} mis en cache');
    } catch (e) {
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] suppliers sync error: $e');
    }
  }

  // ── Tables / Chambres restaurant ─────────────────────────────────────────

  Future<void> _syncRestaurantTables({String? warehouseId}) async {
    try {
      final res = await dio.get('/api/restaurant/tables/',
          queryParameters: warehouseId != null
              ? {'warehouse_id': warehouseId} : null,
          options: kBackgroundOptions);
      final items = (res.data as List)
          .map((e) => RestaurantTableModel.fromJson(e as Map<String, dynamic>))
          .toList();
      await LocalDbService.instance.upsertRestaurantTables(
          items, warehouseId: warehouseId);
      await LocalDbService.instance.deleteStaleRestaurantTables(
          items.map((t) => t.id).toList(), warehouseId: warehouseId);
      await LocalDbService.instance.setLastSynced('restaurant_tables');
      debugPrint('[OfflineCache] restaurant_tables: ${items.length} mis en cache');
    } catch (e) {
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] tables sync error: $e');
    }
  }

  // ── Commandes ouvertes restaurant ─────────────────────────────────────────

  Future<void> _syncRestaurantOrders({String? warehouseId}) async {
    try {
      final res = await dio.get('/api/restaurant/orders/',
          queryParameters: warehouseId != null
              ? {'warehouse_id': warehouseId} : null,
          options: kBackgroundOptions);
      final items = (res.data as List)
          .map((e) => RestaurantOrderModel.fromJson(e as Map<String, dynamic>))
          .toList();
      await LocalDbService.instance.upsertRestaurantOrders(
          items, warehouseId: warehouseId);
      await LocalDbService.instance.deleteStaleRestaurantOrders(
          items.map((o) => o.id).toList(), warehouseId: warehouseId);
      await LocalDbService.instance.setLastSynced('restaurant_orders');
      debugPrint('[OfflineCache] restaurant_orders: ${items.length} mis en cache');
    } catch (e) {
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] orders sync error: $e');
    }
  }

  // ── Menu items ────────────────────────────────────────────────────────────

  Future<void> _syncMenuItems({String? warehouseId}) async {
    try {
      final res = await dio.get('/api/restaurant/menu-items/',
          queryParameters: {
            if (warehouseId != null) 'warehouse_id': warehouseId,
          },
          options: kBackgroundOptions);
      final items = (res.data as List)
          .map((e) => MenuItemModel.fromJson(e as Map<String, dynamic>))
          .toList();
      await LocalDbService.instance.upsertMenuItems(
          items, warehouseId: warehouseId);
      await LocalDbService.instance.deleteStaleMenuItems(
          items.map((m) => m.id).toList(), warehouseId: warehouseId);
      await LocalDbService.instance.setLastSynced('menu_items');
      debugPrint('[OfflineCache] menu_items: ${items.length} mis en cache');
    } catch (e) {
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] menu_items sync error: $e');
    }
  }

  // ── Tâches housekeeping ───────────────────────────────────────────────────

  Future<void> _syncHousekeepingTasks({String? warehouseId}) async {
    try {
      final res = await dio.get('/api/restaurant/housekeeping/tasks',
          queryParameters: warehouseId != null
              ? {'warehouse_id': warehouseId} : null,
          options: kBackgroundOptions);
      final items = (res.data as List)
          .map((e) => HousekeepingTaskModel.fromJson(e as Map<String, dynamic>))
          .toList();
      await LocalDbService.instance.upsertHousekeepingTasks(items);
      await LocalDbService.instance.deleteStaleHousekeepingTasks(
          items.map((t) => t.id).toList(), warehouseId: warehouseId);
      await LocalDbService.instance.setLastSynced('housekeeping_tasks');
      debugPrint('[OfflineCache] housekeeping: ${items.length} mis en cache');
    } catch (e) {
      if (!_isPermissionDenied(e)) debugPrint('[OfflineCache] housekeeping sync error: $e');
    }
  }
}
