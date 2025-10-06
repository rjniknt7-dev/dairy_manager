// lib/services/database_helper.dart
// COMPLETE DATABASE HELPER - PRODUCTION READY

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? _col(String name) {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection(name);
  }

  Future<bool> _isConnected() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  Future<bool> get canSync async => await _isConnected() && _uid != null;

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'dairy.db');
    return openDatabase(
      path,
      version: 23,
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
      firestoreId TEXT UNIQUE,
      isDeleted INTEGER DEFAULT 0,
      isSynced INTEGER DEFAULT 0
    )
  ''');

    await db.execute('''
    CREATE TABLE products (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE,
      weight REAL,
      price REAL,
      costPrice REAL DEFAULT 0,
      stock REAL DEFAULT 0,
      firestoreId TEXT UNIQUE,
      updatedAt TEXT,
      isDeleted INTEGER DEFAULT 0,
      isSynced INTEGER DEFAULT 0
    )
  ''');

    await db.execute('''
    CREATE TABLE bills (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      firestoreId TEXT UNIQUE,
      clientId INTEGER,
      totalAmount REAL,
      paidAmount REAL,
      carryForward REAL,
      date TEXT,
      updatedAt TEXT,
      isSynced INTEGER DEFAULT 0,
      isDeleted INTEGER DEFAULT 0,
      FOREIGN KEY(clientId) REFERENCES clients(id)
    )
  ''');

    await db.execute('''
    CREATE TABLE bill_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      firestoreId TEXT UNIQUE,
      billId INTEGER,
      productId INTEGER,
      quantity REAL,
      price REAL,
      updatedAt TEXT,
      isSynced INTEGER DEFAULT 0,
      isDeleted INTEGER DEFAULT 0,
      FOREIGN KEY(billId) REFERENCES bills(id),
      FOREIGN KEY(productId) REFERENCES products(id)
    )
  ''');

    await db.execute('''
    CREATE TABLE ledger (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      clientId INTEGER NOT NULL,
      firestoreId TEXT UNIQUE,
      billId INTEGER,
      type TEXT NOT NULL,
      amount REAL NOT NULL,
      date TEXT NOT NULL,
      note TEXT,
      updatedAt TEXT,
      isSynced INTEGER DEFAULT 0,
      isDeleted INTEGER DEFAULT 0,
      FOREIGN KEY(clientId) REFERENCES clients(id),
      FOREIGN KEY(billId) REFERENCES bills(id)
    )
  ''');

    await db.execute('''
    CREATE TABLE demand_batch (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      demandDate TEXT NOT NULL,
      closed INTEGER NOT NULL DEFAULT 0,
      firestoreId TEXT UNIQUE,
      isSynced INTEGER DEFAULT 0,
      isDeleted INTEGER DEFAULT 0
    )
  ''');

    await db.execute('''
    CREATE TABLE demand (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  batchId INTEGER,
  clientId INTEGER,
  productId INTEGER,
  quantity REAL,
  date TEXT,
  updatedAt TEXT,
  isSynced INTEGER DEFAULT 0,
  isDeleted INTEGER DEFAULT 0,
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
      updatedAt TEXT,
      isDeleted INTEGER DEFAULT 0,
      FOREIGN KEY(productId) REFERENCES products(id) ON DELETE CASCADE
    )
  ''');
  }
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Upgrade demand table
    if (oldVersion < 22) {
      try {
        await db.execute(
            'ALTER TABLE demand ADD COLUMN updatedAt TEXT'
        );
        debugPrint('Column updatedAt added to demand table');
      } catch (e) {
        debugPrint('Column updatedAt might already exist in demand: $e');
      }

      try {
        await db.execute(
            'ALTER TABLE demand_batch ADD COLUMN updatedAt TEXT'
        );
        debugPrint('Column updatedAt added to demand_batch table');
      } catch (e) {
        debugPrint('Column updatedAt might already exist in demand_batch: $e');
      }
    }

    // Upgrade products table (optional, if you need usageCount)
    if (oldVersion < 21) {
      try {
        await db.execute(
            'ALTER TABLE products ADD COLUMN usageCount INTEGER DEFAULT 0'
        );
        debugPrint('Column usageCount added to products table');
      } catch (e) {
        debugPrint('Column usageCount might already exist: $e');
      }
    }

    // Upgrade stock table (optional)
    if (oldVersion < 20) {
      try {
        await db.execute(
            'ALTER TABLE stock ADD COLUMN updatedAt TEXT'
        );
        debugPrint('Column updatedAt added to stock table');
      } catch (e) {
        debugPrint('Column updatedAt might already exist in stock: $e');
      }
    }

    // Upgrade bills table (optional)
    if (oldVersion < 18) {
      try {
        await db.execute(
            'ALTER TABLE bills ADD COLUMN updatedAt TEXT'
        );
        debugPrint('Column updatedAt added to bills table');
      } catch (e) {
        debugPrint('Column updatedAt might already exist in bills: $e');
      }
    }
  }
  /// Generic wrapper for any DB action.
  /// Saves locally and attempts background Firebase sync.
  Future<T> runDbAction<T>(Future<T> Function(Database db) action) async {
    final db = await database;

    try {
      // Run the local DB action immediately
      final result = await action(db);

      // ✅ Notify listeners/UI immediately that operation succeeded locally
      debugPrint('Local DB action completed successfully');

      // Try syncing in background (non-blocking)
      _isConnected().then((connected) async {
        if (connected && _uid != null) {
          try {
            await _syncPendingChanges();
            debugPrint('Background sync completed');
          } catch (e) {
            debugPrint('Background sync failed: $e');
          }
        } else {
          debugPrint('Offline: queued for later sync');
        }
      });

      return result; // ✅ Return immediately so UI can close
    } catch (e) {
      debugPrint('DB action failed: $e');
      rethrow;
    }
  }

  /// Sync all unsynced rows from local DB to Firebase
  Future<void> _syncPendingChanges() async {
    final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger', 'demand', 'demand_batch', 'stock'];

    for (var table in tables) {
      final db = await database;
      final unsynced = await db.query(table, where: 'isSynced = 0');

      for (var row in unsynced) {
        try {
          final col = _col(table);
          if (col != null && row['firestoreId'] != null) {
            await col.doc(row['firestoreId'] as String?).set(row);
            await db.update(table, {'isSynced': 1}, where: 'id = ?', whereArgs: [row['id']]);
          }
        } catch (e) {
          debugPrint('Sync failed for $table row ${row['id']}: $e');
        }
      }
    }
  }



  // ========================================================================
  // UTILITY - MUST BE EARLY
  // ========================================================================

  Future<List<Map<String, dynamic>>> getUnsynced(String table) async {
    final dbClient = await database;
    return dbClient.query(table,
        where: '(isSynced = 0 OR isSynced IS NULL) AND (isDeleted = 0 OR isDeleted IS NULL)');
  }

  // ========================================================================
  // SYNC METHODS
  // ========================================================================

  Future<void> _autoSyncToFirebase(String table, int localId,
      String operation) async {
    if (!await canSync) return;

    try {
      await Future.delayed(Duration(milliseconds: 100));

      switch (table) {
        case 'clients':
          await _syncClientToFirebase(localId, operation);
          break;
        case 'products':
          await _syncProductToFirebase(localId, operation);
          break;
        case 'bills':
          await _syncBillToFirebase(localId, operation);
          break;
        case 'bill_items':
          await _syncBillItemToFirebase(localId, operation);
          break;
        case 'ledger':
          await _syncLedgerToFirebase(localId, operation);
          break;
        case 'demand_batch':
          await _syncDemandBatchToFirebase(localId, operation);
          break;
        case 'demand':
          await _syncDemandToFirebase(localId, operation);
          break;
      }
    } catch (e) {
      debugPrint('Auto sync failed for $table:$localId - $e');
    }
  }

  Future<void> _syncClientToFirebase(int localId, String operation) async {
    final col = _col('clients');
    if (col == null) return;

    final db = await database;
    final rows = await db.query(
        'clients', where: 'id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return;

    final client = Client.fromMap(rows.first);

    if (operation == 'delete') {
      if (client.firestoreId?.isNotEmpty == true) {
        await col.doc(client.firestoreId).delete();
      }
      return;
    }

    String? firestoreId = client.firestoreId;
    final docId = firestoreId ?? localId.toString();

    await col.doc(docId).set(client.toFirestore(), SetOptions(merge: true));

    if (firestoreId == null || firestoreId.isEmpty) {
      await db.update('clients', {
        'firestoreId': docId,
        'isSynced': 1,
      }, where: 'id = ?', whereArgs: [localId]);
    } else {
      await db.update(
          'clients', {'isSynced': 1}, where: 'id = ?', whereArgs: [localId]);
    }
  }

  Future<void> _syncProductToFirebase(int localId, String operation) async {
    final col = _col('products');
    if (col == null) return;

    final db = await database;
    final rows = await db.query(
        'products', where: 'id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return;

    final product = Product.fromMap(rows.first);

    if (operation == 'delete') {
      if (product.firestoreId?.isNotEmpty == true) {
        await col.doc(product.firestoreId).delete();
      }
      return;
    }

    String? firestoreId = product.firestoreId;
    final docId = firestoreId ?? localId.toString();

    await col.doc(docId).set(product.toFirestore(), SetOptions(merge: true));

    if (firestoreId == null || firestoreId.isEmpty) {
      await db.update('products', {
        'firestoreId': docId,
        'isSynced': 1,
      }, where: 'id = ?', whereArgs: [localId]);
    } else {
      await db.update(
          'products', {'isSynced': 1}, where: 'id = ?', whereArgs: [localId]);
    }
  }

  Future<void> _syncBillToFirebase(int localId, String operation) async {
    final col = _col('bills');
    if (col == null) return;

    final db = await database;
    final rows = await db.query(
        'bills', where: 'id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return;

    final bill = Bill.fromMap(rows.first);

    if (operation == 'delete') {
      if (bill.firestoreId?.isNotEmpty == true) {
        await col.doc(bill.firestoreId).delete();
      }
      return;
    }

    String? firestoreId = bill.firestoreId;
    final docId = firestoreId ?? localId.toString();

    await col.doc(docId).set(bill.toFirestore(), SetOptions(merge: true));

    if (firestoreId == null || firestoreId.isEmpty) {
      await db.update('bills', {
        'firestoreId': docId,
        'isSynced': 1,
      }, where: 'id = ?', whereArgs: [localId]);
    } else {
      await db.update(
          'bills', {'isSynced': 1}, where: 'id = ?', whereArgs: [localId]);
    }
  }

  Future<void> _syncBillItemToFirebase(int localId, String operation) async {
    final col = _col('bill_items');
    if (col == null) return;

    final db = await database;
    final rows = await db.query(
        'bill_items', where: 'id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return;

    final billItem = BillItem.fromMap(rows.first);

    if (operation == 'delete') {
      if (billItem.firestoreId?.isNotEmpty == true) {
        await col.doc(billItem.firestoreId).delete();
      }
      return;
    }

    String? firestoreId = billItem.firestoreId;
    final docId = firestoreId ?? localId.toString();

    await col.doc(docId).set(billItem.toFirestore(), SetOptions(merge: true));

    if (firestoreId == null || firestoreId.isEmpty) {
      await db.update('bill_items', {
        'firestoreId': docId,
        'isSynced': 1,
      }, where: 'id = ?', whereArgs: [localId]);
    } else {
      await db.update(
          'bill_items', {'isSynced': 1}, where: 'id = ?', whereArgs: [localId]);
    }
  }

  Future<void> _syncLedgerToFirebase(int localId, String operation) async {
    final col = _col('ledger');
    if (col == null) return;

    final db = await database;
    final rows = await db.query(
        'ledger', where: 'id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return;

    final ledger = LedgerEntry.fromMap(rows.first);

    if (operation == 'delete') {
      if (ledger.firestoreId?.isNotEmpty == true) {
        await col.doc(ledger.firestoreId).delete();
      }
      return;
    }

    String? firestoreId = ledger.firestoreId;
    final docId = firestoreId ?? localId.toString();

    await col.doc(docId).set(ledger.toFirestore(), SetOptions(merge: true));

    if (firestoreId == null || firestoreId.isEmpty) {
      await db.update('ledger', {
        'firestoreId': docId,
        'isSynced': 1,
      }, where: 'id = ?', whereArgs: [localId]);
    } else {
      await db.update(
          'ledger', {'isSynced': 1}, where: 'id = ?', whereArgs: [localId]);
    }
  }

  Future<void> _syncDemandBatchToFirebase(int localId, String operation) async {
    final col = _col('demand_batch');
    if (col == null) return;

    final db = await database;
    final rows = await db.query(
        'demand_batch', where: 'id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return;

    final batch = rows.first;
    if (operation == 'delete') {
      final firestoreId = batch['firestoreId'] as String?;
      if (firestoreId?.isNotEmpty == true) {
        await col.doc(firestoreId).delete();
      }
      return;
    }

    String? firestoreId = batch['firestoreId'] as String?;
    final docId = firestoreId ?? localId.toString();

    await col.doc(docId).set(batch, SetOptions(merge: true));

    if (firestoreId == null || firestoreId.isEmpty) {
      await db.update('demand_batch', {
        'firestoreId': docId,
        'isSynced': 1,
      }, where: 'id = ?', whereArgs: [localId]);
    } else {
      await db.update('demand_batch', {'isSynced': 1}, where: 'id = ?',
          whereArgs: [localId]);
    }
  }

  Future<void> _syncDemandToFirebase(int localId, String operation) async {
    final col = _col('demand');
    if (col == null) return;

    final db = await database;
    final rows = await db.query(
        'demand', where: 'id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return;

    final demand = rows.first;
    if (operation == 'delete') {
      final firestoreId = demand['firestoreId'] as String?;
      if (firestoreId?.isNotEmpty == true) {
        await col.doc(firestoreId).delete();
      }
      return;
    }

    String? firestoreId = demand['firestoreId'] as String?;
    final docId = firestoreId ?? localId.toString();

    await col.doc(docId).set(demand, SetOptions(merge: true));

    if (firestoreId == null || firestoreId.isEmpty) {
      await db.update('demand', {
        'firestoreId': docId,
        'isSynced': 1,
      }, where: 'id = ?', whereArgs: [localId]);
    } else {
      await db.update(
          'demand', {'isSynced': 1}, where: 'id = ?', whereArgs: [localId]);
    }
  }

  // ========================================================================
  // CLIENTS
  // ========================================================================

  Future<List<Client>> getClients() async {
    final db = await database;
    final rows = await db.query(
        'clients', where: 'isDeleted = 0', orderBy: 'name ASC');
    return rows.map((m) => Client.fromMap(m)).toList();
  }

  Future<Client?> getClientById(int id) async {
    final db = await database;
    final rows = await db.query('clients', where: 'id = ? AND isDeleted = 0',
        whereArgs: [id],
        limit: 1);
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

  Future<int> getClientsCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM clients WHERE isDeleted = 0');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> insertClient(Client c) async {
    final db = await database;
    final updatedClient = c.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    final id = await db.insert('clients', updatedClient.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('clients', id, 'insert');
    });

    return id;
  }

  Future<int> updateClient(Client c) async {
    final db = await database;
    final updatedClient = c.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    final result = await db.update('clients', updatedClient.toMap(),
        where: 'id = ?', whereArgs: [c.id]);

    if (result > 0 && c.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('clients', c.id!, 'update');
      });
    }

    return result;
  }

  Future<int> deleteClient(int id) async {
    final db = await database;

    final result = await db.update('clients', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('clients', id, 'delete');
      });
    }

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

  Future<List<Product>> getProducts() async {
    final db = await database;

    final rows = await db.rawQuery('''
    SELECT p.*, 
           IFNULL(COUNT(bi.id), 0) AS usageCount
    FROM products p
    LEFT JOIN bill_items bi 
      ON p.id = bi.productId AND bi.isDeleted = 0
    WHERE p.isDeleted = 0
    GROUP BY p.id
    ORDER BY usageCount DESC, LOWER(p.name) ASC
  ''');

    final safeRows = rows.map((m) {
      final safeMap = Map<String, dynamic>.from(m);
      safeMap['stock'] ??= 0.0;
      safeMap['costPrice'] ??= 0.0;
      safeMap['isSynced'] ??= 0;
      return safeMap;
    }).toList();

    return safeRows.map((m) => Product.fromMap(m)).toList();
  }


  Future<Product?> getProductById(int id) async {
    final db = await database;
    final rows = await db.query('products', where: 'id = ? AND isDeleted = 0',
        whereArgs: [id],
        limit: 1);
    if (rows.isEmpty) return null;

    final row = rows.first;
    final safeRow = Map<String, dynamic>.from(row);
    safeRow['stock'] ??= 0.0;
    safeRow['costPrice'] ??= 0.0;

    return Product.fromMap(safeRow);
  }

  Future<List<Product>> searchProducts(String query) async {
    final db = await database;

    final rows = await db.rawQuery('''
    SELECT p.*, 
           IFNULL(COUNT(bi.id), 0) AS usageCount
    FROM products p
    LEFT JOIN bill_items bi 
      ON p.id = bi.productId AND bi.isDeleted = 0
    WHERE p.isDeleted = 0 AND p.name LIKE ?
    GROUP BY p.id
    ORDER BY usageCount DESC, LOWER(p.name) ASC
  ''', ['%$query%']);

    final safeRows = rows.map((m) {
      final safeMap = Map<String, dynamic>.from(m);
      safeMap['stock'] ??= 0.0;
      safeMap['costPrice'] ??= 0.0;
      safeMap['isSynced'] ??= 0;
      return safeMap;
    }).toList();

    return safeRows.map((m) => Product.fromMap(m)).toList();
  }


  Future<int> getProductsCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM products WHERE isDeleted = 0');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> insertProduct(Product p) async {
    final db = await database;
    final updatedProduct = p.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    final id = await db.insert('products', updatedProduct.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('products', id, 'insert');
    });

    return id;
  }

  Future<int> updateProduct(Product p) async {
    final db = await database;
    final updatedProduct = p.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    final result = await db.update('products', updatedProduct.toMap(),
        where: 'id = ?', whereArgs: [p.id]);

    if (result > 0 && p.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('products', p.id!, 'update');
      });
    }

    return result;
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;

    final result = await db.update('products', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('products', id, 'delete');
      });
    }

    return result;
  }

  Future<int> insertProductMap(Map<String, dynamic> map) async {
    final product = Product.fromMap(map);
    return await insertProduct(product);
  }

  Future<void> saveProductsToLocal(List<Product> products) async {
    final dbClient = await database;
    final batch = dbClient.batch();
    for (final p in products) {
      batch.insert(
          'products', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ========================================================================
  // BILLS - ALL METHODS INCLUDED
  // ========================================================================

  Future<List<Bill>> getAllBills() async {
    final db = await database;
    final rows = await db.query(
        'bills', where: 'isDeleted = 0', orderBy: 'date DESC');
    return rows.map((r) => Bill.fromMap(r)).toList();
  }

  Future<List<Map<String, dynamic>>> getBills() async {
    final dbClient = await database;
    return dbClient.query(
        'bills', where: 'isDeleted = 0', orderBy: 'date DESC');
  }

  Future<Bill?> getBillById(int billId) async {
    final db = await database;
    final rows = await db.query('bills',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [billId],
        limit: 1);
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
        'SELECT COUNT(*) as count FROM bills WHERE isDeleted = 0');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<double> getTotalBillsAmount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT SUM(totalAmount) as total FROM bills WHERE isDeleted = 0');
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
    if (rows.isNotEmpty && rows.first['carryForward'] != null) {
      final v = rows.first['carryForward'];
      if (v is int) return v.toDouble();
      if (v is double) return v;
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('bills', id, 'insert');
    });

    return id;
  }

  Future<int> insertBillWithItems(Bill bill, List<BillItem> items) async {
    final db = await database;

    return await db.transaction<int>((txn) async {
      // Bill insert
      final billId = await txn.insert(
        'bills',
        bill.copyWith(isSynced: false, updatedAt: DateTime.now()).toMap(),
      );

      // Ledger entry for bill
      await txn.insert(
        'ledger',
        {
          'clientId': bill.clientId,
          'type': 'bill',
          'amount': bill.totalAmount,
          'date': bill.date.toIso8601String(),
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );

      // Bill items insert + stock update
      for (var item in items) {
        final itemMap = item.copyWith(
          billId: billId,
          isSynced: false,
          updatedAt: DateTime.now(),
        ).toMap();

        final itemId = await txn.insert('bill_items', itemMap);

        // Stock update
        final stockRow = await txn.query(
          'products',
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [item.productId],
        );

        double existingQty =
        stockRow.isNotEmpty ? (stockRow.first['stock'] as num).toDouble() : 0;

        final newQty = (existingQty - item.quantity).clamp(0, double.infinity);

        await txn.update(
          'products',
          {
            'stock': newQty,
            'isSynced': 0,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [item.productId],
        );

        // Auto-sync
        _autoSyncToFirebase('bill_items', itemId, 'insert');
        _autoSyncToFirebase('products', item.productId, 'update');
      }

      _autoSyncToFirebase('bills', billId, 'insert');

      return billId;
    });
  }


  Future<int> updateBillWithLedger(Bill bill, {List<BillItem>? updatedItems}) async {
    final db = await database;

    return await db.transaction<int>((txn) async {
      // 1️⃣ Update bill
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

      if (result == 0 || bill.id == null) return 0;

      // 2️⃣ Optional: Update bill items if provided
      if (updatedItems != null) {
        // Delete old items
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

        // Insert new items and update stock
        for (var item in updatedItems) {
          final itemId = await txn.insert(
            'bill_items',
            item.copyWith(
              billId: bill.id,
              isSynced: false,
              updatedAt: DateTime.now(),
            ).toMap(),
          );

          final stockRow = await txn.query(
            'products',
            columns: ['stock'],
            where: 'id = ? AND isDeleted = 0',
            whereArgs: [item.productId],
          );

          double existingQty =
          stockRow.isNotEmpty ? (stockRow.first['stock'] as num).toDouble() : 0.0;
          final newQty = (existingQty - item.quantity).clamp(0, double.infinity);

          await txn.update(
            'products',
            {
              'stock': newQty,
              'isSynced': 0,
              'updatedAt': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [item.productId],
          );

          _autoSyncToFirebase('bill_items', itemId, 'insert');
          _autoSyncToFirebase('products', item.productId, 'update');
        }
      }

      // 3️⃣ Update ledger entry for this bill
      await txn.update(
        'ledger',
        {
          'amount': bill.totalAmount ?? 0.0,
          'date': bill.date.toIso8601String(),
          'note': 'Bill updated',
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'billId = ? AND type = ?',
        whereArgs: [bill.id, 'bill'],
      );

      _autoSyncToFirebase('bills', bill.id!, 'update');

      return result;
    });
  }




  Future<int> updateBill(Bill bill) async {
    final db = await database;
    final updatedBill = bill.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(),
    );

    final result = await db.update('bills', updatedBill.toMap(),
        where: 'id = ?', whereArgs: [bill.id]);

    if (result > 0 && bill.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('bills', bill.id!, 'update');
      });
    }

    return result;
  }

  Future<void> updateBillTotal(int billId, double total) async {
    final dbClient = await database;
    final result = await dbClient.update(
      'bills',
      {
        'totalAmount': total,
        'isSynced': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [billId],
    );

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('bills', billId, 'update');
      });
    }
  }

  Future<int> deleteBill(int id) async {
    final db = await database;
    final result = await db.update('bills', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('bills', id, 'delete');
      });
    }
    return result;
  }

  // ========================================================================
  // BILL ITEMS
  // ========================================================================

  Future<List<BillItem>> getBillItems(int billId) async {
    final db = await database;
    final rows = await db.query('bill_items',
        where: 'billId = ? AND isDeleted = 0',
        whereArgs: [billId]);
    return rows.map((r) => BillItem.fromMap(r)).toList();
  }

  Future<List<Map<String, dynamic>>> getBillItemsByBillId(int billId) async {
    final db = await database;
    return db.query('bill_items',
        where: 'billId = ? AND isDeleted = 0',
        whereArgs: [billId]);
  }

  Future<int> insertBillItem(BillItem item) async {
    final db = await database;
    final updatedItem = item.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(),
    );

    final id = await db.insert('bill_items', updatedItem.toMap());

    // ✅ Increment usage count whenever a product is billed
    await db.rawUpdate(
      'UPDATE products SET usageCount = usageCount + 1, isSynced = 0, updatedAt = ? WHERE id = ?',
      [DateTime.now().toIso8601String(), item.productId],
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('bill_items', id, 'insert');
      _autoSyncToFirebase('products', item.productId, 'update');
    });

    return id;
  }


  Future<int> deleteBillItem(int id) async {
    final db = await database;
    final result = await db.update('bill_items', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('bill_items', id, 'delete');
      });
    }
    return result;
  }

  // ========================================================================
  // LEDGER - CRITICAL
  // ========================================================================

  Future<List<LedgerEntry>> getAllLedgerEntries() async {
    final db = await database;
    final rows = await db.query(
        'ledger', where: 'isDeleted = 0', orderBy: 'date DESC');
    return rows.map((r) => LedgerEntry.fromMap(r)).toList();
  }

  Future<List<Map<String, dynamic>>> getLedgerEntries() async {
    final dbClient = await database;
    return dbClient.query(
        'ledger', where: 'isDeleted = 0', orderBy: 'date DESC');
  }

  Future<List<LedgerEntry>> getLedgerEntriesByClient(int clientId) async {
    final db = await database;
    final rows = await db.query('ledger',
        where: 'clientId = ? AND isDeleted = 0',
        whereArgs: [clientId],
        orderBy: 'date ASC');
    return rows.map((r) => LedgerEntry.fromMap(r)).toList();
  }

  Future<double> getClientBalance(int clientId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        SUM(CASE WHEN type = 'bill' THEN amount ELSE 0 END) as totalBills,
        SUM(CASE WHEN type = 'payment' THEN amount ELSE 0 END) as totalPayments
      FROM ledger
      WHERE clientId = ? AND isDeleted = 0
    ''', [clientId]);

    if (result.isEmpty) return 0.0;
    final totalBills = (result.first['totalBills'] as num?)?.toDouble() ?? 0.0;
    final totalPayments = (result.first['totalPayments'] as num?)?.toDouble() ??
        0.0;
    return totalBills - totalPayments;
  }

  Future<int> insertLedgerEntry(LedgerEntry entry) async {
    final db = await database;
    final updatedEntry = entry.copyWith(
        isSynced: false,
        updatedAt: DateTime.now()
    );

    final id = await db.insert('ledger', updatedEntry.toMap());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('ledger', id, 'insert');
    });

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('ledger', id, 'insert');
    });

    return id;
  }

  Future<int> updateLedgerEntry(LedgerEntry entry) async {
    final db = await database;
    final updatedEntry = entry.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(),
    );

    final result = await db.update('ledger', updatedEntry.toMap(),
        where: 'id = ?', whereArgs: [entry.id]);

    if (result > 0 && entry.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('ledger', entry.id!, 'update');
      });
    }

    return result;
  }

  Future<int> deleteLedgerEntry(int id) async {
    final db = await database;
    final result = await db.update('ledger', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('ledger', id, 'delete');
      });
    }
    return result;
  }

  // ========================================================================
  // STOCK
  // ========================================================================

  Future<double> getStock(int productId) async {
    final db = await database;
    final res = await db.query('products',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [productId],
        limit: 1);

    if (res.isNotEmpty) {
      return (res.first['stock'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  Future<void> setStock(int productId, double qty) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'products',
        {
          'stock': qty,
          'updatedAt': DateTime.now().toIso8601String(),
          'isSynced': 0,
        },
        where: 'id = ?',
        whereArgs: [productId],
      );

      await txn.insert(
        'stock',
        {
          'productId': productId,
          'quantity': qty,
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('products', productId, 'update');
    });
  }

  Future<List<Map<String, dynamic>>> getAllStock() async {
    final dbClient = await database;
    return dbClient.rawQuery('''
      SELECT p.id AS id,
             p.name,
             p.stock AS quantity
      FROM products p
      WHERE p.isDeleted = 0
      ORDER BY p.name
    ''');
  }

  // ========================================================================
  // DEMAND
  // ========================================================================

  String _dateOnlyIso(DateTime dt) => dt.toIso8601String().substring(0, 10);

  Future<int> getOrCreateBatchForDate(DateTime date) async {
    final db = await database;
    final ds = _dateOnlyIso(date);
    final rows = await db.query('demand_batch',
        where: 'demandDate = ? AND closed = 0 AND isDeleted = 0',
        whereArgs: [ds], limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as int;

    final id = await db.insert('demand_batch', {
      'demandDate': ds,
      'closed': 0,
      'isSynced': 0
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('demand_batch', id, 'insert');
    });

    return id;
  }

  Future<List<Map<String, dynamic>>> getDemandHistory() async {
    final db = await database;
    return db.query(
        'demand_batch', where: 'isDeleted = 0', orderBy: 'demandDate DESC');
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

  // ========================================================================
  // SYNC
  // ========================================================================

  Future<bool> forceSyncToFirebase() async {
    if (!await canSync) {
      debugPrint('Cannot sync: no connection or not authenticated');
      return false;
    }

    try {
      debugPrint('Starting manual force sync...');
      final tables = [
        'clients',
        'products',
        'bills',
        'bill_items',
        'ledger',
        'demand_batch',
        'demand'
      ];

      for (final table in tables) {
        final unsynced = await getUnsynced(table);
        debugPrint('Syncing ${unsynced.length} unsynced records from $table');

        for (final row in unsynced) {
          final id = row['id'] as int;
          await _autoSyncToFirebase(table, id, 'update');
        }
      }

      debugPrint('Manual sync completed');
      return true;
    } catch (e) {
      debugPrint('Manual sync failed: $e');
      return false;
    }
  }

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
      'demand'
    ];

    for (final table in tables) {
      final totalCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 0')
      ) ?? 0;

      final unsyncedCount = Sqflite.firstIntValue(
          await db.rawQuery(
              'SELECT COUNT(*) FROM $table WHERE isDeleted = 0 AND isSynced = 0')
      ) ?? 0;

      status[table] = {
        'total': totalCount,
        'unsynced': unsyncedCount,
        'syncedPercent': totalCount > 0 ? ((totalCount - unsyncedCount) /
            totalCount * 100).round() : 100,
      };
    }

    status['canSync'] = await canSync;
    status['isAuthenticated'] = _uid != null;
    return status;
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
      'pendingPayments': (pendingPayments.first['total'] as num?)?.toDouble() ??
          0.0,
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
  // UTILITIES
  // ========================================================================

  Future<bool> clientExists(int id) async {
    final db = await database;
    final result = await db.query('clients', where: 'id = ? AND isDeleted = 0',
        whereArgs: [id],
        limit: 1);
    return result.isNotEmpty;
  }

  Future<bool> productExists(int id) async {
    final db = await database;
    final result = await db.query('products', where: 'id = ? AND isDeleted = 0',
        whereArgs: [id],
        limit: 1);
    return result.isNotEmpty;
  }

  Future<bool> billExists(int id) async {
    final db = await database;
    final result = await db.query(
        'bills', where: 'id = ? AND isDeleted = 0', whereArgs: [id], limit: 1);
    return result.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> rawQuery(String sql,
      [List<Object?>? args]) async {
    final dbClient = await database;
    return dbClient.rawQuery(sql, args);
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  } // Add these methods to your DatabaseHelper class

  Future<void> adjustStock(int productId, double deltaQty) async {
    final current = await getStock(productId);
    final double newQty = (current + deltaQty)
        .clamp(0, double.infinity)
        .toDouble();
    await setStock(productId, newQty);
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

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('products', productId, 'update');
      });
    }

    return result;
  }

  Future<void> updateBillItemQuantityWithStock(int itemId,
      double newQty) async {
    final dbClient = await database;

    final currentItemMap = await dbClient.query(
      'bill_items',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [itemId],
      limit: 1,
    );
    if (currentItemMap.isEmpty) return;

    final oldQty = (currentItemMap.first['quantity'] as num).toDouble();
    final productId = currentItemMap.first['productId'] as int;
    final diff = newQty - oldQty;

    await dbClient.update(
      'bill_items',
      {
        'quantity': newQty,
        'isSynced': 0,
        'updatedAt': DateTime.now().toIso8601String()
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );

    final currentStock = await getStock(productId);
    final newStock = (currentStock - diff).clamp(0, double.infinity).toDouble();
    await setStock(productId, newStock);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('bill_items', itemId, 'update');
    });
  }

  Future<int> updateBillWithItems(Bill bill, List<BillItem> items) async {
    final db = await database;

    return await db.transaction<int>((txn) async {
      // 1️⃣ Update bill
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

      // 2️⃣ Delete old bill items (soft delete)
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

      // 3️⃣ Insert new bill items + adjust stock
      for (var item in items) {
        final itemMap = item.copyWith(
          billId: bill.id,
          isSynced: false,
          updatedAt: DateTime.now(),
        ).toMap();

        final itemId = await txn.insert('bill_items', itemMap);

        // Stock update
        final stockRow = await txn.query(
          'products',
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [item.productId],
        );

        double existingQty =
        stockRow.isNotEmpty ? (stockRow.first['stock'] as num).toDouble() : 0;

        final newQty = (existingQty - item.quantity).clamp(0, double.infinity);

        await txn.update(
          'products',
          {
            'stock': newQty,
            'isSynced': 0,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [item.productId],
        );

        // Auto-sync
        _autoSyncToFirebase('bill_items', itemId, 'insert');
        _autoSyncToFirebase('products', item.productId, 'update');
      }

      // 4️⃣ Update ledger entry for this bill
      await txn.update(
        'ledger',
        {
          'amount': bill.totalAmount,
          'isSynced': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'clientId = ? AND type = ? AND date = ?',
        whereArgs: [bill.clientId, 'bill', bill.date.toIso8601String()],
      );

      // 5️⃣ Auto-sync bill
      _autoSyncToFirebase('bills', bill.id!, 'update');

      return result;
    });
  }



  Future<int?> closeBatch(int batchId, {bool createNextDay = false}) async {
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
      await adjustStock(pid, qty);
    }

    await db.update(
      'demand_batch',
      {'closed': 1, 'isSynced': 0},
      where: 'id = ?',
      whereArgs: [batchId],
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('demand_batch', batchId, 'update');
    });

    if (createNextDay) {
      final nextDay = DateTime.now().add(const Duration(days: 1));
      return getOrCreateBatchForDate(nextDay);
    }
    return null;
  }
  // ========================================================================
// DELETE BILL COMPLETELY
// ========================================================================
  Future<void> deleteBillCompletely(int billId) async {
    final db = await database;
    await db.transaction((txn) async {
      // Delete all bill items
      await txn.delete('bill_items', where: 'billId = ?', whereArgs: [billId]);

      // Delete the bill itself
      await txn.delete('bills', where: 'id = ?', whereArgs: [billId]);

      // Delete related ledger entries (if any)
      await txn.delete('ledger', where: 'billId = ?', whereArgs: [billId]);
    });

    // Sync deletion to Firebase
    _autoSyncToFirebase('bills', billId, 'delete');
  }

// ========================================================================
// INSERT DEMAND ENTRY
// ========================================================================
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

    // Sync to Firebase
    _autoSyncToFirebase('demand', id, 'insert');

    return id;
  }

}