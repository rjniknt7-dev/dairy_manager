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
  // ----------------- SINGLETON -----------------
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  // ----------------- INITIALIZATION -----------------
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
    // ----------------- TABLE CREATION -----------------
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

  // ----------------- ON UPGRADE -----------------
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Add migrations for versions 2–11
    if (oldVersion < 2) {
      await db.execute('CREATE TABLE IF NOT EXISTS ledger (...)'); // ledger table creation
    }
    if (oldVersion < 3) {
      await db.execute('CREATE TABLE IF NOT EXISTS demand_batch (...)');
      await db.execute('CREATE TABLE IF NOT EXISTS demand (...)');
    }
    if (oldVersion < 4) {
      await db.execute('CREATE TABLE IF NOT EXISTS stock (...)');
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

  // ----------------- CLIENTS -----------------
  Future<List<Client>> getClients() async {
    final db = await database;
    final rows = await db.query('clients');
    return rows.map((m) => Client.fromMap(m)).toList();
  }

  Future<int> insertClient(Client c) async {
    final db = await database;
    return db.insert('clients', c.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> updateClient(Client c) async {
    final db = await database;
    return db.update('clients', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<int> deleteClient(int id) async {
    final db = await database;
    return db.delete('clients', where: 'id = ?', whereArgs: [id]);
  }

  // ----------------- PRODUCTS -----------------
  Future<List<Product>> getProducts() async {
    final db = await database;
    final rows = await db.query('products');
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
    return db.insert('products', p.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> updateProduct(Product p) async {
    final db = await database;
    return db.update('products', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  // ----------------- STOCK -----------------
  Future<void> setStock(int productId, double qty) async {
    final db = await database;
    await db.insert('stock', {'productId': productId, 'quantity': qty}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<double> getStock(int productId) async {
    final db = await database;
    final res = await db.query('stock', where: 'productId = ?', whereArgs: [productId]);
    if (res.isNotEmpty) return (res.first['quantity'] as num).toDouble();
    return 0.0;
  }

  Future<void> adjustStock(int productId, double deltaQty) async {
    final current = await getStock(productId);
    final newQty = (current + deltaQty).clamp(0, double.infinity).toDouble();
    await setStock(productId, newQty);
  }

  Future<List<Map<String, dynamic>>> getAllStock() async {
    final db = await database;
    return db.rawQuery('''
      SELECT s.productId AS id, p.name, s.quantity
      FROM stock s
      LEFT JOIN products p ON p.id = s.productId
      ORDER BY p.name
    ''');
  }

  // ----------------- BILLS & BILL ITEMS -----------------
  // insertBill, updateBill, deleteBill, getBillById, getBillsByClient, insertBillWithItems, etc.
  // Include full stock-sync logic when adjusting bill items
  // (omitted for brevity, can reuse from your part3/part4 code)

  // ----------------- LEDGER -----------------
  // insertLedgerEntry, getLedgerEntriesByClient, insertCashPayment, deleteLedgerEntry

  // ----------------- DEMAND / BATCH -----------------
  // getOrCreateBatchForDate, insertDemandEntry, getCurrentBatchTotals, getDemandHistory
  // getBatchClientDetails, getBatchById, getBatchDetails, closeBatch

  // ----------------- SYNC UTILITIES -----------------
  Future<void> markRowSynced(String table, int id) async {
    final db = await database;
    await db.update(table, {'isSynced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getUnsynced(String table) async {
    final db = await database;
    return db.query(table, where: 'isSynced = 0');
  }

  // ----------------- RAW SQL -----------------
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<Object?>? args]) async {
    final dbClient = await database;
    return dbClient.rawQuery(sql, args);
  }
}