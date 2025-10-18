// lib/services/database_helper.dart - v5.2 (COMPLETE & CORRECTED)

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

  static const int DATABASE_VERSION = 28;
  static const String DATABASE_NAME = 'dairy_manager_v6.db';

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), DATABASE_NAME);
    debugPrint('Database path: $path');
    return openDatabase(
      path,
      version: DATABASE_VERSION,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        debugPrint('✅ Foreign keys enabled');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('🔨 Creating new database schema v$version...');

    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE clients (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, phone TEXT, address TEXT,
          createdAt TEXT, updatedAt TEXT, firestoreId TEXT UNIQUE,
          isDeleted INTEGER DEFAULT 0, isSynced INTEGER DEFAULT 0
        )
      ''');
      await txn.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, weight REAL, price REAL,
          costPrice REAL DEFAULT 0, stock REAL DEFAULT 0, createdAt TEXT, updatedAt TEXT,
          firestoreId TEXT UNIQUE, isDeleted INTEGER DEFAULT 0, isSynced INTEGER DEFAULT 0
        )
      ''');
      await txn.execute('''
        CREATE TABLE bills (
          id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, clientId INTEGER,
          totalAmount REAL, paidAmount REAL, carryForward REAL, discount REAL DEFAULT 0, tax REAL DEFAULT 0,
          date TEXT, dueDate TEXT, paymentStatus TEXT DEFAULT 'pending', notes TEXT,
          createdAt TEXT, updatedAt TEXT, isSynced INTEGER DEFAULT 0, isDeleted INTEGER DEFAULT 0,
          FOREIGN KEY(clientId) REFERENCES clients(id)
        )
      ''');
      await txn.execute('''
        CREATE TABLE bill_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, billId INTEGER, productId INTEGER,
          quantity REAL, price REAL, discount REAL DEFAULT 0, tax REAL DEFAULT 0,
          createdAt TEXT, updatedAt TEXT, isSynced INTEGER DEFAULT 0, isDeleted INTEGER DEFAULT 0,
          FOREIGN KEY(billId) REFERENCES bills(id), FOREIGN KEY(productId) REFERENCES products(id)
        )
      ''');
      await txn.execute('''
        CREATE TABLE ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT, clientId INTEGER NOT NULL, firestoreId TEXT UNIQUE,
          billId INTEGER, type TEXT NOT NULL, amount REAL NOT NULL, date TEXT NOT NULL,
          note TEXT, paymentMethod TEXT, referenceNumber TEXT, createdAt TEXT, updatedAt TEXT,
          isSynced INTEGER DEFAULT 0, isDeleted INTEGER DEFAULT 0,
          FOREIGN KEY(clientId) REFERENCES clients(id), FOREIGN KEY(billId) REFERENCES bills(id)
        )
      ''');
      await txn.execute('''
        CREATE TABLE demand_batch (
          id INTEGER PRIMARY KEY AUTOINCREMENT, demandDate TEXT NOT NULL, closed INTEGER NOT NULL DEFAULT 0,
          updatedAt TEXT, createdAt TEXT, firestoreId TEXT UNIQUE,
          isSynced INTEGER DEFAULT 0, isDeleted INTEGER DEFAULT 0
        )
      ''');
      await txn.execute('''
        CREATE TABLE demand (
          id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, batchId INTEGER, clientId INTEGER,
          productId INTEGER, quantity REAL, date TEXT, createdAt TEXT, updatedAt TEXT,
          isSynced INTEGER DEFAULT 0, isDeleted INTEGER DEFAULT 0,
          FOREIGN KEY(batchId) REFERENCES demand_batch(id),
          FOREIGN KEY(clientId) REFERENCES clients(id),
          FOREIGN KEY(productId) REFERENCES products(id)
        )
      ''');
      await txn.execute('''
        CREATE TABLE purchases (
          id INTEGER PRIMARY KEY AUTOINCREMENT, productId INTEGER NOT NULL, quantity REAL NOT NULL,
          costPrice REAL NOT NULL, purchaseDate TEXT NOT NULL, supplier TEXT, notes TEXT, createdAt TEXT,
          isSynced INTEGER DEFAULT 0, isDeleted INTEGER DEFAULT 0,
          FOREIGN KEY(productId) REFERENCES products(id) ON DELETE CASCADE
        )
      ''');
    });

    debugPrint('✅ Database schema v$version created successfully.');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('🔄 Upgrading database from v$oldVersion to v$newVersion...');

    if (oldVersion < 27) {
      await _runV27Migration(db);
    }
    if (oldVersion < 28) {
      await _runV28Migration(db);
    }
  }

  Future<void> _runV27Migration(Database db) async {
    debugPrint('🚀 Applying migration for v27...');
    await _addColumnIfNotExists(db, 'bills', 'discount', 'REAL DEFAULT 0');
    await _addColumnIfNotExists(db, 'bills', 'tax', 'REAL DEFAULT 0');
    await _addColumnIfNotExists(db, 'bills', 'dueDate', 'TEXT');
    await _addColumnIfNotExists(db, 'bills', 'paymentStatus', 'TEXT DEFAULT \'pending\'');
    await _addColumnIfNotExists(db, 'bills', 'notes', 'TEXT');
    await _addColumnIfNotExists(db, 'bills', 'createdAt', 'TEXT');
    await _addColumnIfNotExists(db, 'bill_items', 'discount', 'REAL DEFAULT 0');
    await _addColumnIfNotExists(db, 'bill_items', 'tax', 'REAL DEFAULT 0');
    await _addColumnIfNotExists(db, 'bill_items', 'createdAt', 'TEXT');
    await _addColumnIfNotExists(db, 'ledger', 'paymentMethod', 'TEXT');
    await _addColumnIfNotExists(db, 'ledger', 'referenceNumber', 'TEXT');
    await _addColumnIfNotExists(db, 'ledger', 'createdAt', 'TEXT');
    await _addColumnIfNotExists(db, 'clients', 'createdAt', 'TEXT');
    await _addColumnIfNotExists(db, 'products', 'createdAt', 'TEXT');
    await _addColumnIfNotExists(db, 'demand_batch', 'createdAt', 'TEXT');
    await _addColumnIfNotExists(db, 'demand', 'createdAt', 'TEXT');
    debugPrint('✅ Migration to v27 completed.');
  }

  Future<void> _runV28Migration(Database db) async {
    debugPrint('🚀 Applying migration for v28...');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT, productId INTEGER NOT NULL, quantity REAL NOT NULL,
        costPrice REAL NOT NULL, purchaseDate TEXT NOT NULL, supplier TEXT, notes TEXT, createdAt TEXT,
        isSynced INTEGER DEFAULT 0, isDeleted INTEGER DEFAULT 0,
        FOREIGN KEY(productId) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    debugPrint('✅ Migration to v28 completed (added purchases table).');
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

  // ========================================================================
  // ✅ ADDED BACK: ESSENTIAL UTILITY METHODS
  // ========================================================================

  Future<List<Map<String, dynamic>>> getUnsynced(String table) async {
    final db = await database;
    return db.query(
      table,
      where: '(isSynced = 0 OR isSynced IS NULL) AND isDeleted = 0',
    );
  }

  Future<String?> getFirestoreId(String table, int localId) async {
    final db = await database;
    final rows = await db.query(table, columns: ['firestoreId'], where: 'id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['firestoreId'] as String?;
  }
  // ========================================================================
  // CLIENTS
  // ========================================================================

  Future<List<Client>> getClients() async {
    final db = await database;
    final rows = await db.query(
      'clients',
      where: 'isDeleted = 0',
      orderBy: 'name ASC',
    );
    return rows.map((m) => Client.fromMap(m)).toList();
  }

  Future<Client?> getClientById(int id) async {
    final db = await database;
    final rows = await db.query(
      'clients',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Client.fromMap(rows.first);
  }

  Future<List<Client>> searchClients(String query) async {
    final db = await database;
    final rows = await db.query(
      'clients',
      where: '(name LIKE ? OR phone LIKE ?) AND isDeleted = 0',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name ASC',
    );
    return rows.map((m) => Client.fromMap(m)).toList();
  }

  Future<int> insertPurchase(Map<String, dynamic> data) async {
    final db = await database;
    // Atomically update stock and add purchase record
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE products SET stock = stock + ?, costPrice = ?, updatedAt = ?, isSynced = 0 WHERE id = ?',
        [data['quantity'], data['costPrice'], DateTime.now().toIso8601String(), data['productId']],
      );
      await txn.insert('purchases', data);
    });
    return 1; // Return 1 for success, or handle ID if needed
  }

  Future<List<Map<String, dynamic>>> getPurchaseHistory({required DateTime startDate, required DateTime endDate}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT p.*, prod.name as productName 
      FROM purchases p
      JOIN products prod ON p.productId = prod.id
      WHERE DATE(p.purchaseDate) BETWEEN ? AND ?
      ORDER BY p.purchaseDate DESC
    ''', [startDate.toIso8601String().substring(0,10), endDate.toIso8601String().substring(0,10)]);
  }

  Future<int> getClientsCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM clients WHERE isDeleted = 0',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> insertClient(Client c) async {
    final db = await database;
    final updatedClient = c.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    final id = await db.insert(
      'clients',
      updatedClient.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('✅ Client inserted locally: ${c.name} (ID: $id)');
    return id;
  }

  Future<int> updateClient(Client c) async {
    final db = await database;
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

    debugPrint('✅ Client updated locally: ${c.name}');
    return result;
  }

  Future<int> deleteClient(int id) async {
    final db = await database;

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

    debugPrint('✅ Client soft-deleted locally (ID: $id)');
    return result;
  }

  Future<int> updateClientWithModel(Client client) async {
    return await updateClient(client);
  }

  Future<int> insertClientMap(Map<String, dynamic> map) async {
    final client = Client.fromMap(map);
    return await insertClient(client);
  }

  // ========================================================================
  // PRODUCTS
  // ========================================================================

  /// ✅ FIXED: Properly handles null values from database
  Future<List<Product>> getProducts() async {
    final db = await database;

    final rows = await db.rawQuery('''
      SELECT p.*, 
             IFNULL(COUNT(DISTINCT bi.billId), 0) AS usageCount
      FROM products p
      LEFT JOIN bill_items bi 
        ON p.id = bi.productId AND bi.isDeleted = 0
      WHERE p.isDeleted = 0
      GROUP BY p.id
      ORDER BY usageCount DESC, LOWER(p.name) ASC
    ''');

    return rows.map((m) {
      final safeMap = Map<String, dynamic>.from(m);
      // Only set defaults if values are actually null
      if (safeMap['stock'] == null) safeMap['stock'] = 0.0;
      if (safeMap['costPrice'] == null) safeMap['costPrice'] = 0.0;
      if (safeMap['usageCount'] == null) safeMap['usageCount'] = 0;
      if (safeMap['isSynced'] == null) safeMap['isSynced'] = 0;
      return Product.fromMap(safeMap);
    }).toList();
  }

  Future<Product?> getProductById(int id) async {
    final db = await database;
    final rows = await db.query(
      'products',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final safeRow = Map<String, dynamic>.from(rows.first);
    if (safeRow['stock'] == null) safeRow['stock'] = 0.0;
    if (safeRow['costPrice'] == null) safeRow['costPrice'] = 0.0;
    if (safeRow['usageCount'] == null) safeRow['usageCount'] = 0;

    return Product.fromMap(safeRow);
  }

  Future<List<Product>> searchProducts(String query) async {
    final db = await database;

    final rows = await db.rawQuery('''
      SELECT p.*, 
             IFNULL(COUNT(DISTINCT bi.billId), 0) AS usageCount
      FROM products p
      LEFT JOIN bill_items bi 
        ON p.id = bi.productId AND bi.isDeleted = 0
      WHERE p.isDeleted = 0 AND p.name LIKE ?
      GROUP BY p.id
      ORDER BY usageCount DESC, LOWER(p.name) ASC
    ''', ['%$query%']);

    return rows.map((m) {
      final safeMap = Map<String, dynamic>.from(m);
      if (safeMap['stock'] == null) safeMap['stock'] = 0.0;
      if (safeMap['costPrice'] == null) safeMap['costPrice'] = 0.0;
      if (safeMap['usageCount'] == null) safeMap['usageCount'] = 0;
      if (safeMap['isSynced'] == null) safeMap['isSynced'] = 0;
      return Product.fromMap(safeMap);
    }).toList();
  }

  Future<int> getProductsCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE isDeleted = 0',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> insertProduct(Product p) async {
    final db = await database;
    final updatedProduct = p.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    final id = await db.insert(
      'products',
      updatedProduct.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('✅ Product inserted locally: ${p.name} (ID: $id)');
    return id;
  }

  Future<int> updateProduct(Product p) async {
    final db = await database;
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

    debugPrint('✅ Product updated locally: ${p.name}');
    return result;
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;

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

    debugPrint('✅ Product soft-deleted locally (ID: $id)');
    return result;
  }

  Future<int> insertProductMap(Map<String, dynamic> map) async {
    final product = Product.fromMap(map);
    return await insertProduct(product);
  }

  Future<void> saveProductsToLocal(List<Product> products) async {
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
  }

  // ========================================================================
  // BILLS
  // ========================================================================

  Future<List<Bill>> getAllBills() async {
    final db = await database;
    final rows = await db.query(
      'bills',
      where: 'isDeleted = 0',
      orderBy: 'date DESC',
    );
    return rows.map((r) => Bill.fromMap(r)).toList();
  }

  Future<List<Map<String, dynamic>>> getBills() async {
    final db = await database;
    return db.query(
      'bills',
      where: 'isDeleted = 0',
      orderBy: 'date DESC',
    );
  }

  Future<Bill?> getBillById(int billId) async {
    final db = await database;
    final rows = await db.query(
      'bills',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [billId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Bill.fromMap(rows.first);
  }

  Future<List<Bill>> getBillsByClient(int clientId) async {
    final db = await database;
    final rows = await db.query(
      'bills',
      where: 'clientId = ? AND isDeleted = 0',
      whereArgs: [clientId],
      orderBy: 'date DESC',
    );
    return rows.map((r) => Bill.fromMap(r)).toList();
  }

  Future<int> getBillsCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM bills WHERE isDeleted = 0',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<double> getTotalBillsAmount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(totalAmount) as total FROM bills WHERE isDeleted = 0',
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getLastCarryForward(int clientId) async {
    final db = await database;
    final rows = await db.query(
      'bills',
      where: 'clientId = ? AND isDeleted = 0',
      whereArgs: [clientId],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final v = rows.first['carryForward'];
      if (v != null) {
        if (v is int) return v.toDouble();
        if (v is double) return v;
      }
    }
    return 0.0;
  }

  Future<int> insertBill(Bill bill) async {
    final db = await database;
    final updatedBill = bill.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(),
    );

    final id = await db.insert('bills', updatedBill.toMap());

    debugPrint('✅ Bill inserted locally (ID: $id)');
    return id;
  }

  Future<int> insertBillWithItems(Bill bill, List<BillItem> items) async {
    final db = await database;

    return await db.transaction<int>((txn) async {
      final billId = await txn.insert(
        'bills',
        bill.copyWith(isSynced: false, updatedAt: DateTime.now()).toMap(),
      );
      debugPrint('✅ Bill created with ID: $billId');

      await txn.insert(
        'ledger',
        {
          'clientId': bill.clientId,
          'billId': billId,
          'type': 'bill',
          'amount': bill.totalAmount,
          'date': bill.date.toIso8601String(),
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
      debugPrint('✅ Ledger entry created for bill $billId');

      for (var item in items) {
        final itemMap = item.copyWith(
          billId: billId,
          isSynced: false,
          updatedAt: DateTime.now(),
        ).toMap();

        await txn.insert('bill_items', itemMap);

        await txn.rawUpdate(
          'UPDATE products SET stock = stock - ?, isSynced = 0, updatedAt = ? WHERE id = ?',
          [item.quantity, DateTime.now().toIso8601String(), item.productId],
        );

        debugPrint('✅ Product ${item.productId}: Stock reduced by ${item.quantity}');
      }

      debugPrint('✅ Bill with ${items.length} items inserted (ID: $billId)');
      return billId;
    });
  }

  /// ✅ CONSOLIDATED: Single method to update bill with items and ledger
  Future<int> updateBillComplete(
      Bill bill,
      List<BillItem> items, {
        bool updateLedger = true,
      }) async {
    final db = await database;

    return await db.transaction<int>((txn) async {
      final oldItems = await txn.query(
        'bill_items',
        where: 'billId = ? AND isDeleted = 0',
        whereArgs: [bill.id],
      );

      debugPrint('🔄 Updating bill ${bill.id} - Found ${oldItems.length} old items');

      for (var oldItemMap in oldItems) {
        final oldProductId = oldItemMap['productId'] as int;
        final oldQuantity = (oldItemMap['quantity'] as num).toDouble();

        await txn.rawUpdate(
          'UPDATE products SET stock = stock + ?, isSynced = 0, updatedAt = ? WHERE id = ?',
          [oldQuantity, DateTime.now().toIso8601String(), oldProductId],
        );

        debugPrint('✅ Restored $oldQuantity units to product $oldProductId');
      }

      final updatedBill = bill.copyWith(
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      final result = await txn.update(
        'bills',
        updatedBill.toMap(),
        where: 'id = ?',
        whereArgs: [bill.id],
      );

      if (result == 0) {
        debugPrint('⚠️ Bill ${bill.id} not found');
        return 0;
      }

      await txn.update(
        'bill_items',
        {
          'isDeleted': 1,
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'billId = ?',
        whereArgs: [bill.id],
      );

      debugPrint('✅ Soft-deleted ${oldItems.length} old bill items');

      for (var item in items) {
        final itemMap = item.copyWith(
          billId: bill.id,
          isSynced: false,
          updatedAt: DateTime.now(),
        ).toMap();

        itemMap.remove('id');
        itemMap.remove('firestoreId');

        await txn.insert('bill_items', itemMap);

        await txn.rawUpdate(
          'UPDATE products SET stock = stock - ?, isSynced = 0, updatedAt = ? WHERE id = ?',
          [item.quantity, DateTime.now().toIso8601String(), item.productId],
        );

        debugPrint('✅ Deducted ${item.quantity} units from product ${item.productId}');
      }

      if (updateLedger) {
        final ledgerUpdated = await txn.update(
          'ledger',
          {
            'amount': bill.totalAmount,
            'date': bill.date.toIso8601String(),
            'isSynced': 0,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'billId = ? AND type = ?',
          whereArgs: [bill.id, 'bill'],
        );

        if (ledgerUpdated > 0) {
          debugPrint('✅ Ledger entry updated for bill ${bill.id}');
        }
      }

      debugPrint('✅ Bill ${bill.id} updated successfully with ${items.length} new items');
      return result;
    });
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
    final db = await database;
    final updatedBill = bill.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(),
    );

    final result = await db.update(
      'bills',
      updatedBill.toMap(),
      where: 'id = ?',
      whereArgs: [bill.id],
    );

    debugPrint('✅ Bill metadata updated (ID: ${bill.id})');
    return result;
  }

  Future<void> updateBillTotal(int billId, double total) async {
    final db = await database;
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
  }

  Future<int> deleteBill(int id) async {
    final db = await database;

    return await db.transaction((txn) async {
      final billItems = await txn.query(
        'bill_items',
        where: 'billId = ? AND isDeleted = 0',
        whereArgs: [id],
      );

      debugPrint('🗑️ Deleting bill $id - Found ${billItems.length} items to restore');

      for (var itemMap in billItems) {
        final productId = itemMap['productId'] as int;
        final quantity = (itemMap['quantity'] as num).toDouble();

        await txn.rawUpdate(
          'UPDATE products SET stock = stock + ?, isSynced = 0, updatedAt = ? WHERE id = ?',
          [quantity, DateTime.now().toIso8601String(), productId],
        );

        debugPrint('✅ Restored $quantity units to product $productId');
      }

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

      debugPrint('✅ Bill $id soft-deleted with stock restoration and ledger cleanup');
      return result;
    });
  }

  Future<void> deleteBillCompletely(int billId) async {
    final db = await database;
    await db.transaction((txn) async {
      final billItems = await txn.query(
        'bill_items',
        where: 'billId = ?',
        whereArgs: [billId],
      );

      for (var itemMap in billItems) {
        final productId = itemMap['productId'] as int;
        final quantity = (itemMap['quantity'] as num).toDouble();

        await txn.rawUpdate(
          'UPDATE products SET stock = stock + ?, updatedAt = ? WHERE id = ?',
          [quantity, DateTime.now().toIso8601String(), productId],
        );

        debugPrint('✅ Restored $quantity to product $productId');
      }

      await txn.delete('bill_items', where: 'billId = ?', whereArgs: [billId]);
      await txn.delete('ledger', where: 'billId = ?', whereArgs: [billId]);
      await txn.delete('bills', where: 'id = ?', whereArgs: [billId]);
    });

    debugPrint('✅ Bill $billId completely deleted with stock restored');
  }

  Future<void> recalculateCarryForward(int clientId) async {
    final db = await database;

    await db.transaction((txn) async {
      final bills = await txn.query(
        'bills',
        where: 'clientId = ? AND isDeleted = 0',
        whereArgs: [clientId],
        orderBy: 'date ASC',
      );

      double runningBalance = 0;

      for (var billMap in bills) {
        final bill = Bill.fromMap(billMap);
        final previousBalance = runningBalance;
        final totalAmt = bill.totalAmount ?? 0.0;
        final paidAmt = bill.paidAmount ?? 0.0;
        runningBalance = previousBalance + totalAmt - paidAmt;

        final currentCarryForward = bill.carryForward ?? 0.0;
        if (currentCarryForward != runningBalance) {
          await txn.update(
            'bills',
            {
              'carryForward': runningBalance,
              'isSynced': 0,
              'updatedAt': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [bill.id],
          );
          debugPrint('✅ Bill ${bill.id} carry forward updated: $runningBalance');
        }
      }
    });

    debugPrint('✅ Carry forward recalculated for client $clientId');
  }

  // ========================================================================
  // BILL ITEMS
  // ========================================================================

  Future<List<BillItem>> getBillItems(int billId) async {
    final db = await database;
    final rows = await db.query(
      'bill_items',
      where: 'billId = ? AND isDeleted = 0',
      whereArgs: [billId],
    );
    return rows.map((r) => BillItem.fromMap(r)).toList();
  }

  Future<List<Map<String, dynamic>>> getBillItemsByBillId(int billId) async {
    final db = await database;
    return db.query(
      'bill_items',
      where: 'billId = ? AND isDeleted = 0',
      whereArgs: [billId],
    );
  }

  Future<int> insertBillItem(BillItem item) async {
    final db = await database;
    final updatedItem = item.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(),
    );

    final id = await db.insert('bill_items', updatedItem.toMap());

    debugPrint('✅ Bill item inserted (ID: $id)');
    return id;
  }

  Future<int> deleteBillItem(int id) async {
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
  }

  Future<void> updateBillItemQuantityWithStock(int itemId, double newQty) async {
    final db = await database;

    final currentItemMap = await db.query(
      'bill_items',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [itemId],
      limit: 1,
    );
    if (currentItemMap.isEmpty) return;

    final oldQty = (currentItemMap.first['quantity'] as num).toDouble();
    final productId = currentItemMap.first['productId'] as int;
    final diff = newQty - oldQty;

    await db.update(
      'bill_items',
      {
        'quantity': newQty,
        'isSynced': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );

    await db.rawUpdate(
      'UPDATE products SET stock = stock - ?, isSynced = 0, updatedAt = ? WHERE id = ?',
      [diff, DateTime.now().toIso8601String(), productId],
    );

    debugPrint('✅ Bill item quantity updated (ID: $itemId)');
  }

  // ========================================================================
  // LEDGER
  // ========================================================================

  Future<List<LedgerEntry>> getAllLedgerEntries() async {
    final db = await database;
    final rows = await db.query(
      'ledger',
      where: 'isDeleted = 0',
      orderBy: 'date DESC',
    );
    return rows.map((r) => LedgerEntry.fromMap(r)).toList();
  }

  Future<List<Map<String, dynamic>>> getLedgerEntries() async {
    final db = await database;
    return db.query(
      'ledger',
      where: 'isDeleted = 0',
      orderBy: 'date DESC',
    );
  }

  Future<List<LedgerEntry>> getLedgerEntriesByClient(int clientId) async {
    final db = await database;
    final rows = await db.query(
      'ledger',
      where: 'clientId = ? AND isDeleted = 0',
      whereArgs: [clientId],
      orderBy: 'date ASC',
    );
    return rows.map((r) => LedgerEntry.fromMap(r)).toList();
  }

  Future<double> getClientBalance(int clientId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(CASE WHEN type = 'bill' THEN amount ELSE -amount END) as balance
      FROM ledger
      WHERE clientId = ? AND isDeleted = 0
    ''', [clientId]);

    if (result.isEmpty || result.first['balance'] == null) return 0.0;
    return (result.first['balance'] as num).toDouble();
  }

  Future<int> insertLedgerEntry(LedgerEntry entry) async {
    final db = await database;
    final updatedEntry = entry.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(),
    );

    final id = await db.insert('ledger', updatedEntry.toMap());

    debugPrint('✅ Ledger entry inserted (ID: $id)');
    return id;
  }

  Future<int> insertCashPayment({
    required int clientId,
    required double amount,
    String? note,
  }) async {
    final db = await database;
    final id = await db.insert('ledger', {
      'clientId': clientId,
      'type': 'payment',
      'amount': amount,
      'date': DateTime.now().toIso8601String(),
      'note': note ?? 'Cash Payment',
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    debugPrint('✅ Cash payment inserted (ID: $id)');
    return id;
  }

  Future<int> updateLedgerEntry(LedgerEntry entry) async {
    final db = await database;
    final updatedEntry = entry.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(),
    );

    final result = await db.update(
      'ledger',
      updatedEntry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );

    debugPrint('✅ Ledger entry updated (ID: ${entry.id})');
    return result;
  }

  Future<int> deleteLedgerEntry(int id) async {
    final db = await database;
    final result = await db.update(
      'ledger',
      {
        'isDeleted': 1,
        'isSynced': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    debugPrint('✅ Ledger entry soft-deleted (ID: $id)');
    return result;
  }
  Future<List<Map<String, dynamic>>> getClientsWithBalances() async {
    final db = await database;
    return db.rawQuery('''
      SELECT 
        c.*,
        COALESCE(l.balance, 0.0) as balance
      FROM clients c
      LEFT JOIN (
        SELECT 
          clientId, 
          SUM(CASE WHEN type = 'bill' THEN amount ELSE -amount END) as balance
        FROM ledger
        WHERE isDeleted = 0
        GROUP BY clientId
      ) l ON c.id = l.clientId
      WHERE c.isDeleted = 0
      ORDER BY c.name ASC
    ''');
  }

  // ========================================================================
  // STOCK MANAGEMENT
  // ========================================================================

  Future<double> getStock(int productId) async {
    final db = await database;
    final res = await db.query(
      'products',
      columns: ['stock'],
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [productId],
      limit: 1,
    );

    if (res.isNotEmpty) {
      return (res.first['stock'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  Future<void> setStock(int productId, double qty) async {
    final db = await database;
    await db.update(
      'products',
      {
        'stock': qty,
        'updatedAt': DateTime.now().toIso8601String(),
        'isSynced': 0,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );

    debugPrint('✅ Stock updated for product $productId: $qty');
  }

  Future<void> adjustStock(int productId, double deltaQty) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE products SET stock = stock + ?, updatedAt = ?, isSynced = 0 WHERE id = ?',
      [deltaQty, DateTime.now().toIso8601String(), productId],
    );
    debugPrint('✅ Stock adjusted for product $productId: ${deltaQty >= 0 ? "+" : ""}$deltaQty');
  }

  Future<int> updateProductStock(int productId, double newQty) async {
    final db = await database;
    final result = await db.update(
      'products',
      {
        'stock': newQty,
        'updatedAt': DateTime.now().toIso8601String(),
        'isSynced': 0,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );

    debugPrint('✅ Product stock updated (ID: $productId, Qty: $newQty)');
    return result;
  }

  Future<List<Map<String, dynamic>>> getAllStock() async {
    final db = await database;
    return db.rawQuery('''
      SELECT p.id, p.name, p.stock as quantity, p.costPrice
      FROM products p
      WHERE p.isDeleted = 0
      ORDER BY p.name
    ''');
  }

  Future<void> syncStockTable() async {
    final db = await database;
    await db.execute('''
      INSERT OR REPLACE INTO stock (productId, quantity, updatedAt, isSynced)
      SELECT id, stock, updatedAt, isSynced FROM products WHERE isDeleted = 0
    ''');
    debugPrint('✅ Stock table synchronized from products');
  }

  // ========================================================================
  // DEMAND MANAGEMENT
  // ========================================================================

  String _dateOnlyIso(DateTime dt) => dt.toIso8601String().substring(0, 10);

  Future<int> getOrCreateBatchForDate(DateTime date) async {
    final db = await database;
    final ds = _dateOnlyIso(date);
    final rows = await db.query(
      'demand_batch',
      where: 'demandDate = ? AND closed = 0 AND isDeleted = 0',
      whereArgs: [ds],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;

    final id = await db.insert('demand_batch', {
      'demandDate': ds,
      'closed': 0,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    debugPrint('✅ Demand batch created (ID: $id)');
    return id;
  }

  Future<List<Map<String, dynamic>>> getDemandHistory() async {
    final db = await database;
    return db.query(
      'demand_batch',
      where: 'isDeleted = 0',
      orderBy: 'demandDate DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getCurrentBatchTotals(int batchId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT p.id AS productId, p.name AS productName, SUM(d.quantity) AS totalQty
      FROM demand d
      JOIN products p ON p.id = d.productId
      WHERE d.batchId = ? AND d.isDeleted = 0 AND p.isDeleted = 0
      GROUP BY d.productId
      ORDER BY p.name
    ''', [batchId]);
  }

  Future<Map<String, dynamic>?> getBatchById(int batchId) async {
    final db = await database;
    final rows = await db.query(
      'demand_batch',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [batchId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getBatchDetails(int batchId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        p.id   AS productId,
        p.name AS productName,
        SUM(d.quantity) AS totalQty
      FROM demand d
      JOIN products p ON p.id = d.productId
      WHERE d.batchId = ? AND d.isDeleted = 0 AND p.isDeleted = 0
      GROUP BY p.id
      ORDER BY p.name
    ''', [batchId]);
  }

  Future<List<Map<String, dynamic>>> getBatchClientDetails(int batchId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT c.id AS clientId, c.name AS clientName,
             p.id AS productId, p.name AS productName,
             SUM(d.quantity) AS qty
      FROM demand d
      JOIN clients c ON c.id = d.clientId
      JOIN products p ON p.id = d.productId
      WHERE d.batchId = ? AND d.isDeleted = 0 AND c.isDeleted = 0 AND p.isDeleted = 0
      GROUP BY c.id, p.id
      ORDER BY c.name, p.name
    ''', [batchId]);
  }

  Future<int> insertDemandEntry({
    required int batchId,
    required int clientId,
    required int productId,
    required double quantity,
  }) async {
    final db = await database;
    final id = await db.insert('demand', {
      'batchId': batchId,
      'clientId': clientId,
      'productId': productId,
      'quantity': quantity,
      'isDeleted': 0,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    debugPrint('✅ Demand entry inserted (ID: $id)');
    return id;
  }

  Future<int?> closeBatch(
      int batchId, {
        bool createNextDay = false,
        bool deductStock = false,
      }) async {
    final db = await database;

    final productTotals = await db.rawQuery('''
      SELECT productId, SUM(quantity) AS totalQty
      FROM demand
      WHERE batchId = ? AND isDeleted = 0
      GROUP BY productId
    ''', [batchId]);

    for (final row in productTotals) {
      final pid = row['productId'] as int;
      final qty = (row['totalQty'] as num).toDouble();

      if (deductStock) {
        await adjustStock(pid, -qty);
        debugPrint('✅ Stock DEDUCTED for product $pid: -$qty');
      } else {
        await adjustStock(pid, qty);
        debugPrint('✅ Stock ADDED for product $pid: +$qty');
      }
    }

    await db.update(
      'demand_batch',
      {
        'closed': 1,
        'isSynced': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [batchId],
    );

    debugPrint('✅ Demand batch closed (ID: $batchId)');

    if (createNextDay) {
      final nextDay = DateTime.now().add(const Duration(days: 1));
      return getOrCreateBatchForDate(nextDay);
    }
    return null;
  }

  // ========================================================================
  // REPORTING
  // ========================================================================

  Future<Map<String, dynamic>> getDashboardStats() async {
    final clientsCount = await getClientsCount();
    final productsCount = await getProductsCount();
    final billsCount = await getBillsCount();
    final totalRevenue = await getTotalBillsAmount();

    final db = await database;

    final pendingPayments = await db.rawQuery('''
      SELECT SUM(amount) as total
      FROM ledger
      WHERE type = 'bill' AND isDeleted = 0
    ''');

    final lowStockCount = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM products
      WHERE stock < 10 AND isDeleted = 0
    ''');

    return {
      'clientsCount': clientsCount,
      'productsCount': productsCount,
      'billsCount': billsCount,
      'totalRevenue': totalRevenue,
      'pendingPayments': (pendingPayments.first['total'] as num?)?.toDouble() ?? 0.0,
      'lowStockCount': (lowStockCount.first['count'] as int?) ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> getOutstandingBalances() async {
    final db = await database;
    return db.rawQuery('''
      SELECT c.id, c.name, c.phone,
             SUM(CASE WHEN l.type = 'bill' THEN l.amount ELSE 0 END) as totalBills,
             SUM(CASE WHEN l.type = 'payment' THEN l.amount ELSE 0 END) as totalPayments,
             (SUM(CASE WHEN l.type = 'bill' THEN l.amount ELSE 0 END) - 
              SUM(CASE WHEN l.type = 'payment' THEN l.amount ELSE 0 END)) as balance
      FROM clients c
      LEFT JOIN ledger l ON l.clientId = c.id AND l.isDeleted = 0
      WHERE c.isDeleted = 0
      GROUP BY c.id, c.name, c.phone
      HAVING balance > 0
      ORDER BY balance DESC
    ''');
  }

  // ========================================================================
  // SYNC STATUS
  // ========================================================================

  Future<Map<String, dynamic>> getSyncStatus() async {
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
        await db.rawQuery(
            'SELECT COUNT(*) FROM $table WHERE isDeleted = 0 AND isSynced = 0'),
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
  }

  // ========================================================================
  // SAFE DELETION
  // ========================================================================

  Future<bool> canHardDeleteClient(int clientId) async {
    final db = await database;

    final billCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM bills WHERE clientId = ?', [clientId])
    ) ?? 0;

    final ledgerCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ledger WHERE clientId = ?', [clientId])
    ) ?? 0;

    final canDelete = billCount == 0 && ledgerCount == 0;

    if (!canDelete) {
      debugPrint('⚠️ Cannot hard delete client $clientId - has $billCount bills, $ledgerCount ledger entries');
    }

    return canDelete;
  }

  Future<bool> canHardDeleteProduct(int productId) async {
    final db = await database;

    final itemCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM bill_items WHERE productId = ?', [productId])
    ) ?? 0;

    final canDelete = itemCount == 0;

    if (!canDelete) {
      debugPrint('⚠️ Cannot hard delete product $productId - used in $itemCount bill items');
    }

    return canDelete;
  }

  Future<bool> hardDeleteClientIfSafe(int clientId) async {
    if (!await canHardDeleteClient(clientId)) {
      debugPrint('⚠️ Client $clientId kept locally (has bills/ledger)');
      return false;
    }

    final db = await database;
    await db.delete('clients', where: 'id = ?', whereArgs: [clientId]);
    debugPrint('✅ Client $clientId permanently deleted');
    return true;
  }

  Future<bool> hardDeleteProductIfSafe(int productId) async {
    if (!await canHardDeleteProduct(productId)) {
      debugPrint('⚠️ Product $productId kept locally (used in bills)');
      return false;
    }

    final db = await database;
    await db.delete('products', where: 'id = ?', whereArgs: [productId]);
    debugPrint('✅ Product $productId permanently deleted');
    return true;
  }

  // ========================================================================
  // UTILITIES
  // ========================================================================

  Future<bool> clientExists(int id) async {
    final db = await database;
    final result = await db.query(
      'clients',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<bool> productExists(int id) async {
    final db = await database;
    final result = await db.query(
      'products',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<bool> billExists(int id) async {
    final db = await database;
    final result = await db.query(
      'bills',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> rawQuery(
      String sql, [
        List<Object?>? args,
      ]) async {
    final db = await database;
    return db.rawQuery(sql, args);
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      debugPrint('✅ Database closed');
    }
  }

  // ========================================================================
  // ADVANCED REPORTING (Continuation in next part due to length)
  // ========================================================================

  Future<Map<String, dynamic>> getYearlySales([int? year]) async {
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
  }

  Future<List<Map<String, dynamic>>> getMonthlySales([int? year]) async {
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
  }

  Future<List<Map<String, dynamic>>> getDailySales(
      DateTime startDate,
      DateTime endDate, {
        int? limit,
        int? offset,
      }) async {
    final db = await database;

    String limitClause = '';
    if (limit != null) {
      limitClause = 'LIMIT $limit';
      if (offset != null) limitClause += ' OFFSET $offset';
    }

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
  ''', [
      startDate.toIso8601String().substring(0, 10),
      endDate.toIso8601String().substring(0, 10)
    ]);
  }

  Future<Map<String, dynamic>> getYearOverYearComparison(int currentYear) async {
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
  }

  Future<List<Map<String, dynamic>>> getProductSalesReport({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? offset,
    String orderBy = 'totalSales',
  }) async {
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
    if (orderBy == 'totalQuantity') {
      orderClause = 'ORDER BY totalQuantity DESC';
    } else if (orderBy == 'totalProfit') {
      orderClause = 'ORDER BY totalProfit DESC';
    } else if (orderBy == 'avgPrice') {
      orderClause = 'ORDER BY avgPrice DESC';
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
    GROUP BY p.id, p.name, p.price, p.costPrice, p.stock
    $orderClause
    $limitClause
  ''', params);
  }

  Future<List<Map<String, dynamic>>> getProductTrends(int productId, {int months = 12}) async {
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
  }

  Future<Map<String, List<Map<String, dynamic>>>> getTopProducts({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10,
  }) async {
    final baseData = await getProductSalesReport(
        startDate: startDate,
        endDate: endDate,
        orderBy: 'totalSales',
        limit: limit * 2
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
  }

  Future<List<Map<String, dynamic>>> getCustomerAnalysis({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? offset,
    String orderBy = 'totalPurchases',
  }) async {
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
    if (orderBy == 'avgBillValue') {
      orderClause = 'ORDER BY avgBillValue DESC';
    } else if (orderBy == 'lastPurchase') {
      orderClause = 'ORDER BY lastPurchaseDate DESC';
    } else if (orderBy == 'frequency') {
      orderClause = 'ORDER BY totalBills DESC';
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
      COUNT(DISTINCT b.id) as totalBills,
      COALESCE(SUM(b.totalAmount), 0) as totalPurchases,
      COALESCE(AVG(b.totalAmount), 0) as avgBillValue,
      MIN(DATE(b.date)) as firstPurchaseDate,
      MAX(DATE(b.date)) as lastPurchaseDate,
      (julianday('now') - julianday(MAX(DATE(b.date)))) as daysSinceLastPurchase,
      COALESCE(SUM(l_bills.amount), 0) as totalBilled,
      COALESCE(SUM(l_payments.amount), 0) as totalPaid,
      (COALESCE(SUM(l_bills.amount), 0) - COALESCE(SUM(l_payments.amount), 0)) as currentOutstanding
    FROM clients c
    LEFT JOIN bills b ON b.clientId = c.id AND b.isDeleted = 0 $dateFilter
    LEFT JOIN ledger l_bills ON l_bills.clientId = c.id AND l_bills.type = 'bill' AND l_bills.isDeleted = 0
    LEFT JOIN ledger l_payments ON l_payments.clientId = c.id AND l_payments.type = 'payment' AND l_payments.isDeleted = 0
    WHERE c.isDeleted = 0
    GROUP BY c.id, c.name, c.phone
    HAVING totalBills > 0
    $orderClause
    $limitClause
  ''', params);
  }

  /// ✅ FIXED: Explicit type checking for conditions
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

      // ✅ Explicit boolean conditions
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
  }

  Future<Map<String, dynamic>> getProfitAnalysis({
    DateTime? startDate,
    DateTime? endDate,
    String groupBy = 'month',
  }) async {
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
    if (groupBy == 'day') {
      groupByClause = "DATE(b.date)";
    } else if (groupBy == 'week') {
      groupByClause = "strftime('%Y-%W', b.date)";
    } else if (groupBy == 'year') {
      groupByClause = "strftime('%Y', b.date)";
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
  }

  Future<List<Map<String, dynamic>>> getProductMarginAnalysis({
    DateTime? startDate,
    DateTime? endDate,
    double? minMarginPercent,
  }) async {
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
    GROUP BY p.id, p.name, p.price, p.costPrice
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
  }

  Future<Map<String, dynamic>> getStockAnalysis() async {
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
  }

  Future<List<Map<String, dynamic>>> getStockTurnoverAnalysis({int days = 30}) async {
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
    GROUP BY p.id, p.name, p.stock, p.costPrice
    ORDER BY turnoverRatio DESC
  ''');
  }

  Future<Map<String, dynamic>> getCollectionEfficiency({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
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
  }

  Future<List<Map<String, dynamic>>> getPaymentPatterns() async {
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
    GROUP BY c.id, c.name
    HAVING totalBills > 0
    ORDER BY avgPaymentDelayDays DESC
  ''');
  }

  Future<Map<String, dynamic>> getBusinessInsights({DateTime? asOfDate}) async {
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
  }

  Future<List<Map<String, dynamic>>> getSeasonalTrends({int years = 2}) async {
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
  }

  Future<Map<String, dynamic>> calculateCustomerLTV(int clientId) async {
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
  }

  Future<List<Map<String, dynamic>>> getDataForExport(
      String reportType, {
        DateTime? startDate,
        DateTime? endDate,
        Map<String, dynamic>? filters,
      }) async {
    if (reportType == 'sales_summary' && startDate != null && endDate != null) {
      return await getDailySales(startDate, endDate);
    } else if (reportType == 'product_performance') {
      return await getProductSalesReport(startDate: startDate, endDate: endDate);
    } else if (reportType == 'customer_analysis') {
      return await getCustomerAnalysis(startDate: startDate, endDate: endDate);
    } else if (reportType == 'profit_analysis') {
      final profitData = await getProfitAnalysis(startDate: startDate, endDate: endDate);
      return profitData['trends'] as List<Map<String, dynamic>>;
    } else if (reportType == 'stock_analysis') {
      final stockData = await getStockAnalysis();
      return stockData['allProducts'] as List<Map<String, dynamic>>;
    }
    return [];
  }
  Future<int> getTodayBillsCount(DateTime start, DateTime end) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM bills 
      WHERE date >= ? AND date < ? AND isDeleted = 0
    ''', [start.toIso8601String(), end.toIso8601String()]);

    return (result.first['count'] as int?) ?? 0;
  }

  /// Get today's total revenue
  Future<double> getTodayRevenue(DateTime start, DateTime end) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(totalAmount), 0) as total FROM bills 
      WHERE date >= ? AND date < ? AND isDeleted = 0
    ''', [start.toIso8601String(), end.toIso8601String()]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Get pending orders count (using demand_batch for purchase orders)
  Future<int> getPendingOrdersCount() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM demand_batch 
      WHERE closed = 0 AND isDeleted = 0
    ''');

    return (result.first['count'] as int?) ?? 0;
  }

  /// Get count of products with low stock (less than 10 units)
  Future<int> getLowStockCount() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM products 
      WHERE stock < 10 AND stock > 0 AND isDeleted = 0
    ''');

    return (result.first['count'] as int?) ?? 0;
  }

  /// Get top selling product for current month
  Future<String?> getTopSellingProduct() async {
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
  }

  /// Get current month's total revenue
  Future<double> getMonthRevenue(DateTime start, DateTime end) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(totalAmount), 0) as total FROM bills 
      WHERE date >= ? AND date < ? AND isDeleted = 0
    ''', [start.toIso8601String(), end.toIso8601String()]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Get quick insights for dashboard
  Future<Map<String, dynamic>> getQuickInsights() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    // Get all stats in parallel for better performance
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
  }

  /// Get recent activity for dashboard
  Future<List<Map<String, dynamic>>> getRecentActivity({int limit = 10}) async {
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
        l.note as description
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
  }

  /// Get week comparison for dashboard
  Future<Map<String, dynamic>> getWeekComparison() async {
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
  }

  /// Get alerts for dashboard (low stock, pending payments, etc.)
  Future<List<Map<String, dynamic>>> getDashboardAlerts() async {
    final alerts = <Map<String, dynamic>>[];

    // Check for low stock items
    final db = await database;
    final lowStockProducts = await db.rawQuery('''
      SELECT name, stock FROM products 
      WHERE stock < 10 AND stock > 0 AND isDeleted = 0
      ORDER BY stock ASC
      LIMIT 5
    ''');

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
  }

  /// Get product performance for dashboard
  Future<List<Map<String, dynamic>>> getProductPerformance({int days = 7}) async {
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
  }

  /// Schema update for minStock and maxStock columns (if you want to add them)
  Future<void> addStockLimitColumns() async {
    final db = await database;

    try {
      // Check if columns already exist
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
      debugPrint('Error adding stock limit columns: $e');
    }
  }

  /// Get inventory status for better stock management
  Future<Map<String, dynamic>> getInventoryStatus() async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT 
        COUNT(CASE WHEN stock <= 0 THEN 1 END) as outOfStock,
        COUNT(CASE WHEN stock > 0 AND stock < 10 THEN 1 END) as lowStock,
        COUNT(CASE WHEN stock >= 10 AND stock < 50 THEN 1 END) as normalStock,
        COUNT(CASE WHEN stock >= 50 THEN 1 END) as highStock,
        SUM(stock * price) as totalInventoryValue
      FROM products
      WHERE isDeleted = 0
    ''');

    if (result.isEmpty) return {};

    return {
      'outOfStock': (result.first['outOfStock'] as int?) ?? 0,
      'lowStock': (result.first['lowStock'] as int?) ?? 0,
      'normalStock': (result.first['normalStock'] as int?) ?? 0,
      'highStock': (result.first['highStock'] as int?) ?? 0,
      'totalValue': (result.first['totalInventoryValue'] as num?)?.toDouble() ?? 0.0,
    };
  }
}