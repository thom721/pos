import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uuid/uuid.dart';

import 'package:pos_connect/data/models/customer_model.dart';
import 'package:pos_connect/data/models/paginated_response.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/purchase_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
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
      version: 3,
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
    if (oldVersion < 3) {
      await _createSalesTables(db);
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
        local_id      TEXT,
        name          TEXT NOT NULL,
        phone         TEXT NOT NULL DEFAULT '',
        nif           TEXT,
        email         TEXT,
        address       TEXT NOT NULL DEFAULT '',
        credit_limit  REAL NOT NULL DEFAULT 0,
        synced        INTEGER NOT NULL DEFAULT 1
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
    await _createSalesTables(db);
  }

  Future<void> _createSalesTables(Database db) async {
    // Ajouter colonne synced + local_id à customers (migration v2→v3)
    try {
      await db.execute('ALTER TABLE customers ADD COLUMN synced INTEGER NOT NULL DEFAULT 1');
      await db.execute('ALTER TABLE customers ADD COLUMN local_id TEXT');
    } catch (_) {} // colonnes déjà présentes
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id             TEXT PRIMARY KEY,
        reference      TEXT NOT NULL DEFAULT '',
        customer_id    TEXT,
        customer_name  TEXT,
        warehouse_id   TEXT,
        total_amount   REAL NOT NULL DEFAULT 0,
        discount       REAL NOT NULL DEFAULT 0,
        final_amount   REAL NOT NULL DEFAULT 0,
        paid_amount    REAL NOT NULL DEFAULT 0,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        status         TEXT NOT NULL DEFAULT 'UNPAID',
        created_at     TEXT NOT NULL,
        synced         INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id             TEXT PRIMARY KEY,
        sale_id        TEXT NOT NULL,
        product_id     TEXT NOT NULL,
        product_name   TEXT,
        quantity       REAL NOT NULL,
        unit_price     REAL NOT NULL,
        original_price REAL,
        subtotal       REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_payments (
        id         TEXT PRIMARY KEY,
        sale_id    TEXT NOT NULL,
        amount     REAL NOT NULL,
        method     TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_created ON sales (created_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items (sale_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id            TEXT PRIMARY KEY,
        supplier_id   TEXT,
        supplier_name TEXT,
        warehouse_id  TEXT,
        total_amount  REAL NOT NULL DEFAULT 0,
        paid_amount   REAL NOT NULL DEFAULT 0,
        status        TEXT NOT NULL DEFAULT 'pending',
        created_at    TEXT NOT NULL,
        synced        INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_items (
        id          TEXT PRIMARY KEY,
        purchase_id TEXT NOT NULL,
        product_id  TEXT NOT NULL,
        product_name TEXT,
        quantity    REAL NOT NULL,
        unit_price  REAL NOT NULL,
        subtotal    REAL NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON purchase_items (purchase_id)');
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

  // ── Ventes (offline-first) ────────────────────────────────────────────────

  /// Insère une vente localement avant l'envoi cloud.
  /// Retourne le [saleId] généré (UUID client).
  Future<String> insertLocalSale({
    required Map<String, dynamic> payload,
    required String? customerName,
  }) async {
    final db = _safeDb;
    if (db == null) throw StateError('SQLite non disponible');

    final saleId   = const Uuid().v4();
    final now      = DateTime.now().toUtc().toIso8601String();
    final total    = (payload['items'] as List).fold<double>(
      0, (s, i) => s + (i['subtotal'] as num).toDouble());
    final discount = (payload['discount'] as num?)?.toDouble() ?? 0;
    final paid     = (payload['paid_amount'] as num?)?.toDouble() ?? 0;

    await db.insert('sales', {
      'id':             saleId,
      'reference':      'HL-${DateTime.now().millisecondsSinceEpoch}',
      'customer_id':    payload['customer_id'],
      'customer_name':  customerName,
      'warehouse_id':   payload['warehouse_id'],
      'total_amount':   total,
      'discount':       discount,
      'final_amount':   total - discount,
      'paid_amount':    paid,
      'payment_method': payload['payment_method'] ?? 'CASH',
      'status':         paid >= (total - discount) ? 'PAID' : 'UNPAID',
      'created_at':     now,
      'synced':         0,
    });

    final batch = db.batch();
    for (final item in (payload['items'] as List)) {
      batch.insert('sale_items', {
        'id':             const Uuid().v4(),
        'sale_id':        saleId,
        'product_id':     item['product_id'],
        'product_name':   item['product_name'],
        'quantity':       item['quantity'],
        'unit_price':     item['unit_price'],
        'original_price': item['original_price'],
        'subtotal':       item['subtotal'],
      });
    }
    await batch.commit(noResult: true);

    return saleId;
  }

  /// Marque une vente locale comme synchronisée et met à jour la référence serveur.
  Future<void> markSaleSynced(String localId, String reference) async {
    final db = _safeDb;
    if (db == null) return;
    await db.update(
      'sales',
      {'synced': 1, 'reference': reference},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Insère ou met à jour des ventes reçues du cloud.
  Future<void> upsertSales(List<SaleModel> sales) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final s in sales) {
      batch.insert('sales', {
        'id':             s.id,
        'reference':      s.reference,
        'customer_id':    s.customerId,
        'customer_name':  s.customerName,
        'total_amount':   s.totalAmount,
        'discount':       s.discount,
        'final_amount':   s.finalAmount,
        'paid_amount':    s.paidAmount,
        'payment_method': s.payments.isNotEmpty ? s.payments.first.method : 'CASH',
        'status':         s.status,
        'created_at':     s.createdAt.toUtc().toIso8601String(),
        'synced':         1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final item in s.items) {
        batch.insert('sale_items', {
          'id':           item.id.isEmpty ? const Uuid().v4() : item.id,
          'sale_id':      s.id,
          'product_id':   item.productId,
          'product_name': item.productName,
          'quantity':     item.quantity,
          'unit_price':   item.unitPrice,
          'original_price': item.originalPrice,
          'subtotal':     item.subtotal,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<PaginatedResponse<SaleModel>> getSales({
    String? search,
    String? status,
    int page = 1,
    int limit = 15,
  }) async {
    final db = _safeDb;
    if (db == null) {
      return PaginatedResponse(
        data: const [],
        meta: PaginationMeta(page: 1, limit: limit, total: 0, pages: 1),
      );
    }

    final where = <String>[];
    final args  = <dynamic>[];
    if (search != null && search.isNotEmpty) {
      where.add('(reference LIKE ? OR customer_name LIKE ?)');
      args.addAll(['%$search%', '%$search%']);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    final whereStr = where.isEmpty ? null : where.join(' AND ');

    final total = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM sales${whereStr != null ? ' WHERE $whereStr' : ''}',
      args,
    )) ?? 0;

    final rows = await db.query(
      'sales',
      where: whereStr,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: (page - 1) * limit,
    );

    final sales = <SaleModel>[];
    for (final row in rows) {
      final itemRows = await db.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [row['id']],
      );
      sales.add(_saleFromRow(row, itemRows));
    }

    return PaginatedResponse(
      data: sales,
      meta: PaginationMeta(
        page: page, limit: limit, total: total,
        pages: (total / limit).ceil().clamp(1, 99999),
      ),
    );
  }

  // ── Clients (offline-first) ───────────────────────────────────────────────

  /// Insère un client localement avec un UUID temporaire.
  /// Retourne le [localId] généré.
  Future<String> insertLocalCustomer({
    required String name,
    required String phone,
    String? nif,
    String? email,
    String? address,
    double creditLimit = 0,
  }) async {
    final db = _safeDb;
    if (db == null) throw StateError('SQLite non disponible');
    final localId = const Uuid().v4();
    await db.insert('customers', {
      'id':           localId,
      'local_id':     localId,
      'name':         name,
      'phone':        phone,
      'nif':          nif,
      'email':        email,
      'address':      address ?? '',
      'credit_limit': creditLimit,
      'synced':       0,
    });
    return localId;
  }

  /// Remplace l'UUID local par le vrai ID serveur après sync.
  Future<void> markCustomerSynced(String localId, String serverId) async {
    final db = _safeDb;
    if (db == null) return;
    if (localId == serverId) {
      await db.update('customers', {'synced': 1},
          where: 'id = ?', whereArgs: [localId]);
      return;
    }
    // Mettre à jour l'ID avec le vrai ID serveur
    await db.execute(
      'UPDATE customers SET id = ?, synced = 1 WHERE id = ?',
      [serverId, localId],
    );
  }

  Future<SaleModel?> getLocalSale(String id) async {
    final db = _safeDb;
    if (db == null) return null;
    final rows = await db.query('sales', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final itemRows = await db.query('sale_items', where: 'sale_id = ?', whereArgs: [id]);
    return _saleFromRow(rows.first, itemRows);
  }

  Future<void> deleteSale(String saleId) async {
    final db = _safeDb;
    if (db == null) return;
    await db.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
    await db.delete('sales', where: 'id = ?', whereArgs: [saleId]);
  }

  /// Décrémente le stock d'un produit lors d'une vente offline.
  Future<void> decrementStock(String productId, double qty) async {
    final db = _safeDb;
    if (db == null) return;
    await db.rawUpdate(
      'UPDATE products SET stock = MAX(0, COALESCE(stock, 0) - ?) WHERE id = ?',
      [qty, productId],
    );
  }

  SaleModel _saleFromRow(Map<String, dynamic> row, List<Map<String, dynamic>> itemRows) {
    return SaleModel(
      id:           row['id'] as String,
      reference:    row['reference'] as String,
      totalAmount:  (row['total_amount'] as num).toDouble(),
      discount:     (row['discount'] as num).toDouble(),
      finalAmount:  (row['final_amount'] as num).toDouble(),
      paidAmount:   (row['paid_amount'] as num).toDouble(),
      status:       row['status'] as String,
      createdAt:    DateTime.parse(row['created_at'] as String).toLocal(),
      customerName: row['customer_name'] as String?,
      customerId:   row['customer_id'] as String?,
      items: itemRows.map((r) => SaleItemModel(
        id:            r['id'] as String,
        productId:     r['product_id'] as String,
        productName:   r['product_name'] as String?,
        quantity:      (r['quantity'] as num).toDouble(),
        unitPrice:     (r['unit_price'] as num).toDouble(),
        originalPrice: r['original_price'] != null ? (r['original_price'] as num).toDouble() : null,
        subtotal:      (r['subtotal'] as num).toDouble(),
      )).toList(),
      payments: const [],
    );
  }

  // ── Achats (offline-first) ────────────────────────────────────────────────

  /// Insère un achat localement avant l'envoi cloud.
  /// Retourne le [purchaseId] généré (UUID client).
  Future<String> insertLocalPurchase({
    required Map<String, dynamic> payload,
  }) async {
    final db = _safeDb;
    if (db == null) throw StateError('SQLite non disponible');

    final purchaseId = const Uuid().v4();
    final now        = DateTime.now().toUtc().toIso8601String();
    final total      = (payload['items'] as List).fold<double>(
      0, (s, i) => s + (i['subtotal'] as num).toDouble());
    final paid       = (payload['paid_amount'] as num?)?.toDouble() ?? 0;

    await db.insert('purchases', {
      'id':           purchaseId,
      'supplier_id':  payload['supplier_id'],
      'supplier_name': payload['supplier_name'],
      'warehouse_id': payload['warehouse_id'],
      'total_amount': total,
      'paid_amount':  paid,
      'status':       paid >= total ? 'paid' : 'pending',
      'created_at':   now,
      'synced':       0,
    });

    final batch = db.batch();
    for (final item in (payload['items'] as List)) {
      batch.insert('purchase_items', {
        'id':           const Uuid().v4(),
        'purchase_id':  purchaseId,
        'product_id':   item['product_id'],
        'product_name': item['product_name'],
        'quantity':     item['quantity'],
        'unit_price':   item['unit_price'],
        'subtotal':     item['subtotal'],
      });
    }
    await batch.commit(noResult: true);

    return purchaseId;
  }

  /// Marque un achat local comme synchronisé et met à jour la référence serveur.
  Future<void> markPurchaseSynced(String localId, String reference) async {
    final db = _safeDb;
    if (db == null) return;
    await db.rawUpdate(
      'UPDATE purchases SET synced = 1 WHERE id = ?',
      [localId],
    );
  }

  /// Insère ou met à jour des achats reçus du cloud.
  Future<void> upsertPurchases(List<PurchaseModel> purchases) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final p in purchases) {
      batch.insert('purchases', {
        'id':           p.id,
        'supplier_id':  p.supplierId,
        'supplier_name': p.supplierName,
        'total_amount': p.totalAmount,
        'paid_amount':  p.paidAmount,
        'status':       p.status,
        'created_at':   p.createdAt.toUtc().toIso8601String(),
        'synced':       1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final item in p.items) {
        batch.insert('purchase_items', {
          'id':           item.id.isEmpty ? const Uuid().v4() : item.id,
          'purchase_id':  p.id,
          'product_id':   item.productId,
          'product_name': item.productName,
          'quantity':     item.orderedQty,
          'unit_price':   item.unitPrice,
          'subtotal':     item.subtotal,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<PaginatedResponse<PurchaseModel>> getPurchases({
    String? search,
    String? status,
    int page = 1,
    int limit = 15,
  }) async {
    final db = _safeDb;
    if (db == null) {
      return PaginatedResponse(
        data: const [],
        meta: PaginationMeta(page: 1, limit: limit, total: 0, pages: 1),
      );
    }

    final where = <String>[];
    final args  = <dynamic>[];
    if (search != null && search.isNotEmpty) {
      where.add('supplier_name LIKE ?');
      args.add('%$search%');
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    final whereStr = where.isEmpty ? null : where.join(' AND ');

    final total = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM purchases${whereStr != null ? ' WHERE $whereStr' : ''}',
      args,
    )) ?? 0;

    final rows = await db.query(
      'purchases',
      where: whereStr,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: (page - 1) * limit,
    );

    final purchases = <PurchaseModel>[];
    for (final row in rows) {
      final itemRows = await db.query(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: [row['id']],
      );
      purchases.add(_purchaseFromRow(row, itemRows));
    }

    return PaginatedResponse(
      data: purchases,
      meta: PaginationMeta(
        page: page, limit: limit, total: total,
        pages: (total / limit).ceil().clamp(1, 99999),
      ),
    );
  }

  /// Incrémente le stock d'un produit lors d'un achat offline.
  Future<void> incrementStock(String productId, double qty) async {
    final db = _safeDb;
    if (db == null) return;
    await db.rawUpdate(
      'UPDATE products SET stock = COALESCE(stock, 0) + ? WHERE id = ?',
      [qty, productId],
    );
  }

  PurchaseModel _purchaseFromRow(
      Map<String, dynamic> row, List<Map<String, dynamic>> itemRows) {
    return PurchaseModel(
      id:           row['id'] as String,
      reference:    '',
      totalAmount:  (row['total_amount'] as num).toDouble(),
      paidAmount:   (row['paid_amount'] as num).toDouble(),
      status:       row['status'] as String,
      createdAt:    DateTime.parse(row['created_at'] as String).toLocal(),
      supplierName: row['supplier_name'] as String?,
      supplierId:   row['supplier_id'] as String?,
      items: itemRows.map((r) => PurchaseItemModel(
        id:          r['id'] as String,
        productId:   r['product_id'] as String,
        productName: r['product_name'] as String?,
        orderedQty:  (r['quantity'] as num).toDouble(),
        unitPrice:   (r['unit_price'] as num).toDouble(),
        subtotal:    (r['subtotal'] as num).toDouble(),
      )).toList(),
    );
  }
}
