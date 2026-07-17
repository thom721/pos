import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pos_connect/data/models/customer_model.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';

/// Cache SQLite local pour les données critiques POS (produits, clients, catégories).
///
/// Alimenté par [OfflineCacheService] lors des syncs.
/// Consulté par les repositories quand l'API est inaccessible.
class LocalDbService {
  LocalDbService._();
  static final LocalDbService instance = LocalDbService._();

  Database? _db;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_db != null) return;
    if (kIsWeb) return; // SQLite non disponible sur web

    if (!Platform.isAndroid && !Platform.isIOS) {
      // Windows / macOS / Linux : utiliser l'implémentation FFI
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = join(await getDatabasesPath(), 'pos_cache.db');
    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: _createSchema,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS warehouses (
          id          TEXT PRIMARY KEY,
          name        TEXT NOT NULL,
          description TEXT,
          is_default  INTEGER NOT NULL DEFAULT 0,
          is_active   INTEGER NOT NULL DEFAULT 1
        )
      ''');
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id            TEXT PRIMARY KEY,
        name          TEXT NOT NULL,
        barcode       TEXT,
        sale_price    REAL NOT NULL DEFAULT 0,
        purchase_price REAL NOT NULL DEFAULT 0,
        alert_stock   INTEGER NOT NULL DEFAULT 0,
        stock         INTEGER,
        category_id   TEXT,
        category_name TEXT,
        image_url     TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id            TEXT PRIMARY KEY,
        name          TEXT NOT NULL,
        phone         TEXT NOT NULL DEFAULT '',
        nif           TEXT,
        email         TEXT,
        address       TEXT NOT NULL DEFAULT '',
        credit_limit  REAL NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id   TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_meta (
        entity_type   TEXT PRIMARY KEY,
        last_synced_at TEXT NOT NULL
      )
    ''');

    // Index pour la recherche texte
    await db.execute('''
      CREATE TABLE warehouses (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        description TEXT,
        is_default  INTEGER NOT NULL DEFAULT 0,
        is_active   INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('CREATE INDEX idx_products_name ON products (name)');
    await db.execute('CREATE INDEX idx_customers_name ON customers (name)');
  }

  Database? get _safeDb => kIsWeb ? null : _db;

  // ── Produits ──────────────────────────────────────────────────────────────

  Future<void> upsertProducts(List<ProductModel> products) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final p in products) {
      batch.insert(
        'products',
        {
          'id': p.id,
          'name': p.name,
          'barcode': p.barcode,
          'sale_price': p.salePrice,
          'purchase_price': p.purchasePrice,
          'alert_stock': p.alertStock,
          'stock': p.stock,
          'category_id': p.category?.id,
          'category_name': p.category?.name,
          'image_url': p.imageUrl,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<PaginatedResponse<ProductModel>> getProducts({
    String? search,
    int page = 1,
    int limit = 20,
    String? categoryId,
  }) async {
    final db = _safeDb;
    if (db == null) return _emptyProducts(limit);

    final where = <String>[];
    final args = <dynamic>[];

    if (search != null && search.isNotEmpty) {
      where.add('(name LIKE ? OR barcode LIKE ?)');
      args.addAll(['%$search%', '%$search%']);
    }
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }

    final whereStr = where.isEmpty ? null : where.join(' AND ');
    final total = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM products${whereStr != null ? ' WHERE $whereStr' : ''}',
            args,
          ),
        ) ??
        0;

    final rows = await db.query(
      'products',
      where: whereStr,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name ASC',
      limit: limit,
      offset: (page - 1) * limit,
    );

    return PaginatedResponse(
      data: rows.map(_productFromRow).toList(),
      meta: PaginationMeta(
        page: page,
        limit: limit,
        total: total,
        pages: (total / limit).ceil().clamp(1, 99999),
      ),
    );
  }

  Future<PaginatedResponse<ProductModel>> searchForSale({
    String? search,
    int page = 1,
    int perPage = 20,
  }) =>
      getProducts(search: search, page: page, limit: perPage);

  ProductModel _productFromRow(Map<String, dynamic> row) => ProductModel(
        id: row['id'] as String,
        name: row['name'] as String,
        barcode: row['barcode'] as String?,
        salePrice: (row['sale_price'] as num).toDouble(),
        purchasePrice: (row['purchase_price'] as num).toDouble(),
        alertStock: row['alert_stock'] as int,
        stock: row['stock'] as int?,
        category: row['category_id'] != null
            ? CategoryModel(
                id: row['category_id'] as String,
                name: (row['category_name'] as String?) ?? '',
              )
            : null,
        imageUrl: row['image_url'] as String?,
      );

  PaginatedResponse<ProductModel> _emptyProducts(int limit) => PaginatedResponse(
        data: const [],
        meta: PaginationMeta(page: 1, limit: limit, total: 0, pages: 1),
      );

  // ── Clients ───────────────────────────────────────────────────────────────

  Future<void> upsertCustomers(List<CustomerModel> customers) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final c in customers) {
      batch.insert(
        'customers',
        {
          'id': c.id,
          'name': c.name,
          'phone': c.phone,
          'nif': c.nif,
          'email': c.email,
          'address': c.address,
          'credit_limit': c.creditLimit,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<PaginatedResponse<CustomerModel>> getCustomers({
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final db = _safeDb;
    if (db == null) {
      return PaginatedResponse(
        data: const [],
        meta: PaginationMeta(page: 1, limit: limit, total: 0, pages: 1),
      );
    }

    final where = <String>[];
    final args = <dynamic>[];
    if (search != null && search.isNotEmpty) {
      where.add('(name LIKE ? OR phone LIKE ?)');
      args.addAll(['%$search%', '%$search%']);
    }
    final whereStr = where.isEmpty ? null : where.join(' AND ');
    final total = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM customers${whereStr != null ? ' WHERE $whereStr' : ''}',
            args,
          ),
        ) ??
        0;

    final rows = await db.query(
      'customers',
      where: whereStr,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name ASC',
      limit: limit,
      offset: (page - 1) * limit,
    );

    return PaginatedResponse(
      data: rows.map(_customerFromRow).toList(),
      meta: PaginationMeta(
        page: page,
        limit: limit,
        total: total,
        pages: (total / limit).ceil().clamp(1, 99999),
      ),
    );
  }

  CustomerModel _customerFromRow(Map<String, dynamic> row) => CustomerModel(
        id: row['id'] as String,
        name: row['name'] as String,
        phone: row['phone'] as String,
        nif: row['nif'] as String?,
        email: row['email'] as String?,
        address: row['address'] as String,
        creditLimit: (row['credit_limit'] as num).toDouble(),
      );

  // ── Catégories ────────────────────────────────────────────────────────────

  Future<void> upsertCategories(List<CategoryModel> categories) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final c in categories) {
      batch.insert(
        'categories',
        {'id': c.id, 'name': c.name},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<CategoryModel>> getCategories() async {
    final db = _safeDb;
    if (db == null) return const [];
    final rows = await db.query('categories', orderBy: 'name ASC');
    return rows
        .map((r) => CategoryModel(
              id: r['id'] as String,
              name: r['name'] as String,
            ))
        .toList();
  }

  // ── Dépôts ───────────────────────────────────────────────────────────────

  Future<void> upsertWarehouses(List<WarehouseModel> warehouses) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final w in warehouses) {
      batch.insert(
        'warehouses',
        {
          'id': w.id,
          'name': w.name,
          'description': w.description,
          'is_default': w.isDefault ? 1 : 0,
          'is_active': w.isActive ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<WarehouseModel>> getWarehouses() async {
    final db = _safeDb;
    if (db == null) return const [];
    final rows = await db.query(
      'warehouses',
      where: 'is_active = 1',
      orderBy: 'is_default DESC, name ASC',
    );
    return rows.map((r) => WarehouseModel(
          id: r['id'] as String,
          name: r['name'] as String,
          description: r['description'] as String?,
          isDefault: (r['is_default'] as int) == 1,
          isActive: (r['is_active'] as int) == 1,
        )).toList();
  }

  // ── Méta-sync ─────────────────────────────────────────────────────────────

  Future<void> setLastSynced(String entityType) async {
    final db = _safeDb;
    if (db == null) return;
    await db.insert(
      'sync_meta',
      {'entity_type': entityType, 'last_synced_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DateTime?> getLastSynced(String entityType) async {
    final db = _safeDb;
    if (db == null) return null;
    final rows = await db.query(
      'sync_meta',
      where: 'entity_type = ?',
      whereArgs: [entityType],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['last_synced_at'] as String);
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────

  Future<bool> isEmpty(String table) async {
    final db = _safeDb;
    if (db == null) return true;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table'),
        ) ??
        0;
    return count == 0;
  }
}
