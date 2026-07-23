import 'dart:convert';
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
import 'package:pos_connect/core/date_utils.dart' show toHaitiTime;
import 'package:pos_connect/data/models/debt_model.dart';
import 'package:pos_connect/data/models/sale_model.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/models/supplier_model.dart';
import 'package:pos_connect/data/models/restaurant_model.dart';

/// Convertit un DateTime naïf "heure Haïti" en chaîne ISO UTC.
/// [toHaitiTime] retourne un naïf non-UTC — .toUtc() utiliserait le fuseau
/// du téléphone, pas Haiti (UTC-5). Cette fonction corrige ça.
String _haitiNaiveToUtcIso(DateTime dt) {
  final asUtc = DateTime.utc(dt.year, dt.month, dt.day,
      dt.hour, dt.minute, dt.second, dt.millisecond);
  return asUtc.add(const Duration(hours: 5)).toIso8601String();
}

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
      version: 15,
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
    if (oldVersion < 4) {
      try { await db.execute("ALTER TABLE purchases ADD COLUMN reference TEXT NOT NULL DEFAULT ''"); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
    }
    if (oldVersion < 5) {
      try { await db.execute('ALTER TABLE categories ADD COLUMN description TEXT'); } catch (_) {}
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS local_users (
          email         TEXT PRIMARY KEY,
          password_hash TEXT NOT NULL,
          user_data     TEXT NOT NULL
        )
      ''');
      try { await db.execute('ALTER TABLE products ADD COLUMN description TEXT'); } catch (_) {}
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cashier_sessions (
          id               TEXT PRIMARY KEY,
          cashier_id       TEXT NOT NULL,
          cashier_name     TEXT,
          register_name    TEXT,
          status           TEXT NOT NULL DEFAULT 'open',
          opening_balance  REAL NOT NULL DEFAULT 0,
          closing_balance  REAL,
          opened_at        TEXT,
          closed_at        TEXT
        )
      ''');
    }
    if (oldVersion < 8) {
      try { await db.execute('ALTER TABLE sales ADD COLUMN cashier_name TEXT'); } catch (_) {}
    }
    if (oldVersion < 9) {
      try { await db.execute('ALTER TABLE products ADD COLUMN synced INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE categories ADD COLUMN synced INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
    }
    if (oldVersion < 10) {
      // Rendre product_id nullable pour les ventes restaurant (plats libres sans produit inventaire)
      // SQLite ne supporte pas ALTER COLUMN — on recrée la table
      try {
        await db.execute('ALTER TABLE sale_items RENAME TO sale_items_old');
        await db.execute('''
          CREATE TABLE sale_items (
            id             TEXT PRIMARY KEY,
            sale_id        TEXT NOT NULL,
            product_id     TEXT,
            label          TEXT,
            product_name   TEXT,
            quantity       REAL NOT NULL,
            unit_price     REAL NOT NULL,
            original_price REAL,
            subtotal       REAL NOT NULL
          )
        ''');
        await db.execute('''
          INSERT INTO sale_items (id, sale_id, product_id, product_name, quantity, unit_price, original_price, subtotal)
          SELECT id, sale_id, product_id, product_name, quantity, unit_price, original_price, subtotal
          FROM sale_items_old
        ''');
        await db.execute('DROP TABLE sale_items_old');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items (sale_id)');
      } catch (_) {}
    }
    if (oldVersion < 11) {
      try { await db.execute('ALTER TABLE sales ADD COLUMN user_id TEXT'); } catch (_) {}
    }
    if (oldVersion < 12) {
      try { await db.execute('ALTER TABLE sale_items ADD COLUMN returned_qty REAL NOT NULL DEFAULT 0'); } catch (_) {}
    }
    if (oldVersion < 13) {
      try { await db.execute('ALTER TABLE products ADD COLUMN warehouse_id TEXT'); } catch (_) {}
    }
    if (oldVersion < 14) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS debts (
          id            TEXT PRIMARY KEY,
          reference     TEXT NOT NULL DEFAULT '',
          partner_id    TEXT,
          partner_name  TEXT,
          total_amount  REAL NOT NULL DEFAULT 0,
          paid_amount   REAL NOT NULL DEFAULT 0,
          balance       REAL NOT NULL DEFAULT 0,
          status        TEXT NOT NULL DEFAULT 'pending',
          created_at    TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_status  ON debts (status)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_partner ON debts (partner_id)');
    }
    if (oldVersion < 15) {
      await _createBusinessTables(db);
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id             TEXT PRIMARY KEY,
        name           TEXT NOT NULL,
        barcode        TEXT,
        description    TEXT,
        sale_price     REAL NOT NULL DEFAULT 0,
        purchase_price REAL NOT NULL DEFAULT 0,
        alert_stock    INTEGER NOT NULL DEFAULT 0,
        stock          INTEGER,
        category_id    TEXT,
        category_name  TEXT,
        image_url      TEXT,
        is_active      INTEGER NOT NULL DEFAULT 1,
        synced         INTEGER NOT NULL DEFAULT 1,
        warehouse_id   TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE local_users (
        email         TEXT PRIMARY KEY,
        password_hash TEXT NOT NULL,
        user_data     TEXT NOT NULL
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
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        description TEXT,
        synced      INTEGER NOT NULL DEFAULT 1
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
        user_id        TEXT,
        warehouse_id   TEXT,
        total_amount   REAL NOT NULL DEFAULT 0,
        discount       REAL NOT NULL DEFAULT 0,
        final_amount   REAL NOT NULL DEFAULT 0,
        paid_amount    REAL NOT NULL DEFAULT 0,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        status         TEXT NOT NULL DEFAULT 'UNPAID',
        cashier_name   TEXT,
        created_at     TEXT NOT NULL,
        synced         INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id             TEXT PRIMARY KEY,
        sale_id        TEXT NOT NULL,
        product_id     TEXT,
        label          TEXT,
        product_name   TEXT,
        quantity       REAL NOT NULL,
        unit_price     REAL NOT NULL,
        original_price REAL,
        subtotal       REAL NOT NULL,
        returned_qty   REAL NOT NULL DEFAULT 0
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
      CREATE TABLE IF NOT EXISTS debts (
        id             TEXT PRIMARY KEY,
        reference_type TEXT NOT NULL DEFAULT '',
        reference_id   TEXT NOT NULL DEFAULT '',
        partner_type   TEXT NOT NULL DEFAULT 'CUSTOMER',
        partner_id     TEXT NOT NULL DEFAULT '',
        partner_name   TEXT,
        total_amount   REAL NOT NULL DEFAULT 0,
        paid_amount    REAL NOT NULL DEFAULT 0,
        balance        REAL NOT NULL DEFAULT 0,
        status         TEXT NOT NULL DEFAULT 'UNPAID',
        created_at     TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_status ON debts (status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_partner ON debts (partner_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id            TEXT PRIMARY KEY,
        reference     TEXT NOT NULL DEFAULT '',
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
    await _createBusinessTables(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cashier_sessions (
        id               TEXT PRIMARY KEY,
        cashier_id       TEXT NOT NULL,
        cashier_name     TEXT,
        register_name    TEXT,
        status           TEXT NOT NULL DEFAULT 'open',
        opening_balance  REAL NOT NULL DEFAULT 0,
        closing_balance  REAL,
        opened_at        TEXT,
        closed_at        TEXT
      )
    ''');
  }

  // ── Tables métier : fournisseurs, restaurant, hôtel ───────────────────────
  // Créées au onCreate ET à l'upgrade v14→v15.
  // Le flag IF NOT EXISTS rend la méthode idempotente dans les deux cas.

  Future<void> _createBusinessTables(Database db) async {
    // ── Fournisseurs (tous les types) ───────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id           TEXT PRIMARY KEY,
        name         TEXT NOT NULL,
        phone        TEXT,
        email        TEXT,
        address      TEXT,
        warehouse_id TEXT
      )
    ''');

    // ── Tables / Chambres (restaurant + hôtel) ──────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_tables (
        id               TEXT PRIMARY KEY,
        name             TEXT NOT NULL,
        capacity         INTEGER NOT NULL DEFAULT 4,
        status           TEXT NOT NULL DEFAULT 'free',
        price            REAL NOT NULL DEFAULT 0,
        price_per_day    REAL NOT NULL DEFAULT 0,
        price_per_moment REAL NOT NULL DEFAULT 0,
        waiter_id        TEXT,
        waiter_name      TEXT,
        warehouse_id     TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rtables_wh
        ON restaurant_tables (warehouse_id)
    ''');

    // ── Attributs chambre (hôtel) ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS room_attributes (
        id       TEXT PRIMARY KEY,
        table_id TEXT NOT NULL,
        key      TEXT NOT NULL,
        value    TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_roomattr_table
        ON room_attributes (table_id)
    ''');

    // ── Commandes restaurant ─────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_orders (
        id           TEXT PRIMARY KEY,
        table_id     TEXT,
        table_name   TEXT,
        waiter_name  TEXT,
        status       TEXT NOT NULL DEFAULT 'open',
        covers       INTEGER NOT NULL DEFAULT 1,
        subtotal     REAL NOT NULL DEFAULT 0,
        tip          REAL NOT NULL DEFAULT 0,
        total        REAL NOT NULL DEFAULT 0,
        notes        TEXT,
        warehouse_id TEXT,
        created_at   TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rorders_table
        ON restaurant_orders (table_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rorders_status
        ON restaurant_orders (status)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS restaurant_order_items (
        id           TEXT PRIMARY KEY,
        order_id     TEXT NOT NULL,
        product_id   TEXT,
        menu_item_id TEXT,
        product_name TEXT NOT NULL DEFAULT '',
        quantity     REAL NOT NULL DEFAULT 1,
        unit_price   REAL NOT NULL DEFAULT 0,
        notes        TEXT,
        status       TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rorder_items_order
        ON restaurant_order_items (order_id)
    ''');

    // ── Menu items (restaurant) ──────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS menu_items (
        id               TEXT PRIMARY KEY,
        name             TEXT NOT NULL,
        description      TEXT,
        price            REAL NOT NULL DEFAULT 0,
        category_id      TEXT,
        category_name    TEXT,
        product_id       TEXT,
        available        INTEGER NOT NULL DEFAULT 1,
        send_to_kitchen  INTEGER NOT NULL DEFAULT 1,
        image_url        TEXT,
        variants_json    TEXT,
        warehouse_id     TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_menuitems_wh
        ON menu_items (warehouse_id)
    ''');

    // ── Tâches housekeeping (hôtel) ──────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS housekeeping_tasks (
        id           TEXT PRIMARY KEY,
        table_id     TEXT NOT NULL,
        warehouse_id TEXT,
        description  TEXT NOT NULL,
        status       TEXT NOT NULL DEFAULT 'pending',
        created_at   TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_hktasks_table
        ON housekeeping_tasks (table_id)
    ''');
  }

  Database? get _safeDb => kIsWeb ? null : _db;

  // ── Réinitialisation lors du logout ──────────────────────────────────────

  /// Efface toutes les données sensibles du cache local.
  /// Appelé à la déconnexion pour éviter les fuites de données entre comptes.
  Future<void> clearAllCachedData() async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final table in [
      'local_users',
      'sale_payments',
      'sale_items',
      'sales',
      'purchase_items',
      'purchases',
      'cashier_sessions',
      'warehouses',
      'products',
      'customers',
      'categories',
      'suppliers',
      'restaurant_order_items',
      'restaurant_orders',
      'restaurant_tables',
      'room_attributes',
      'menu_items',
      'housekeeping_tasks',
      'sync_meta',
    ]) {
      batch.delete(table);
    }
    await batch.commit(noResult: true);
  }

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
          'description': p.description,
          'sale_price': p.salePrice,
          'purchase_price': p.purchasePrice,
          'alert_stock': p.alertStock,
          'stock': p.stock,
          'category_id': p.category?.id,
          'category_name': p.category?.name,
          'image_url': p.imageUrl,
          'is_active': p.isActive ? 1 : 0,
          'synced': 1,
          'warehouse_id': p.warehouseId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Supprime les produits locaux dont l'ID n'est plus présent côté serveur.
  /// N'affecte que les enregistrements synced=1 pour préserver les données offline.
  Future<void> deleteStaleProducts(List<String> serverIds) async {
    final db = _safeDb;
    if (db == null || serverIds.isEmpty) return;
    final placeholders = List.filled(serverIds.length, '?').join(',');
    await db.delete('products',
        where: 'id NOT IN ($placeholders) AND synced = 1', whereArgs: serverIds);
  }

  Future<PaginatedResponse<ProductModel>> getProducts({
    String? search,
    int page = 1,
    int limit = 20,
    String? categoryId,
  }) async {
    final db = _safeDb;
    if (db == null) return _emptyProducts(limit);

    final where = <String>['is_active = 1'];
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
        description: row['description'] as String?,
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
        warehouseId: row['warehouse_id'] as String?,
      );

  // ── Auth hors ligne ───────────────────────────────────────────────────────

  Future<void> saveLocalUser(String email, String passwordHash, String userDataJson) async {
    final db = _safeDb;
    if (db == null) return;
    await db.insert(
      'local_users',
      {'email': email, 'password_hash': passwordHash, 'user_data': userDataJson},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getLocalUser(String email) async {
    final db = _safeDb;
    if (db == null) return null;
    final rows = await db.query(
      'local_users',
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Supprime tous les users locaux sauf celui passé en paramètre.
  /// Appelé après login cloud réussi — un seul user peut se connecter
  /// offline sur ce terminal (sécurité POS).
  Future<void> clearOtherLocalUsers(String keepEmail) async {
    final db = _safeDb;
    if (db == null) return;
    await db.delete(
      'local_users',
      where: 'email != ?',
      whereArgs: [keepEmail],
    );
  }

  /// Bulk insert depuis le sync — sauvegarde tous les utilisateurs du tenant
  /// avec leur offline_hash pour permettre l'auth hors ligne.
  Future<void> upsertLocalUsers(List<Map<String, dynamic>> users) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final u in users) {
      final email = (u['email'] as String?)?.toLowerCase();
      final offlineHash = u['offline_hash'] as String?;
      if (email == null || offlineHash == null) continue;
      batch.insert(
        'local_users',
        {
          'email': email,
          'password_hash': offlineHash,
          'user_data': jsonEncode(u),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

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

  Future<void> deleteStaleCustomers(List<String> serverIds) async {
    final db = _safeDb;
    if (db == null || serverIds.isEmpty) return;
    final placeholders = List.filled(serverIds.length, '?').join(',');
    await db.delete('customers',
        where: 'id NOT IN ($placeholders) AND synced = 1', whereArgs: serverIds);
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
        {'id': c.id, 'name': c.name, 'description': c.description, 'synced': 1},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteStaleCategories(List<String> serverIds) async {
    final db = _safeDb;
    if (db == null || serverIds.isEmpty) return;
    final placeholders = List.filled(serverIds.length, '?').join(',');
    await db.delete('categories',
        where: 'id NOT IN ($placeholders) AND synced = 1', whereArgs: serverIds);
  }

  Future<List<CategoryModel>> getCategories() async {
    final db = _safeDb;
    if (db == null) return const [];
    final rows = await db.query('categories', orderBy: 'name ASC');
    return rows
        .map((r) => CategoryModel(
              id: r['id'] as String,
              name: r['name'] as String,
              description: r['description'] as String?,
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

  // ── Sessions caisse ───────────────────────────────────────────────────────

  Future<void> upsertSessions(List<Map<String, dynamic>> sessions) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final s in sessions) {
      batch.insert(
        'cashier_sessions',
        {
          'id':              s['id'],
          'cashier_id':      s['cashier_id'],
          'cashier_name':    s['cashier_name'],
          'register_name':   s['register_name'],
          'status':          s['status'] ?? 'open',
          'opening_balance': (s['opening_balance'] as num?)?.toDouble() ?? 0.0,
          'closing_balance': (s['closing_balance'] as num?)?.toDouble(),
          'opened_at':       s['opened_at']?.toString(),
          'closed_at':       s['closed_at']?.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getOpenSessions() async {
    final db = _safeDb;
    if (db == null) return [];
    return db.query(
      'cashier_sessions',
      where: 'status = ?',
      whereArgs: ['open'],
      orderBy: 'opened_at ASC',
    );
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

  // ── Transactions ─────────────────────────────────────────────────────────

  /// Exécute [action] dans une transaction SQLite atomique.
  /// Si la DB n'est pas disponible (web ou non initialisée), ne fait rien.
  Future<void> runTransaction(Future<void> Function(DatabaseExecutor txn) action) async {
    final db = _safeDb;
    if (db == null) return;
    await db.transaction((txn) => action(txn));
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
      'reference':      'HL-${const Uuid().v4().substring(0, 8).toUpperCase()}',
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
        'label':          item['label'],
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

    // Récupérer les warehouse_id existants (l'API ne les renvoie pas toujours),
    // afin de ne pas écraser un warehouse_id local valide avec null.
    final ids = sales.map((s) => s.id).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final existingRows = ids.isEmpty
        ? <Map<String, Object?>>[]
        : await db.rawQuery(
            'SELECT id, warehouse_id FROM sales WHERE id IN ($placeholders)',
            ids,
          );
    final existingWarehouseIds = {
      for (final row in existingRows)
        row['id'] as String: row['warehouse_id'] as String?,
    };

    final batch = db.batch();
    for (final s in sales) {
      final warehouseId = s.warehouseId ?? existingWarehouseIds[s.id];
      batch.insert('sales', {
        'id':             s.id,
        'reference':      s.reference,
        'customer_id':    s.customerId,
        'customer_name':  s.customerName,
        'user_id':        s.userId,
        'total_amount':   s.totalAmount,
        'discount':       s.discount,
        'final_amount':   s.finalAmount,
        'paid_amount':    s.paidAmount,
        'payment_method': s.payments.isNotEmpty ? s.payments.first.method : 'CASH',
        'status':         s.status,
        'cashier_name':   s.userFullName,
        'warehouse_id':   warehouseId,
        'created_at':     _haitiNaiveToUtcIso(s.createdAt),
        'synced':         1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Supprimer d'abord les lignes existantes pour éviter les doublons résiduels
      batch.delete('sale_items',    where: 'sale_id = ?', whereArgs: [s.id]);
      batch.delete('sale_payments', where: 'sale_id = ?', whereArgs: [s.id]);

      for (final item in s.items) {
        batch.insert('sale_items', {
          'id':             item.id.isEmpty ? const Uuid().v4() : item.id,
          'sale_id':        s.id,
          'product_id':     item.productId,
          'label':          item.label,
          'product_name':   item.productName,
          'quantity':       item.quantity,
          'unit_price':     item.unitPrice,
          'original_price': item.originalPrice,
          'subtotal':       item.subtotal,
          'returned_qty':   item.returnedQty,
        });
      }
      for (final p in s.payments) {
        batch.insert('sale_payments', {
          'id':         p.id.isEmpty ? const Uuid().v4() : p.id,
          'sale_id':    s.id,
          'amount':     p.amount,
          'method':     p.method,
          'created_at': _haitiNaiveToUtcIso(p.createdAt),
        });
      }
    }
    await batch.commit(noResult: true);

    // Supprimer les doublons locaux temporaires : après upsert d'une vente cloud,
    // la vente locale (UUID client) avec la même référence devient obsolète.
    for (final s in sales) {
      if (s.reference.isEmpty) continue;
      final dupes = await db.query(
        'sales',
        columns: ['id'],
        where: 'reference = ? AND id != ?',
        whereArgs: [s.reference, s.id],
      );
      for (final row in dupes) {
        final dupeId = row['id'] as String;
        await db.delete('sale_items',    where: 'sale_id = ?', whereArgs: [dupeId]);
        await db.delete('sale_payments', where: 'sale_id = ?', whereArgs: [dupeId]);
        await db.delete('sales',         where: 'id = ?',      whereArgs: [dupeId]);
      }
    }
  }

  Future<PaginatedResponse<SaleModel>> getSales({
    String? search,
    String? status,
    String? warehouseId,
    String? cashierId,
    int page = 1,
    int limit = 15,
    DateTime? dateFrom,
    DateTime? dateTo,
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
    if (warehouseId != null) {
      where.add('warehouse_id = ?');
      args.add(warehouseId);
    }
    if (cashierId != null) {
      where.add('user_id = ?');
      args.add(cashierId);
    }
    if (search != null && search.isNotEmpty) {
      where.add('(reference LIKE ? OR customer_name LIKE ?)');
      args.addAll(['%$search%', '%$search%']);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    if (dateFrom != null) {
      where.add('created_at >= ?');
      args.add(dateFrom.toUtc().toIso8601String());
    }
    if (dateTo != null) {
      where.add('created_at < ?');
      args.add(dateTo.toUtc().toIso8601String());
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
      createdAt:    toHaitiTime(DateTime.parse(row['created_at'] as String)),
      customerName:  row['customer_name'] as String?,
      customerId:    row['customer_id'] as String?,
      userId:        row['user_id'] as String?,
      userFullName:  row['cashier_name'] as String?,
      items: itemRows.map((r) => SaleItemModel(
        id:            r['id'] as String,
        productId:     r['product_id'] as String?,
        label:         r['label'] as String?,
        productName:   r['product_name'] as String?,
        quantity:      (r['quantity'] as num).toDouble(),
        unitPrice:     (r['unit_price'] as num).toDouble(),
        originalPrice: r['original_price'] != null ? (r['original_price'] as num).toDouble() : null,
        subtotal:      (r['subtotal'] as num).toDouble(),
        returnedQty:   r['returned_qty'] != null ? (r['returned_qty'] as num).toDouble() : 0,
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
      'reference':    'LOC-${DateTime.now().millisecondsSinceEpoch}',
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
        'quantity':     item['ordered_qty'] ?? item['quantity'],
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
      "UPDATE purchases SET synced = 1, reference = ? WHERE id = ?",
      [reference, localId],
    );
  }

  /// Insère ou met à jour des achats reçus du cloud.
  Future<void> upsertPurchases(List<PurchaseModel> purchases) async {
    final db = _safeDb;
    if (db == null) return;

    final ids = purchases.map((p) => p.id).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final existingRows = ids.isEmpty
        ? <Map<String, Object?>>[]
        : await db.rawQuery(
            'SELECT id, warehouse_id FROM purchases WHERE id IN ($placeholders)',
            ids,
          );
    final existingWarehouseIds = {
      for (final row in existingRows)
        row['id'] as String: row['warehouse_id'] as String?,
    };

    final batch = db.batch();
    for (final p in purchases) {
      final warehouseId = p.warehouseId ?? existingWarehouseIds[p.id];
      batch.insert('purchases', {
        'id':            p.id,
        'reference':     p.reference,
        'supplier_id':   p.supplierId,
        'supplier_name': p.supplierName,
        'warehouse_id':  warehouseId,
        'total_amount':  p.totalAmount,
        'paid_amount':   p.paidAmount,
        'status':        p.status,
        'created_at':    _haitiNaiveToUtcIso(p.createdAt),
        'synced':        1,
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
      where.add('(supplier_name LIKE ? OR reference LIKE ?)');
      args.addAll(['%$search%', '%$search%']);
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

  // ── Dettes ────────────────────────────────────────────────────────────────

  Future<void> upsertDebts(List<DebtModel> debts) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final d in debts) {
      batch.insert('debts', {
        'id':             d.id,
        'reference_type': d.referenceType,
        'reference_id':   d.referenceId,
        'partner_type':   d.partnerType,
        'partner_id':     d.partnerId,
        'partner_name':   d.partnerName,
        'total_amount':   d.totalAmount,
        'paid_amount':    d.paidAmount,
        'balance':        d.balance,
        'status':         d.status,
        'created_at':     _haitiNaiveToUtcIso(d.createdAt),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<PaginatedResponse<DebtModel>> getDebts({
    String? partnerType,
    String? status,
    int page = 1,
    int limit = 50,
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
    if (partnerType != null && partnerType.isNotEmpty) {
      where.add('partner_type = ?');
      args.add(partnerType.toUpperCase());
    }
    if (status != null && status.isNotEmpty) {
      where.add('status = ?');
      args.add(status.toUpperCase());
    }
    final whereStr = where.isEmpty ? null : where.join(' AND ');

    final total = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM debts${whereStr != null ? ' WHERE $whereStr' : ''}',
      args,
    )) ?? 0;

    final rows = await db.query(
      'debts',
      where: whereStr,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: (page - 1) * limit,
    );

    final debts = rows.map((row) => DebtModel(
      id:            row['id'] as String,
      referenceType: row['reference_type'] as String,
      referenceId:   row['reference_id'] as String,
      partnerType:   row['partner_type'] as String,
      partnerId:     row['partner_id'] as String,
      partnerName:   row['partner_name'] as String?,
      totalAmount:   (row['total_amount'] as num).toDouble(),
      paidAmount:    (row['paid_amount'] as num).toDouble(),
      balance:       (row['balance'] as num).toDouble(),
      status:        row['status'] as String,
      createdAt:     toHaitiTime(DateTime.parse(row['created_at'] as String)),
    )).toList();

    return PaginatedResponse(
      data: debts,
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
      reference:    row['reference'] as String? ?? '',
      totalAmount:  (row['total_amount'] as num).toDouble(),
      paidAmount:   (row['paid_amount'] as num).toDouble(),
      status:       row['status'] as String,
      createdAt:    toHaitiTime(DateTime.parse(row['created_at'] as String)),
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

  // ── Fournisseurs ──────────────────────────────────────────────────────────

  Future<void> upsertSuppliers(List<SupplierModel> suppliers) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final s in suppliers) {
      batch.insert('suppliers', {
        'id':      s.id,
        'name':    s.name,
        'phone':   s.phone,
        'email':   s.email,
        'address': s.address,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<SupplierModel>> getSuppliers({String? search}) async {
    final db = _safeDb;
    if (db == null) return const [];
    final rows = search != null && search.isNotEmpty
        ? await db.query('suppliers',
            where: 'name LIKE ?',
            whereArgs: ['%$search%'],
            orderBy: 'name ASC')
        : await db.query('suppliers', orderBy: 'name ASC');
    return rows.map((r) => SupplierModel(
      id:      r['id'] as String,
      name:    r['name'] as String,
      phone:   r['phone'] as String?,
      email:   r['email'] as String?,
      address: r['address'] as String?,
    )).toList();
  }

  Future<void> deleteStaleSuppliers(List<String> serverIds) async {
    final db = _safeDb;
    if (db == null || serverIds.isEmpty) return;
    final ph = List.filled(serverIds.length, '?').join(',');
    await db.delete('suppliers', where: 'id NOT IN ($ph)', whereArgs: serverIds);
  }

  // ── Tables / Chambres restaurant ─────────────────────────────────────────

  Future<void> upsertRestaurantTables(
      List<RestaurantTableModel> tables, {String? warehouseId}) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final t in tables) {
      batch.insert('restaurant_tables', {
        'id':               t.id,
        'name':             t.name,
        'capacity':         t.capacity,
        'status':           t.status,
        'price':            t.price,
        'price_per_day':    t.pricePerDay,
        'price_per_moment': t.pricePerMoment,
        'waiter_id':        t.waiterId,
        'waiter_name':      t.waiterName,
        'warehouse_id':     warehouseId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // Attributs chambre : supprimer+réinsérer
      batch.delete('room_attributes', where: 'table_id = ?', whereArgs: [t.id]);
      for (final a in t.attributes) {
        batch.insert('room_attributes', {
          'id':       const Uuid().v4(),
          'table_id': t.id,
          'key':      a.key,
          'value':    a.value,
        });
      }
    }
    await batch.commit(noResult: true);
  }

  Future<List<RestaurantTableModel>> getRestaurantTables(
      {String? warehouseId}) async {
    final db = _safeDb;
    if (db == null) return const [];
    final rows = warehouseId != null
        ? await db.query('restaurant_tables',
            where: 'warehouse_id = ?',
            whereArgs: [warehouseId],
            orderBy: 'name ASC')
        : await db.query('restaurant_tables', orderBy: 'name ASC');

    final tables = <RestaurantTableModel>[];
    for (final r in rows) {
      final attrRows = await db.query('room_attributes',
          where: 'table_id = ?', whereArgs: [r['id']]);
      tables.add(RestaurantTableModel(
        id:             r['id'] as String,
        name:           r['name'] as String,
        capacity:       r['capacity'] as int,
        status:         r['status'] as String,
        price:          (r['price'] as num).toDouble(),
        pricePerDay:    (r['price_per_day'] as num).toDouble(),
        pricePerMoment: (r['price_per_moment'] as num).toDouble(),
        waiterId:       r['waiter_id'] as String?,
        waiterName:     r['waiter_name'] as String?,
        attributes: attrRows
            .map((a) => RoomAttr(
                key: a['key'] as String, value: a['value'] as String))
            .toList(),
      ));
    }
    return tables;
  }

  Future<void> deleteStaleRestaurantTables(
      List<String> serverIds, {String? warehouseId}) async {
    final db = _safeDb;
    if (db == null || serverIds.isEmpty) return;
    final ph = List.filled(serverIds.length, '?').join(',');
    final where = warehouseId != null
        ? 'id NOT IN ($ph) AND warehouse_id = ?'
        : 'id NOT IN ($ph)';
    final args = warehouseId != null
        ? [...serverIds, warehouseId]
        : serverIds;
    await db.delete('restaurant_tables', where: where, whereArgs: args);
  }

  // ── Menu items ───────────────────────────────────────────────────────────

  Future<void> upsertMenuItems(
      List<MenuItemModel> items, {String? warehouseId}) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final m in items) {
      batch.insert('menu_items', {
        'id':              m.id,
        'name':            m.name,
        'description':     m.description,
        'price':           m.price,
        'category_id':     m.categoryId,
        'category_name':   m.categoryName,
        'product_id':      m.productId,
        'available':       m.available ? 1 : 0,
        'send_to_kitchen': m.sendToKitchen ? 1 : 0,
        'image_url':       m.imageUrl,
        'variants_json':   m.variantsData != null
            ? jsonEncode(m.variantsData) : null,
        'warehouse_id':    m.warehouseId ?? warehouseId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<MenuItemModel>> getMenuItems(
      {String? warehouseId, bool availableOnly = false}) async {
    final db = _safeDb;
    if (db == null) return const [];
    final where = <String>[];
    final args  = <dynamic>[];
    if (availableOnly) { where.add('available = 1'); }
    if (warehouseId != null) {
      where.add('warehouse_id = ?');
      args.add(warehouseId);
    }
    final rows = await db.query('menu_items',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'name ASC');
    return rows.map((r) {
      Map<String, dynamic>? vd;
      final vj = r['variants_json'] as String?;
      if (vj != null) {
        try { vd = jsonDecode(vj) as Map<String, dynamic>; } catch (_) {}
      }
      return MenuItemModel(
        id:            r['id'] as String,
        name:          r['name'] as String,
        description:   r['description'] as String?,
        price:         (r['price'] as num).toDouble(),
        categoryId:    r['category_id'] as String?,
        categoryName:  r['category_name'] as String?,
        productId:     r['product_id'] as String?,
        available:     (r['available'] as int) == 1,
        sendToKitchen: (r['send_to_kitchen'] as int) == 1,
        imageUrl:      r['image_url'] as String?,
        variantsData:  vd,
        warehouseId:   r['warehouse_id'] as String?,
      );
    }).toList();
  }

  Future<void> deleteStaleMenuItems(
      List<String> serverIds, {String? warehouseId}) async {
    final db = _safeDb;
    if (db == null || serverIds.isEmpty) return;
    final ph = List.filled(serverIds.length, '?').join(',');
    final where = warehouseId != null
        ? 'id NOT IN ($ph) AND warehouse_id = ?'
        : 'id NOT IN ($ph)';
    final args = warehouseId != null
        ? [...serverIds, warehouseId]
        : serverIds;
    await db.delete('menu_items', where: where, whereArgs: args);
  }

  // ── Commandes restaurant (ouvertes) ──────────────────────────────────────

  Future<void> upsertRestaurantOrders(
      List<RestaurantOrderModel> orders, {String? warehouseId}) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final o in orders) {
      batch.insert('restaurant_orders', {
        'id':           o.id,
        'table_id':     o.tableId,
        'table_name':   o.tableName,
        'waiter_name':  o.waiterName,
        'status':       o.status,
        'covers':       o.covers,
        'subtotal':     o.subtotal,
        'tip':          o.tip,
        'total':        o.total,
        'notes':        o.notes,
        'warehouse_id': warehouseId,
        'created_at':   o.createdAt?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      batch.delete('restaurant_order_items',
          where: 'order_id = ?', whereArgs: [o.id]);
      for (final item in o.items) {
        batch.insert('restaurant_order_items', {
          'id':           item.id,
          'order_id':     o.id,
          'product_id':   item.productId,
          'menu_item_id': item.menuItemId,
          'product_name': item.productName,
          'quantity':     item.quantity,
          'unit_price':   item.unitPrice,
          'notes':        item.notes,
          'status':       item.status,
        });
      }
    }
    await batch.commit(noResult: true);
  }

  Future<List<RestaurantOrderModel>> getOpenRestaurantOrders(
      {String? warehouseId}) async {
    final db = _safeDb;
    if (db == null) return const [];
    final rows = await db.query('restaurant_orders',
        where: warehouseId != null
            ? "status != 'closed' AND warehouse_id = ?"
            : "status != 'closed'",
        whereArgs: warehouseId != null ? [warehouseId] : null,
        orderBy: 'created_at ASC');
    final orders = <RestaurantOrderModel>[];
    for (final r in rows) {
      final itemRows = await db.query('restaurant_order_items',
          where: 'order_id = ?', whereArgs: [r['id']]);
      orders.add(RestaurantOrderModel(
        id:         r['id'] as String,
        tableId:    r['table_id'] as String?,
        tableName:  r['table_name'] as String?,
        waiterName: r['waiter_name'] as String?,
        status:     r['status'] as String,
        covers:     r['covers'] as int,
        subtotal:   (r['subtotal'] as num).toDouble(),
        tip:        (r['tip'] as num).toDouble(),
        total:      (r['total'] as num).toDouble(),
        notes:      r['notes'] as String?,
        createdAt:  r['created_at'] != null
            ? DateTime.tryParse(r['created_at'] as String) : null,
        items: itemRows.map((i) => RestaurantOrderItemModel(
          id:          i['id'] as String,
          productId:   i['product_id'] as String?,
          menuItemId:  i['menu_item_id'] as String?,
          productName: i['product_name'] as String? ?? '',
          quantity:    (i['quantity'] as num).toDouble(),
          unitPrice:   (i['unit_price'] as num).toDouble(),
          notes:       i['notes'] as String?,
          status:      i['status'] as String? ?? 'pending',
        )).toList(),
      ));
    }
    return orders;
  }

  Future<RestaurantOrderModel?> getRestaurantOrderByTable(
      String tableId) async {
    final db = _safeDb;
    if (db == null) return null;
    final rows = await db.query('restaurant_orders',
        where: "table_id = ? AND status != 'closed'",
        whereArgs: [tableId],
        limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final itemRows = await db.query('restaurant_order_items',
        where: 'order_id = ?', whereArgs: [r['id']]);
    return RestaurantOrderModel(
      id:         r['id'] as String,
      tableId:    r['table_id'] as String?,
      tableName:  r['table_name'] as String?,
      waiterName: r['waiter_name'] as String?,
      status:     r['status'] as String,
      covers:     r['covers'] as int,
      subtotal:   (r['subtotal'] as num).toDouble(),
      tip:        (r['tip'] as num).toDouble(),
      total:      (r['total'] as num).toDouble(),
      notes:      r['notes'] as String?,
      createdAt:  r['created_at'] != null
          ? DateTime.tryParse(r['created_at'] as String) : null,
      items: itemRows.map((i) => RestaurantOrderItemModel(
        id:          i['id'] as String,
        productId:   i['product_id'] as String?,
        menuItemId:  i['menu_item_id'] as String?,
        productName: i['product_name'] as String? ?? '',
        quantity:    (i['quantity'] as num).toDouble(),
        unitPrice:   (i['unit_price'] as num).toDouble(),
        notes:       i['notes'] as String?,
        status:      i['status'] as String? ?? 'pending',
      )).toList(),
    );
  }

  Future<void> deleteStaleRestaurantOrders(
      List<String> serverIds, {String? warehouseId}) async {
    final db = _safeDb;
    if (db == null || serverIds.isEmpty) return;
    final ph = List.filled(serverIds.length, '?').join(',');
    final where = warehouseId != null
        ? 'id NOT IN ($ph) AND warehouse_id = ?'
        : 'id NOT IN ($ph)';
    final args = warehouseId != null
        ? [...serverIds, warehouseId]
        : serverIds;
    await db.delete('restaurant_orders', where: where, whereArgs: args);
  }

  // ── Tâches housekeeping ──────────────────────────────────────────────────

  Future<void> upsertHousekeepingTasks(
      List<HousekeepingTaskModel> tasks) async {
    final db = _safeDb;
    if (db == null) return;
    final batch = db.batch();
    for (final t in tasks) {
      batch.insert('housekeeping_tasks', {
        'id':           t.id,
        'table_id':     t.tableId,
        'warehouse_id': t.warehouseId,
        'description':  t.description,
        'status':       t.status,
        'created_at':   t.createdAt?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<HousekeepingTaskModel>> getHousekeepingTasks(
      {String? tableId, String? warehouseId}) async {
    final db = _safeDb;
    if (db == null) return const [];
    final where = <String>[];
    final args  = <dynamic>[];
    if (tableId != null) { where.add('table_id = ?'); args.add(tableId); }
    if (warehouseId != null) {
      where.add('warehouse_id = ?');
      args.add(warehouseId);
    }
    final rows = await db.query('housekeeping_tasks',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'created_at DESC');
    return rows.map((r) => HousekeepingTaskModel(
      id:          r['id'] as String,
      tableId:     r['table_id'] as String,
      warehouseId: r['warehouse_id'] as String?,
      description: r['description'] as String,
      status:      r['status'] as String,
      createdAt:   r['created_at'] != null
          ? DateTime.tryParse(r['created_at'] as String) : null,
    )).toList();
  }

  Future<void> deleteStaleHousekeepingTasks(
      List<String> serverIds, {String? warehouseId}) async {
    final db = _safeDb;
    if (db == null || serverIds.isEmpty) return;
    final ph = List.filled(serverIds.length, '?').join(',');
    final where = warehouseId != null
        ? 'id NOT IN ($ph) AND warehouse_id = ?'
        : 'id NOT IN ($ph)';
    final args = warehouseId != null
        ? [...serverIds, warehouseId]
        : serverIds;
    await db.delete('housekeeping_tasks',
        where: where, whereArgs: args);
  }
}
