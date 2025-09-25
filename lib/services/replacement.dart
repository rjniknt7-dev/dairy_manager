// lib/services/database_helper_part1.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../models/client.dart';
import '../models/product.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/ledger_entry.dart';

class DatabaseHelper {
  // Singleton
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'dairy.db');
    return openDatabase(
      path,
      version: 11,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // CLIENTS
    await db.execute('''
      CREATE TABLE clients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE,
        phone TEXT,
        address TEXT,
        updatedAt TEXT,
        firestoreId TEXT,
        isSynced INTEGER DEFAULT 0
      )
    ''');

    // PRODUCTS
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE,
        weight REAL,
        price REAL,
        stock REAL DEFAULT 0,
        updatedAt TEXT,
        firestoreId TEXT,
        isSynced INTEGER DEFAULT 0
      )
    ''');

    // BILLS
    await db.execute('''
      CREATE TABLE bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firestoreId TEXT,
        clientId INTEGER,
        totalAmount REAL,
        paidAmount REAL,
        carryForward REAL,
        date TEXT,
        isSynced INTEGER DEFAULT 0,
        FOREIGN KEY(clientId) REFERENCES clients(id)
      )
    ''');

    // BILL ITEMS
    await db.execute('''
      CREATE TABLE bill_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firestoreId TEXT,
        billId INTEGER,
        productId INTEGER,
        quantity REAL,
        price REAL,
        updatedAt TEXT,
        isSynced INTEGER DEFAULT 0,
        FOREIGN KEY(billId) REFERENCES bills(id),
        FOREIGN KEY(productId) REFERENCES products(id)
      )
    ''');

    // LEDGER
    await db.execute('''
      CREATE TABLE ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clientId INTEGER NOT NULL,
        billId INTEGER,
        firestoreId TEXT,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        note TEXT,
        updatedAt TEXT,
        isSynced INTEGER DEFAULT 0,
        FOREIGN KEY(clientId) REFERENCES clients(id),
        FOREIGN KEY(billId) REFERENCES bills(id)
      )
    ''');

    // DEMAND BATCH & DEMAND
    await db.execute('''
      CREATE TABLE demand_batch (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        demandDate TEXT NOT NULL,
        closed INTEGER NOT NULL DEFAULT 0,
        firestoreId TEXT,
        isSynced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE demand (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firestoreId TEXT,
        batchId INTEGER,
        clientId INTEGER,
        productId INTEGER,
        quantity REAL,
        date TEXT,
        isSynced INTEGER DEFAULT 0,
        FOREIGN KEY(batchId) REFERENCES demand_batch(id),
        FOREIGN KEY(clientId) REFERENCES clients(id),
        FOREIGN KEY(productId) REFERENCES products(id)
      )
    ''');

    // STOCK
    await db.execute('''
      CREATE TABLE stock (
        productId INTEGER PRIMARY KEY,
        quantity REAL NOT NULL DEFAULT 0,
        isSynced INTEGER DEFAULT 0,
        FOREIGN KEY(productId) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Always keep migrations idempotent
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          clientId INTEGER NOT NULL,
          billId INTEGER,
          firestoreId TEXT,
          type TEXT NOT NULL,
          amount REAL NOT NULL,
          date TEXT NOT NULL,
          note TEXT,
          updatedAt TEXT,
          FOREIGN KEY(clientId) REFERENCES clients(id),
          FOREIGN KEY(billId) REFERENCES bills(id)
        )
      ''');
    }

    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS demand_batch (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          demandDate TEXT NOT NULL,
          closed INTEGER NOT NULL DEFAULT 0,
          firestoreId TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS demand (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          batchId INTEGER,
          clientId INTEGER,
          productId INTEGER,
          quantity REAL,
          date TEXT,
          firestoreId TEXT,
          FOREIGN KEY(batchId) REFERENCES demand_batch(id),
          FOREIGN KEY(clientId) REFERENCES clients(id),
          FOREIGN KEY(productId) REFERENCES products(id)
        )
      ''');
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock (
          productId INTEGER PRIMARY KEY,
          quantity REAL NOT NULL DEFAULT 0,
          FOREIGN KEY(productId) REFERENCES products(id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 6) {
      await db.execute('ALTER TABLE clients ADD COLUMN updatedAt TEXT');
      await db.execute('ALTER TABLE products ADD COLUMN updatedAt TEXT');
    }

    if (oldVersion < 7) {
      await db.execute('ALTER TABLE products ADD COLUMN firestoreId TEXT');
    }

    if (oldVersion < 8) {
      await db.execute('ALTER TABLE bills ADD COLUMN firestoreId TEXT');
      await db.execute('ALTER TABLE bill_items ADD COLUMN firestoreId TEXT');
      await db.execute('ALTER TABLE ledger ADD COLUMN firestoreId TEXT');
      await db.execute('ALTER TABLE demand_batch ADD COLUMN firestoreId TEXT');
      await db.execute('ALTER TABLE demand ADD COLUMN firestoreId TEXT');
    }

    if (oldVersion < 9) {
      await db.execute('ALTER TABLE ledger ADD COLUMN updatedAt TEXT');
    }

    if (oldVersion < 10) {
      await db.execute('ALTER TABLE products ADD COLUMN stock REAL DEFAULT 0');
      await db.execute('ALTER TABLE products ADD COLUMN isSynced INTEGER DEFAULT 0');
    } else {
      final cols = await db.rawQuery("PRAGMA table_info(products)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('stock')) {
        await db.execute('ALTER TABLE products ADD COLUMN stock REAL DEFAULT 0');
      }
      if (!colNames.contains('isSynced')) {
        await db.execute('ALTER TABLE products ADD COLUMN isSynced INTEGER DEFAULT 0');
      }
    }
  }
}
// lib/services/database_helper_part2.dart
part of 'database_helper_part1.dart';

