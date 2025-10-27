// lib/services/database_helper.dart - v5.3 (PRODUCTION-READY - ANALYZER CLEAN)

// ignore_for_file: constant_identifier_names

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../models/client.dart';
import '../models/product.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/ledger_entry.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  // ========================================================================
  // CONSTANTS
  // ========================================================================
  static const int DATABASE_VERSION = 30;
  static const String DATABASE_NAME = 'dairy_manager_v6.db';

  // Stock thresholds
  static const double LOW_STOCK_THRESHOLD = 10.0;
  static const double OUT_OF_STOCK_THRESHOLD = 0.0;
  static const double CRITICAL_STOCK_THRESHOLD = 5.0;

  // Pagination defaults
  static const int DEFAULT_PAGE_SIZE = 50;
  static const int MAX_PAGE_SIZE = 500;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    try {
      final path = join(await getDatabasesPath(), DATABASE_NAME);
      debugPrint('📍 Database path: $path');

      return await openDatabase(
        path,
        version: DATABASE_VERSION,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          try {
            await db.execute('PRAGMA foreign_keys = ON');

            // ✅ FIX: Use rawQuery for PRAGMA that returns results
            final walResult = await db.rawQuery('PRAGMA journal_mode = WAL');
            debugPrint('✅ WAL mode activated: $walResult');

            // Optional performance optimizations
            await db.rawQuery('PRAGMA synchronous = NORMAL');
            await db.rawQuery('PRAGMA temp_store = MEMORY');

          } catch (e) {
            debugPrint('⚠️ PRAGMA setup warning: $e');
            // Continue without WAL mode if it fails
          }
        },
      );
    } catch (e) {
      debugPrint('❌ Database initialization failed: $e');
      rethrow;
    }
  }
  // lib/services/database_helper.dart - Add after _initDb()

  Future<void> _configurePragma(Database db) async {
    try {
      // Enable foreign keys
      await db.execute('PRAGMA foreign_keys = ON');

      // Set WAL mode using rawQuery (returns result)
      final walResult = await db.rawQuery('PRAGMA journal_mode = WAL');
      debugPrint('✅ WAL mode result: $walResult');

      // Optional: Set other optimizations
      await db.rawQuery('PRAGMA synchronous = NORMAL');
      await db.rawQuery('PRAGMA temp_store = MEMORY');
      await db.rawQuery('PRAGMA mmap_size = 30000000000');

      debugPrint('✅ Database PRAGMA configured successfully');
    } catch (e) {
      debugPrint('⚠️ PRAGMA configuration warning: $e');
      // Don't rethrow - continue with default settings
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('🔨 Creating new database schema v$version...');

    try {
      await db.transaction((txn) async {
        // CLIENTS TABLE
        await txn.execute('''
          CREATE TABLE clients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE CHECK(length(trim(name)) > 0),
            phone TEXT,
            address TEXT,
            balance REAL NOT NULL DEFAULT 0.0,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            firestoreId TEXT UNIQUE,
            isDeleted INTEGER NOT NULL DEFAULT 0 CHECK(isDeleted IN (0, 1)),
            isSynced INTEGER NOT NULL DEFAULT 0 CHECK(isSynced IN (0, 1))
          )
        ''');

        // PRODUCTS TABLE
        await txn.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE CHECK(length(trim(name)) > 0),
            weight REAL CHECK(weight IS NULL OR weight > 0),
            price REAL NOT NULL CHECK(price >= 0),
            costPrice REAL NOT NULL DEFAULT 0 CHECK(costPrice >= 0),
            stock REAL NOT NULL DEFAULT 0 CHECK(stock >= 0),
            minStock REAL DEFAULT 10 CHECK(minStock >= 0),
            maxStock REAL DEFAULT 100 CHECK(maxStock >= minStock),
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            firestoreId TEXT UNIQUE,
            isDeleted INTEGER NOT NULL DEFAULT 0 CHECK(isDeleted IN (0, 1)),
            isSynced INTEGER NOT NULL DEFAULT 0 CHECK(isSynced IN (0, 1))
          )
        ''');

        // BILLS TABLE
        await txn.execute('''
          CREATE TABLE bills (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            clientId INTEGER NOT NULL,
            totalAmount REAL NOT NULL DEFAULT 0 CHECK(totalAmount >= 0),
            paidAmount REAL NOT NULL DEFAULT 0 CHECK(paidAmount >= 0),
            carryForward REAL NOT NULL DEFAULT 0,
            discount REAL NOT NULL DEFAULT 0 CHECK(discount >= 0),
            tax REAL NOT NULL DEFAULT 0 CHECK(tax >= 0),
            date TEXT NOT NULL,
            dueDate TEXT,
            paymentStatus TEXT NOT NULL DEFAULT 'pending' CHECK(paymentStatus IN ('pending', 'partial', 'paid', 'overdue')),
            notes TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            isSynced INTEGER NOT NULL DEFAULT 0 CHECK(isSynced IN (0, 1)),
            isDeleted INTEGER NOT NULL DEFAULT 0 CHECK(isDeleted IN (0, 1)),
            FOREIGN KEY(clientId) REFERENCES clients(id) ON DELETE RESTRICT
          )
        ''');

        // BILL_ITEMS TABLE
        await txn.execute('''
          CREATE TABLE bill_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            billId INTEGER NOT NULL,
            productId INTEGER NOT NULL,
            quantity REAL NOT NULL CHECK(quantity > 0),
            price REAL NOT NULL CHECK(price >= 0),
            discount REAL NOT NULL DEFAULT 0 CHECK(discount >= 0),
            tax REAL NOT NULL DEFAULT 0 CHECK(tax >= 0),
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            isSynced INTEGER NOT NULL DEFAULT 0 CHECK(isSynced IN (0, 1)),
            isDeleted INTEGER NOT NULL DEFAULT 0 CHECK(isDeleted IN (0, 1)),
            FOREIGN KEY(billId) REFERENCES bills(id) ON DELETE CASCADE,
            FOREIGN KEY(productId) REFERENCES products(id) ON DELETE RESTRICT
          )
        ''');

        // LEDGER TABLE
        await txn.execute('''
          CREATE TABLE ledger (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            clientId INTEGER NOT NULL,
            firestoreId TEXT UNIQUE,
            billId INTEGER,
            type TEXT NOT NULL CHECK(type IN ('bill', 'payment', 'adjustment')),
            amount REAL NOT NULL CHECK(amount > 0),
            date TEXT NOT NULL,
            note TEXT,
            paymentMethod TEXT CHECK(paymentMethod IN ('cash', 'card', 'upi', 'cheque', 'bank_transfer', NULL)),
            referenceNumber TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            isSynced INTEGER NOT NULL DEFAULT 0 CHECK(isSynced IN (0, 1)),
            isDeleted INTEGER NOT NULL DEFAULT 0 CHECK(isDeleted IN (0, 1)),
            FOREIGN KEY(clientId) REFERENCES clients(id) ON DELETE RESTRICT,
            FOREIGN KEY(billId) REFERENCES bills(id) ON DELETE SET NULL
          )
        ''');

        // DEMAND_BATCH TABLE
        await txn.execute('''
          CREATE TABLE demand_batch (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            demandDate TEXT NOT NULL,
            closed INTEGER NOT NULL DEFAULT 0 CHECK(closed IN (0, 1)),
            updatedAt TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            firestoreId TEXT UNIQUE,
            isSynced INTEGER NOT NULL DEFAULT 0 CHECK(isSynced IN (0, 1)),
            isDeleted INTEGER NOT NULL DEFAULT 0 CHECK(isDeleted IN (0, 1))
          )
        ''');

        // DEMAND TABLE
        await txn.execute('''
          CREATE TABLE demand (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            batchId INTEGER NOT NULL,
            clientId INTEGER NOT NULL,
            productId INTEGER NOT NULL,
            quantity REAL NOT NULL CHECK(quantity > 0),
            date TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            isSynced INTEGER NOT NULL DEFAULT 0 CHECK(isSynced IN (0, 1)),
            isDeleted INTEGER NOT NULL DEFAULT 0 CHECK(isDeleted IN (0, 1)),
            FOREIGN KEY(batchId) REFERENCES demand_batch(id) ON DELETE CASCADE,
            FOREIGN KEY(clientId) REFERENCES clients(id) ON DELETE RESTRICT,
            FOREIGN KEY(productId) REFERENCES products(id) ON DELETE RESTRICT
          )
        ''');

        // PURCHASES TABLE
        await txn.execute('''
          CREATE TABLE purchases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            productId INTEGER NOT NULL,
            quantity REAL NOT NULL CHECK(quantity > 0),
            costPrice REAL NOT NULL CHECK(costPrice >= 0),
            purchaseDate TEXT NOT NULL,
            supplier TEXT,
            notes TEXT,
            createdAt TEXT NOT NULL,
            isSynced INTEGER NOT NULL DEFAULT 0 CHECK(isSynced IN (0, 1)),
            isDeleted INTEGER NOT NULL DEFAULT 0 CHECK(isDeleted IN (0, 1)),
            FOREIGN KEY(productId) REFERENCES products(id) ON DELETE CASCADE
          )
        ''');

        // CREATE INDEXES FOR PERFORMANCE
        await _createIndexes(txn);

        debugPrint('✅ Database schema v$version created successfully with indexes');
      });
    } catch (e) {
      debugPrint('❌ Database creation failed: $e');
      rethrow;
    }
  }

  Future<void> _createIndexes(Transaction txn) async {
    try {
      // Bills indexes
      await txn.execute('CREATE INDEX idx_bills_clientId ON bills(clientId) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_bills_date ON bills(date DESC) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_bills_paymentStatus ON bills(paymentStatus) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_bills_firestoreId ON bills(firestoreId)');

      // Bill items indexes
      await txn.execute('CREATE INDEX idx_bill_items_billId ON bill_items(billId) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_bill_items_productId ON bill_items(productId) WHERE isDeleted = 0');

      // Ledger indexes
      await txn.execute('CREATE INDEX idx_ledger_clientId ON ledger(clientId) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_ledger_date ON ledger(date DESC) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_ledger_type ON ledger(type) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_ledger_billId ON ledger(billId) WHERE isDeleted = 0');

      // Demand indexes
      await txn.execute('CREATE INDEX idx_demand_batchId ON demand(batchId) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_demand_clientId ON demand(clientId) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_demand_productId ON demand(productId) WHERE isDeleted = 0');

      // Demand batch indexes
      await txn.execute('CREATE INDEX idx_demand_batch_date ON demand_batch(demandDate DESC) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_demand_batch_closed ON demand_batch(closed) WHERE isDeleted = 0');

      // Purchases indexes
      await txn.execute('CREATE INDEX idx_purchases_productId ON purchases(productId) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_purchases_date ON purchases(purchaseDate DESC) WHERE isDeleted = 0');

      // Products indexes
      await txn.execute('CREATE INDEX idx_products_name ON products(name COLLATE NOCASE) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_products_stock ON products(stock) WHERE isDeleted = 0');

      // Clients indexes
      await txn.execute('CREATE INDEX idx_clients_name ON clients(name COLLATE NOCASE) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_clients_balance ON clients(balance) WHERE isDeleted = 0');

      // Sync indexes
      await txn.execute('CREATE INDEX idx_clients_sync ON clients(isSynced) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_products_sync ON products(isSynced) WHERE isDeleted = 0');
      await txn.execute('CREATE INDEX idx_bills_sync ON bills(isSynced) WHERE isDeleted = 0');

      debugPrint('✅ All indexes created successfully');
    } catch (e) {
      debugPrint('⚠️ Index creation warning: $e');
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('🔄 Upgrading database from v$oldVersion to v$newVersion...');

    try {
      if (oldVersion < 27) await _runV27Migration(db);
      if (oldVersion < 28) await _runV28Migration(db);
      if (oldVersion < 29) await _runV29Migration(db);
      if (oldVersion < 30) await _runV30Migration(db);

      debugPrint('✅ Database upgraded successfully to v$newVersion');
    } catch (e) {
      debugPrint('❌ Database upgrade failed: $e');
      rethrow;
    }
  }

  Future<void> _runV27Migration(Database db) async {
    debugPrint('🚀 Applying migration for v27...');
    await _addColumnIfNotExists(db, 'bills', 'discount', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(db, 'bills', 'tax', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(db, 'bills', 'dueDate', 'TEXT');
    await _addColumnIfNotExists(db, 'bills', 'paymentStatus', 'TEXT NOT NULL DEFAULT \'pending\'');
    await _addColumnIfNotExists(db, 'bills', 'notes', 'TEXT');
    await _addColumnIfNotExists(db, 'bills', 'createdAt', 'TEXT NOT NULL DEFAULT \'\'');
    await _addColumnIfNotExists(db, 'bill_items', 'discount', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(db, 'bill_items', 'tax', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(db, 'bill_items', 'createdAt', 'TEXT NOT NULL DEFAULT \'\'');
    await _addColumnIfNotExists(db, 'ledger', 'paymentMethod', 'TEXT');
    await _addColumnIfNotExists(db, 'ledger', 'referenceNumber', 'TEXT');
    await _addColumnIfNotExists(db, 'ledger', 'createdAt', 'TEXT NOT NULL DEFAULT \'\'');
    await _addColumnIfNotExists(db, 'clients', 'createdAt', 'TEXT NOT NULL DEFAULT \'\'');
    await _addColumnIfNotExists(db, 'products', 'createdAt', 'TEXT NOT NULL DEFAULT \'\'');
    await _addColumnIfNotExists(db, 'demand_batch', 'createdAt', 'TEXT NOT NULL DEFAULT \'\'');
    await _addColumnIfNotExists(db, 'demand', 'createdAt', 'TEXT NOT NULL DEFAULT \'\'');
    debugPrint('✅ Migration to v27 completed.');
  }

  Future<void> _runV28Migration(Database db) async {
    debugPrint('🚀 Applying migration for v28...');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        productId INTEGER NOT NULL,
        quantity REAL NOT NULL CHECK(quantity > 0),
        costPrice REAL NOT NULL CHECK(costPrice >= 0),
        purchaseDate TEXT NOT NULL,
        supplier TEXT,
        notes TEXT,
        createdAt TEXT NOT NULL DEFAULT '',
        isSynced INTEGER NOT NULL DEFAULT 0,
        isDeleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(productId) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    debugPrint('✅ Migration to v28 completed.');
  }

  Future<void> _runV29Migration(Database db) async {
    debugPrint('🚀 Applying migration for v29...');
    await _addColumnIfNotExists(db, 'clients', 'balance', 'REAL NOT NULL DEFAULT 0.0');

    // Recalculate all client balances
    await _recalculateAllClientBalances(db);
    debugPrint('✅ Migration to v29 completed.');
  }

  Future<void> _runV30Migration(Database db) async {
    debugPrint('🚀 Applying migration for v30 (Production hardening)...');

    // Add stock limit columns
    await _addColumnIfNotExists(db, 'products', 'minStock', 'REAL DEFAULT 10');
    await _addColumnIfNotExists(db, 'products', 'maxStock', 'REAL DEFAULT 100');

    // Create all indexes
    await db.transaction((txn) async {
      await _createIndexes(txn);
    });

    debugPrint('✅ Migration to v30 completed.');
  }

  Future<void> _addColumnIfNotExists(Database db, String table, String column, String type) async {
    try {
      var tableInfo = await db.rawQuery('PRAGMA table_info($table)');
      if (!tableInfo.any((col) => col['name'] == column)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
        debugPrint('✅ Column added: $table.$column');
      }
    } catch (e) {
      debugPrint('⚠️ Error adding column $table.$column: $e');
    }
  }

  Future<void> _recalculateAllClientBalances(Database db) async {
    try {
      final clients = await db.query('clients', where: 'isDeleted = 0');

      for (var client in clients) {
        final clientId = client['id'] as int;
        final balance = await _calculateClientBalanceFromLedger(db, clientId);

        await db.update(
          'clients',
          {'balance': balance, 'updatedAt': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [clientId],
        );
      }

      debugPrint('✅ All client balances recalculated');
    } catch (e) {
      debugPrint('⚠️ Error recalculating balances: $e');
    }
  }

  Future<double> _calculateClientBalanceFromLedger(Database db, int clientId) async {
    final result = await db.rawQuery('''
      SELECT SUM(CASE WHEN type = 'bill' THEN amount ELSE -amount END) as balance
      FROM ledger
      WHERE clientId = ? AND isDeleted = 0
    ''', [clientId]);

    if (result.isEmpty || result.first['balance'] == null) return 0.0;
    return (result.first['balance'] as num).toDouble();
  }

  // ========================================================================
  // UTILITY METHODS
  // ========================================================================

  Future<List<Map<String, dynamic>>> getUnsynced(String table) async {
    try {
      final db = await database;
      return await db.query(
        table,
        where: '(isSynced = 0 OR isSynced IS NULL) AND isDeleted = 0',
      );
    } catch (e) {
      debugPrint('❌ Error getting unsynced records from $table: $e');
      return [];
    }
  }

  Future<String?> getFirestoreId(String table, int localId) async {
    try {
      final db = await database;
      final rows = await db.query(
        table,
        columns: ['firestoreId'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['firestoreId'] as String?;
    } catch (e) {
      debugPrint('❌ Error getting Firestore ID: $e');
      return null;
    }
  }

  String _validateAndTrimText(String text, String fieldName) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('$fieldName cannot be empty');
    }
    return trimmed;
  }

  // ========================================================================
  // CLIENTS
  // ========================================================================

  Future<List<Client>> getClients({int? limit, int? offset}) async {
    try {
      final db = await database;
      final rows = await db.query(
        'clients',
        where: 'isDeleted = 0',
        orderBy: 'name COLLATE NOCASE ASC',
        limit: limit,
        offset: offset,
      );
      return rows.map((m) => Client.fromMap(m)).toList();
    } catch (e) {
      debugPrint('❌ Error getting clients: $e');
      return [];
    }
  }

  Future<Client?> getClientById(int id) async {
    try {
      final db = await database;
      final rows = await db.query(
        'clients',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Client.fromMap(rows.first);
    } catch (e) {
      debugPrint('❌ Error getting client by ID: $e');
      return null;
    }
  }

  Future<List<Client>> searchClients(String query) async {
    try {
      final db = await database;
      final searchTerm = '%${query.trim()}%';
      final rows = await db.query(
        'clients',
        where: '(name LIKE ? OR phone LIKE ?) AND isDeleted = 0',
        whereArgs: [searchTerm, searchTerm],
        orderBy: 'name COLLATE NOCASE ASC',
      );
      return rows.map((m) => Client.fromMap(m)).toList();
    } catch (e) {
      debugPrint('❌ Error searching clients: $e');
      return [];
    }
  }

  Future<int> getClientsCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM clients WHERE isDeleted = 0',
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      debugPrint('❌ Error getting clients count: $e');
      return 0;
    }
  }

  Future<int> insertClient(Client c) async {
    try {
      final db = await database;

      // Validate
      _validateAndTrimText(c.name, 'Client name');

      final now = DateTime.now();
      final updatedClient = c.copyWith(
        createdAt: c.createdAt ?? now,
        updatedAt: now,
        isSynced: false,
      );

      final id = await db.insert(
        'clients',
        updatedClient.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint('✅ Client inserted: ${c.name} (ID: $id)');
      return id;
    } catch (e) {
      debugPrint('❌ Error inserting client: $e');
      rethrow;
    }
  }

  Future<int> updateClient(Client c) async {
    try {
      final db = await database;

      // Validate
      _validateAndTrimText(c.name, 'Client name');

      final updatedClient = c.copyWith(
        updatedAt: DateTime.now(),
        isSynced: false,
      );

      final result = await db.update(
        'clients',
        updatedClient.toMap(),
        where: 'id = ?',
        whereArgs: [c.id],
      );

      if (result > 0) {
        debugPrint('✅ Client updated: ${c.name}');
      } else {
        debugPrint('⚠️ Client not found for update: ID ${c.id}');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error updating client: $e');
      rethrow;
    }
  }

  Future<int> deleteClient(int id) async {
    try {
      final db = await database;

      // Check if client has bills or ledger entries
      final billCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM bills WHERE clientId = ? AND isDeleted = 0', [id])
      ) ?? 0;

      if (billCount > 0) {
        throw Exception('Cannot delete client with existing bills. Please use soft delete.');
      }

      final result = await db.update(
        'clients',
        {
          'isDeleted': 1,
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      debugPrint('✅ Client soft-deleted (ID: $id)');
      return result;
    } catch (e) {
      debugPrint('❌ Error deleting client: $e');
      rethrow;
    }
  }

  Future<int> updateClientWithModel(Client client) => updateClient(client);

  Future<int> insertClientMap(Map<String, dynamic> map) async {
    try {
      final client = Client.fromMap(map);
      return await insertClient(client);
    } catch (e) {
      debugPrint('❌ Error inserting client from map: $e');
      rethrow;
    }
  }

  // ========================================================================
  // PRODUCTS
  // ========================================================================

  Future<List<Product>> getProducts({int? limit, int? offset}) async {
    try {
      final db = await database;

      final rows = await db.rawQuery('''
        SELECT p.*, 
               COALESCE(COUNT(DISTINCT bi.billId), 0) AS usageCount
        FROM products p
        LEFT JOIN bill_items bi 
          ON p.id = bi.productId AND bi.isDeleted = 0
        WHERE p.isDeleted = 0
        GROUP BY p.id
        ORDER BY usageCount DESC, LOWER(p.name) ASC
        ${limit != null ? 'LIMIT $limit' : ''}
        ${offset != null ? 'OFFSET $offset' : ''}
      ''');

      return rows.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      debugPrint('❌ Error getting products: $e');
      return [];
    }
  }

  Future<Product?> getProductById(int id) async {
    try {
      final db = await database;
      final rows = await db.query(
        'products',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Product.fromMap(rows.first);
    } catch (e) {
      debugPrint('❌ Error getting product by ID: $e');
      return null;
    }
  }

  Future<List<Product>> searchProducts(String query) async {
    try {
      final db = await database;
      final searchTerm = '%${query.trim()}%';

      final rows = await db.rawQuery('''
        SELECT p.*, 
               COALESCE(COUNT(DISTINCT bi.billId), 0) AS usageCount
        FROM products p
        LEFT JOIN bill_items bi 
          ON p.id = bi.productId AND bi.isDeleted = 0
        WHERE p.isDeleted = 0 AND p.name LIKE ?
        GROUP BY p.id
        ORDER BY usageCount DESC, LOWER(p.name) ASC
      ''', [searchTerm]);

      return rows.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      debugPrint('❌ Error searching products: $e');
      return [];
    }
  }

  Future<int> getProductsCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM products WHERE isDeleted = 0',
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      debugPrint('❌ Error getting products count: $e');
      return 0;
    }
  }

  Future<int> insertProduct(Product p) async {
    try {
      final db = await database;

      // Validate
      _validateAndTrimText(p.name, 'Product name');

      if (p.price < 0) throw ArgumentError('Price cannot be negative');

      final now = DateTime.now();
      final updatedProduct = p.copyWith(
        createdAt: p.createdAt ?? now,
        updatedAt: now,
        isSynced: false,
      );

      final id = await db.insert(
        'products',
        updatedProduct.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint('✅ Product inserted: ${p.name} (ID: $id)');
      return id;
    } catch (e) {
      debugPrint('❌ Error inserting product: $e');
      rethrow;
    }
  }

  Future<int> updateProduct(Product p) async {
    try {
      final db = await database;

      // Validate
      _validateAndTrimText(p.name, 'Product name');

      if (p.price < 0) throw ArgumentError('Price cannot be negative');

      final updatedProduct = p.copyWith(
        updatedAt: DateTime.now(),
        isSynced: false,
      );

      final result = await db.update(
        'products',
        updatedProduct.toMap(),
        where: 'id = ?',
        whereArgs: [p.id],
      );

      if (result > 0) {
        debugPrint('✅ Product updated: ${p.name}');
      } else {
        debugPrint('⚠️ Product not found for update: ID ${p.id}');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error updating product: $e');
      rethrow;
    }
  }

  Future<int> deleteProduct(int id) async {
    try {
      final db = await database;

      // Check if product is used in any bills
      final itemCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM bill_items WHERE productId = ? AND isDeleted = 0', [id])
      ) ?? 0;

      if (itemCount > 0) {
        throw Exception('Cannot delete product used in bills. Please use soft delete.');
      }

      final result = await db.update(
        'products',
        {
          'isDeleted': 1,
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      debugPrint('✅ Product soft-deleted (ID: $id)');
      return result;
    } catch (e) {
      debugPrint('❌ Error deleting product: $e');
      rethrow;
    }
  }

  Future<int> insertProductMap(Map<String, dynamic> map) async {
    try {
      final product = Product.fromMap(map);
      return await insertProduct(product);
    } catch (e) {
      debugPrint('❌ Error inserting product from map: $e');
      rethrow;
    }
  }

  Future<void> saveProductsToLocal(List<Product> products) async {
    try {
      final db = await database;
      final batch = db.batch();

      for (final p in products) {
        batch.insert(
          'products',
          p.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      debugPrint('✅ ${products.length} products saved locally');
    } catch (e) {
      debugPrint('❌ Error saving products: $e');
      rethrow;
    }
  }

  // ========================================================================
  // PURCHASES
  // ========================================================================

  Future<int> insertPurchase(Map<String, dynamic> data) async {
    try {
      final db = await database;

      // Validate
      if (data['quantity'] == null || data['quantity'] <= 0) {
        throw ArgumentError('Purchase quantity must be greater than 0');
      }
      if (data['costPrice'] == null || data['costPrice'] < 0) {
        throw ArgumentError('Cost price cannot be negative');
      }

      final now = DateTime.now().toIso8601String();
      data['createdAt'] = now;

      int purchaseId = 0;

      await db.transaction((txn) async {
        // Update product stock and cost price
        final updated = await txn.rawUpdate('''
          UPDATE products 
          SET stock = stock + ?, 
              costPrice = ?, 
              updatedAt = ?, 
              isSynced = 0 
          WHERE id = ? AND isDeleted = 0
        ''', [data['quantity'], data['costPrice'], now, data['productId']]);

        if (updated == 0) {
          throw Exception('Product not found or deleted');
        }

        // Insert purchase record
        purchaseId = await txn.insert('purchases', data);

        debugPrint('✅ Purchase recorded: ${data['quantity']} units for product ${data['productId']}');
      });

      return purchaseId;
    } catch (e) {
      debugPrint('❌ Error inserting purchase: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getPurchaseHistory({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final db = await database;

      final start = startDate.toIso8601String().substring(0, 10);
      final end = endDate.toIso8601String().substring(0, 10);

      return await db.rawQuery('''
        SELECT p.*, prod.name as productName 
        FROM purchases p
        JOIN products prod ON p.productId = prod.id
        WHERE DATE(p.purchaseDate) BETWEEN ? AND ? AND p.isDeleted = 0
        ORDER BY p.purchaseDate DESC
      ''', [start, end]);
    } catch (e) {
      debugPrint('❌ Error getting purchase history: $e');
      return [];
    }
  }

  // ========================================================================
  // BILLS
  // ========================================================================

  Future<List<Bill>> getAllBills({int? limit, int? offset}) async {
    try {
      final db = await database;
      final rows = await db.query(
        'bills',
        where: 'isDeleted = 0',
        orderBy: 'date DESC',
        limit: limit,
        offset: offset,
      );
      return rows.map((r) => Bill.fromMap(r)).toList();
    } catch (e) {
      debugPrint('❌ Error getting all bills: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getBills() async {
    try {
      final db = await database;
      return await db.query(
        'bills',
        where: 'isDeleted = 0',
        orderBy: 'date DESC',
      );
    } catch (e) {
      debugPrint('❌ Error getting bills: $e');
      return [];
    }
  }

  Future<Bill?> getBillById(int billId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'bills',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [billId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Bill.fromMap(rows.first);
    } catch (e) {
      debugPrint('❌ Error getting bill by ID: $e');
      return null;
    }
  }

  Future<List<Bill>> getBillsByClient(int clientId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'bills',
        where: 'clientId = ? AND isDeleted = 0',
        whereArgs: [clientId],
        orderBy: 'date DESC',
      );
      return rows.map((r) => Bill.fromMap(r)).toList();
    } catch (e) {
      debugPrint('❌ Error getting bills by client: $e');
      return [];
    }
  }

  Future<int> getBillsCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM bills WHERE isDeleted = 0',
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      debugPrint('❌ Error getting bills count: $e');
      return 0;
    }
  }

  Future<double> getTotalBillsAmount() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT SUM(totalAmount) as total FROM bills WHERE isDeleted = 0',
      );
      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      debugPrint('❌ Error getting total bills amount: $e');
      return 0.0;
    }
  }

  Future<double> getLastCarryForward(int clientId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'bills',
        columns: ['carryForward'],
        where: 'clientId = ? AND isDeleted = 0',
        whereArgs: [clientId],
        orderBy: 'date DESC',
        limit: 1,
      );

      if (rows.isEmpty) return 0.0;

      final value = rows.first['carryForward'];
      if (value == null) return 0.0;

      return (value as num).toDouble();
    } catch (e) {
      debugPrint('❌ Error getting last carry forward: $e');
      return 0.0;
    }
  }

  Future<int> insertBill(Bill bill) async {
    try {
      final db = await database;

      // Validate
      if (bill.totalAmount < 0) throw ArgumentError('Total amount cannot be negative');

      final now = DateTime.now();
      final updatedBill = bill.copyWith(
        createdAt: bill.createdAt ?? now,
        updatedAt: now,
        isSynced: false,
      );

      final id = await db.insert('bills', updatedBill.toMap());

      debugPrint('✅ Bill inserted (ID: $id)');
      return id;
    } catch (e) {
      debugPrint('❌ Error inserting bill: $e');
      rethrow;
    }
  }

  Future<int> insertBillWithItems(Bill bill, List<BillItem> items) async {
    try {
      final db = await database;

      // Validate
      if (items.isEmpty) throw ArgumentError('Bill must have at least one item');
      if (bill.totalAmount < 0) throw ArgumentError('Total amount cannot be negative');

      return await db.transaction<int>((txn) async {
        final now = DateTime.now();

        // Insert bill
        final billId = await txn.insert(
          'bills',
          bill.copyWith(
            createdAt: bill.createdAt ?? now,
            updatedAt: now,
            isSynced: false,
          ).toMap(),
        );

        debugPrint('✅ Bill created with ID: $billId');

        // Insert ledger entry for bill
        await txn.insert(
          'ledger',
          {
            'clientId': bill.clientId,
            'billId': billId,
            'type': 'bill',
            'amount': bill.totalAmount,
            'date': bill.date.toIso8601String(),
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
            'isSynced': 0,
            'isDeleted': 0,
          },
        );

        // Update client balance
        await txn.rawUpdate('''
          UPDATE clients 
          SET balance = balance + ?,
              updatedAt = ?,
              isSynced = 0
          WHERE id = ?
        ''', [bill.totalAmount, now.toIso8601String(), bill.clientId]);

        debugPrint('✅ Ledger entry created and client balance updated');

        // Insert bill items and update stock
        for (var item in items) {
          // Validate item
          if (item.quantity <= 0) throw ArgumentError('Item quantity must be greater than 0');
          if (item.price < 0) throw ArgumentError('Item price cannot be negative');

          // Check stock availability
          final stockCheck = await txn.rawQuery(
            'SELECT stock FROM products WHERE id = ? AND isDeleted = 0',
            [item.productId],
          );

          if (stockCheck.isEmpty) {
            throw Exception('Product ${item.productId} not found');
          }

          final currentStock = (stockCheck.first['stock'] as num).toDouble();
          if (currentStock < item.quantity) {
            final product = await txn.query('products', where: 'id = ?', whereArgs: [item.productId]);
            final productName = product.isNotEmpty ? product.first['name'] : 'Unknown';
            throw Exception('Insufficient stock for $productName. Available: $currentStock, Required: ${item.quantity}');
          }

          // Insert bill item
          final itemMap = item.copyWith(
            billId: billId,
            createdAt: item.createdAt ?? now,
            updatedAt: now,
            isSynced: false,
          ).toMap();

          await txn.insert('bill_items', itemMap);

          // Update product stock
          final updated = await txn.rawUpdate('''
            UPDATE products 
            SET stock = stock - ?, 
                isSynced = 0, 
                updatedAt = ? 
            WHERE id = ? AND stock >= ?
          ''', [item.quantity, now.toIso8601String(), item.productId, item.quantity]);

          if (updated == 0) {
            throw Exception('Failed to update stock for product ${item.productId}');
          }

          debugPrint('✅ Product ${item.productId}: Stock reduced by ${item.quantity}');
        }

        debugPrint('✅ Bill with ${items.length} items inserted successfully');
        return billId;
      });
    } catch (e) {
      debugPrint('❌ Error inserting bill with items: $e');
      rethrow;
    }
  }

  Future<int> updateBillComplete(
      Bill bill,
      List<BillItem> items, {
        bool updateLedger = true,
      }) async {
    try {
      final db = await database;

      // Validate
      if (items.isEmpty) throw ArgumentError('Bill must have at least one item');
      if (bill.totalAmount < 0) throw ArgumentError('Total amount cannot be negative');

      return await db.transaction<int>((txn) async {
        final now = DateTime.now();

        // Get old bill for balance adjustment
        final oldBillRows = await txn.query(
          'bills',
          where: 'id = ? AND isDeleted = 0',
          whereArgs: [bill.id],
        );

        if (oldBillRows.isEmpty) {
          throw Exception('Bill ${bill.id} not found');
        }

        final oldBill = Bill.fromMap(oldBillRows.first);
        final balanceDiff = bill.totalAmount - oldBill.totalAmount;

        // Get old items to restore stock
        final oldItems = await txn.query(
          'bill_items',
          where: 'billId = ? AND isDeleted = 0',
          whereArgs: [bill.id],
        );

        debugPrint('🔄 Updating bill ${bill.id} - Found ${oldItems.length} old items');

        // Restore stock for old items
        for (var oldItemMap in oldItems) {
          final oldProductId = oldItemMap['productId'] as int;
          final oldQuantity = (oldItemMap['quantity'] as num).toDouble();

          await txn.rawUpdate('''
            UPDATE products 
            SET stock = stock + ?, 
                isSynced = 0, 
                updatedAt = ? 
            WHERE id = ?
          ''', [oldQuantity, now.toIso8601String(), oldProductId]);

          debugPrint('✅ Restored $oldQuantity units to product $oldProductId');
        }

        // Update bill
        final result = await txn.update(
          'bills',
          bill.copyWith(
            updatedAt: now,
            isSynced: false,
          ).toMap(),
          where: 'id = ?',
          whereArgs: [bill.id],
        );

        if (result == 0) throw Exception('Failed to update bill ${bill.id}');

        // Soft delete old items
        await txn.update(
          'bill_items',
          {
            'isDeleted': 1,
            'isSynced': 0,
            'updatedAt': now.toIso8601String(),
          },
          where: 'billId = ?',
          whereArgs: [bill.id],
        );

        // Insert new items and deduct stock
        for (var item in items) {
          // Validate
          if (item.quantity <= 0) throw ArgumentError('Item quantity must be greater than 0');

          // Check stock
          final stockCheck = await txn.rawQuery(
            'SELECT stock, name FROM products WHERE id = ? AND isDeleted = 0',
            [item.productId],
          );

          if (stockCheck.isEmpty) {
            throw Exception('Product ${item.productId} not found');
          }

          final currentStock = (stockCheck.first['stock'] as num).toDouble();
          if (currentStock < item.quantity) {
            final productName = stockCheck.first['name'];
            throw Exception('Insufficient stock for $productName. Available: $currentStock');
          }

          final itemMap = item.copyWith(
            billId: bill.id,
            createdAt: item.createdAt ?? now,
            updatedAt: now,
            isSynced: false,
          ).toMap();

          itemMap.remove('id');
          itemMap.remove('firestoreId');

          await txn.insert('bill_items', itemMap);

          // Deduct stock
          await txn.rawUpdate('''
            UPDATE products 
            SET stock = stock - ?, 
                isSynced = 0, 
                updatedAt = ? 
            WHERE id = ?
          ''', [item.quantity, now.toIso8601String(), item.productId]);

          debugPrint('✅ Deducted ${item.quantity} units from product ${item.productId}');
        }

        // Update ledger if requested
        if (updateLedger) {
          final ledgerUpdated = await txn.update(
            'ledger',
            {
              'amount': bill.totalAmount,
              'date': bill.date.toIso8601String(),
              'isSynced': 0,
              'updatedAt': now.toIso8601String(),
            },
            where: 'billId = ? AND type = ? AND isDeleted = 0',
            whereArgs: [bill.id, 'bill'],
          );

          if (ledgerUpdated > 0) {
            // Update client balance
            await txn.rawUpdate('''
              UPDATE clients 
              SET balance = balance + ?,
                  updatedAt = ?,
                  isSynced = 0
              WHERE id = ?
            ''', [balanceDiff, now.toIso8601String(), bill.clientId]);

            debugPrint('✅ Ledger and balance updated for bill ${bill.id}');
          }
        }

        debugPrint('✅ Bill ${bill.id} updated with ${items.length} new items');
        return result;
      });
    } catch (e) {
      debugPrint('❌ Error updating bill: $e');
      rethrow;
    }
  }

  @Deprecated('Use updateBillComplete() instead')
  Future<int> updateBillWithItems(Bill bill, List<BillItem> items) async {
    return updateBillComplete(bill, items, updateLedger: true);
  }

  @Deprecated('Use updateBillComplete() instead')
  Future<int> updateBillWithLedger(Bill bill, {List<BillItem>? updatedItems}) async {
    if (updatedItems != null) {
      return updateBillComplete(bill, updatedItems, updateLedger: true);
    } else {
      return updateBill(bill);
    }
  }

  Future<int> updateBill(Bill bill) async {
    try {
      final db = await database;

      final updatedBill = bill.copyWith(
        updatedAt: DateTime.now(),
        isSynced: false,
      );

      final result = await db.update(
        'bills',
        updatedBill.toMap(),
        where: 'id = ?',
        whereArgs: [bill.id],
      );

      if (result > 0) {
        debugPrint('✅ Bill metadata updated (ID: ${bill.id})');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error updating bill: $e');
      rethrow;
    }
  }

  Future<void> updateBillTotal(int billId, double total) async {
    try {
      final db = await database;

      if (total < 0) throw ArgumentError('Total cannot be negative');

      await db.update(
        'bills',
        {
          'totalAmount': total,
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [billId],
      );

      debugPrint('✅ Bill total updated (ID: $billId)');
    } catch (e) {
      debugPrint('❌ Error updating bill total: $e');
      rethrow;
    }
  }

  Future<int> deleteBill(int id) async {
    try {
      final db = await database;

      return await db.transaction((txn) async {
        // Get bill details for balance adjustment
        final billRows = await txn.query(
          'bills',
          where: 'id = ? AND isDeleted = 0',
          whereArgs: [id],
        );

        if (billRows.isEmpty) {
          debugPrint('⚠️ Bill $id not found');
          return 0;
        }

        final bill = Bill.fromMap(billRows.first);

        // Get bill items to restore stock
        final billItems = await txn.query(
          'bill_items',
          where: 'billId = ? AND isDeleted = 0',
          whereArgs: [id],
        );

        debugPrint('🗑️ Deleting bill $id - Restoring stock for ${billItems.length} items');

        // Restore stock
        for (var itemMap in billItems) {
          final productId = itemMap['productId'] as int;
          final quantity = (itemMap['quantity'] as num).toDouble();

          await txn.rawUpdate('''
            UPDATE products 
            SET stock = stock + ?, 
                isSynced = 0, 
                updatedAt = ? 
            WHERE id = ?
          ''', [quantity, DateTime.now().toIso8601String(), productId]);

          debugPrint('✅ Restored $quantity units to product $productId');
        }

        // Soft delete bill items
        await txn.update(
          'bill_items',
          {
            'isDeleted': 1,
            'isSynced': 0,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'billId = ?',
          whereArgs: [id],
        );

        // Soft delete ledger entries
        await txn.update(
          'ledger',
          {
            'isDeleted': 1,
            'isSynced': 0,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'billId = ? AND type = ?',
          whereArgs: [id, 'bill'],
        );

        // Update client balance
        await txn.rawUpdate('''
          UPDATE clients 
          SET balance = balance - ?,
              updatedAt = ?,
              isSynced = 0
          WHERE id = ?
        ''', [bill.totalAmount, DateTime.now().toIso8601String(), bill.clientId]);

        // Soft delete bill
        final result = await txn.update(
          'bills',
          {
            'isDeleted': 1,
            'isSynced': 0,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );

        debugPrint('✅ Bill $id deleted with stock restoration and balance adjustment');
        return result;
      });
    } catch (e) {
      debugPrint('❌ Error deleting bill: $e');
      rethrow;
    }
  }

  Future<void> deleteBillCompletely(int billId) async {
    try {
      final db = await database;

      await db.transaction((txn) async {
        // Get bill for balance adjustment
        final billRows = await txn.query('bills', where: 'id = ?', whereArgs: [billId]);
        if (billRows.isEmpty) return;

        final bill = Bill.fromMap(billRows.first);

        // Restore stock
        final billItems = await txn.query('bill_items', where: 'billId = ?', whereArgs: [billId]);

        for (var itemMap in billItems) {
          final productId = itemMap['productId'] as int;
          final quantity = (itemMap['quantity'] as num).toDouble();

          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ?, updatedAt = ? WHERE id = ?',
            [quantity, DateTime.now().toIso8601String(), productId],
          );
        }

        // Update client balance
        await txn.rawUpdate('''
          UPDATE clients 
          SET balance = balance - ?,
              updatedAt = ?
          WHERE id = ?
        ''', [bill.totalAmount, DateTime.now().toIso8601String(), bill.clientId]);

        // Hard delete
        await txn.delete('bill_items', where: 'billId = ?', whereArgs: [billId]);
        await txn.delete('ledger', where: 'billId = ?', whereArgs: [billId]);
        await txn.delete('bills', where: 'id = ?', whereArgs: [billId]);
      });

      debugPrint('✅ Bill $billId completely deleted');
    } catch (e) {
      debugPrint('❌ Error completely deleting bill: $e');
      rethrow;
    }
  }

  Future<void> recalculateCarryForward(int clientId) async {
    try {
      final db = await database;

      await db.transaction((txn) async {
        final bills = await txn.query(
          'bills',
          where: 'clientId = ? AND isDeleted = 0',
          whereArgs: [clientId],
          orderBy: 'date ASC',
        );

        double runningBalance = 0;
        final now = DateTime.now().toIso8601String();

        for (var billMap in bills) {
          final bill = Bill.fromMap(billMap);
          final previousBalance = runningBalance;
          final totalAmt = bill.totalAmount;
          final paidAmt = bill.paidAmount;
          runningBalance = previousBalance + totalAmt - paidAmt;

          final currentCarryForward = bill.carryForward;
          if (currentCarryForward != runningBalance) {
            await txn.update(
              'bills',
              {
                'carryForward': runningBalance,
                'isSynced': 0,
                'updatedAt': now,
              },
              where: 'id = ?',
              whereArgs: [bill.id],
            );
          }
        }
      });

      debugPrint('✅ Carry forward recalculated for client $clientId');
    } catch (e) {
      debugPrint('❌ Error recalculating carry forward: $e');
      rethrow;
    }
  }

  // ========================================================================
  // BILL ITEMS
  // ========================================================================

  Future<List<BillItem>> getBillItems(int billId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'bill_items',
        where: 'billId = ? AND isDeleted = 0',
        whereArgs: [billId],
      );
      return rows.map((r) => BillItem.fromMap(r)).toList();
    } catch (e) {
      debugPrint('❌ Error getting bill items: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getBillItemsByBillId(int billId) async {
    try {
      final db = await database;
      return await db.query(
        'bill_items',
        where: 'billId = ? AND isDeleted = 0',
        whereArgs: [billId],
      );
    } catch (e) {
      debugPrint('❌ Error getting bill items by bill ID: $e');
      return [];
    }
  }

  Future<int> insertBillItem(BillItem item) async {
    try {
      final db = await database;

      if (item.quantity <= 0) throw ArgumentError('Quantity must be greater than 0');

      final now = DateTime.now();
      final updatedItem = item.copyWith(
        createdAt: item.createdAt ?? now,
        updatedAt: now,
        isSynced: false,
      );

      final id = await db.insert('bill_items', updatedItem.toMap());

      debugPrint('✅ Bill item inserted (ID: $id)');
      return id;
    } catch (e) {
      debugPrint('❌ Error inserting bill item: $e');
      rethrow;
    }
  }

  Future<int> deleteBillItem(int id) async {
    try {
      final db = await database;

      final result = await db.update(
        'bill_items',
        {
          'isDeleted': 1,
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      debugPrint('✅ Bill item soft-deleted (ID: $id)');
      return result;
    } catch (e) {
      debugPrint('❌ Error deleting bill item: $e');
      rethrow;
    }
  }

  Future<void> updateBillItemQuantityWithStock(int itemId, double newQty) async {
    try {
      final db = await database;

      if (newQty <= 0) throw ArgumentError('Quantity must be greater than 0');

      await db.transaction((txn) async {
        final currentItemMap = await txn.query(
          'bill_items',
          where: 'id = ? AND isDeleted = 0',
          whereArgs: [itemId],
          limit: 1,
        );

        if (currentItemMap.isEmpty) {
          throw Exception('Bill item $itemId not found');
        }

        final oldQty = (currentItemMap.first['quantity'] as num).toDouble();
        final productId = currentItemMap.first['productId'] as int;
        final diff = newQty - oldQty;

        // Check stock if increasing quantity
        if (diff > 0) {
          final stockCheck = await txn.rawQuery(
            'SELECT stock FROM products WHERE id = ? AND isDeleted = 0',
            [productId],
          );

          if (stockCheck.isEmpty) throw Exception('Product not found');

          final currentStock = (stockCheck.first['stock'] as num).toDouble();
          if (currentStock < diff) {
            throw Exception('Insufficient stock. Available: $currentStock, Required: $diff');
          }
        }

        final now = DateTime.now().toIso8601String();

        await txn.update(
          'bill_items',
          {
            'quantity': newQty,
            'isSynced': 0,
            'updatedAt': now,
          },
          where: 'id = ?',
          whereArgs: [itemId],
        );

        await txn.rawUpdate('''
          UPDATE products 
          SET stock = stock - ?, 
              isSynced = 0, 
              updatedAt = ? 
          WHERE id = ?
        ''', [diff, now, productId]);
      });

      debugPrint('✅ Bill item quantity updated (ID: $itemId)');
    } catch (e) {
      debugPrint('❌ Error updating bill item quantity: $e');
      rethrow;
    }
  }

  // ========================================================================
  // LEDGER
  // ========================================================================

  Future<List<LedgerEntry>> getAllLedgerEntries({int? limit, int? offset}) async {
    try {
      final db = await database;
      final rows = await db.query(
        'ledger',
        where: 'isDeleted = 0',
        orderBy: 'date DESC',
        limit: limit,
        offset: offset,
      );
      return rows.map((r) => LedgerEntry.fromMap(r)).toList();
    } catch (e) {
      debugPrint('❌ Error getting all ledger entries: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getLedgerEntries() async {
    try {
      final db = await database;
      return await db.query(
        'ledger',
        where: 'isDeleted = 0',
        orderBy: 'date DESC',
      );
    } catch (e) {
      debugPrint('❌ Error getting ledger entries: $e');
      return [];
    }
  }

  Future<List<LedgerEntry>> getLedgerEntriesByClient(int clientId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'ledger',
        where: 'clientId = ? AND isDeleted = 0',
        whereArgs: [clientId],
        orderBy: 'date ASC',
      );
      return rows.map((r) => LedgerEntry.fromMap(r)).toList();
    } catch (e) {
      debugPrint('❌ Error getting ledger entries by client: $e');
      return [];
    }
  }

  Future<double> getClientBalance(int clientId) async {
    try {
      final db = await database;

      // Get from clients table for performance
      final result = await db.query(
        'clients',
        columns: ['balance'],
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [clientId],
        limit: 1,
      );

      if (result.isEmpty) return 0.0;
      return (result.first['balance'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      debugPrint('❌ Error getting client balance: $e');
      return 0.0;
    }
  }

  Future<int> insertLedgerEntry(LedgerEntry entry) async {
    try {
      final db = await database;

      if (entry.amount <= 0) throw ArgumentError('Amount must be greater than 0');

      return await db.transaction((txn) async {
        final now = DateTime.now();
        final updatedEntry = entry.copyWith(
          createdAt: entry.createdAt ?? now,
          updatedAt: now,
          isSynced: false,
        );

        final id = await txn.insert('ledger', updatedEntry.toMap());

        // Update client balance
        final balanceChange = entry.type == 'bill' ? entry.amount : -entry.amount;

        await txn.rawUpdate('''
          UPDATE clients 
          SET balance = balance + ?,
              updatedAt = ?,
              isSynced = 0
          WHERE id = ?
        ''', [balanceChange, now.toIso8601String(), entry.clientId]);

        debugPrint('✅ Ledger entry inserted and balance updated (ID: $id)');
        return id;
      });
    } catch (e) {
      debugPrint('❌ Error inserting ledger entry: $e');
      rethrow;
    }
  }

  Future<int> insertCashPayment({
    required int clientId,
    required double amount,
    String? note,
  }) async {
    try {
      if (amount <= 0) throw ArgumentError('Payment amount must be greater than 0');

      final db = await database;

      return await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();

        final id = await txn.insert('ledger', {
          'clientId': clientId,
          'type': 'payment',
          'amount': amount,
          'date': now,
          'note': note ?? 'Cash Payment',
          'paymentMethod': 'cash',
          'createdAt': now,
          'updatedAt': now,
          'isSynced': 0,
          'isDeleted': 0,
        });

        // Update client balance
        await txn.rawUpdate('''
          UPDATE clients 
          SET balance = balance - ?,
              updatedAt = ?,
              isSynced = 0
          WHERE id = ?
        ''', [amount, now, clientId]);

        debugPrint('✅ Cash payment inserted and balance updated (ID: $id)');
        return id;
      });
    } catch (e) {
      debugPrint('❌ Error inserting cash payment: $e');
      rethrow;
    }
  }

  Future<int> updateLedgerEntry(LedgerEntry entry) async {
    try {
      final db = await database;

      if (entry.amount <= 0) throw ArgumentError('Amount must be greater than 0');

      return await db.transaction((txn) async {
        // Get old entry for balance adjustment
        final oldRows = await txn.query(
          'ledger',
          where: 'id = ? AND isDeleted = 0',
          whereArgs: [entry.id],
        );

        if (oldRows.isEmpty) throw Exception('Ledger entry not found');

        final oldEntry = LedgerEntry.fromMap(oldRows.first);
        final oldBalanceChange = oldEntry.type == 'bill' ? oldEntry.amount : -oldEntry.amount;
        final newBalanceChange = entry.type == 'bill' ? entry.amount : -entry.amount;
        final balanceDiff = newBalanceChange - oldBalanceChange;

        final updatedEntry = entry.copyWith(
          updatedAt: DateTime.now(),
          isSynced: false,
        );

        final result = await txn.update(
          'ledger',
          updatedEntry.toMap(),
          where: 'id = ?',
          whereArgs: [entry.id],
        );

        // Update client balance
        if (balanceDiff != 0) {
          await txn.rawUpdate('''
            UPDATE clients 
            SET balance = balance + ?,
                updatedAt = ?,
                isSynced = 0
            WHERE id = ?
          ''', [balanceDiff, DateTime.now().toIso8601String(), entry.clientId]);
        }

        debugPrint('✅ Ledger entry and balance updated (ID: ${entry.id})');
        return result;
      });
    } catch (e) {
      debugPrint('❌ Error updating ledger entry: $e');
      rethrow;
    }
  }

  Future<int> deleteLedgerEntry(int id) async {
    try {
      final db = await database;

      return await db.transaction((txn) async {
        // Get entry for balance adjustment
        final rows = await txn.query(
          'ledger',
          where: 'id = ? AND isDeleted = 0',
          whereArgs: [id],
        );

        if (rows.isEmpty) return 0;

        final entry = LedgerEntry.fromMap(rows.first);
        final balanceChange = entry.type == 'bill' ? -entry.amount : entry.amount;

        final result = await txn.update(
          'ledger',
          {
            'isDeleted': 1,
            'isSynced': 0,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );

        // Update client balance
        await txn.rawUpdate('''
          UPDATE clients 
          SET balance = balance + ?,
              updatedAt = ?,
              isSynced = 0
          WHERE id = ?
        ''', [balanceChange, DateTime.now().toIso8601String(), entry.clientId]);

        debugPrint('✅ Ledger entry soft-deleted and balance adjusted (ID: $id)');
        return result;
      });
    } catch (e) {
      debugPrint('❌ Error deleting ledger entry: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getClientsWithBalances() async {
    try {
      final db = await database;
      return await db.rawQuery('''
        SELECT c.*
        FROM clients c
        WHERE c.isDeleted = 0
        ORDER BY c.name COLLATE NOCASE ASC
      ''');
    } catch (e) {
      debugPrint('❌ Error getting clients with balances: $e');
      return [];
    }
  }

  // ========================================================================
  // STOCK MANAGEMENT
  // ========================================================================

  Future<double> getStock(int productId) async {
    try {
      final db = await database;
      final res = await db.query(
        'products',
        columns: ['stock'],
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [productId],
        limit: 1,
      );

      if (res.isEmpty) return 0.0;
      return (res.first['stock'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      debugPrint('❌ Error getting stock: $e');
      return 0.0;
    }
  }

  Future<void> setStock(int productId, double qty) async {
    try {
      if (qty < 0) throw ArgumentError('Stock cannot be negative');

      final db = await database;

      final updated = await db.update(
        'products',
        {
          'stock': qty,
          'updatedAt': DateTime.now().toIso8601String(),
          'isSynced': 0,
        },
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [productId],
      );

      if (updated > 0) {
        debugPrint('✅ Stock set for product $productId: $qty');
      }
    } catch (e) {
      debugPrint('❌ Error setting stock: $e');
      rethrow;
    }
  }

  Future<void> adjustStock(int productId, double deltaQty) async {
    try {
      final db = await database;

      // Check if adjustment would result in negative stock
      if (deltaQty < 0) {
        final currentStock = await getStock(productId);
        if (currentStock + deltaQty < 0) {
          throw Exception('Cannot adjust stock: would result in negative value');
        }
      }

      await db.rawUpdate('''
        UPDATE products 
        SET stock = stock + ?, 
            updatedAt = ?, 
            isSynced = 0 
        WHERE id = ? AND isDeleted = 0
      ''', [deltaQty, DateTime.now().toIso8601String(), productId]);

      debugPrint('✅ Stock adjusted for product $productId: ${deltaQty >= 0 ? "+" : ""}$deltaQty');
    } catch (e) {
      debugPrint('❌ Error adjusting stock: $e');
      rethrow;
    }
  }

  Future<int> updateProductStock(int productId, double newQty) async {
    try {
      if (newQty < 0) throw ArgumentError('Stock cannot be negative');

      final db = await database;

      final result = await db.update(
        'products',
        {
          'stock': newQty,
          'updatedAt': DateTime.now().toIso8601String(),
          'isSynced': 0,
        },
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [productId],
      );

      if (result > 0) {
        debugPrint('✅ Product stock updated (ID: $productId, Qty: $newQty)');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error updating product stock: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAllStock() async {
    try {
      final db = await database;
      return await db.rawQuery('''
        SELECT p.id, p.name, p.stock as quantity, p.costPrice
        FROM products p
        WHERE p.isDeleted = 0
        ORDER BY p.name COLLATE NOCASE
      ''');
    } catch (e) {
      debugPrint('❌ Error getting all stock: $e');
      return [];
    }
  }

  Future<void> syncStockTable() async {
    try {
      final db = await database;
      await db.execute('''
        INSERT OR REPLACE INTO stock (productId, quantity, updatedAt, isSynced)
        SELECT id, stock, updatedAt, isSynced FROM products WHERE isDeleted = 0
      ''');
      debugPrint('✅ Stock table synchronized');
    } catch (e) {
      debugPrint('❌ Error syncing stock table: $e');
    }
  }

  // ========================================================================
  // DEMAND MANAGEMENT
  // ========================================================================

  String _dateOnlyIso(DateTime dt) => dt.toIso8601String().substring(0, 10);

  Future<int?> getBatchIdForDate(DateTime date) async {
    try {
      final db = await database;
      final dateStr = _dateOnlyIso(date);

      final result = await db.rawQuery('''
        SELECT id, demandDate, closed
        FROM demand_batch
        WHERE DATE(demandDate) = ? AND isDeleted = 0
        LIMIT 1
      ''', [dateStr]);

      if (result.isEmpty) return null;

      return result.first['id'] as int;
    } catch (e) {
      debugPrint('❌ Error getting batch ID for date: $e');
      return null;
    }
  }

  Future<int> getOrCreateBatchForDate(DateTime date) async {
    try {
      final db = await database;
      final ds = _dateOnlyIso(date);

      final rows = await db.rawQuery('''
        SELECT id
        FROM demand_batch
        WHERE DATE(demandDate) = ? AND isDeleted = 0
        LIMIT 1
      ''', [ds]);

      if (rows.isNotEmpty) {
        return rows.first['id'] as int;
      }

      final now = DateTime.now().toIso8601String();
      final id = await db.insert('demand_batch', {
        'demandDate': ds,
        'closed': 0,
        'isSynced': 0,
        'createdAt': now,
        'updatedAt': now,
        'isDeleted': 0,
      });

      debugPrint('✅ Created demand batch (ID: $id) for date: $ds');
      return id;
    } catch (e) {
      debugPrint('❌ Error getting or creating batch: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getDemandHistory() async {
    try {
      final db = await database;
      return await db.query(
        'demand_batch',
        where: 'isDeleted = 0',
        orderBy: 'demandDate DESC',
      );
    } catch (e) {
      debugPrint('❌ Error getting demand history: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getBatchesWithEntries() async {
    try {
      final db = await database;
      return await db.rawQuery('''
        SELECT 
          db.id,
          db.demandDate,
          db.closed,
          db.createdAt,
          COUNT(DISTINCT d.id) as entryCount,
          SUM(d.quantity) as totalQuantity
        FROM demand_batch db
        INNER JOIN demand d ON d.batchId = db.id AND d.isDeleted = 0
        WHERE db.isDeleted = 0
        GROUP BY db.id
        HAVING entryCount > 0
        ORDER BY db.demandDate DESC
      ''');
    } catch (e) {
      debugPrint('❌ Error getting batches with entries: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getCurrentBatchTotals(int batchId) async {
    try {
      final db = await database;
      return await db.rawQuery('''
        SELECT 
          p.id AS productId, 
          p.name AS productName, 
          SUM(d.quantity) AS totalQty
        FROM demand d
        JOIN products p ON p.id = d.productId
        WHERE d.batchId = ? AND d.isDeleted = 0 AND p.isDeleted = 0
        GROUP BY d.productId
        ORDER BY p.name COLLATE NOCASE
      ''', [batchId]);
    } catch (e) {
      debugPrint('❌ Error getting current batch totals: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getBatchById(int batchId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'demand_batch',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [batchId],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (e) {
      debugPrint('❌ Error getting batch by ID: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getBatchDetails(int batchId) async {
    try {
      final db = await database;
      return await db.rawQuery('''
        SELECT 
          p.id AS productId,
          p.name AS productName,
          SUM(d.quantity) AS totalQty
        FROM demand d
        JOIN products p ON p.id = d.productId
        WHERE d.batchId = ? AND d.isDeleted = 0 AND p.isDeleted = 0
        GROUP BY p.id
        ORDER BY p.name COLLATE NOCASE
      ''', [batchId]);
    } catch (e) {
      debugPrint('❌ Error getting batch details: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getBatchClientDetails(int batchId) async {
    try {
      final db = await database;
      return await db.rawQuery('''
        SELECT 
          c.id AS clientId, 
          c.name AS clientName,
          p.id AS productId, 
          p.name AS productName,
          SUM(d.quantity) AS qty
        FROM demand d
        JOIN clients c ON c.id = d.clientId
        JOIN products p ON p.id = d.productId
        WHERE d.batchId = ? AND d.isDeleted = 0 AND c.isDeleted = 0 AND p.isDeleted = 0
        GROUP BY c.id, p.id
        ORDER BY c.name COLLATE NOCASE, p.name COLLATE NOCASE
      ''', [batchId]);
    } catch (e) {
      debugPrint('❌ Error getting batch client details: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getBatchStats(int batchId) async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT 
          COUNT(DISTINCT d.productId) as productCount,
          COUNT(DISTINCT d.clientId) as clientCount,
          COALESCE(SUM(d.quantity), 0) as totalQuantity,
          COALESCE(SUM(d.quantity * p.costPrice), 0) as totalCost
        FROM demand d
        JOIN products p ON d.productId = p.id
        WHERE d.batchId = ? AND d.isDeleted = 0
      ''', [batchId]);

      if (result.isEmpty) {
        return {
          'productCount': 0,
          'clientCount': 0,
          'totalQuantity': 0.0,
          'totalCost': 0.0,
        };
      }

      return Map<String, dynamic>.from(result.first);
    } catch (e) {
      debugPrint('❌ Error getting batch stats: $e');
      return {
        'productCount': 0,
        'clientCount': 0,
        'totalQuantity': 0.0,
        'totalCost': 0.0,
      };
    }
  }

  Future<bool> batchHasEntries(int batchId) async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT COUNT(*) as count 
        FROM demand 
        WHERE batchId = ? AND isDeleted = 0
      ''', [batchId]);

      final count = Sqflite.firstIntValue(result) ?? 0;
      return count > 0;
    } catch (e) {
      debugPrint('❌ Error checking batch entries: $e');
      return false;
    }
  }

  Future<int> insertDemandEntry({
    required int batchId,
    required int clientId,
    required int productId,
    required double quantity,
  }) async {
    try {
      if (quantity <= 0) throw ArgumentError('Quantity must be greater than 0');

      final db = await database;
      final now = DateTime.now().toIso8601String();

      final id = await db.insert('demand', {
        'batchId': batchId,
        'clientId': clientId,
        'productId': productId,
        'quantity': quantity,
        'date': now,
        'isDeleted': 0,
        'isSynced': 0,
        'createdAt': now,
        'updatedAt': now,
      });

      debugPrint('✅ Demand entry inserted (ID: $id)');
      return id;
    } catch (e) {
      debugPrint('❌ Error inserting demand entry: $e');
      rethrow;
    }
  }

  Future<int> deleteDemandEntry(int entryId) async {
    try {
      final db = await database;

      final result = await db.update(
        'demand',
        {
          'isDeleted': 1,
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [entryId],
      );

      debugPrint('✅ Demand entry soft-deleted (ID: $entryId)');
      return result;
    } catch (e) {
      debugPrint('❌ Error deleting demand entry: $e');
      rethrow;
    }
  }

  Future<int> updateDemandEntry({
    required int entryId,
    required double quantity,
  }) async {
    try {
      if (quantity <= 0) throw ArgumentError('Quantity must be greater than 0');

      final db = await database;

      final result = await db.update(
        'demand',
        {
          'quantity': quantity,
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [entryId],
      );

      debugPrint('✅ Demand entry updated (ID: $entryId)');
      return result;
    } catch (e) {
      debugPrint('❌ Error updating demand entry: $e');
      rethrow;
    }
  }

  Future<void> reopenBatch(int batchId) async {
    try {
      final db = await database;

      await db.update(
        'demand_batch',
        {
          'closed': 0,
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [batchId],
      );

      debugPrint('✅ Batch $batchId reopened');
    } catch (e) {
      debugPrint('❌ Error reopening batch: $e');
      rethrow;
    }
  }

  Future<int?> closeBatch(
      int batchId, {
        bool createNextDay = false,
        bool deductStock = false,
      }) async {
    try {
      final db = await database;

      await db.transaction((txn) async {
        final productTotals = await txn.rawQuery('''
          SELECT productId, SUM(quantity) AS totalQty
          FROM demand
          WHERE batchId = ? AND isDeleted = 0
          GROUP BY productId
        ''', [batchId]);

        for (final row in productTotals) {
          final pid = row['productId'] as int;
          final qty = (row['totalQty'] as num).toDouble();
          final adjustment = deductStock ? -qty : qty;

          await txn.rawUpdate('''
            UPDATE products 
            SET stock = stock + ?, 
                isSynced = 0, 
                updatedAt = ? 
            WHERE id = ?
          ''', [adjustment, DateTime.now().toIso8601String(), pid]);
        }

        await txn.update(
          'demand_batch',
          {
            'closed': 1,
            'isSynced': 0,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [batchId],
        );
      });

      debugPrint('✅ Batch $batchId closed');

      if (createNextDay) {
        final nextDay = DateTime.now().add(const Duration(days: 1));
        return getOrCreateBatchForDate(nextDay);
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error closing batch: $e');
      rethrow;
    }
  }

  // ========================================================================
  // BASIC REPORTING
  // ========================================================================

  Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final clientsCount = await getClientsCount();
      final productsCount = await getProductsCount();
      final billsCount = await getBillsCount();
      final totalRevenue = await getTotalBillsAmount();

      final db = await database;

      final pendingPayments = await db.rawQuery('''
        SELECT COALESCE(SUM(amount), 0) as total
        FROM ledger
        WHERE type = 'bill' AND isDeleted = 0
      ''');

      final lowStockCount = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM products
        WHERE stock < ? AND isDeleted = 0
      ''', [LOW_STOCK_THRESHOLD]);

      return {
        'clientsCount': clientsCount,
        'productsCount': productsCount,
        'billsCount': billsCount,
        'totalRevenue': totalRevenue,
        'pendingPayments': (pendingPayments.first['total'] as num?)?.toDouble() ?? 0.0,
        'lowStockCount': (lowStockCount.first['count'] as int?) ?? 0,
      };
    } catch (e) {
      debugPrint('❌ Error getting dashboard stats: $e');
      return {
        'clientsCount': 0,
        'productsCount': 0,
        'billsCount': 0,
        'totalRevenue': 0.0,
        'pendingPayments': 0.0,
        'lowStockCount': 0,
      };
    }
  }

  Future<List<Map<String, dynamic>>> getOutstandingBalances() async {
    try {
      final db = await database;
      return await db.rawQuery('''
        SELECT 
          c.id, 
          c.name, 
          c.phone,
          c.balance
        FROM clients c
        WHERE c.isDeleted = 0 AND c.balance > 0
        ORDER BY c.balance DESC
      ''');
    } catch (e) {
      debugPrint('❌ Error getting outstanding balances: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final db = await database;
      final Map<String, dynamic> status = {};
      final tables = [
        'clients',
        'products',
        'bills',
        'bill_items',
        'ledger',
        'demand_batch',
        'demand',
      ];

      for (final table in tables) {
        final totalCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 0'),
        ) ?? 0;

        final unsyncedCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 0 AND isSynced = 0'),
        ) ?? 0;

        status[table] = {
          'total': totalCount,
          'unsynced': unsyncedCount,
          'syncedPercent': totalCount > 0
              ? ((totalCount - unsyncedCount) / totalCount * 100).round()
              : 100,
        };
      }

      return status;
    } catch (e) {
      debugPrint('❌ Error getting sync status: $e');
      return {};
    }
  }

  // ========================================================================
  // SAFE DELETION
  // ========================================================================

  Future<bool> canHardDeleteClient(int clientId) async {
    try {
      final db = await database;

      final billCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM bills WHERE clientId = ?', [clientId])
      ) ?? 0;

      final ledgerCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ledger WHERE clientId = ?', [clientId])
      ) ?? 0;

      return billCount == 0 && ledgerCount == 0;
    } catch (e) {
      debugPrint('❌ Error checking if can delete client: $e');
      return false;
    }
  }

  Future<bool> canHardDeleteProduct(int productId) async {
    try {
      final db = await database;

      final itemCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM bill_items WHERE productId = ?', [productId])
      ) ?? 0;

      return itemCount == 0;
    } catch (e) {
      debugPrint('❌ Error checking if can delete product: $e');
      return false;
    }
  }

  Future<bool> hardDeleteClientIfSafe(int clientId) async {
    try {
      if (!await canHardDeleteClient(clientId)) {
        debugPrint('⚠️ Client $clientId has related records');
        return false;
      }

      final db = await database;
      await db.delete('clients', where: 'id = ?', whereArgs: [clientId]);
      debugPrint('✅ Client $clientId hard deleted');
      return true;
    } catch (e) {
      debugPrint('❌ Error hard deleting client: $e');
      return false;
    }
  }

  Future<bool> hardDeleteProductIfSafe(int productId) async {
    try {
      if (!await canHardDeleteProduct(productId)) {
        debugPrint('⚠️ Product $productId used in bills');
        return false;
      }

      final db = await database;
      await db.delete('products', where: 'id = ?', whereArgs: [productId]);
      debugPrint('✅ Product $productId hard deleted');
      return true;
    } catch (e) {
      debugPrint('❌ Error hard deleting product: $e');
      return false;
    }
  }

  // ========================================================================
  // UTILITIES
  // ========================================================================

  Future<bool> clientExists(int id) async {
    try {
      final db = await database;
      final result = await db.query(
        'clients',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [id],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      debugPrint('❌ Error checking client exists: $e');
      return false;
    }
  }

  Future<bool> productExists(int id) async {
    try {
      final db = await database;
      final result = await db.query(
        'products',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [id],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      debugPrint('❌ Error checking product exists: $e');
      return false;
    }
  }

  Future<bool> billExists(int id) async {
    try {
      final db = await database;
      final result = await db.query(
        'bills',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [id],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      debugPrint('❌ Error checking bill exists: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<Object?>? args]) async {
    try {
      final db = await database;
      return await db.rawQuery(sql, args);
    } catch (e) {
      debugPrint('❌ Error executing raw query: $e');
      return [];
    }
  }

  Future<int> rawUpdate(String sql, [List<Object?>? args]) async {
    try {
      final db = await database;
      return await db.rawUpdate(sql, args);
    } catch (e) {
      debugPrint('❌ Error executing raw update: $e');
      return 0;
    }
  }

  Future<void> close() async {
    try {
      if (_db != null) {
        await _db!.close();
        _db = null;
        debugPrint('✅ Database closed');
      }
    } catch (e) {
      debugPrint('❌ Error closing database: $e');
    }
  }
  // ========================================================================
  // ADVANCED REPORTING & ANALYTICS
  // ========================================================================

  Future<Map<String, dynamic>> getYearlySales([int? year]) async {
    try {
      final db = await database;
      final targetYear = year ?? DateTime.now().year;

      final result = await db.rawQuery('''
        SELECT 
          COUNT(DISTINCT b.id) as totalBills,
          COALESCE(SUM(b.totalAmount), 0) as totalSales,
          COALESCE(SUM(bi.quantity * p.costPrice), 0) as totalCost,
          COALESCE(SUM(b.totalAmount) - SUM(bi.quantity * p.costPrice), 0) as totalProfit,
          COUNT(DISTINCT b.clientId) as uniqueCustomers,
          AVG(b.totalAmount) as avgBillValue
        FROM bills b
        LEFT JOIN bill_items bi ON bi.billId = b.id AND bi.isDeleted = 0
        LEFT JOIN products p ON p.id = bi.productId
        WHERE strftime('%Y', b.date) = ? AND b.isDeleted = 0
      ''', [targetYear.toString()]);

      final data = result.isNotEmpty ? result.first : <String, dynamic>{};

      return {
        'year': targetYear,
        'totalBills': (data['totalBills'] as int?) ?? 0,
        'totalSales': (data['totalSales'] as num?)?.toDouble() ?? 0.0,
        'totalCost': (data['totalCost'] as num?)?.toDouble() ?? 0.0,
        'totalProfit': (data['totalProfit'] as num?)?.toDouble() ?? 0.0,
        'uniqueCustomers': (data['uniqueCustomers'] as int?) ?? 0,
        'avgBillValue': (data['avgBillValue'] as num?)?.toDouble() ?? 0.0,
      };
    } catch (e) {
      debugPrint('❌ Error getting yearly sales: $e');
      return {
        'year': year ?? DateTime.now().year,
        'totalBills': 0,
        'totalSales': 0.0,
        'totalCost': 0.0,
        'totalProfit': 0.0,
        'uniqueCustomers': 0,
        'avgBillValue': 0.0,
      };
    }
  }

  Future<List<Map<String, dynamic>>> getMonthlySales([int? year]) async {
    try {
      final db = await database;
      final targetYear = year ?? DateTime.now().year;

      return await db.rawQuery('''
        SELECT 
          strftime('%m', b.date) as month,
          strftime('%Y-%m', b.date) as yearMonth,
          COUNT(DISTINCT b.id) as totalBills,
          COALESCE(SUM(b.totalAmount), 0) as totalSales,
          COALESCE(SUM(bi.quantity * p.costPrice), 0) as totalCost,
          COUNT(DISTINCT b.clientId) as uniqueCustomers
        FROM bills b
        LEFT JOIN bill_items bi ON bi.billId = b.id AND bi.isDeleted = 0
        LEFT JOIN products p ON p.id = bi.productId
        WHERE strftime('%Y', b.date) = ? AND b.isDeleted = 0
        GROUP BY strftime('%Y-%m', b.date)
        ORDER BY month
      ''', [targetYear.toString()]);
    } catch (e) {
      debugPrint('❌ Error getting monthly sales: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getDailySales(
      DateTime startDate,
      DateTime endDate, {
        int? limit,
        int? offset,
      }) async {
    try {
      final db = await database;

      String limitClause = '';
      if (limit != null) {
        limitClause = 'LIMIT $limit';
        if (offset != null) limitClause += ' OFFSET $offset';
      }

      final start = startDate.toIso8601String().substring(0, 10);
      final end = endDate.toIso8601String().substring(0, 10);

      return await db.rawQuery('''
        SELECT 
          DATE(b.date) as date,
          COUNT(DISTINCT b.id) as totalBills,
          COALESCE(SUM(b.totalAmount), 0) as totalSales,
          COALESCE(SUM(bi.quantity * p.costPrice), 0) as totalCost,
          COUNT(DISTINCT b.clientId) as uniqueCustomers
        FROM bills b
        LEFT JOIN bill_items bi ON bi.billId = b.id AND bi.isDeleted = 0
        LEFT JOIN products p ON p.id = bi.productId
        WHERE DATE(b.date) BETWEEN ? AND ? AND b.isDeleted = 0
        GROUP BY DATE(b.date)
        ORDER BY DATE(b.date) DESC
        $limitClause
      ''', [start, end]);
    } catch (e) {
      debugPrint('❌ Error getting daily sales: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getYearOverYearComparison(int currentYear) async {
    try {
      final currentYearData = await getYearlySales(currentYear);
      final previousYearData = await getYearlySales(currentYear - 1);

      final currentSales = currentYearData['totalSales'] as double;
      final previousSales = previousYearData['totalSales'] as double;
      final salesGrowth = previousSales > 0 ? ((currentSales - previousSales) / previousSales * 100) : 0.0;

      final currentProfit = currentYearData['totalProfit'] as double;
      final previousProfit = previousYearData['totalProfit'] as double;
      final profitGrowth = previousProfit > 0 ? ((currentProfit - previousProfit) / previousProfit * 100) : 0.0;

      return {
        'currentYear': currentYearData,
        'previousYear': previousYearData,
        'salesGrowthPercent': salesGrowth,
        'profitGrowthPercent': profitGrowth,
      };
    } catch (e) {
      debugPrint('❌ Error getting year over year comparison: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getProductSalesReport({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? offset,
    String orderBy = 'totalSales',
  }) async {
    try {
      final db = await database;

      String dateFilter = '';
      List<String> params = [];

      if (startDate != null && endDate != null) {
        dateFilter = 'AND DATE(b.date) BETWEEN ? AND ?';
        params.addAll([
          startDate.toIso8601String().substring(0, 10),
          endDate.toIso8601String().substring(0, 10)
        ]);
      }

      String orderClause = 'ORDER BY totalSales DESC';
      switch (orderBy) {
        case 'totalQuantity':
          orderClause = 'ORDER BY totalQuantity DESC';
          break;
        case 'totalProfit':
          orderClause = 'ORDER BY totalProfit DESC';
          break;
        case 'avgPrice':
          orderClause = 'ORDER BY avgPrice DESC';
          break;
      }

      String limitClause = '';
      if (limit != null) {
        limitClause = 'LIMIT $limit';
        if (offset != null) limitClause += ' OFFSET $offset';
      }

      return await db.rawQuery('''
        SELECT 
          p.id as productId,
          p.name as productName,
          p.price as currentPrice,
          p.costPrice as currentCostPrice,
          p.stock as currentStock,
          COALESCE(SUM(bi.quantity), 0) as totalQuantity,
          COALESCE(SUM(bi.quantity * bi.price), 0) as totalSales,
          COALESCE(SUM(bi.quantity * p.costPrice), 0) as totalCost,
          COALESCE(SUM(bi.quantity * bi.price) - SUM(bi.quantity * p.costPrice), 0) as totalProfit,
          COALESCE(AVG(bi.price), 0) as avgPrice,
          COUNT(DISTINCT b.id) as totalBills,
          COUNT(DISTINCT b.clientId) as uniqueCustomers
        FROM products p
        LEFT JOIN bill_items bi ON bi.productId = p.id AND bi.isDeleted = 0
        LEFT JOIN bills b ON b.id = bi.billId AND b.isDeleted = 0 $dateFilter
        WHERE p.isDeleted = 0
        GROUP BY p.id
        $orderClause
        $limitClause
      ''', params);
    } catch (e) {
      debugPrint('❌ Error getting product sales report: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getProductTrends(int productId, {int months = 12}) async {
    try {
      final db = await database;

      return await db.rawQuery('''
        SELECT 
          strftime('%Y-%m', b.date) as yearMonth,
          COALESCE(SUM(bi.quantity), 0) as quantity,
          COALESCE(SUM(bi.quantity * bi.price), 0) as sales,
          COALESCE(AVG(bi.price), 0) as avgPrice,
          COUNT(DISTINCT b.id) as totalBills
        FROM bills b
        JOIN bill_items bi ON bi.billId = b.id
        WHERE bi.productId = ? AND b.isDeleted = 0 AND bi.isDeleted = 0
          AND DATE(b.date) >= DATE('now', '-$months months')
        GROUP BY strftime('%Y-%m', b.date)
        ORDER BY yearMonth
      ''', [productId]);
    } catch (e) {
      debugPrint('❌ Error getting product trends: $e');
      return [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> getTopProducts({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10,
  }) async {
    try {
      final baseData = await getProductSalesReport(
        startDate: startDate,
        endDate: endDate,
        orderBy: 'totalSales',
        limit: limit * 2,
      );

      final topBySales = List<Map<String, dynamic>>.from(baseData).take(limit).toList();

      final topByQuantity = List<Map<String, dynamic>>.from(baseData);
      topByQuantity.sort((a, b) => (b['totalQuantity'] as num).compareTo(a['totalQuantity'] as num));

      final topByProfit = List<Map<String, dynamic>>.from(baseData);
      topByProfit.sort((a, b) => (b['totalProfit'] as num).compareTo(a['totalProfit'] as num));

      final mostPopular = List<Map<String, dynamic>>.from(baseData);
      mostPopular.sort((a, b) => (b['totalBills'] as num).compareTo(a['totalBills'] as num));

      return {
        'topBySales': topBySales,
        'topByQuantity': topByQuantity.take(limit).toList(),
        'topByProfit': topByProfit.take(limit).toList(),
        'mostPopular': mostPopular.take(limit).toList(),
      };
    } catch (e) {
      debugPrint('❌ Error getting top products: $e');
      return {
        'topBySales': [],
        'topByQuantity': [],
        'topByProfit': [],
        'mostPopular': [],
      };
    }
  }

  Future<List<Map<String, dynamic>>> getCustomerAnalysis({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? offset,
    String orderBy = 'totalPurchases',
  }) async {
    try {
      final db = await database;

      String dateFilter = '';
      List<String> params = [];

      if (startDate != null && endDate != null) {
        dateFilter = 'AND DATE(b.date) BETWEEN ? AND ?';
        params.addAll([
          startDate.toIso8601String().substring(0, 10),
          endDate.toIso8601String().substring(0, 10)
        ]);
      }

      String orderClause = 'ORDER BY totalPurchases DESC';
      switch (orderBy) {
        case 'avgBillValue':
          orderClause = 'ORDER BY avgBillValue DESC';
          break;
        case 'lastPurchase':
          orderClause = 'ORDER BY lastPurchaseDate DESC';
          break;
        case 'frequency':
          orderClause = 'ORDER BY totalBills DESC';
          break;
      }

      String limitClause = '';
      if (limit != null) {
        limitClause = 'LIMIT $limit';
        if (offset != null) limitClause += ' OFFSET $offset';
      }

      return await db.rawQuery('''
        SELECT 
          c.id as clientId,
          c.name as clientName,
          c.phone as clientPhone,
          c.balance as currentOutstanding,
          COUNT(DISTINCT b.id) as totalBills,
          COALESCE(SUM(b.totalAmount), 0) as totalPurchases,
          COALESCE(AVG(b.totalAmount), 0) as avgBillValue,
          MIN(DATE(b.date)) as firstPurchaseDate,
          MAX(DATE(b.date)) as lastPurchaseDate,
          (julianday('now') - julianday(MAX(DATE(b.date)))) as daysSinceLastPurchase
        FROM clients c
        LEFT JOIN bills b ON b.clientId = c.id AND b.isDeleted = 0 $dateFilter
        WHERE c.isDeleted = 0
        GROUP BY c.id
        HAVING totalBills > 0
        $orderClause
        $limitClause
      ''', params);
    } catch (e) {
      debugPrint('❌ Error getting customer analysis: $e');
      return [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> getCustomerSegmentation({
    int championDays = 30,
    int championMinBills = 10,
    double championMinAmount = 50000,
    int loyalDays = 60,
    int loyalMinBills = 5,
    int potentialDays = 90,
    double potentialMinAmount = 20000,
    int newCustomerDays = 30,
    int newCustomerMaxBills = 3,
    int atRiskDays = 120,
    int atRiskMinBills = 5,
    int lostDays = 180,
    double cannotLoseMinAmount = 30000,
  }) async {
    try {
      final customers = await getCustomerAnalysis();

      final champions = <Map<String, dynamic>>[];
      final loyalCustomers = <Map<String, dynamic>>[];
      final potentialLoyalists = <Map<String, dynamic>>[];
      final newCustomers = <Map<String, dynamic>>[];
      final atRiskCustomers = <Map<String, dynamic>>[];
      final cannotLoseThem = <Map<String, dynamic>>[];
      final lostCustomers = <Map<String, dynamic>>[];

      for (final customer in customers) {
        final daysSinceLastPurchase = (customer['daysSinceLastPurchase'] as num?)?.toDouble() ?? 999.0;
        final totalBills = (customer['totalBills'] as num?)?.toInt() ?? 0;
        final totalPurchases = (customer['totalPurchases'] as num?)?.toDouble() ?? 0.0;

        final isChampion = daysSinceLastPurchase <= championDays.toDouble() &&
            totalBills >= championMinBills &&
            totalPurchases >= championMinAmount;

        final isLoyal = daysSinceLastPurchase <= loyalDays.toDouble() &&
            totalBills >= loyalMinBills;

        final isPotential = daysSinceLastPurchase <= potentialDays.toDouble() &&
            totalPurchases >= potentialMinAmount;

        final isNew = daysSinceLastPurchase <= newCustomerDays.toDouble() &&
            totalBills <= newCustomerMaxBills;

        final isAtRisk = daysSinceLastPurchase <= atRiskDays.toDouble() &&
            totalBills >= atRiskMinBills;

        final cannotLose = daysSinceLastPurchase <= lostDays.toDouble() &&
            totalPurchases >= cannotLoseMinAmount;

        if (isChampion) {
          champions.add(customer);
        } else if (isLoyal) {
          loyalCustomers.add(customer);
        } else if (isPotential) {
          potentialLoyalists.add(customer);
        } else if (isNew) {
          newCustomers.add(customer);
        } else if (isAtRisk) {
          atRiskCustomers.add(customer);
        } else if (cannotLose) {
          cannotLoseThem.add(customer);
        } else {
          lostCustomers.add(customer);
        }
      }

      return {
        'champions': champions,
        'loyalCustomers': loyalCustomers,
        'potentialLoyalists': potentialLoyalists,
        'newCustomers': newCustomers,
        'atRiskCustomers': atRiskCustomers,
        'cannotLoseThem': cannotLoseThem,
        'lostCustomers': lostCustomers,
      };
    } catch (e) {
      debugPrint('❌ Error getting customer segmentation: $e');
      return {
        'champions': [],
        'loyalCustomers': [],
        'potentialLoyalists': [],
        'newCustomers': [],
        'atRiskCustomers': [],
        'cannotLoseThem': [],
        'lostCustomers': [],
      };
    }
  }

  Future<Map<String, dynamic>> getProfitAnalysis({
    DateTime? startDate,
    DateTime? endDate,
    String groupBy = 'month',
  }) async {
    try {
      final db = await database;

      String dateFilter = '';
      List<String> params = [];

      if (startDate != null && endDate != null) {
        dateFilter = 'WHERE DATE(b.date) BETWEEN ? AND ?';
        params.addAll([
          startDate.toIso8601String().substring(0, 10),
          endDate.toIso8601String().substring(0, 10)
        ]);
      } else {
        dateFilter = 'WHERE 1=1';
      }

      String groupByClause = "strftime('%Y-%m', b.date)";
      switch (groupBy) {
        case 'day':
          groupByClause = "DATE(b.date)";
          break;
        case 'week':
          groupByClause = "strftime('%Y-%W', b.date)";
          break;
        case 'year':
          groupByClause = "strftime('%Y', b.date)";
          break;
      }

      final trends = await db.rawQuery('''
        SELECT 
          $groupByClause as period,
          COALESCE(SUM(bi.quantity * bi.price), 0) as sales,
          COALESCE(SUM(bi.quantity * p.costPrice), 0) as cost,
          (COALESCE(SUM(bi.quantity * bi.price), 0) - COALESCE(SUM(bi.quantity * p.costPrice), 0)) as profit,
          COUNT(DISTINCT b.id) as billCount
        FROM bills b
        JOIN bill_items bi ON bi.billId = b.id AND bi.isDeleted = 0
        JOIN products p ON p.id = bi.productId
        $dateFilter AND b.isDeleted = 0
        GROUP BY $groupByClause
        ORDER BY period
      ''', params);

      double totalSales = 0, totalCost = 0, totalProfit = 0;
      for (final row in trends) {
        totalSales += (row['sales'] as num?)?.toDouble() ?? 0;
        totalCost += (row['cost'] as num?)?.toDouble() ?? 0;
        totalProfit += (row['profit'] as num?)?.toDouble() ?? 0;
      }

      final avgMargin = totalSales > 0 ? (totalProfit / totalSales * 100) : 0;

      return {
        'trends': trends,
        'summary': {
          'totalSales': totalSales,
          'totalCost': totalCost,
          'totalProfit': totalProfit,
          'avgMarginPercent': avgMargin,
          'periods': trends.length,
        }
      };
    } catch (e) {
      debugPrint('❌ Error getting profit analysis: $e');
      return {
        'trends': [],
        'summary': {
          'totalSales': 0.0,
          'totalCost': 0.0,
          'totalProfit': 0.0,
          'avgMarginPercent': 0.0,
          'periods': 0,
        }
      };
    }
  }

  Future<List<Map<String, dynamic>>> getProductMarginAnalysis({
    DateTime? startDate,
    DateTime? endDate,
    double? minMarginPercent,
  }) async {
    try {
      final db = await database;

      String dateFilter = '';
      List<String> params = [];

      if (startDate != null && endDate != null) {
        dateFilter = 'AND DATE(b.date) BETWEEN ? AND ?';
        params.addAll([
          startDate.toIso8601String().substring(0, 10),
          endDate.toIso8601String().substring(0, 10)
        ]);
      }

      final results = await db.rawQuery('''
        SELECT 
          p.id as productId,
          p.name as productName,
          p.price as currentPrice,
          p.costPrice as currentCostPrice,
          COALESCE(SUM(bi.quantity), 0) as totalQuantity,
          COALESCE(SUM(bi.quantity * bi.price), 0) as totalSales,
          COALESCE(SUM(bi.quantity * p.costPrice), 0) as totalCost,
          (COALESCE(SUM(bi.quantity * bi.price), 0) - COALESCE(SUM(bi.quantity * p.costPrice), 0)) as totalProfit,
          COALESCE(AVG(bi.price), 0) as avgSellingPrice
        FROM products p
        LEFT JOIN bill_items bi ON bi.productId = p.id AND bi.isDeleted = 0
        LEFT JOIN bills b ON b.id = bi.billId AND b.isDeleted = 0 $dateFilter
        WHERE p.isDeleted = 0
        GROUP BY p.id
        HAVING totalQuantity > 0
        ORDER BY totalProfit DESC
      ''', params);

      final analysis = <Map<String, dynamic>>[];
      for (final row in results) {
        final sales = (row['totalSales'] as num?)?.toDouble() ?? 0;
        final cost = (row['totalCost'] as num?)?.toDouble() ?? 0;
        final profit = sales - cost;
        final marginPercent = sales > 0 ? (profit / sales * 100) : 0;

        final analysisRow = Map<String, dynamic>.from(row);
        analysisRow['marginPercent'] = marginPercent;
        final totalQty = (row['totalQuantity'] as num?)?.toDouble() ?? 0;
        analysisRow['profitPerUnit'] = totalQty > 0 ? profit / totalQty : 0;

        final shouldInclude = minMarginPercent == null || marginPercent >= minMarginPercent;
        if (shouldInclude) {
          analysis.add(analysisRow);
        }
      }

      return analysis;
    } catch (e) {
      debugPrint('❌ Error getting product margin analysis: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getStockAnalysis() async {
    try {
      final db = await database;

      final stockData = await db.rawQuery('''
        SELECT 
          p.id,
          p.name,
          p.stock,
          p.costPrice,
          p.price,
          (p.stock * p.costPrice) as stockValue,
          COALESCE(sales_7d.quantity, 0) as sold7Days,
          COALESCE(sales_30d.quantity, 0) as sold30Days,
          COALESCE(sales_7d.quantity, 0) / 7.0 as dailyAvgSales
        FROM products p
        LEFT JOIN (
          SELECT bi.productId, SUM(bi.quantity) as quantity
          FROM bill_items bi
          JOIN bills b ON b.id = bi.billId
          WHERE DATE(b.date) >= DATE('now', '-7 days') 
            AND b.isDeleted = 0 AND bi.isDeleted = 0
          GROUP BY bi.productId
        ) sales_7d ON sales_7d.productId = p.id
        LEFT JOIN (
          SELECT bi.productId, SUM(bi.quantity) as quantity
          FROM bill_items bi
          JOIN bills b ON b.id = bi.billId
          WHERE DATE(b.date) >= DATE('now', '-30 days') 
            AND b.isDeleted = 0 AND bi.isDeleted = 0
          GROUP BY bi.productId
        ) sales_30d ON sales_30d.productId = p.id
        WHERE p.isDeleted = 0
        ORDER BY stockValue DESC
      ''');

      double totalStockValue = 0;
      final fastMoving = <Map<String, dynamic>>[];
      final slowMoving = <Map<String, dynamic>>[];
      final deadStock = <Map<String, dynamic>>[];
      final overStocked = <Map<String, dynamic>>[];
      final underStocked = <Map<String, dynamic>>[];

      for (final product in stockData) {
        final stock = (product['stock'] as num?)?.toDouble() ?? 0;
        final stockValue = (product['stockValue'] as num?)?.toDouble() ?? 0;
        final dailyAvg = (product['dailyAvgSales'] as num?)?.toDouble() ?? 0;
        final sold7Days = (product['sold7Days'] as num?)?.toDouble() ?? 0;

        totalStockValue += stockValue;

        final daysOfStock = dailyAvg > 0 ? stock / dailyAvg : 999.0;

        final productData = Map<String, dynamic>.from(product);
        productData['daysOfStock'] = daysOfStock;
        final sold30Days = (product['sold30Days'] as num?)?.toDouble() ?? 0;
        productData['turnoverRate'] = stock > 0 ? sold30Days / stock : 0;

        final hasNoRecentSales = sold7Days == 0 && stock > 0;
        if (hasNoRecentSales) {
          deadStock.add(productData);
        } else if (dailyAvg > 0) {
          if (daysOfStock <= 3) {
            fastMoving.add(productData);
          } else if (daysOfStock > 14) {
            slowMoving.add(productData);
          }

          if (daysOfStock > 30) {
            overStocked.add(productData);
          } else if (daysOfStock < 2) {
            underStocked.add(productData);
          }
        }
      }

      return {
        'totalStockValue': totalStockValue,
        'totalProducts': stockData.length,
        'fastMoving': fastMoving,
        'slowMoving': slowMoving,
        'deadStock': deadStock,
        'overStocked': overStocked,
        'underStocked': underStocked,
        'allProducts': stockData,
      };
    } catch (e) {
      debugPrint('❌ Error getting stock analysis: $e');
      return {
        'totalStockValue': 0.0,
        'totalProducts': 0,
        'fastMoving': [],
        'slowMoving': [],
        'deadStock': [],
        'overStocked': [],
        'underStocked': [],
        'allProducts': [],
      };
    }
  }

  Future<List<Map<String, dynamic>>> getStockTurnoverAnalysis({int days = 30}) async {
    try {
      final db = await database;

      return await db.rawQuery('''
        SELECT 
          p.id,
          p.name,
          p.stock,
          p.costPrice,
          COALESCE(SUM(bi.quantity), 0) as soldQuantity,
          (p.stock * p.costPrice) as stockValue,
          CASE 
            WHEN p.stock > 0 THEN COALESCE(SUM(bi.quantity), 0) / p.stock
            ELSE 0 
          END as turnoverRatio,
          CASE 
            WHEN COALESCE(SUM(bi.quantity), 0) > 0 THEN ($days * p.stock) / COALESCE(SUM(bi.quantity), 0)
            ELSE 999 
          END as daysOfStock
        FROM products p
        LEFT JOIN bill_items bi ON bi.productId = p.id AND bi.isDeleted = 0
        LEFT JOIN bills b ON b.id = bi.billId 
          AND DATE(b.date) >= DATE('now', '-$days days') 
          AND b.isDeleted = 0
        WHERE p.isDeleted = 0
        GROUP BY p.id
        ORDER BY turnoverRatio DESC
      ''');
    } catch (e) {
      debugPrint('❌ Error getting stock turnover analysis: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getCollectionEfficiency({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final db = await database;

      String dateFilter = '';
      List<String> params = [];

      if (startDate != null && endDate != null) {
        dateFilter = 'AND DATE(l.date) BETWEEN ? AND ?';
        params.addAll([
          startDate.toIso8601String().substring(0, 10),
          endDate.toIso8601String().substring(0, 10)
        ]);
      }

      final result = await db.rawQuery('''
        SELECT 
          COALESCE(SUM(CASE WHEN l.type = 'bill' THEN l.amount ELSE 0 END), 0) as totalBilled,
          COALESCE(SUM(CASE WHEN l.type = 'payment' THEN l.amount ELSE 0 END), 0) as totalCollected,
          COUNT(CASE WHEN l.type = 'bill' THEN 1 END) as billCount,
          COUNT(CASE WHEN l.type = 'payment' THEN 1 END) as paymentCount
        FROM ledger l
        WHERE l.isDeleted = 0 $dateFilter
      ''', params);

      final data = result.isNotEmpty ? result.first : <String, dynamic>{};
      final totalBilled = (data['totalBilled'] as num?)?.toDouble() ?? 0;
      final totalCollected = (data['totalCollected'] as num?)?.toDouble() ?? 0;
      final collectionRate = totalBilled > 0 ? (totalCollected / totalBilled * 100) : 0;
      final billCount = (data['billCount'] as int?) ?? 0;
      final paymentCount = (data['paymentCount'] as int?) ?? 0;

      return {
        'totalBilled': totalBilled,
        'totalCollected': totalCollected,
        'collectionRate': collectionRate,
        'billCount': billCount,
        'paymentCount': paymentCount,
        'averageBillValue': billCount > 0 ? totalBilled / billCount : 0,
        'averagePaymentValue': paymentCount > 0 ? totalCollected / paymentCount : 0,
      };
    } catch (e) {
      debugPrint('❌ Error getting collection efficiency: $e');
      return {
        'totalBilled': 0.0,
        'totalCollected': 0.0,
        'collectionRate': 0.0,
        'billCount': 0,
        'paymentCount': 0,
        'averageBillValue': 0.0,
        'averagePaymentValue': 0.0,
      };
    }
  }

  Future<List<Map<String, dynamic>>> getPaymentPatterns() async {
    try {
      final db = await database;

      return await db.rawQuery('''
        SELECT 
          c.id as clientId,
          c.name as clientName,
          COUNT(DISTINCT b.id) as totalBills,
          COUNT(DISTINCT CASE WHEN l.type = 'payment' THEN l.id END) as totalPayments,
          COALESCE(SUM(CASE WHEN l.type = 'bill' THEN l.amount ELSE 0 END), 0) as totalBilled,
          COALESCE(SUM(CASE WHEN l.type = 'payment' THEN l.amount ELSE 0 END), 0) as totalPaid,
          COALESCE(AVG(CASE WHEN l.type = 'payment' THEN 
            julianday(l.date) - julianday(b.date) 
          END), 0) as avgPaymentDelayDays,
          MAX(DATE(CASE WHEN l.type = 'bill' THEN l.date END)) as lastBillDate,
          MAX(DATE(CASE WHEN l.type = 'payment' THEN l.date END)) as lastPaymentDate
        FROM clients c
        LEFT JOIN bills b ON b.clientId = c.id AND b.isDeleted = 0
        LEFT JOIN ledger l ON l.clientId = c.id AND l.isDeleted = 0
        WHERE c.isDeleted = 0
        GROUP BY c.id
        HAVING totalBills > 0
        ORDER BY avgPaymentDelayDays DESC
      ''');
    } catch (e) {
      debugPrint('❌ Error getting payment patterns: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getBusinessInsights({DateTime? asOfDate}) async {
    try {
      final targetDate = asOfDate ?? DateTime.now();
      final last30Days = targetDate.subtract(const Duration(days: 30));
      final last60Days = targetDate.subtract(const Duration(days: 60));

      final current30 = await getDailySales(last30Days, targetDate);
      final previous30 = await getDailySales(last60Days, last30Days);

      final currentSales = current30.fold<double>(0, (sum, day) => sum + ((day['totalSales'] as num?)?.toDouble() ?? 0));
      final previousSales = previous30.fold<double>(0, (sum, day) => sum + ((day['totalSales'] as num?)?.toDouble() ?? 0));

      final salesGrowth = previousSales > 0 ? ((currentSales - previousSales) / previousSales * 100) : 0;

      final customerAnalysis = await getCustomerAnalysis(startDate: last30Days, endDate: targetDate, limit: 100);
      final totalCustomers = customerAnalysis.length;
      final avgCustomerValue = totalCustomers > 0
          ? customerAnalysis.fold<double>(0, (sum, c) => sum + ((c['totalPurchases'] as num?)?.toDouble() ?? 0)) / totalCustomers
          : 0;

      final profitAnalysis = await getProfitAnalysis(startDate: last30Days, endDate: targetDate);
      final profitMargin = (profitAnalysis['summary'] as Map<String, dynamic>)['avgMarginPercent'] as double;

      final topProducts = await getTopProducts(startDate: last30Days, endDate: targetDate, limit: 5);

      return {
        'salesGrowth': salesGrowth,
        'currentSales': currentSales,
        'previousSales': previousSales,
        'totalCustomers': totalCustomers,
        'avgCustomerValue': avgCustomerValue,
        'profitMargin': profitMargin,
        'topProducts': topProducts,
        'generatedAt': targetDate.toIso8601String(),
      };
    } catch (e) {
      debugPrint('❌ Error getting business insights: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getSeasonalTrends({int years = 2}) async {
    try {
      final db = await database;

      return await db.rawQuery('''
        SELECT 
          strftime('%m', b.date) as month,
          strftime('%Y', b.date) as year,
          COALESCE(SUM(b.totalAmount), 0) as sales,
          COUNT(DISTINCT b.id) as billCount,
          COUNT(DISTINCT b.clientId) as uniqueCustomers
        FROM bills b
        WHERE b.isDeleted = 0 
          AND DATE(b.date) >= DATE('now', '-$years years')
        GROUP BY strftime('%Y', b.date), strftime('%m', b.date)
        ORDER BY year, month
      ''');
    } catch (e) {
      debugPrint('❌ Error getting seasonal trends: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> calculateCustomerLTV(int clientId) async {
    try {
      final db = await database;

      final result = await db.rawQuery('''
        SELECT 
          MIN(DATE(b.date)) as firstPurchase,
          MAX(DATE(b.date)) as lastPurchase,
          COUNT(DISTINCT b.id) as totalOrders,
          COALESCE(SUM(b.totalAmount), 0) as totalSpent,
          COALESCE(AVG(b.totalAmount), 0) as avgOrderValue
        FROM bills b
        WHERE b.clientId = ? AND b.isDeleted = 0
      ''', [clientId]);

      if (result.isEmpty) return {};

      final data = result.first;
      final firstPurchaseStr = data['firstPurchase'] as String?;
      final lastPurchaseStr = data['lastPurchase'] as String?;

      if (firstPurchaseStr == null || lastPurchaseStr == null) return {};

      final firstPurchase = DateTime.parse(firstPurchaseStr);
      final lastPurchase = DateTime.parse(lastPurchaseStr);
      final daysBetween = lastPurchase.difference(firstPurchase).inDays;
      final totalOrders = (data['totalOrders'] as int?) ?? 0;
      final totalSpent = (data['totalSpent'] as num?)?.toDouble() ?? 0;
      final avgOrderValue = (data['avgOrderValue'] as num?)?.toDouble() ?? 0;

      final purchaseFrequency = daysBetween > 0 ? totalOrders / (daysBetween / 30.0) : 0;
      final estimatedLTV = avgOrderValue * purchaseFrequency * 12;

      return {
        'clientId': clientId,
        'firstPurchase': firstPurchase.toIso8601String(),
        'lastPurchase': lastPurchase.toIso8601String(),
        'totalOrders': totalOrders,
        'totalSpent': totalSpent,
        'avgOrderValue': avgOrderValue,
        'purchaseFrequencyPerMonth': purchaseFrequency,
        'estimatedAnnualLTV': estimatedLTV,
        'customerAge': daysBetween,
      };
    } catch (e) {
      debugPrint('❌ Error calculating customer LTV: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getDataForExport(
      String reportType, {
        DateTime? startDate,
        DateTime? endDate,
        Map<String, dynamic>? filters,
      }) async {
    try {
      switch (reportType) {
        case 'sales_summary':
          if (startDate != null && endDate != null) {
            return await getDailySales(startDate, endDate);
          }
          return [];

        case 'product_performance':
          return await getProductSalesReport(startDate: startDate, endDate: endDate);

        case 'customer_analysis':
          return await getCustomerAnalysis(startDate: startDate, endDate: endDate);

        case 'profit_analysis':
          final profitData = await getProfitAnalysis(startDate: startDate, endDate: endDate);
          return profitData['trends'] as List<Map<String, dynamic>>;

        case 'stock_analysis':
          final stockData = await getStockAnalysis();
          return stockData['allProducts'] as List<Map<String, dynamic>>;

        default:
          return [];
      }
    } catch (e) {
      debugPrint('❌ Error getting data for export: $e');
      return [];
    }
  }

  // ========================================================================
  // DASHBOARD QUICK STATS
  // ========================================================================

  Future<int> getTodayBillsCount(DateTime start, DateTime end) async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT COUNT(*) as count FROM bills 
        WHERE date >= ? AND date < ? AND isDeleted = 0
      ''', [start.toIso8601String(), end.toIso8601String()]);

      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      debugPrint('❌ Error getting today bills count: $e');
      return 0;
    }
  }

  Future<double> getTodayRevenue(DateTime start, DateTime end) async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(totalAmount), 0) as total FROM bills 
        WHERE date >= ? AND date < ? AND isDeleted = 0
      ''', [start.toIso8601String(), end.toIso8601String()]);

      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      debugPrint('❌ Error getting today revenue: $e');
      return 0.0;
    }
  }

  Future<int> getPendingOrdersCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT COUNT(*) as count FROM demand_batch 
        WHERE closed = 0 AND isDeleted = 0
      ''');

      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      debugPrint('❌ Error getting pending orders count: $e');
      return 0;
    }
  }

  Future<int> getLowStockCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT COUNT(*) as count FROM products 
        WHERE stock < ? AND stock > 0 AND isDeleted = 0
      ''', [LOW_STOCK_THRESHOLD]);

      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      debugPrint('❌ Error getting low stock count: $e');
      return 0;
    }
  }

  Future<String?> getTopSellingProduct() async {
    try {
      final db = await database;
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);

      final result = await db.rawQuery('''
        SELECT p.name, SUM(bi.quantity) as totalSold
        FROM bill_items bi
        JOIN products p ON bi.productId = p.id
        JOIN bills b ON bi.billId = b.id
        WHERE b.date >= ? AND b.isDeleted = 0 AND bi.isDeleted = 0
        GROUP BY p.id, p.name
        ORDER BY totalSold DESC
        LIMIT 1
      ''', [monthStart.toIso8601String()]);

      if (result.isNotEmpty) {
        return result.first['name'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting top selling product: $e');
      return null;
    }
  }

  Future<double> getMonthRevenue(DateTime start, DateTime end) async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(totalAmount), 0) as total FROM bills 
        WHERE date >= ? AND date < ? AND isDeleted = 0
      ''', [start.toIso8601String(), end.toIso8601String()]);

      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      debugPrint('❌ Error getting month revenue: $e');
      return 0.0;
    }
  }

  Future<Map<String, dynamic>> getQuickInsights() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 1);

      final results = await Future.wait([
        getTodayBillsCount(todayStart, todayEnd),
        getTodayRevenue(todayStart, todayEnd),
        getPendingOrdersCount(),
        getLowStockCount(),
        getTopSellingProduct(),
        getMonthRevenue(monthStart, monthEnd),
      ]);

      return {
        'todayBills': results[0],
        'todayRevenue': results[1],
        'pendingOrders': results[2],
        'lowStock': results[3],
        'topProduct': results[4] ?? 'No sales yet',
        'monthRevenue': results[5],
      };
    } catch (e) {
      debugPrint('❌ Error getting quick insights: $e');
      return {
        'todayBills': 0,
        'todayRevenue': 0.0,
        'pendingOrders': 0,
        'lowStock': 0,
        'topProduct': 'No sales yet',
        'monthRevenue': 0.0,
      };
    }
  }

  Future<List<Map<String, dynamic>>> getRecentActivity({int limit = 10}) async {
    try {
      final db = await database;

      // Get recent bills
      final recentBills = await db.rawQuery('''
        SELECT 
          'bill' as type,
          b.id,
          b.date,
          b.totalAmount as amount,
          c.name as clientName,
          'New Bill' as description
        FROM bills b
        LEFT JOIN clients c ON b.clientId = c.id
        WHERE b.isDeleted = 0
        ORDER BY b.date DESC
        LIMIT ?
      ''', [limit ~/ 2]);

      // Get recent payments
      final recentPayments = await db.rawQuery('''
        SELECT 
          'payment' as type,
          l.id,
          l.date,
          l.amount,
          c.name as clientName,
          COALESCE(l.note, 'Payment Received') as description
        FROM ledger l
        LEFT JOIN clients c ON l.clientId = c.id
        WHERE l.type = 'payment' AND l.isDeleted = 0
        ORDER BY l.date DESC
        LIMIT ?
      ''', [limit ~/ 2]);

      // Combine and sort by date
      final allActivity = [...recentBills, ...recentPayments];
      allActivity.sort((a, b) {
        final dateA = DateTime.parse(a['date'] as String);
        final dateB = DateTime.parse(b['date'] as String);
        return dateB.compareTo(dateA);
      });

      return allActivity.take(limit).toList();
    } catch (e) {
      debugPrint('❌ Error getting recent activity: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getWeekComparison() async {
    try {
      final now = DateTime.now();
      final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));
      final thisWeekEnd = thisWeekStart.add(const Duration(days: 7));
      final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
      final lastWeekEnd = thisWeekStart;

      final thisWeekRevenue = await getTodayRevenue(thisWeekStart, thisWeekEnd);
      final lastWeekRevenue = await getTodayRevenue(lastWeekStart, lastWeekEnd);

      final thisWeekBills = await getTodayBillsCount(thisWeekStart, thisWeekEnd);
      final lastWeekBills = await getTodayBillsCount(lastWeekStart, lastWeekEnd);

      final revenueGrowth = lastWeekRevenue > 0
          ? ((thisWeekRevenue - lastWeekRevenue) / lastWeekRevenue * 100)
          : 0.0;

      final billsGrowth = lastWeekBills > 0
          ? ((thisWeekBills - lastWeekBills) / lastWeekBills * 100)
          : 0.0;

      return {
        'thisWeek': {
          'revenue': thisWeekRevenue,
          'bills': thisWeekBills,
        },
        'lastWeek': {
          'revenue': lastWeekRevenue,
          'bills': lastWeekBills,
        },
        'growth': {
          'revenue': revenueGrowth,
          'bills': billsGrowth,
        },
      };
    } catch (e) {
      debugPrint('❌ Error getting week comparison: $e');
      return {
        'thisWeek': {'revenue': 0.0, 'bills': 0},
        'lastWeek': {'revenue': 0.0, 'bills': 0},
        'growth': {'revenue': 0.0, 'bills': 0.0},
      };
    }
  }

  Future<List<Map<String, dynamic>>> getDashboardAlerts() async {
    try {
      final alerts = <Map<String, dynamic>>[];

      final db = await database;

      // Check for low stock items
      final lowStockProducts = await db.rawQuery('''
        SELECT name, stock FROM products 
        WHERE stock < ? AND stock > 0 AND isDeleted = 0
        ORDER BY stock ASC
        LIMIT 5
      ''', [LOW_STOCK_THRESHOLD]);

      for (final product in lowStockProducts) {
        alerts.add({
          'type': 'low_stock',
          'severity': 'warning',
          'title': 'Low Stock Alert',
          'message': '${product['name']} has only ${product['stock']} units left',
          'icon': 'warning',
          'color': 'orange',
        });
      }

      // Check for out of stock items
      final outOfStock = await db.rawQuery('''
        SELECT COUNT(*) as count FROM products 
        WHERE stock <= 0 AND isDeleted = 0
      ''');

      final outOfStockCount = (outOfStock.first['count'] as int?) ?? 0;
      if (outOfStockCount > 0) {
        alerts.add({
          'type': 'out_of_stock',
          'severity': 'error',
          'title': 'Out of Stock',
          'message': '$outOfStockCount products are out of stock',
          'icon': 'error',
          'color': 'red',
        });
      }

      // Check for pending demands
      final pendingDemands = await db.rawQuery('''
        SELECT COUNT(*) as count FROM demand_batch 
        WHERE closed = 0 AND isDeleted = 0
      ''');

      final pendingCount = (pendingDemands.first['count'] as int?) ?? 0;
      if (pendingCount > 0) {
        alerts.add({
          'type': 'pending_demands',
          'severity': 'info',
          'title': 'Pending Orders',
          'message': 'You have $pendingCount pending demand batches',
          'icon': 'pending',
          'color': 'blue',
        });
      }

      // Check for large outstanding balances
      final outstandingBalances = await getOutstandingBalances();
      if (outstandingBalances.isNotEmpty) {
        final totalOutstanding = outstandingBalances.fold<double>(
          0,
              (sum, client) => sum + ((client['balance'] as num?)?.toDouble() ?? 0),
        );

        if (totalOutstanding > 10000) {
          alerts.add({
            'type': 'outstanding_payment',
            'severity': 'warning',
            'title': 'Outstanding Payments',
            'message': 'Total outstanding: ₹${totalOutstanding.toStringAsFixed(2)}',
            'icon': 'payment',
            'color': 'orange',
          });
        }
      }

      return alerts;
    } catch (e) {
      debugPrint('❌ Error getting dashboard alerts: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getProductPerformance({int days = 7}) async {
    try {
      final db = await database;
      final startDate = DateTime.now().subtract(Duration(days: days));

      return await db.rawQuery('''
        SELECT 
          p.id,
          p.name,
          p.stock,
          COALESCE(SUM(bi.quantity), 0) as soldQuantity,
          COALESCE(SUM(bi.quantity * bi.price), 0) as revenue,
          COUNT(DISTINCT b.id) as billCount
        FROM products p
        LEFT JOIN bill_items bi ON bi.productId = p.id AND bi.isDeleted = 0
        LEFT JOIN bills b ON b.id = bi.billId 
          AND b.date >= ? AND b.isDeleted = 0
        WHERE p.isDeleted = 0
        GROUP BY p.id, p.name, p.stock
        ORDER BY revenue DESC
        LIMIT 10
      ''', [startDate.toIso8601String()]);
    } catch (e) {
      debugPrint('❌ Error getting product performance: $e');
      return [];
    }
  }

  Future<void> addStockLimitColumns() async {
    try {
      final db = await database;

      final tableInfo = await db.rawQuery('PRAGMA table_info(products)');
      final hasMinStock = tableInfo.any((col) => col['name'] == 'minStock');
      final hasMaxStock = tableInfo.any((col) => col['name'] == 'maxStock');

      if (!hasMinStock) {
        await db.execute('ALTER TABLE products ADD COLUMN minStock REAL DEFAULT 10');
        debugPrint('✅ minStock column added to products table');
      }

      if (!hasMaxStock) {
        await db.execute('ALTER TABLE products ADD COLUMN maxStock REAL DEFAULT 100');
        debugPrint('✅ maxStock column added to products table');
      }
    } catch (e) {
      debugPrint('❌ Error adding stock limit columns: $e');
    }
  }

  Future<Map<String, dynamic>> getInventoryStatus() async {
    try {
      final db = await database;

      final result = await db.rawQuery('''
        SELECT 
          COUNT(CASE WHEN stock <= 0 THEN 1 END) as outOfStock,
          COUNT(CASE WHEN stock > 0 AND stock < ? THEN 1 END) as lowStock,
          COUNT(CASE WHEN stock >= ? AND stock < 50 THEN 1 END) as normalStock,
          COUNT(CASE WHEN stock >= 50 THEN 1 END) as highStock,
          SUM(stock * price) as totalInventoryValue
        FROM products
        WHERE isDeleted = 0
      ''', [LOW_STOCK_THRESHOLD, LOW_STOCK_THRESHOLD]);

      if (result.isEmpty) {
        return {
          'outOfStock': 0,
          'lowStock': 0,
          'normalStock': 0,
          'highStock': 0,
          'totalValue': 0.0,
        };
      }

      return {
        'outOfStock': (result.first['outOfStock'] as int?) ?? 0,
        'lowStock': (result.first['lowStock'] as int?) ?? 0,
        'normalStock': (result.first['normalStock'] as int?) ?? 0,
        'highStock': (result.first['highStock'] as int?) ?? 0,
        'totalValue': (result.first['totalInventoryValue'] as num?)?.toDouble() ?? 0.0,
      };
    } catch (e) {
      debugPrint('❌ Error getting inventory status: $e');
      return {
        'outOfStock': 0,
        'lowStock': 0,
        'normalStock': 0,
        'highStock': 0,
        'totalValue': 0.0,
      };
    }
  }
}