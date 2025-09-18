// lib/services/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

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

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'dairy.db');
    return openDatabase(
      path,
      version: 11,            // 🔼 bumped to 11
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

  }

  Future<void> _onCreate(Database db, int version) async {
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

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE,
        weight REAL,
        price REAL,
        stock REAL DEFAULT 0,
        firestoreId TEXT,
        updatedAt TEXT,
        isSynced INTEGER DEFAULT 0  
      )
    ''');

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

    await db.execute('''
      CREATE TABLE ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clientId INTEGER NOT NULL,
        firestoreId TEXT,
        billId INTEGER,
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
    // Keep all migrations idempotent (use IF NOT EXISTS or guard checks)
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
    // 🔄 Ensure products table always has required columns
    if (oldVersion < 10) {
      // Add columns only if they don’t exist (idempotent)
      await db.execute(
          'ALTER TABLE products ADD COLUMN stock REAL DEFAULT 0');
      await db.execute(
          'ALTER TABLE products ADD COLUMN isSynced INTEGER DEFAULT 0');
    } else {
      // ✅ For users who already have version 10 but missed the columns
      final cols = await db.rawQuery("PRAGMA table_info(products)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('stock')) {
        await db.execute(
            'ALTER TABLE products ADD COLUMN stock REAL DEFAULT 0');
      }
      if (!colNames.contains('isSynced')) {
        await db.execute(
            'ALTER TABLE products ADD COLUMN isSynced INTEGER DEFAULT 0');
      }
    }
  }


    // ---------------------------------------------------------------------------
  // CLIENTS
  // ---------------------------------------------------------------------------

  Future<List<Client>> getClients() async {
    final db = await database;
    final rows = await db.query('clients');
    return rows.map((m) => Client.fromMap(m)).toList();
  }

  Future<int> insertClient(Client c) async {
    final db = await database;
    return db.insert('clients', c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> updateClient(Client c) async {
    final db = await database;
    return db.update('clients', c.toMap(),
        where: 'id = ?', whereArgs: [c.id]);
  }

  Future<int> deleteClient(int id) async {
    final db = await database;
    return db.delete('clients', where: 'id = ?', whereArgs: [id]);
  }


  // ---------------------------------------------------------------------------
  // PRODUCTS
  // ---------------------------------------------------------------------------

  // --- line ~270  AFTER ---
  Future<List<Product>> getProducts() async {
    final db = await database;
    final rows = await db.query('products');

    // ✅ Guarantee 'stock' exists with default 0.0 to avoid crashes
    final safeRows = rows.map((m) {
      if (!m.containsKey('stock') || m['stock'] == null) {
        return {...m, 'stock': 0.0};
      }
      return m;
    }).toList();

    return safeRows.map((m) => Product.fromMap(m)).toList();
  }
  // ~line 285
  /// Save a list of products from Firestore to local SQLite
  Future<void> saveProductsToLocal(List<Product> products) async {
    final dbClient = await database;
    final batch = dbClient.batch();
    for (final p in products) {
      batch.insert(
        'products',
        p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace, // overwrite existing
      );
    }
    await batch.commit(noResult: true);
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

  // Stock helpers
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
    // clamp() -> num, so cast to double
    final double newQty = (current + deltaQty).clamp(0, double.infinity) as double;

    await setStock(productId, newQty);
  }


// ---------------------------------------------------------------------------
// BILLS / ITEMS / LEDGER / DEMAND
// -----------------------------------------


// ----------------- BILLS, BILL ITEMS, LEDGER, DEMAND -------------
// (The rest of your methods remain exactly as in your latest working version.)
// Keep all other CRUD and transaction methods unchanged.


// ----------------- BILLS -----------------
  Future<int> insertBill(Bill bill) async {
    final db = await database;
    return db.insert('bills', bill.toMap());
  }

  Future<Bill?> getBillById(int billId) async {
    final db = await database;
    final rows =
    await db.query('bills', where: 'id = ?', whereArgs: [billId], limit: 1);
    if (rows.isEmpty) return null;
    return Bill.fromMap(rows.first);
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

  Future<int> updateBill(Bill bill) async {
    final db = await database;
    return db.update('bills', bill.toMap(),
        where: 'id = ?', whereArgs: [bill.id]);
  }

  Future<int> deleteBill(int id) async {
    final db = await database;
    return db.delete('bills', where: 'id = ?', whereArgs: [id]);
  }

  /// Insert bill + items + ledger entry + reduce stock
  Future<int> insertBillWithItems(Bill bill, List<BillItem> items) async {
    final db = await database;
    return db.transaction((txn) async {
      final billId = await txn.insert('bills', bill.toMap());
      for (var item in items) {
        final m = item.toMap()
          ..['billId'] = billId;
        await txn.insert('bill_items', m);

        // auto reduce stock
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
      // ledger entry
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

  Future<void> updateBillWithItems(Bill bill, List<BillItem> items) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('bills', bill.toMap(),
          where: 'id = ?', whereArgs: [bill.id]);
      await txn.delete('bill_items', where: 'billId = ?', whereArgs: [bill.id]);
      for (var item in items) {
        final m = item.toMap()
          ..['billId'] = bill.id;
        await txn.insert('bill_items', m);
        // NOTE: Adjusting stock on update can be implemented if needed.
      }
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

  // ----------------- BILL ITEMS -----------------
  Future<List<BillItem>> getBillItems(int billId) async {
    final db = await database;
    final rows =
    await db.query('bill_items', where: 'billId = ?', whereArgs: [billId]);
    return rows.map((r) => BillItem.fromMap(r)).toList();
  }

  /// ✅ Restored to keep old UI code working
  Future<List<Map<String, dynamic>>> getBillItemsByBillId(int billId) async {
    final db = await database;
    return db.query('bill_items', where: 'billId = ?', whereArgs: [billId]);
  }

  Future<int> insertBillItem(BillItem item) async {
    final db = await database;
    return db.insert('bill_items', item.toMap());
  }

  Future<int> deleteBillItemsByBillId(int billId) async {
    final db = await database;
    return db.delete('bill_items', where: 'billId = ?', whereArgs: [billId]);
  }

  Future<int> deleteBillItem(int id) async {
    final db = await database;
    return db.delete('bill_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBillCompletely(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('bill_items', where: 'billId = ?', whereArgs: [id]);
      await txn.delete('bills', where: 'id = ?', whereArgs: [id]);
      await txn.delete('ledger', where: 'billId = ?', whereArgs: [id]);
    });
  }

  // ----------------- LEDGER -----------------
  Future<int> insertLedgerEntry(LedgerEntry entry) async {
    final db = await database;
    return db.insert('ledger', entry.toMap());
  }

  Future<List<LedgerEntry>> getLedgerEntriesByClient(int clientId) async {
    final db = await database;
    final rows = await db.query('ledger',
        where: 'clientId = ?', whereArgs: [clientId], orderBy: 'date ASC');
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

  // ----------------- DEMAND / PURCHASE ORDERS -----------------
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
    final rows = await db.query(
      'demand_batch',
      where: 'id = ?',
      whereArgs: [batchId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Totals per product for a specific purchase-order batch.
  /// Used by DemandHistoryScreen to show product totals.
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


  /// Close a demand (purchase order) batch:
  ///  • marks it closed
  ///  • automatically adds the ordered quantities to inventory
  ///  • optionally creates a next-day batch
  Future<int?> closeBatch(int batchId, {bool createNextDay = false}) async {
    final db = await database;

    // 1. Aggregate totals per product for this batch
    final productTotals = await db.rawQuery('''
    SELECT productId, SUM(quantity) AS totalQty
    FROM demand
    WHERE batchId = ?
    GROUP BY productId
  ''', [batchId]);

    // 2. Update stock: add the ordered quantity for each product
    for (final row in productTotals) {
      final pid = row['productId'] as int;
      final qty = (row['totalQty'] as num).toDouble();
      await adjustStock(pid, qty); // <-- increments or creates stock row
    }

    // 3. Mark the batch as closed
    await db.update(
      'demand_batch',
      {'closed': 1},
      where: 'id = ?',
      whereArgs: [batchId],
    );

    // 4. Optionally create a next-day batch
    if (createNextDay) {
      final nextDay = DateTime.now().add(const Duration(days: 1));
      return getOrCreateBatchForDate(nextDay);
    }
    return null;
  }

  // ✅ Run raw SQL queries (used in demand_history_screen)
  Future<List<Map<String, dynamic>>> rawQuery(String sql,
      [List<Object?>? args]) async {
    final dbClient = await database;
    return dbClient.rawQuery(sql, args);
  }

// ----------------- BILL ITEM EDIT + STOCK ADJUST -----------------

  /// Update the quantity of a bill item AND keep inventory in sync.
  /// This will:
  ///   • Add back the old quantity to stock
  ///   • Subtract the new quantity from stock
  ///   • Update bill_items and bills.totalAmount
  Future<void> updateBillItemWithStock({
    required int billItemId,
    required double newQty,
  }) async {
    final dbClient = await database;

    await dbClient.transaction((txn) async {
      // 1️⃣ Get the existing item and related bill
      final itemRows = await txn.query(
        'bill_items',
        where: 'id = ?',
        whereArgs: [billItemId],
        limit: 1,
      );
      if (itemRows.isEmpty) return;
      final item = itemRows.first;
      final double oldQty = (item['quantity'] as num).toDouble();
      final double price = (item['price'] as num).toDouble();
      final int productId = item['productId'] as int;
      final int billId = item['billId'] as int;

      // 2️⃣ Adjust stock: add back old, subtract new
      final stockRows = await txn.query(
        'stock',
        where: 'productId = ?',
        whereArgs: [productId],
      );
      final currentStock = stockRows.isNotEmpty
          ? (stockRows.first['quantity'] as num).toDouble()
          : 0.0;
      final newStock = (currentStock + oldQty - newQty)
          .clamp(0, double.infinity)
          .toDouble();
      await txn.insert(
        'stock',
        {'productId': productId, 'quantity': newStock},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 3️⃣ Update the bill item
      await txn.update(
        'bill_items',
        {'quantity': newQty},
        where: 'id = ?',
        whereArgs: [billItemId],
      );

      // 4️⃣ Re-calculate and update the bill total
      final totalRow = await txn.rawQuery(
        'SELECT SUM(quantity * price) AS total FROM bill_items WHERE billId = ?',
        [billId],
      );
      final double newTotal =
      ((totalRow.first['total'] ?? 0) as num).toDouble();

      await txn.update(
        'bills',
        {'totalAmount': newTotal},
        where: 'id = ?',
        whereArgs: [billId],
      );
    });
  }

  /// Convenience: call this if you only need to change the total
  Future<void> updateBillTotal(int billId, double total) async {
    final dbClient = await database;
    await dbClient.update(
      'bills',
      {'totalAmount': total},
      where: 'id = ?',
      whereArgs: [billId],
    );
  }

  /// ✅ Update quantity of a bill item only (no stock logic)
  Future<void> updateBillItemQuantity(int itemId, double qty) async {
    final dbClient = await database;
    await dbClient.update(
      'bill_items',
      {'quantity': qty},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// Update a bill item and keep product stock in sync.
  /// This will also adjust the product's available stock by the difference.
  Future<void> updateBillItemQuantityWithStock(int itemId,
      double newQty) async {
    final dbClient = await database;

    // 1️⃣ Get current item info
    final currentItemMap = await dbClient.query(
      'bill_items',
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (currentItemMap.isEmpty) return;

    final oldQty = (currentItemMap.first['quantity'] as num).toDouble();
    final productId = currentItemMap.first['productId'] as int;

    // 2️⃣ Calculate difference
    final diff = newQty - oldQty;

    // 3️⃣ Update the bill_items table
    await dbClient.update(
      'bill_items',
      {'quantity': newQty},
      where: 'id = ?',
      whereArgs: [itemId],
    );

    // 4️⃣ Update product stock (subtract if diff > 0, add back if diff < 0)
    await dbClient.rawUpdate(
      'UPDATE products SET stock = stock - ? WHERE id = ?',
      [diff, productId],
    );
  }

  // lib/services/database_helper.dart
// Add these methods inside the DatabaseHelper class

  /// Update product stock (used by inventory/stock screens)
  Future<int> updateProductStock(int productId, double newQty) async {
    final db = await database;
    return await db.update(
      'products',
      {
        'stock': newQty,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  /// Update client based on Client model
  Future<int> updateClientWithModel(Client client) async {
    final db = await database;
    return await db.update(
      'clients',
      client.toMap(),
      where: 'id = ?',
      whereArgs: [client.id],
    );
  }

  /// Optional convenience method: insert client map
  Future<int> insertClientMap(Map<String, dynamic> map) async {
    final db = await database;
    return await db.insert('clients', map);
  }

  /// Optional convenience method: insert product map
  Future<int> insertProductMap(Map<String, dynamic> map) async {
    final db = await database;
    return await db.insert('products', map);
  }
  // Add at bottom of DatabaseHelper
  Future<List<Map<String, dynamic>>> getAllStock() async {
    final dbClient = await database;
    return dbClient.rawQuery('''
    SELECT s.productId AS id,
           p.name,
           s.quantity
    FROM stock s
    LEFT JOIN products p ON p.id = s.productId
    ORDER BY p.name
  ''');
  }


  Future<List<Map<String, dynamic>>> getBills() async {
    final dbClient = await database;
    return dbClient.query('bills');        // adjust to your schema
  }

  Future<List<Map<String, dynamic>>> getLedgerEntries() async {
    final dbClient = await database;
    return dbClient.query('ledger'); // ✅ correct table
  }
  // Mark any table’s row as synced after successful cloud backup
  Future<void> markRowSynced(String table, int id) async {
    final dbClient = await database;
    await dbClient.update(
      table,
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

// Get unsynced rows from any table
  Future<List<Map<String, dynamic>>> getUnsynced(String table) async {
    final dbClient = await database;
    return dbClient.query(table, where: 'isSynced = 0');
  }









}