extension ClientProductStock on DatabaseHelper {
  // ----------------- CLIENTS -----------------
  Future<List<Client>> getClients() async {
    final db = await database;
    final rows = await db.query('clients', orderBy: 'name ASC');
    return rows.map((m) => Client.fromMap(m)).toList();
  }

  Future<int> insertClient(Client client) async {
    final db = await database;
    return db.insert(
      'clients',
      client.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort, // avoid duplicates
    );
  }

  Future<int> updateClient(Client client) async {
    final db = await database;
    return db.update(
      'clients',
      client.toMap(),
      where: 'id = ?',
      whereArgs: [client.id],
    );
  }

  Future<int> deleteClient(int clientId) async {
    final db = await database;
    return db.delete('clients', where: 'id = ?', whereArgs: [clientId]);
  }

  // Convenience method for future sync
  Future<int> markClientSynced(int clientId) async {
    final db = await database;
    return db.update(
      'clients',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [clientId],
    );
  }

  // ----------------- PRODUCTS -----------------
  Future<List<Product>> getProducts() async {
    final db = await database;
    final rows = await db.query('products', orderBy: 'name ASC');

    // Safety: Ensure stock key exists
    final safeRows = rows.map((m) {
      if (!m.containsKey('stock') || m['stock'] == null) {
        return {...m, 'stock': 0.0};
      }
      return m;
    }).toList();

    return safeRows.map((m) => Product.fromMap(m)).toList();
  }

