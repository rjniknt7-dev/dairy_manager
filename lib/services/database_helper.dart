// lib/services/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart'as sqflite;
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

  // Firebase helpers
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
      version: 20, // Incremented version
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
    // Ensure stock.updatedAt exists
    if (oldVersion < 20) {
      try {
        await db.execute('ALTER TABLE stock ADD COLUMN updatedAt TEXT');
      } catch (e) {
        debugPrint('Column updatedAt might already exist in stock table: $e');
      }
    }

    // Bills.updatedAt
    if (oldVersion < 18) {
      try {
        await db.execute('ALTER TABLE bills ADD COLUMN updatedAt TEXT');
      } catch (e) {
        debugPrint('updatedAt column might already exist in bills table: $e');
      }

      // Add UNIQUE index on firestoreId columns
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
        try {
          final indexInfo = await db.rawQuery("PRAGMA index_list('$table')");
          final hasUniqueIndex = indexInfo.any((index) {
            final name = index['name'] as String?;
            return name?.contains('firestoreId') ?? false;
          });
          if (!hasUniqueIndex) {
            await db.execute(
                'CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_firestoreId ON $table(firestoreId)'
            );
          }
        } catch (e) {
          debugPrint('Error adding unique constraint to $table: $e');
        }
      }
    }
      // Keep existing migrations...
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
      await db.execute(
          'ALTER TABLE products ADD COLUMN isSynced INTEGER DEFAULT 0');
    }

    if (oldVersion < 11) {
      final tables = [
        'clients',
        'bills',
        'bill_items',
        'ledger',
        'demand_batch',
        'demand',
        'stock'
      ];
      for (final table in tables) {
        try {
          await db.execute(
              'ALTER TABLE $table ADD COLUMN isSynced INTEGER DEFAULT 0');
        } catch (e) {
          // Column might already exist
        }
      }
    }

    if (oldVersion < 12) {
      try {
        await db.execute(
            'ALTER TABLE bills ADD COLUMN isSynced INTEGER DEFAULT 0');
      } catch (e) {
        // Column might already exist
      }
    }

    if (oldVersion < 13) {
      try {
        await db.execute(
            'ALTER TABLE products ADD COLUMN costPrice REAL DEFAULT 0');
      } catch (e) {
        // Column might already exist
      }
    }

    if (oldVersion < 14) {
      final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger'];
      for (final t in tables) {
        final cols = await db.rawQuery('PRAGMA table_info($t)');
        final hasCol = cols.any((c) => c['name'] == 'isDeleted');
        if (!hasCol) {
          await db.execute(
              'ALTER TABLE $t ADD COLUMN isDeleted INTEGER DEFAULT 0');
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // IMPROVED AUTO SYNC METHODS
  // ---------------------------------------------------------------------------

  /// Improved auto sync that runs AFTER transaction completion
  Future<void> _autoSyncToFirebase(String table, int localId,
      String operation) async {
    if (!await canSync) return;

    try {
      // 3️⃣ Wait a brief moment to ensure transaction is complete
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

  // Improved sync methods with duplicate prevention
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

    // 1️⃣ Use deterministic ID - local primary key as Firestore docId
    final docId = firestoreId ?? localId.toString();

    // Always use .doc().set() instead of .add()
    await col.doc(docId).set(client.toFirestore(), SetOptions(merge: true));

    if (firestoreId == null || firestoreId.isEmpty) {
      firestoreId = docId;
      await db.update('clients', {
        'firestoreId': firestoreId,
        'isSynced': 1,
      }, where: 'id = ?', whereArgs: [localId]);
    } else {
      await db.update(
          'clients', {'isSynced': 1}, where: 'id = ?', whereArgs: [localId]);
    }
  }


  // Similar improvements for other sync methods...
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
      firestoreId = docId;
      await db.update('products', {
        'firestoreId': firestoreId,
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
      firestoreId = docId;
      await db.update('bills', {
        'firestoreId': firestoreId,
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
      firestoreId = docId;
      await db.update('bill_items', {
        'firestoreId': firestoreId,
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
      firestoreId = docId;
      await db.update('ledger', {
        'firestoreId': firestoreId,
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
      firestoreId = docId;
      await db.update('demand_batch', {
        'firestoreId': firestoreId,
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
      firestoreId = docId;
      await db.update('demand', {
        'firestoreId': firestoreId,
        'isSynced': 1,
      }, where: 'id = ?', whereArgs: [localId]);
    } else {
      await db.update(
          'demand', {'isSynced': 1}, where: 'id = ?', whereArgs: [localId]);
    }
  }

  // ---------------------------------------------------------------------------
  // IMPROVED RESTORE FROM FIREBASE WITH DUPLICATE PREVENTION
  // ---------------------------------------------------------------------------

  Future<bool> restoreFromFirebaseIfEmpty() async {
    if (!await canSync) return false;

    final db = await database;

    // Check if local DB is empty
    final clientCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM clients WHERE isDeleted = 0')) ?? 0;
    final productCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM products WHERE isDeleted = 0')) ?? 0;

    if (clientCount > 0 || productCount > 0) {
      debugPrint('Local DB not empty, skipping restore');
      return false;
    }

    debugPrint('Local DB empty, restoring from Firebase...');

    try {
      await _restoreClientsFromFirebase();
      await _restoreProductsFromFirebase();
      await _restoreBillsFromFirebase();
      await _restoreBillItemsFromFirebase();
      await _restoreLedgerFromFirebase();
      await _restoreDemandBatchesFromFirebase();
      await _restoreDemandsFromFirebase();

      debugPrint('Successfully restored data from Firebase');
      return true;
    } catch (e) {
      debugPrint('Failed to restore from Firebase: $e');
      return false;
    }
  }

  Future<void> _restoreClientsFromFirebase() async {
    final col = _col('clients');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await database;

    for (final doc in snapshot.docs) {
      final client = Client.fromFirestore(doc);
      final localData = client.copyWith(isSynced: true).toMap();
      localData['firestoreId'] = doc.id;

      // 6️⃣ Use conflict resolution to prevent duplicates
      await db.insert(
        'clients',
        localData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    debugPrint('Restored ${snapshot.docs.length} clients');
  }

  Future<void> _restoreProductsFromFirebase() async {
    final col = _col('products');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await database;

    for (final doc in snapshot.docs) {
      final product = Product.fromFirestore(doc);
      final localData = product.copyWith(isSynced: true).toMap();
      localData['firestoreId'] = doc.id;

      await db.insert(
        'products',
        localData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    debugPrint('Restored ${snapshot.docs.length} products');
  }

  Future<void> _restoreBillsFromFirebase() async {
    final col = _col('bills');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await database;

    for (final doc in snapshot.docs) {
      final bill = Bill.fromFirestore(doc.id, doc.data());
      final localData = bill.toMap();
      localData['isSynced'] = 1;
      localData['firestoreId'] = doc.id;

      await db.insert(
        'bills',
        localData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    debugPrint('Restored ${snapshot.docs.length} bills');
  }

  Future<void> _restoreBillItemsFromFirebase() async {
    final col = _col('bill_items');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await database;

    for (final doc in snapshot.docs) {
      final item = BillItem.fromFirestore(doc);
      final localData = item.copyWith(isSynced: true).toMap();
      localData['firestoreId'] = doc.id;

      await db.insert(
        'bill_items',
        localData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    debugPrint('Restored ${snapshot.docs.length} bill items');
  }

  Future<void> _restoreLedgerFromFirebase() async {
    final col = _col('ledger');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await database;

    for (final doc in snapshot.docs) {
      final entry = LedgerEntry.fromFirestore(doc);
      final localData = entry.copyWith(isSynced: true).toMap();
      localData['firestoreId'] = doc.id;

      await db.insert(
        'ledger',
        localData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    debugPrint('Restored ${snapshot.docs.length} ledger entries');
  }

  Future<void> _restoreDemandBatchesFromFirebase() async {
    final col = _col('demand_batch');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await database;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      data['firestoreId'] = doc.id;
      data['isSynced'] = 1;

      await db.insert(
        'demand_batch',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    debugPrint('Restored ${snapshot.docs.length} demand batches');
  }

  Future<void> _restoreDemandsFromFirebase() async {
    final col = _col('demand');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await database;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      data['firestoreId'] = doc.id;
      data['isSynced'] = 1;

      await db.insert(
        'demand',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    debugPrint('Restored ${snapshot.docs.length} demands');
  }

  // ---------------------------------------------------------------------------
  // IMPROVED CLIENTS WITH BETTER CONFLICT HANDLING
  // ---------------------------------------------------------------------------

  Future<int> insertClient(Client c) async {
    final db = await database;
    final updatedClient = c.copyWith(
      updatedAt: DateTime.now(), // 4️⃣ Always update timestamp
      isSynced: false,
    );

    // 5️⃣ Use replace instead of abort to handle conflicts gracefully
    final id = await db.insert('clients', updatedClient.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    // 3️⃣ Sync after transaction completion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('clients', id, 'insert');
    });

    return id;
  }

  Future<int> updateClient(Client c) async {
    final db = await database;
    final updatedClient = c.copyWith(
      updatedAt: DateTime.now(), // 4️⃣ Always update timestamp
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

  // ---------------------------------------------------------------------------
  // IMPROVED BILLS WITH ITEMS AND STOCK HANDLING
  // ---------------------------------------------------------------------------

  Future<int> insertBillWithItems(Bill bill, List<BillItem> items) async {
    final db = await database;
    return await db.transaction<int>((txn) async {
      // Insert Bill
      final billId = await txn.insert(
        'bills',
        bill.copyWith(isSynced: false, updatedAt: DateTime.now()).toMap(),
      );

      // Insert Bill Items and adjust stock
      for (var item in items) {
        final itemMap = item.copyWith(
          billId: billId,
          isSynced: false,
          updatedAt: DateTime.now(),
        ).toMap();

        // Insert BillItem
        final itemId = await txn.insert('bill_items', itemMap);

        // Reduce Stock
        final stockRow = await txn.query(
          'stock',
          columns: ['quantity'],
          where: 'productId = ?',
          whereArgs: [item.productId],
        );

        double existingQty = stockRow.isNotEmpty
            ? (stockRow.first['quantity'] as num).toDouble()
            : 0.0;

        final newQty = (existingQty - item.quantity).clamp(0, double.infinity);

        if (stockRow.isNotEmpty) {
          await txn.update(
            'stock',
            {'quantity': newQty, 'isSynced': 0, 'updatedAt': DateTime.now().toIso8601String()},
            where: 'productId = ?',
            whereArgs: [item.productId],
          );
        } else {
          await txn.insert(
            'stock',
            {
              'productId': item.productId,
              'quantity': newQty,
              'isSynced': 0,
              'updatedAt': DateTime.now().toIso8601String(),
            },
          );
        }

        // Auto-sync this bill item
        _autoSyncToFirebase('bill_items', itemId, 'insert');
      }

      // Auto-sync the bill after items
      _autoSyncToFirebase('bills', billId, 'insert');

      return billId;
    });
  }

  // 2️⃣ Unified stock management using products table as source of truth
  Future<void> _updateProductStock(
      sqflite.Transaction txn, int productId, double soldQuantity) async {

    // Get current stock from products table
    final currentStock = await txn.rawQuery(
      'SELECT stock FROM products WHERE id = ?',
      [productId],
    );

    double existingStock = 0.0;
    if (currentStock.isNotEmpty) {
      existingStock = (currentStock.first['stock'] as num?)?.toDouble() ?? 0.0;
    }

    // Subtract sold quantity
    final newStock = (existingStock - soldQuantity).clamp(0, double.infinity);

    // Update products table
    await txn.update(
      'products',
      {
        'stock': newStock,
        'updatedAt': DateTime.now().toIso8601String(),
        'isSynced': 0,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );

    // Update stock table
    await txn.insert(
      'stock',
      {
        'productId': productId,
        'quantity': newStock,
        'updatedAt': DateTime.now().toIso8601String(), // ✅ add updatedAt
        'isSynced': 0,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }


  // ---------------------------------------------------------------------------
  // IMPROVED STOCK MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<void> setStock(int productId, double qty) async {
    final db = await database;

    await db.transaction((txn) async {
      // 2️⃣ Update products table as source of truth
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

      // Update stock table for consistency
      await txn.insert(
        'stock',
        {
          'productId': productId,
          'quantity': qty,
          'isSynced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    // Sync only the product, not both tables
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('products', productId, 'update');
    });
  }

  // ---------------------------------------------------------------------------
  // IMPROVED MANUAL SYNC
  // ---------------------------------------------------------------------------

  Future<bool> forceSyncToFirebase() async {
    if (!await canSync) {
      debugPrint('Cannot sync: no connection or not authenticated');
      return false;
    }

    try {
      debugPrint('Starting manual force sync...');

      // 7️⃣ Include all tables that need sync
      final tables = [
        'clients', 'products', 'bills', 'bill_items', 'ledger',
        'demand_batch', 'demand'
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

  // ---------------------------------------------------------------------------
  // UTILITY METHODS
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getUnsynced(String table) async {
    final dbClient = await database;
    return dbClient.query(
        table, where: '(isSynced = 0 OR isSynced IS NULL) AND isDeleted = 0');
  }

  // Existing methods remain the same but with timestamp updates where needed...
  Future<int> updateBillTotal(int billId, double total) async {
    final dbClient = await database;
    final result = await dbClient.update(
      'bills',
      {
        'totalAmount': total,
        'isSynced': 0,
        'updatedAt': DateTime.now().toIso8601String(), // 4️⃣ Add timestamp
      },
      where: 'id = ?',
      whereArgs: [billId],
    );

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('bills', billId, 'update');
      });
    }

    return result;
  }

// ... (keep all other existing methods but ensure they update timestamps where needed)
// ... (previous code continues)

  // ---------------------------------------------------------------------------
  // CLIENTS (WITH IMPROVED CONFLICT HANDLING)
  // ---------------------------------------------------------------------------

  Future<List<Client>> getClients() async {
    final db = await database;
    final rows = await db.query('clients', where: 'isDeleted = 0', orderBy: 'name ASC');
    return rows.map((m) => Client.fromMap(m)).toList();
  }

  Future<int> deleteClient(int id) async {
    final db = await database;

    // Soft delete with timestamp
    final result = await db.update('clients', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(), // 4️⃣ Add timestamp
    }, where: 'id = ?', whereArgs: [id]);

    // Auto sync to Firebase
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

  // ---------------------------------------------------------------------------
  // PRODUCTS (WITH IMPROVED STOCK HANDLING)
  // ---------------------------------------------------------------------------

  Future<List<Product>> getProducts() async {
    final db = await database;
    final rows = await db.query('products', where: 'isDeleted = 0', orderBy: 'name ASC');

    final safeRows = rows.map((m) {
      final safeMap = Map<String, dynamic>.from(m);
      safeMap['stock'] ??= 0.0;
      safeMap['costPrice'] ??= 0.0;
      safeMap['isSynced'] ??= 0;
      return safeMap;
    }).toList();

    return safeRows.map((m) => Product.fromMap(m)).toList();
  }

  Future<int> insertProduct(Product p) async {
    final db = await database;
    final updatedProduct = p.copyWith(
      updatedAt: DateTime.now(), // 4️⃣ Add timestamp
      isSynced: false,
    );

    // 5️⃣ Use replace for better conflict handling
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
      updatedAt: DateTime.now(), // 4️⃣ Add timestamp
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

    // Soft delete with timestamp
    final result = await db.update('products', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(), // 4️⃣ Add timestamp
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

  Future<int> updateProductStock(int productId, double newQty) async {
    final db = await database;
    final result = await db.update(
      'products',
      {
        'stock': newQty,
        'updatedAt': DateTime.now().toIso8601String(), // 4️⃣ Add timestamp
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
  Future<void> reduceStockForBill(List<BillItem> items) async {
    for (var item in items) {
      final product = await getProductById(item.productId); // fetch current stock
      if (product != null) {
        final newStock =
        (product.stock - item.quantity).clamp(0, double.infinity).toDouble();
        await updateProductStock(product.id!, newStock);
      }
    }
  }



  // ---------------------------------------------------------------------------
  // BILLS (WITH IMPROVED SYNC HANDLING)
  // ---------------------------------------------------------------------------

  Future<int> insertBill(Bill bill) async {
    final db = await database;
    final updatedBill = bill.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(), // 4️⃣ Add timestamp
    );

    final id = await db.insert('bills', updatedBill.toMap());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('bills', id, 'insert');
    });

    return id;
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

  Future<int> updateBill(Bill bill) async {
    final db = await database;
    final updatedBill = bill.copyWith(
      isSynced: false,
      updatedAt: DateTime.now(), // 4️⃣ Add timestamp
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

  Future<int> deleteBill(int id) async {
    final db = await database;

    // Soft delete with timestamp
    final result = await db.update('bills', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(), // 4️⃣ Add timestamp
    }, where: 'id = ?', whereArgs: [id]);

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('bills', id, 'delete');
      });
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> getBills() async {
    final dbClient = await database;
    return dbClient.query('bills', where: 'isDeleted = 0', orderBy: 'date DESC');
  }

  Future<void> updateBillWithItems(Bill bill, List<BillItem> newItems) async {
    final db = await database;

    await db.transaction((txn) async {
      // 1️⃣ Update Bill itself
      await txn.update(
        'bills',
        bill.copyWith(isSynced: false, updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [bill.id],
      );
      _autoSyncToFirebase('bills', bill.id!, 'update');

      // 2️⃣ Get existing items
      final existingRows = await txn.query(
        'bill_items',
        where: 'billId = ?',
        whereArgs: [bill.id],
      );

      final existingItems = existingRows.map((row) => BillItem.fromMap(row)).toList();

      // 3️⃣ Track item IDs
      final existingIds = existingItems.map((e) => e.id).toSet();
      final newIds = newItems.where((i) => i.id != null).map((i) => i.id).toSet();

      // 4️⃣ Remove deleted items & restore stock
      for (var oldItem in existingItems) {
        if (!newIds.contains(oldItem.id)) {
          // Restore stock for the removed item
          // Restore stock
          final stockRow = await txn.query(
            'stock',
            columns: ['quantity'],
            where: 'productId = ?',
            whereArgs: [oldItem.productId],
          );
          if (stockRow.isNotEmpty) {
            double existingQty = (stockRow.first['quantity'] as num).toDouble();
            await txn.update(
              'stock',
              {'quantity': existingQty + oldItem.quantity, 'isSynced': 0, 'updatedAt': DateTime.now().toIso8601String()},
              where: 'productId = ?',
              whereArgs: [oldItem.productId],
            );
          }
          else {
            // If stock row doesn't exist, create it
            await txn.insert(
              'stock',
              {
                'productId': oldItem.productId,
                'quantity': oldItem.quantity,
                'isSynced': 0,
                'updatedAt': DateTime.now().toIso8601String()
              },
            );
          }

          // Delete the item itself
          await txn.delete('bill_items', where: 'id = ?', whereArgs: [oldItem.id]);
          _autoSyncToFirebase('bill_items', oldItem.id!, 'delete');
        }
      }


      // 5️⃣ Add or update new items
      for (var item in newItems) {
        if (item.id == null) {
          // New item: insert
          final itemId = await txn.insert(
            'bill_items',
            item.copyWith(
              billId: bill.id,
              isSynced: false,
              updatedAt: DateTime.now(),
            ).toMap(),
          );

          // Reduce stock
          final stockRow = await txn.query(
            'stock',
            columns: ['quantity'],
            where: 'productId = ?',
            whereArgs: [item.productId],
          );

          double existingQty = stockRow.isNotEmpty ? (stockRow.first['quantity'] as num).toDouble() : 0.0;
          final newQty = (existingQty - item.quantity).clamp(0, double.infinity);

          if (stockRow.isNotEmpty) {
            await txn.update(
              'stock',
              {'quantity': newQty, 'isSynced': 0, 'updatedAt': DateTime.now().toIso8601String()},
              where: 'productId = ?',
              whereArgs: [item.productId],
            );
          } else {
            await txn.insert(
              'stock',
              {'productId': item.productId, 'quantity': newQty, 'isSynced': 0, 'updatedAt': DateTime.now().toIso8601String()},
            );
          }

          _autoSyncToFirebase('bill_items', itemId, 'insert');
        } else {
          // Existing item: update quantity & other fields
          final oldItem = existingItems.firstWhere((e) => e.id == item.id);

          // Adjust stock based on quantity difference
          final diff = item.quantity - oldItem.quantity;
          final stockRow = await txn.query(
            'stock',
            columns: ['quantity'],
            where: 'productId = ?',
            whereArgs: [item.productId],
          );
          double existingQty = stockRow.isNotEmpty ? (stockRow.first['quantity'] as num).toDouble() : 0.0;
          final newQty = (existingQty - diff).clamp(0, double.infinity);

          if (stockRow.isNotEmpty) {
            await txn.update(
              'stock',
              {'quantity': newQty, 'isSynced': 0, 'updatedAt': DateTime.now().toIso8601String()},
              where: 'productId = ?',
              whereArgs: [item.productId],
            );
          }

          // Update item
          await txn.update(
            'bill_items',
            item.copyWith(isSynced: false, updatedAt: DateTime.now()).toMap(),
            where: 'id = ?',
            whereArgs: [item.id],
          );

          _autoSyncToFirebase('bill_items', item.id!, 'update');
        }
      }
    });
  }

  Future<void> deleteBillCompletely(int id) async {
    final db = await database;

    await db.transaction((txn) async {
      // Mark as deleted with timestamps
      await txn.update('bill_items', {
        'isDeleted': 1,
        'isSynced': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      }, where: 'billId = ?', whereArgs: [id]);

      await txn.update('bills', {
        'isDeleted': 1,
        'isSynced': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [id]);

      await txn.update('ledger', {
        'isDeleted': 1,
        'isSynced': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      }, where: 'billId = ?', whereArgs: [id]);
    }).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('bills', id, 'delete');
      });
    });
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

  // ---------------------------------------------------------------------------
  // BILL ITEMS (WITH PROPER SYNC)
  // ---------------------------------------------------------------------------

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
        updatedAt: DateTime.now() // 4️⃣ Add timestamp
    );

    final id = await db.insert('bill_items', updatedItem.toMap());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('bill_items', id, 'insert');
    });

    return id;
  }

  Future<int> deleteBillItemsByBillId(int billId) async {
    final db = await database;
    return db.update('bill_items', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'billId = ?', whereArgs: [billId]);
  }

  Future<int> deleteBillItem(int id) async {
    final db = await database;

    final result = await db.update('bill_items', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(), // 4️⃣ Add timestamp
    }, where: 'id = ?', whereArgs: [id]);

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('bill_items', id, 'delete');
      });
    }

    return result;
  }

  Future<void> updateBillItemQuantity(int itemId, double qty) async {
    final dbClient = await database;
    final result = await dbClient.update(
      'bill_items',
      {
        'quantity': qty,
        'isSynced': 0,
        'updatedAt': DateTime.now().toIso8601String() // 4️⃣ Add timestamp
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('bill_items', itemId, 'update');
      });
    }
  }

  Future<void> updateBillItemQuantityWithStock(int itemId, double newQty) async {
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
        'updatedAt': DateTime.now().toIso8601String() // 4️⃣ Add timestamp
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );

    // Use the improved stock adjustment method
    final currentStock = await getStock(productId);
    final newStock = (currentStock - diff).clamp(0, double.infinity) as double;
    await setStock(productId, newStock);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('bill_items', itemId, 'update');
    });
  }

  // ---------------------------------------------------------------------------
  // LEDGER (WITH IMPROVED SYNC)
  // ---------------------------------------------------------------------------

  Future<int> insertLedgerEntry(LedgerEntry entry) async {
    final db = await database;
    final updatedEntry = entry.copyWith(
        isSynced: false,
        updatedAt: DateTime.now() // 4️⃣ Add timestamp
    );

    final id = await db.insert('ledger', updatedEntry.toMap());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('ledger', id, 'insert');
    });

    return id;
  }

  Future<List<LedgerEntry>> getLedgerEntriesByClient(int clientId) async {
    final db = await database;
    final rows = await db.query('ledger',
        where: 'clientId = ? AND isDeleted = 0',
        whereArgs: [clientId],
        orderBy: 'date ASC');
    return rows.map((r) => LedgerEntry.fromMap(r)).toList();
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
      'updatedAt': DateTime.now().toIso8601String(), // 4️⃣ Add timestamp
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('ledger', id, 'insert');
    });

    return id;
  }

  Future<int> deleteLedgerEntry(int id) async {
    final db = await database;

    final result = await db.update('ledger', {
      'isDeleted': 1,
      'isSynced': 0,
      'updatedAt': DateTime.now().toIso8601String(), // 4️⃣ Add timestamp
    }, where: 'id = ?', whereArgs: [id]);

    if (result > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSyncToFirebase('ledger', id, 'delete');
      });
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> getLedgerEntries() async {
    final dbClient = await database;
    return dbClient.query('ledger', where: 'isDeleted = 0', orderBy: 'date DESC');
  }

  // ---------------------------------------------------------------------------
  // STOCK HELPERS (UNIFIED MANAGEMENT)
  // ---------------------------------------------------------------------------

  Future<double> getStock(int productId) async {
    final db = await database;
    // 2️⃣ Use products table as source of truth
    final res = await db.query('products',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [productId],
        limit: 1);

    if (res.isNotEmpty) {
      return (res.first['stock'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  Future<void> adjustStock(int productId, double deltaQty) async {
    final current = await getStock(productId);
    final double newQty = (current + deltaQty).clamp(0, double.infinity) as double;
    await setStock(productId, newQty);
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

  // ---------------------------------------------------------------------------
  // DEMAND / PURCHASE ORDERS (WITH IMPROVED SYNC)
  // ---------------------------------------------------------------------------

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
      'date': DateTime.now().toIso8601String(),
      'isSynced': 0,
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSyncToFirebase('demand', id, 'insert');
    });

    return id;
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

  Future<List<Map<String, dynamic>>> getDemandHistory() async {
    final db = await database;
    return db.query('demand_batch', where: 'isDeleted = 0', orderBy: 'demandDate DESC');
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
      {
        'closed': 1,
        'isSynced': 0,
        // Note: No updatedAt for demand_batch as it doesn't have the column
      },
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

  // ---------------------------------------------------------------------------
  // SYNC HELPERS
  // ---------------------------------------------------------------------------

  Future<void> markRowSynced(String table, int id) async {
    final dbClient = await database;
    await dbClient.update(
      table,
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveProductsToLocal(List<Product> products) async {
    final dbClient = await database;
    final batch = dbClient.batch();
    for (final p in products) {
      batch.insert(
        'products',
        p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------------------
  // UTILITY
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<Object?>? args]) async {
    final dbClient = await database;
    return dbClient.rawQuery(sql, args);
  }

  /// Get sync status for monitoring
  Future<Map<String, dynamic>> getSyncStatus() async {
    final db = await database;
    final Map<String, dynamic> status = {};

    final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger', 'demand_batch', 'demand'];

    for (final table in tables) {
      final totalCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 0')
      ) ?? 0;

      final unsyncedCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 0 AND isSynced = 0')
      ) ?? 0;

      status[table] = {
        'total': totalCount,
        'unsynced': unsyncedCount,
        'syncedPercent': totalCount > 0 ? ((totalCount - unsyncedCount) / totalCount * 100).round() : 100,
      };
    }

    status['canSync'] = await canSync;
    status['isAuthenticated'] = _uid != null;

    return status;
  }

  /// Clean up old deleted records (maintenance)
  Future<void> cleanupOldDeletedRecords({int daysOld = 30}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: daysOld)).toIso8601String();

    final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger', 'demand_batch', 'demand'];

    for (final table in tables) {
      final deleted = await db.delete(
        table,
        where: 'isDeleted = 1 AND updatedAt < ?',
        whereArgs: [cutoff],
      );

      if (deleted > 0) {
        debugPrint('🧹 Cleaned $deleted old deleted records from $table');
      }
    }
  }

  /// Reset sync status for recovery
  Future<void> resetSyncStatus() async {
    final db = await database;
    final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger', 'demand_batch', 'demand'];

    for (final table in tables) {
      await db.update(
        table,
        {'isSynced': 0},
        where: 'isDeleted = 0',
      );
    }

    debugPrint('🔄 Sync status reset for all tables');
  }
  // …last existing method…

  Future<Product?> getProductById(int productId) async {
    final db = await database;
    final rows = await db.query(
      'products',
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

} // end of class



