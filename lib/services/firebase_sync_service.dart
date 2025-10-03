// lib/services/firebase_sync_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/client.dart';
import '../models/product.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/ledger_entry.dart';
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

class FirebaseSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // 2️⃣ Mutex flag to prevent concurrent sync
  bool _syncing = false;

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
      debugPrint('Connectivity check failed: $e');
      return false;
    }
  }

  Future<bool> get canSync async => await _isConnected() && _uid != null;

  // ---------------------------------------------------------------------------
  // MAIN SYNC METHODS WITH MUTEX PROTECTION
  // ---------------------------------------------------------------------------

  /// Complete sync: Upload local changes, then download Firebase data (without overwriting)
  Future<SyncResult> syncAllData() async {
    // 2️⃣ Mutex protection - prevent concurrent sync
    if (_syncing) {
      debugPrint('⏸️ Sync already in progress, skipping...');
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No internet connection or not authenticated');
    }

    _syncing = true;
    try {
      debugPrint('🔄 Starting complete sync...');

      // Step 1: Upload all local changes to Firebase
      await _uploadAllLocalChanges();

      // Step 2: Download and merge Firebase data (without overwriting local changes)
      await _downloadAndMergeFromFirebase();

      debugPrint('✅ Complete sync finished successfully');
      return SyncResult(success: true, message: 'Sync completed successfully');
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
      return SyncResult(success: false, message: 'Sync failed: $e');
    } finally {
      _syncing = false; // 2️⃣ Always release the mutex
    }
  }

  /// First-time restore: Only for fresh installs when local DB is empty
  Future<SyncResult> restoreFromFirebaseIfEmpty() async {
    // 2️⃣ Mutex protection for restore as well
    if (_syncing) {
      debugPrint('⏸️ Sync in progress, skipping restore...');
      return SyncResult(success: false, message: 'Sync in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No internet connection or not authenticated');
    }

    _syncing = true;
    try {
      final db = await _dbHelper.database;

      // Check if local DB is actually empty
      final clientCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM clients WHERE isDeleted = 0')) ?? 0;
      final productCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products WHERE isDeleted = 0')) ?? 0;

      if (clientCount > 0 || productCount > 0) {
        debugPrint('📱 Local DB not empty, skipping restore');
        return SyncResult(success: true, message: 'Local data exists, no restore needed');
      }

      debugPrint('📥 Local DB empty, restoring from Firebase...');

      await _restoreAllDataFromFirebase();

      debugPrint('✅ Data restored from Firebase successfully');
      return SyncResult(success: true, message: 'Data restored from Firebase');
    } catch (e) {
      debugPrint('❌ Restore failed: $e');
      return SyncResult(success: false, message: 'Restore failed: $e');
    } finally {
      _syncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // UPLOAD LOCAL CHANGES TO FIREBASE WITH DETERMINISTIC IDs
  // ---------------------------------------------------------------------------

  Future<void> _uploadAllLocalChanges() async {
    debugPrint('📤 Uploading local changes to Firebase...');

    // Process deletions first
    await _processPendingDeletions();

    // Then upload new/modified records
    await _uploadUnsyncedClients();
    await _uploadUnsyncedProducts();
    await _uploadUnsyncedBills();
    await _uploadUnsyncedBillItems();
    await _uploadUnsyncedLedgerEntries();
    await _uploadUnsyncedDemandBatches();
    await _uploadUnsyncedDemands();

    debugPrint('✅ Local changes uploaded');
  }

  Future<void> _processPendingDeletions() async {
    final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger', 'demand_batch', 'demand'];

    for (final table in tables) {
      await _processTableDeletions(table);
    }
  }

  Future<void> _processTableDeletions(String table) async {
    final col = _col(table);
    if (col == null) return;

    final db = await _dbHelper.database;
    final deletedRows = await db.query(table, where: 'isDeleted = 1');

    debugPrint('🗑️ Processing ${deletedRows.length} deletions for $table');

    for (final row in deletedRows) {
      final firestoreId = row['firestoreId'] as String?;
      if (firestoreId != null && firestoreId.isNotEmpty) {
        try {
          await col.doc(firestoreId).delete();
          debugPrint('🗑️ Deleted $table doc: $firestoreId');
        } catch (e) {
          debugPrint('⚠️ Failed to delete $table doc $firestoreId: $e');
        }
      }

      // Remove from local DB after Firebase deletion
      await db.delete(table, where: 'id = ?', whereArgs: [row['id']]);
    }
  }

  Future<void> _uploadUnsyncedClients() async {
    final col = _col('clients');
    if (col == null) return;

    final unsyncedClients = await _dbHelper.getUnsynced('clients');
    debugPrint('📤 Uploading ${unsyncedClients.length} clients');

    final db = await _dbHelper.database;

    for (final clientMap in unsyncedClients) {
      await db.transaction((txn) async { // 3️⃣ Atomic operation
        try {
          final client = Client.fromMap(clientMap);
          String? firestoreId = clientMap['firestoreId'] as String?;

          // 1️⃣ Use deterministic ID - local primary key as Firestore docId
          final docId = firestoreId ?? client.id.toString();

          // Always use .doc().set() instead of .add()
          await col.doc(docId).set(client.toFirestore(), SetOptions(merge: true));

          if (firestoreId == null || firestoreId.isEmpty) {
            firestoreId = docId;
            debugPrint('📤 Created/Updated client: ${client.name} -> $firestoreId');
          } else {
            debugPrint('📤 Updated client: ${client.name}');
          }

          // 3️⃣ Mark as synced in the same transaction
          await txn.update('clients', {
            'firestoreId': firestoreId,
            'isSynced': 1,
          }, where: 'id = ?', whereArgs: [client.id]);

        } catch (e) {
          debugPrint('❌ Failed to upload client: $e');
          throw e; // Re-throw to ensure transaction rollback
        }
      });
    }
  }

  Future<void> _uploadUnsyncedProducts() async {
    final col = _col('products');
    if (col == null) return;

    final unsyncedProducts = await _dbHelper.getUnsynced('products');
    debugPrint('📤 Uploading ${unsyncedProducts.length} products');

    final db = await _dbHelper.database;

    for (final productMap in unsyncedProducts) {
      await db.transaction((txn) async { // 3️⃣ Atomic operation
        try {
          final product = Product.fromMap(productMap);
          String? firestoreId = productMap['firestoreId'] as String?;

          // 1️⃣ Use deterministic ID
          final docId = firestoreId ?? product.id.toString();

          await col.doc(docId).set(product.toFirestore(), SetOptions(merge: true));

          if (firestoreId == null || firestoreId.isEmpty) {
            firestoreId = docId;
            debugPrint('📤 Created/Updated product: ${product.name} -> $firestoreId');
          } else {
            debugPrint('📤 Updated product: ${product.name}');
          }

          // 3️⃣ Atomic update
          await txn.update('products', {
            'firestoreId': firestoreId,
            'isSynced': 1,
          }, where: 'id = ?', whereArgs: [product.id]);

        } catch (e) {
          debugPrint('❌ Failed to upload product: $e');
          throw e;
        }
      });
    }
  }

  Future<void> _uploadUnsyncedBills() async {
    final col = _col('bills');
    if (col == null) return;

    final unsyncedBills = await _dbHelper.getUnsynced('bills');
    debugPrint('📤 Uploading ${unsyncedBills.length} bills');

    final db = await _dbHelper.database;

    for (final billMap in unsyncedBills) {
      await db.transaction((txn) async { // 3️⃣ Atomic operation
        try {
          final bill = Bill.fromMap(billMap);
          String? firestoreId = bill.firestoreId;

          // 1️⃣ Use deterministic ID
          final docId = firestoreId ?? bill.id.toString();

          await col.doc(docId).set(bill.toFirestore(), SetOptions(merge: true));

          if (firestoreId == null || firestoreId.isEmpty) {
            firestoreId = docId;
            debugPrint('📤 Created/Updated bill: #${bill.id} -> $firestoreId');
          } else {
            debugPrint('📤 Updated bill: #${bill.id}');
          }

          // 3️⃣ Atomic update
          await txn.update('bills', {
            'firestoreId': firestoreId,
            'isSynced': 1,
          }, where: 'id = ?', whereArgs: [bill.id]);

        } catch (e) {
          debugPrint('❌ Failed to upload bill: $e');
          throw e;
        }
      });
    }
  }

  Future<void> _uploadUnsyncedBillItems() async {
    final col = _col('bill_items');
    if (col == null) return;

    final unsyncedItems = await _dbHelper.getUnsynced('bill_items');
    debugPrint('📤 Uploading ${unsyncedItems.length} bill items');

    final db = await _dbHelper.database;

    for (final itemMap in unsyncedItems) {
      await db.transaction((txn) async { // 3️⃣ Atomic operation
        try {
          final item = BillItem.fromMap(itemMap);
          String? firestoreId = itemMap['firestoreId'] as String?;

          // 1️⃣ Use deterministic ID
          final docId = firestoreId ?? item.id.toString();

          await col.doc(docId).set(item.toFirestore(), SetOptions(merge: true));

          if (firestoreId == null || firestoreId.isEmpty) {
            firestoreId = docId;
            debugPrint('📤 Created/Updated bill item: ${item.id} -> $firestoreId');
          } else {
            debugPrint('📤 Updated bill item: ${item.id}');
          }

          // 3️⃣ Atomic update
          await txn.update('bill_items', {
            'firestoreId': firestoreId,
            'isSynced': 1,
          }, where: 'id = ?', whereArgs: [item.id]);

        } catch (e) {
          debugPrint('❌ Failed to upload bill item: $e');
          throw e;
        }
      });
    }
  }

  Future<void> _uploadUnsyncedLedgerEntries() async {
    final col = _col('ledger');
    if (col == null) return;

    final unsyncedEntries = await _dbHelper.getUnsynced('ledger');
    debugPrint('📤 Uploading ${unsyncedEntries.length} ledger entries');

    final db = await _dbHelper.database;

    for (final entryMap in unsyncedEntries) {
      await db.transaction((txn) async { // 3️⃣ Atomic operation
        try {
          final entry = LedgerEntry.fromMap(entryMap);
          String? firestoreId = entryMap['firestoreId'] as String?;

          // 1️⃣ Use deterministic ID
          final docId = firestoreId ?? entry.id.toString();

          await col.doc(docId).set(entry.toFirestore(), SetOptions(merge: true));

          if (firestoreId == null || firestoreId.isEmpty) {
            firestoreId = docId;
            debugPrint('📤 Created/Updated ledger entry: ${entry.id} -> $firestoreId');
          } else {
            debugPrint('📤 Updated ledger entry: ${entry.id}');
          }

          // 3️⃣ Atomic update
          await txn.update('ledger', {
            'firestoreId': firestoreId,
            'isSynced': 1,
          }, where: 'id = ?', whereArgs: [entry.id]);

        } catch (e) {
          debugPrint('❌ Failed to upload ledger entry: $e');
          throw e;
        }
      });
    }
  }

  Future<void> _uploadUnsyncedDemandBatches() async {
    final col = _col('demand_batch');
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced('demand_batch');
    debugPrint('📤 Uploading ${unsynced.length} demand batches');

    final db = await _dbHelper.database;

    for (final batchMap in unsynced) {
      await db.transaction((txn) async { // 3️⃣ Atomic operation
        try {
          String? firestoreId = batchMap['firestoreId'] as String?;

          // 1️⃣ Use deterministic ID
          final docId = firestoreId ?? batchMap['id'].toString();

          await col.doc(docId).set(batchMap, SetOptions(merge: true));

          if (firestoreId == null || firestoreId.isEmpty) {
            firestoreId = docId;
            debugPrint('📤 Created/Updated demand batch: ${batchMap['id']} -> $firestoreId');
          } else {
            debugPrint('📤 Updated demand batch: ${batchMap['id']}');
          }

          // 3️⃣ Atomic update
          await txn.update('demand_batch', {
            'firestoreId': firestoreId,
            'isSynced': 1,
          }, where: 'id = ?', whereArgs: [batchMap['id']]);

        } catch (e) {
          debugPrint('❌ Failed to upload demand batch: $e');
          throw e;
        }
      });
    }
  }

  Future<void> _uploadUnsyncedDemands() async {
    final col = _col('demand');
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced('demand');
    debugPrint('📤 Uploading ${unsynced.length} demands');

    final db = await _dbHelper.database;

    for (final demandMap in unsynced) {
      await db.transaction((txn) async { // 3️⃣ Atomic operation
        try {
          String? firestoreId = demandMap['firestoreId'] as String?;

          // 1️⃣ Use deterministic ID
          final docId = firestoreId ?? demandMap['id'].toString();

          await col.doc(docId).set(demandMap, SetOptions(merge: true));

          if (firestoreId == null || firestoreId.isEmpty) {
            firestoreId = docId;
            debugPrint('📤 Created/Updated demand: ${demandMap['id']} -> $firestoreId');
          } else {
            debugPrint('📤 Updated demand: ${demandMap['id']}');
          }

          // 3️⃣ Atomic update
          await txn.update('demand', {
            'firestoreId': firestoreId,
            'isSynced': 1,
          }, where: 'id = ?', whereArgs: [demandMap['id']]);

        } catch (e) {
          debugPrint('❌ Failed to upload demand: $e');
          throw e;
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // DOWNLOAD AND MERGE FROM FIREBASE (NON-DESTRUCTIVE)
  // ---------------------------------------------------------------------------

  Future<void> _downloadAndMergeFromFirebase() async {
    debugPrint('📥 Downloading and merging Firebase data...');

    await _downloadAndMergeClients();
    await _downloadAndMergeProducts();
    await _downloadAndMergeBills();
    await _downloadAndMergeBillItems();
    await _downloadAndMergeLedgerEntries();
    await _downloadAndMergeDemandBatches();
    await _downloadAndMergeDemands();

    debugPrint('✅ Firebase data merged');
  }

  Future<void> _downloadAndMergeClients() async {
    final col = _col('clients');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('📥 Processing ${snapshot.docs.length} clients from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final client = Client.fromFirestore(doc);

        // Check if this client already exists locally
        final existing = await db.query(
          'clients',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        final localData = client.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;

        if (existing.isEmpty) {
          // New client from Firebase - add to local DB
          await db.insert('clients', localData);
          debugPrint('📥 Added new client from Firebase: ${client.name}');
        } else {
          final existingRow = existing.first;
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          // Only update if local version is not modified (preserve local changes)
          if (!isLocallyModified) {
            await db.update('clients', localData,
                where: 'firestoreId = ?', whereArgs: [doc.id]);
            debugPrint('📥 Updated client from Firebase: ${client.name}');
          } else {
            debugPrint('📱 Keeping local changes for client: ${client.name}');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to download clients: $e');
    }
  }

  Future<void> _downloadAndMergeProducts() async {
    final col = _col('products');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('📥 Processing ${snapshot.docs.length} products from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final product = Product.fromFirestore(doc);

        final existing = await db.query(
          'products',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        final localData = product.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;

        if (existing.isEmpty) {
          // New product from Firebase
          await db.insert('products', localData);
          debugPrint('📥 Added new product from Firebase: ${product.name}');
        } else {
          final existingRow = existing.first;
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified) {
            await db.update('products', localData,
                where: 'firestoreId = ?', whereArgs: [doc.id]);
            debugPrint('📥 Updated product from Firebase: ${product.name}');
          } else {
            debugPrint('📱 Keeping local changes for product: ${product.name}');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to download products: $e');
    }
  }

  Future<void> _downloadAndMergeBills() async {
    final col = _col('bills');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('📥 Processing ${snapshot.docs.length} bills from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final bill = Bill.fromFirestore(doc.id, doc.data());

        final existing = await db.query(
          'bills',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        final localData = bill.toMap();
        localData['isSynced'] = 1;

        if (existing.isEmpty) {
          await db.insert('bills', localData);
          debugPrint('📥 Added new bill from Firebase: #${bill.id}');
        } else {
          final existingRow = existing.first;
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified) {
            await db.update('bills', localData,
                where: 'firestoreId = ?', whereArgs: [doc.id]);
            debugPrint('📥 Updated bill from Firebase: #${bill.id}');
          } else {
            debugPrint('📱 Keeping local changes for bill: #${bill.id}');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to download bills: $e');
    }
  }

  Future<void> _downloadAndMergeBillItems() async {
    final col = _col('bill_items');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('📥 Processing ${snapshot.docs.length} bill items from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final item = BillItem.fromFirestore(doc);

        final existing = await db.query(
          'bill_items',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        final localData = item.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;

        if (existing.isEmpty) {
          await db.insert('bill_items', localData);
          debugPrint('📥 Added new bill item from Firebase: ${item.id}');
        } else {
          final existingRow = existing.first;
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified) {
            await db.update('bill_items', localData,
                where: 'firestoreId = ?', whereArgs: [doc.id]);
            debugPrint('📥 Updated bill item from Firebase: ${item.id}');
          } else {
            debugPrint('📱 Keeping local changes for bill item: ${item.id}');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to download bill items: $e');
    }
  }

  Future<void> _downloadAndMergeLedgerEntries() async {
    final col = _col('ledger');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('📥 Processing ${snapshot.docs.length} ledger entries from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final entry = LedgerEntry.fromFirestore(doc);

        final existing = await db.query(
          'ledger',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        final localData = entry.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;

        if (existing.isEmpty) {
          await db.insert('ledger', localData);
          debugPrint('📥 Added new ledger entry from Firebase: ${entry.id}');
        } else {
          final existingRow = existing.first;
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified) {
            await db.update('ledger', localData,
                where: 'firestoreId = ?', whereArgs: [doc.id]);
            debugPrint('📥 Updated ledger entry from Firebase: ${entry.id}');
          } else {
            debugPrint('📱 Keeping local changes for ledger entry: ${entry.id}');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to download ledger entries: $e');
    }
  }

  Future<void> _downloadAndMergeDemandBatches() async {
    final col = _col('demand_batch');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('📥 Processing ${snapshot.docs.length} demand batches from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;

        final existing = await db.query(
          'demand_batch',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          await db.insert('demand_batch', data);
          debugPrint('📥 Added new demand batch from Firebase: ${data['id']}');
        } else {
          final existingRow = existing.first;
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified) {
            await db.update('demand_batch', data,
                where: 'firestoreId = ?', whereArgs: [doc.id]);
            debugPrint('📥 Updated demand batch from Firebase: ${data['id']}');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to download demand batches: $e');
    }
  }

  Future<void> _downloadAndMergeDemands() async {
    final col = _col('demand');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('📥 Processing ${snapshot.docs.length} demands from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;

        final existing = await db.query(
          'demand',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          await db.insert('demand', data);
          debugPrint('📥 Added new demand from Firebase: ${data['id']}');
        } else {
          final existingRow = existing.first;
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified) {
            await db.update('demand', data,
                where: 'firestoreId = ?', whereArgs: [doc.id]);
            debugPrint('📥 Updated demand from Firebase: ${data['id']}');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to download demands: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // FRESH INSTALL RESTORE (COMPLETE RESTORE)
  // ---------------------------------------------------------------------------

  Future<void> _restoreAllDataFromFirebase() async {
    debugPrint('📥 Starting fresh restore from Firebase...');

    await _restoreClientsFromFirebase();
    await _restoreProductsFromFirebase();
    await _restoreBillsFromFirebase();
    await _restoreBillItemsFromFirebase();
    await _restoreLedgerFromFirebase();
    await _restoreDemandBatchesFromFirebase();
    await _restoreDemandsFromFirebase();

    debugPrint('✅ Fresh restore completed');
  }

  Future<void> _restoreClientsFromFirebase() async {
    final col = _col('clients');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('📥 Restoring ${snapshot.docs.length} clients');

    for (final doc in snapshot.docs) {
      final client = Client.fromFirestore(doc);
      final localData = client.copyWith(isSynced: true).toMap();
      localData['firestoreId'] = doc.id;
      await db.insert('clients', localData);
    }
  }

  Future<void> _restoreProductsFromFirebase() async {
    final col = _col('products');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('📥 Restoring ${snapshot.docs.length} products');

    for (final doc in snapshot.docs) {
      final product = Product.fromFirestore(doc);
      final localData = product.copyWith(isSynced: true).toMap();
      localData['firestoreId'] = doc.id;
      await db.insert('products', localData);
    }
  }

  Future<void> _restoreBillsFromFirebase() async {
    final col = _col('bills');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('📥 Restoring ${snapshot.docs.length} bills');

    for (final doc in snapshot.docs) {
      final bill = Bill.fromFirestore(doc.id, doc.data());
      final localData = bill.toMap();
      localData['isSynced'] = 1;
      await db.insert('bills', localData);
    }
  }

  Future<void> _restoreBillItemsFromFirebase() async {
    final col = _col('bill_items');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('📥 Restoring ${snapshot.docs.length} bill items');

    for (final doc in snapshot.docs) {
      final item = BillItem.fromFirestore(doc);
      final localData = item.copyWith(isSynced: true).toMap();
      localData['firestoreId'] = doc.id;
      await db.insert('bill_items', localData);
    }
  }

  Future<void> _restoreLedgerFromFirebase() async {
    final col = _col('ledger');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('📥 Restoring ${snapshot.docs.length} ledger entries');

    for (final doc in snapshot.docs) {
      final entry = LedgerEntry.fromFirestore(doc);
      final localData = entry.copyWith(isSynced: true).toMap();
      localData['firestoreId'] = doc.id;
      await db.insert('ledger', localData);
    }
  }

  Future<void> _restoreDemandBatchesFromFirebase() async {
    final col = _col('demand_batch');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('📥 Restoring ${snapshot.docs.length} demand batches');

    for (final doc in snapshot.docs) {
      final data = doc.data();
      data['firestoreId'] = doc.id;
      data['isSynced'] = 1;
      await db.insert('demand_batch', data);
    }
  }

  Future<void> _restoreDemandsFromFirebase() async {
    final col = _col('demand');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('📥 Restoring ${snapshot.docs.length} demands');

    for (final doc in snapshot.docs) {
      final data = doc.data();
      data['firestoreId'] = doc.id;
      data['isSynced'] = 1;
      await db.insert('demand', data);
    }
  }

  // ---------------------------------------------------------------------------
  // INDIVIDUAL SYNC METHODS WITH MUTEX PROTECTION
  // ---------------------------------------------------------------------------

  Future<SyncResult> syncClients() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No connection or not authenticated');
    }

    _syncing = true;
    try {
      debugPrint('🔄 Syncing clients...');
      await _processTableDeletions('clients');
      await _uploadUnsyncedClients();
      await _downloadAndMergeClients();
      return SyncResult(success: true, message: 'Clients synced successfully');
    } catch (e) {
      debugPrint('❌ Client sync failed: $e');
      return SyncResult(success: false, message: 'Client sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<SyncResult> syncProducts() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No connection or not authenticated');
    }

    _syncing = true;
    try {
      debugPrint('🔄 Syncing products...');
      await _processTableDeletions('products');
      await _uploadUnsyncedProducts();
      await _downloadAndMergeProducts();
      return SyncResult(success: true, message: 'Products synced successfully');
    } catch (e) {
      debugPrint('❌ Product sync failed: $e');
      return SyncResult(success: false, message: 'Product sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<SyncResult> syncBills() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No connection or not authenticated');
    }

    _syncing = true;
    try {
      debugPrint('🔄 Syncing bills...');
      await _processTableDeletions('bills');
      await _processTableDeletions('bill_items');
      await _uploadUnsyncedBills();
      await _uploadUnsyncedBillItems();
      await _downloadAndMergeBills();
      await _downloadAndMergeBillItems();
      return SyncResult(success: true, message: 'Bills synced successfully');
    } catch (e) {
      debugPrint('❌ Bill sync failed: $e');
      return SyncResult(success: false, message: 'Bill sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<SyncResult> syncLedger() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No connection or not authenticated');
    }

    _syncing = true;
    try {
      debugPrint('🔄 Syncing ledger...');
      await _processTableDeletions('ledger');
      await _uploadUnsyncedLedgerEntries();
      await _downloadAndMergeLedgerEntries();
      return SyncResult(success: true, message: 'Ledger synced successfully');
    } catch (e) {
      debugPrint('❌ Ledger sync failed: $e');
      return SyncResult(success: false, message: 'Ledger sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // AUTO SYNC ON APP STARTUP
  // ---------------------------------------------------------------------------

  /// Call this when app starts to handle both fresh installs and regular sync
  Future<SyncResult> autoSyncOnStartup() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      debugPrint('📱 Starting in offline mode');
      return SyncResult(success: false, message: 'Starting offline - no connection');
    }

    _syncing = true;
    try {
      debugPrint('🚀 Auto sync on startup...');

      // First check if this is a fresh install
      final restoreResult = await restoreFromFirebaseIfEmpty();
      if (restoreResult.success && restoreResult.message.contains('restored')) {
        // Fresh install - data was restored
        return SyncResult(success: true, message: 'Welcome! Your data has been restored from cloud');
      }

      // Not a fresh install - do regular sync
      final syncResult = await syncAllData();
      return SyncResult(
          success: syncResult.success,
          message: syncResult.success ? 'App synced with cloud' : syncResult.message
      );

    } catch (e) {
      debugPrint('❌ Auto sync failed: $e');
      return SyncResult(success: false, message: 'Sync failed, working offline');
    } finally {
      _syncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // UTILITY METHODS
  // ---------------------------------------------------------------------------

  /// Force upload all local data (useful for debugging or manual recovery)
  Future<SyncResult> forceUploadAllData() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No connection or not authenticated');
    }

    _syncing = true;
    try {
      debugPrint('🔄 Force uploading all local data...');

      // Mark all data as unsynced first
      final db = await _dbHelper.database;
      final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger', 'demand_batch', 'demand'];

      for (final table in tables) {
        await db.update(table, {'isSynced': 0}, where: 'isDeleted = 0');
      }

      // Now upload everything
      await _uploadAllLocalChanges();

      return SyncResult(success: true, message: 'All local data uploaded to cloud');
    } catch (e) {
      debugPrint('❌ Force upload failed: $e');
      return SyncResult(success: false, message: 'Force upload failed: $e');
    } finally {
      _syncing = false;
    }
  }

  /// Get sync status information
  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final db = await _dbHelper.database;
      final Map<String, dynamic> status = {};

      final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger'];

      for (final table in tables) {
        final totalCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 0')
        ) ?? 0;

        final unsyncedCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 0 AND isSynced = 0')
        ) ?? 0;

        final deletedCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 1')
        ) ?? 0;

        status[table] = {
          'total': totalCount,
          'unsynced': unsyncedCount,
          'pendingDeletion': deletedCount,
          'syncedPercent': totalCount > 0 ? ((totalCount - unsyncedCount) / totalCount * 100).round() : 100,
        };
      }

      status['canSync'] = await canSync;
      status['isAuthenticated'] = _uid != null;
      status['hasConnection'] = await _isConnected();
      status['isSyncing'] = _syncing; // 2️⃣ Include sync status

      return status;
    } catch (e) {
      debugPrint('❌ Failed to get sync status: $e');
      return {'error': e.toString()};
    }
  }

  /// Clean up old deleted records (optional maintenance)
  Future<void> cleanupDeletedRecords({int daysOld = 30}) async {
    try {
      final db = await _dbHelper.database;
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      final cutoffString = cutoffDate.toIso8601String();

      final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger'];
      int totalCleaned = 0;

      for (final table in tables) {
        final deleted = await db.delete(
          table,
          where: 'isDeleted = 1 AND updatedAt < ?',
          whereArgs: [cutoffString],
        );
        totalCleaned += deleted;
        if (deleted > 0) {
          debugPrint('🧹 Cleaned $deleted old deleted records from $table');
        }
      }

      if (totalCleaned > 0) {
        debugPrint('🧹 Total cleanup: $totalCleaned old deleted records removed');
      }
    } catch (e) {
      debugPrint('❌ Cleanup failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // ERROR RECOVERY
  // ---------------------------------------------------------------------------

  /// Reset sync status (mark all as unsynced for re-upload)
  Future<SyncResult> resetSyncStatus() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync in progress, cannot reset');
    }

    try {
      final db = await _dbHelper.database;
      final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger', 'demand_batch', 'demand'];

      for (final table in tables) {
        await db.update(table, {'isSynced': 0}, where: 'isDeleted = 0');
      }

      debugPrint('🔄 Sync status reset - all data marked for re-upload');
      return SyncResult(success: true, message: 'Sync status reset successfully');
    } catch (e) {
      debugPrint('❌ Reset sync status failed: $e');
      return SyncResult(success: false, message: 'Reset failed: $e');
    }
  }
}

/// Sync operation result class
class SyncResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? details;

  SyncResult({
    required this.success,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'SyncResult(success: $success, message: $message)';
}