  Future<int> insertProduct(Product p) async {
    final db = await database;
    return db.insert('products', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> updateProduct(Product p) async {
    final db = await database;
    return db.update('products', p.toMap(),
        where: 'id = ?', whereArgs: [p.id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  // ----------------- STOCK -----------------
  Future<void> setStock(int productId, double qty) async {
    final db = await database;
    await db.insert('stock', {'productId': productId, 'quantity': qty},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<double> getStock(int productId) async {
    final db = await database;
    final res = await db.query('stock',
        where: 'productId = ?', whereArgs: [productId]);
    if (res.isNotEmpty) return (res.first['quantity'] as num).toDouble();
    return 0;
  }

  Future<void> adjustStock(int productId, double deltaQty) async {
    final current = await getStock(productId);
    final double newQty = (current + deltaQty).clamp(0, double.infinity);
    await setStock(productId, newQty);
  }

  Future<List<Map<String, dynamic>>> getAllStock() async {
    final db = await database;
    return db.rawQuery('''
      SELECT s.productId AS id,
             p.name,
             s.quantity
      FROM stock s
      LEFT JOIN products p ON p.id = s.productId
      ORDER BY p.name
    ''');
  }

  // ----------------- SYNC HELPERS -----------------
  // Get unsynced rows for any table
  Future<List<Map<String, dynamic>>> getUnsynced(String table) async {
    final db = await database;
    return db.query(table, where: 'isSynced = 0');
  }

  // Mark any row as synced after cloud backup
  Future<void> markRowSynced(String table, int id) async {
    final db = await database;
    await db.update(
      table,
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Convenience: insert map directly for future dynamic sync
  Future<int> insertClientMap(Map<String, dynamic> map) async {
    final db = await database;
    return db.insert('clients', map);
  }

  Future<int> insertProductMap(Map<String, dynamic> map) async {
    final db = await database;
    return db.insert('products', map);
  }

  // Update stock for a product (used in inventory screen)
  Future<int> updateProductStock(int productId, double newQty) async {
    final db = await database;
    return db.update(
      'products',
      {
        'stock': newQty,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }
}// lib/services/database_helper_part3.dart
part of 'database_helper_part1.dart';

extension BillLedgerManagement on DatabaseHelper {
  // ----------------- BILLS -----------------
  Future<int> insertBill(Bill bill) async {
    final db = await database;
    return db.insert('bills', bill.toMap());
  }

  Future<int> updateBill(Bill bill) async {
    final db = await database;
    return db.update('bills', bill.toMap(),
        where: 'id = ?', whereArgs: [bill.id]);
  }

  Future<int> deleteBill(int billId) async {
    final db = await database;
    return db.delete('bills', where: 'id = ?', whereArgs: [billId]);
  }

  Future<List<Bill>> getBillsByClient(int clientId) async {
    final db = await database;
    final rows = await db.query(
      'bills',
      where: 'clientId = ?',
      whereArgs: [clientId],
      orderBy: 'date DESC',
    );
    return rows.map((r) => Bill.fromMap(r)).toList();
  }

  Future<Bill?> getBillById(int billId) async {
    final db = await database;
    final rows =
        await db.query('bills', where: 'id = ?', whereArgs: [billId], limit: 1);
    if (rows.isEmpty) return null;
    return Bill.fromMap(rows.first);
  }

  Future<double> getLastCarryForward(int clientId) async {
    final db = await database;
    final rows = await db.query(
      'bills',
      where: 'clientId = ?',
      whereArgs: [clientId],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isNotEmpty && rows.first['carryForward'] != null) {
      final v = rows.first['carryForward'];
      if (v is int) return v.toDouble();
      if (v is double) return v;
    }
    return 0.0;
  }

  // ----------------- BILL ITEMS -----------------
  Future<List<BillItem>> getBillItems(int billId) async {
    final db = await database;
    final rows =
        await db.query('bill_items', where: 'billId = ?', whereArgs: [billId]);
    return rows.map((r) => BillItem.fromMap(r)).toList();
  }

  Future<int> insertBillItem(BillItem item) async {
    final db = await database;
    return db.insert('bill_items', item.toMap());
  }

  Future<int> deleteBillItem(int itemId) async {
    final db = await database;
    return db.delete('bill_items', where: 'id = ?', whereArgs: [itemId]);
  }

  Future<int> deleteBillItemsByBillId(int billId) async {
    final db = await database;
    return db.delete('bill_items', where: 'billId = ?', whereArgs: [billId]);
  }

  // ----------------- INSERT BILL WITH ITEMS & STOCK -----------------
  Future<int> insertBillWithItems(Bill bill, List<BillItem> items) async {
    final db = await database;
    return db.transaction((txn) async {
      // Insert bill
      final billId = await txn.insert('bills', bill.toMap());

      // Insert items and adjust stock
      for (final item in items) {
        final m = item.toMap()..['billId'] = billId;
        await txn.insert('bill_items', m);

        // Auto-reduce stock
        final current = await txn.rawQuery(
          'SELECT quantity FROM stock WHERE productId = ?',
          [item.productId],
        );
        final existingQty = current.isNotEmpty
            ? (current.first['quantity'] as num).toDouble()
            : 0.0;
        final newQty =
            (existingQty - item.quantity).clamp(0, double.infinity).toDouble();
        await txn.insert(
          'stock',
          {'productId': item.productId, 'quantity': newQty},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Insert ledger entry
      await txn.insert('ledger', {
        'clientId': bill.clientId,
        'billId': billId,
        'type': 'bill',
        'amount': bill.totalAmount,
        'date': bill.date.toIso8601String(),
        'note': 'Bill #$billId',
      });

      return billId;
    });
  }

  // ----------------- UPDATE BILL WITH ITEMS & STOCK -----------------
  Future<void> updateBillWithItems(Bill bill, List<BillItem> items) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Update bill
      await txn.update('bills', bill.toMap(),
          where: 'id = ?', whereArgs: [bill.id]);

      // 2. Delete old items
      await txn.delete('bill_items', where: 'billId = ?', whereArgs: [bill.id]);

      // 3. Insert new items
      for (final item in items) {
        final m = item.toMap()..['billId'] = bill.id;
        await txn.insert('bill_items', m);
      }

      // 4. Update ledger
      final updated = await txn.update(
        'ledger',
        {
          'amount': bill.totalAmount,
          'date': bill.date.toIso8601String(),
          'note': 'Bill #${bill.id}',
        },
        where: 'billId = ? AND type = ?',
        whereArgs: [bill.id, 'bill'],
      );

      if (updated == 0) {
        await txn.insert('ledger', {
          'clientId': bill.clientId,
          'billId': bill.id,
          'type': 'bill',
          'amount': bill.totalAmount,
          'date': bill.date.toIso8601String(),
          'note': 'Bill #${bill.id}',
        });
      }
    });
  }

  // ----------------- LEDGER -----------------
  Future<int> insertLedgerEntry(LedgerEntry entry) async {
    final db = await database;
    return db.insert('ledger', entry.toMap());
  }

  Future<List<LedgerEntry>> getLedgerEntriesByClient(int clientId) async {
    final db = await database;
    final rows = await db.query(
      'ledger',
      where: 'clientId = ?',
      whereArgs: [clientId],
      orderBy: 'date ASC',
    );
    return rows.map((r) => LedgerEntry.fromMap(r)).toList();
  }

  Future<int> insertCashPayment({
    required int clientId,
    required double amount,
    String? note,
  }) async {
    final db = await database;
    return db.insert('ledger', {
      'clientId': clientId,
      'type': 'payment',
      'amount': amount,
      'date': DateTime.now().toIso8601String(),
      'note': note ?? 'Cash Payment',
    });
  }

  Future<int> deleteLedgerEntry(int id) async {
    final db = await database;
    return db.delete('ledger', where: 'id = ?', whereArgs: [id]);
  }

  // ----------------- UPDATE BILL ITEM WITH STOCK -----------------
  Future<void> updateBillItemWithStock({
    required int billItemId,
    required double newQty,
  }) async {
    final dbClient = await database;

    await dbClient.transaction((txn) async {
      // 1️⃣ Get the existing item
      final itemRows = await txn.query(
        'bill_items',
        where: 'id = ?',
        whereArgs: [billItemId],
        limit: 1,
      );
      if (itemRows.isEmpty) return;
      final item = itemRows.first;
      final double oldQty = (item['quantity'] as num).toDouble();
      final int productId = item['productId'] as int;
      final int billId = item['billId'] as int;

      // 2️⃣ Adjust stock
      final stockRows = await txn.query('stock',
          where: 'productId = ?', whereArgs: [productId]);
      final currentStock = stockRows.isNotEmpty
          ? (stockRows.first['quantity'] as num).toDouble()
          : 0.0;
      final newStock = (currentStock + oldQty - newQty)
          .clamp(0, double.infinity)
          .toDouble();
      await txn.insert('stock', {'productId': productId, 'quantity': newStock},
          conflictAlgorithm: ConflictAlgorithm.replace);

      // 3️⃣ Update bill item
      await txn.update('bill_items', {'quantity': newQty},
          where: 'id = ?', whereArgs: [billItemId]);

      // 4️⃣ Update bill total
      final totalRow = await txn.rawQuery(
          'SELECT SUM(quantity * price) AS total FROM bill_items WHERE billId = ?',
          [billId]);
      final double newTotal = ((totalRow.first['total'] ?? 0) as num).toDouble();

      await txn.update('bills', {'totalAmount': newTotal},
          where: 'id = ?', whereArgs: [billId]);
    });
  }
}// lib/services/database_helper_part4.dart
part of 'database_helper_part1.dart';

extension DemandStockUtilities on DatabaseHelper {
  // ----------------- DEMAND BATCH -----------------
  String _dateOnlyIso(DateTime dt) => dt.toIso8601String().substring(0, 10);

  Future<int> getOrCreateBatchForDate(DateTime date) async {
    final db = await database;
    final ds = _dateOnlyIso(date);
    final rows = await db.query('demand_batch',
        where: 'demandDate = ? AND closed = 0', whereArgs: [ds], limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as int;

    return db.insert('demand_batch', {'demandDate': ds, 'closed': 0});
  }

  Future<int> insertDemandEntry({
    required int batchId,
    required int clientId,
    required int productId,
    required double quantity,
  }) async {
    final db = await database;
    return db.insert('demand', {
      'batchId': batchId,
      'clientId': clientId,
      'productId': productId,
      'quantity': quantity,
      'date': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getCurrentBatchTotals(int batchId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT p.id AS productId, p.name AS productName, SUM(d.quantity) AS totalQty
      FROM demand d
      JOIN products p ON p.id = d.productId
      WHERE d.batchId = ?
      GROUP BY d.productId
      ORDER BY p.name
    ''', [batchId]);
  }

  Future<List<Map<String, dynamic>>> getDemandHistory() async {
    final db = await database;
    return db.query('demand_batch', orderBy: 'demandDate DESC');
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
      WHERE d.batchId = ?
      GROUP BY c.id, p.id
      ORDER BY c.name, p.name
    ''', [batchId]);
  }

  Future<Map<String, dynamic>?> getBatchById(int batchId) async {
    final db = await database;
    final rows = await db.query('demand_batch',
        where: 'id = ?', whereArgs: [batchId], limit: 1);
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
      WHERE d.batchId = ?
      GROUP BY p.id
      ORDER BY p.name
    ''', [batchId]);
  }

  /// Close a demand batch
  /// 1. Marks it as closed
  /// 2. Updates stock for all products in the batch
  /// 3. Optionally creates a next-day batch
  Future<int?> closeBatch(int batchId, {bool createNextDay = false}) async {
    final db = await database;

    // 1. Aggregate totals per product
    final productTotals = await db.rawQuery('''
      SELECT productId, SUM(quantity) AS totalQty
      FROM demand
      WHERE batchId = ?
      GROUP BY productId
    ''', [batchId]);

    // 2. Update stock
    for (final row in productTotals) {
      final pid = row['productId'] as int;
      final qty = (row['totalQty'] as num).toDouble();
      await adjustStock(pid, qty); // Increment stock
    }

    // 3. Mark batch closed
    await db.update('demand_batch', {'closed': 1},
        where: 'id = ?', whereArgs: [batchId]);

    // 4. Optionally create next-day batch
    if (createNextDay) {
      final nextDay = DateTime.now().add(const Duration(days: 1));
      return getOrCreateBatchForDate(nextDay);
    }

    return null;
  }

  // ----------------- STOCK MANAGEMENT -----------------
  Future<void> adjustStock(int productId, double deltaQty) async {
    final current = await getStock(productId);
    final newQty = (current + deltaQty).clamp(0, double.infinity).toDouble();
    await setStock(productId, newQty);
  }

  Future<double> getStock(int productId) async {
    final db = await database;
    final res =
        await db.query('stock', where: 'productId = ?', whereArgs: [productId]);
    if (res.isNotEmpty) return (res.first['quantity'] as num).toDouble();
    return 0.0;
  }

  Future<void> setStock(int productId, double qty) async {
    final db = await database;
    await db.insert(
      'stock',
      {'productId': productId, 'quantity': qty},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllStock() async {
    final db = await database;
    return db.rawQuery('''
      SELECT s.productId AS id,
             p.name,
             s.quantity
      FROM stock s
      LEFT JOIN products p ON p.id = s.productId
      ORDER BY p.name
    ''');
  }

  // ----------------- SYNC UTILITIES -----------------
  Future<void> markRowSynced(String table, int id) async {
    final db = await database;
    await db.update(table, {'isSynced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getUnsynced(String table) async {
    final db = await database;
    return db.query(table, where: 'isSynced = 0');
  }

  // ----------------- RAW SQL HELPER -----------------
  Future<List<Map<String, dynamic>>> rawQuery(String sql,
      [List<Object?>? args]) async {
    final dbClient = await database;
    return dbClient.rawQuery(sql, args);
  }
}