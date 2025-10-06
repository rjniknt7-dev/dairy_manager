// lib/services/firebase_sync_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import 'dart:math' as math;

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
  final Uuid _uuid = Uuid();

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

  Future<SyncResult> syncAllData() async {
    if (_syncing) {
      debugPrint('Sync already in progress, skipping...');
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No internet connection or not authenticated');
    }

    _syncing = true;
    try {
      debugPrint('Starting complete sync...');

      await _uploadAllLocalChanges();
      await _downloadAndMergeFromFirebase();

      debugPrint('Complete sync finished successfully');
      return SyncResult(success: true, message: 'Sync completed successfully');
    } catch (e) {
      debugPrint('Sync failed: $e');
      return SyncResult(success: false, message: 'Sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<SyncResult> restoreFromFirebaseIfEmpty() async {
    if (_syncing) {
      debugPrint('Sync in progress, skipping restore...');
      return SyncResult(success: false, message: 'Sync in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No internet connection or not authenticated');
    }

    _syncing = true;
    try {
      final db = await _dbHelper.database;

      final clientCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM clients WHERE isDeleted = 0')
      ) ?? 0;
      final productCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM products WHERE isDeleted = 0')
      ) ?? 0;

      if (clientCount > 0 || productCount > 0) {
        debugPrint('Local DB not empty, skipping restore');
        return SyncResult(success: true, message: 'Local data exists, no restore needed');
      }

      debugPrint('Local DB empty, restoring from Firebase...');
      await _restoreAllDataFromFirebase();

      debugPrint('Data restored from Firebase successfully');
      return SyncResult(success: true, message: 'Data restored from Firebase');
    } catch (e) {
      debugPrint('Restore failed: $e');
      return SyncResult(success: false, message: 'Restore failed: $e');
    } finally {
      _syncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // UPLOAD LOCAL CHANGES TO FIREBASE
  // ---------------------------------------------------------------------------

  Future<void> _uploadAllLocalChanges() async {
    debugPrint('Uploading local changes to Firebase...');

    await _processPendingDeletions();

    await _uploadUnsyncedClients();
    await _uploadUnsyncedProducts();
    await _uploadUnsyncedBills();
    await _uploadUnsyncedBillItems();
    await _uploadUnsyncedLedgerEntries();
    await _uploadUnsyncedDemandBatches();
    await _uploadUnsyncedDemands();

    debugPrint('Local changes uploaded');
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

    debugPrint('Processing ${deletedRows.length} deletions for $table');

    for (final row in deletedRows) {
      final firestoreId = row['firestoreId'] as String?;
      if (firestoreId != null && firestoreId.isNotEmpty) {
        try {
          await col.doc(firestoreId).delete();
          debugPrint('Deleted $table doc: $firestoreId');
        } catch (e) {
          debugPrint('Failed to delete $table doc $firestoreId: $e');
        }
      }

      await db.delete(table, where: 'id = ?', whereArgs: [row['id']]);
    }
  }

  Future<void> _uploadUnsyncedClients() async {
    final col = _col('clients');
    if (col == null) return;

    final unsyncedClients = await _dbHelper.getUnsynced('clients');
    debugPrint('Uploading ${unsyncedClients.length} clients');

    final db = await _dbHelper.database;

    for (final clientMap in unsyncedClients) {
      try {
        final client = Client.fromMap(clientMap);
        String? firestoreId = clientMap['firestoreId'] as String?;

        // Generate UUID if not present
        if (firestoreId == null || firestoreId.isEmpty) {
          firestoreId = _uuid.v4();
        }

        // Upload to Firebase with retry logic
        await _uploadWithRetry(
          col.doc(firestoreId),
          client.toFirestore(),
        );

        // Mark as synced ONLY after successful upload
        await db.update('clients', {
          'firestoreId': firestoreId,
          'isSynced': 1,
        }, where: 'id = ?', whereArgs: [client.id]);

        debugPrint('Uploaded client: ${client.name} -> $firestoreId');
      } catch (e) {
        debugPrint('Failed to upload client: $e - keeping as unsynced');
        // Don't rethrow - continue with other clients
      }
    }
  }

  Future<void> _uploadUnsyncedProducts() async {
    final col = _col('products');
    if (col == null) return;

    final unsyncedProducts = await _dbHelper.getUnsynced('products');
    debugPrint('Uploading ${unsyncedProducts.length} products');

    final db = await _dbHelper.database;

    for (final productMap in unsyncedProducts) {
      try {
        final product = Product.fromMap(productMap);
        String? firestoreId = productMap['firestoreId'] as String?;

        if (firestoreId == null || firestoreId.isEmpty) {
          firestoreId = _uuid.v4();
        }

        await _uploadWithRetry(
          col.doc(firestoreId),
          product.toFirestore(),
        );

        await db.update('products', {
          'firestoreId': firestoreId,
          'isSynced': 1,
        }, where: 'id = ?', whereArgs: [product.id]);

        debugPrint('Uploaded product: ${product.name} -> $firestoreId');
      } catch (e) {
        debugPrint('Failed to upload product: $e');
      }
    }
  }

  Future<void> _uploadUnsyncedBills() async {
    final col = _col('bills');
    if (col == null) return;

    final unsyncedBills = await _dbHelper.getUnsynced('bills');
    debugPrint('Uploading ${unsyncedBills.length} bills');

    final db = await _dbHelper.database;

    for (final billMap in unsyncedBills) {
      try {
        final bill = Bill.fromMap(billMap);
        String? firestoreId = bill.firestoreId;

        if (firestoreId == null || firestoreId.isEmpty) {
          firestoreId = _uuid.v4();
        }

        await _uploadWithRetry(
          col.doc(firestoreId),
          bill.toFirestore(),
        );

        await db.update('bills', {
          'firestoreId': firestoreId,
          'isSynced': 1,
        }, where: 'id = ?', whereArgs: [bill.id]);

        debugPrint('Uploaded bill: #${bill.id} -> $firestoreId');
      } catch (e) {
        debugPrint('Failed to upload bill: $e');
      }
    }
  }

  Future<void> _uploadUnsyncedBillItems() async {
    final col = _col('bill_items');
    if (col == null) return;

    final unsyncedItems = await _dbHelper.getUnsynced('bill_items');
    debugPrint('Uploading ${unsyncedItems.length} bill items');

    final db = await _dbHelper.database;

    for (final itemMap in unsyncedItems) {
      try {
        final item = BillItem.fromMap(itemMap);
        String? firestoreId = itemMap['firestoreId'] as String?;

        if (firestoreId == null || firestoreId.isEmpty) {
          firestoreId = _uuid.v4();
        }

        await _uploadWithRetry(
          col.doc(firestoreId),
          item.toFirestore(),
        );

        await db.update('bill_items', {
          'firestoreId': firestoreId,
          'isSynced': 1,
        }, where: 'id = ?', whereArgs: [item.id]);

        debugPrint('Uploaded bill item: ${item.id} -> $firestoreId');
      } catch (e) {
        debugPrint('Failed to upload bill item: $e');
      }
    }
  }

  Future<void> _uploadUnsyncedLedgerEntries() async {
    final col = _col('ledger');
    if (col == null) return;

    final unsyncedEntries = await _dbHelper.getUnsynced('ledger');
    debugPrint('Uploading ${unsyncedEntries.length} ledger entries');

    final db = await _dbHelper.database;

    for (final entryMap in unsyncedEntries) {
      try {
        final entry = LedgerEntry.fromMap(entryMap);
        String? firestoreId = entryMap['firestoreId'] as String?;

        if (firestoreId == null || firestoreId.isEmpty) {
          firestoreId = _uuid.v4();
        }

        await _uploadWithRetry(
          col.doc(firestoreId),
          entry.toFirestore(),
        );

        await db.update('ledger', {
          'firestoreId': firestoreId,
          'isSynced': 1,
        }, where: 'id = ?', whereArgs: [entry.id]);

        debugPrint('Uploaded ledger entry: ${entry.id} -> $firestoreId');
      } catch (e) {
        debugPrint('Failed to upload ledger entry: $e');
      }
    }
  }

  // --------------------- UPLOAD UNSYNCED DEMAND BATCHES ---------------------
  Future<void> _uploadUnsyncedDemandBatches() async {
    final col = _col('demand_batch');
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced('demand_batch');
    debugPrint('Uploading ${unsynced.length} demand batches');

    final db = await _dbHelper.database;

    for (final batchMap in unsynced) {
      try {
        String? firestoreId = batchMap['firestoreId'] as String?;
        if (firestoreId == null || firestoreId.isEmpty) {
          firestoreId = _uuid.v4();
        }

        final uploadData = Map<String, dynamic>.from(batchMap);
        uploadData.remove('id');
        uploadData['updatedAt'] = DateTime.now().toIso8601String(); // Ensure timestamp is fresh

        await _uploadWithRetry(col.doc(firestoreId), uploadData);

        await db.update('demand_batch', {
          'firestoreId': firestoreId,
          'isSynced': 1,
          'updatedAt': uploadData['updatedAt'],
        }, where: 'id = ?', whereArgs: [batchMap['id']]);

        debugPrint('Uploaded demand batch: ${batchMap['id']} -> $firestoreId');
      } catch (e) {
        debugPrint('Failed to upload demand batch: $e');
      }
    }
  }

  // --------------------- UPLOAD UNSYNCED DEMANDS ---------------------
  Future<void> _uploadUnsyncedDemands() async {
    final col = _col('demand');
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced('demand');
    debugPrint('Uploading ${unsynced.length} demands');

    final db = await _dbHelper.database;

    for (final demandMap in unsynced) {
      try {
        String? firestoreId = demandMap['firestoreId'] as String?;
        if (firestoreId == null || firestoreId.isEmpty) {
          firestoreId = _uuid.v4();
        }

        final uploadData = Map<String, dynamic>.from(demandMap);
        uploadData.remove('id');
        uploadData['updatedAt'] = DateTime.now().toIso8601String(); // Ensure timestamp is fresh

        await _uploadWithRetry(col.doc(firestoreId), uploadData);

        await db.update('demand', {
          'firestoreId': firestoreId,
          'isSynced': 1,
          'updatedAt': uploadData['updatedAt'],
        }, where: 'id = ?', whereArgs: [demandMap['id']]);

        debugPrint('Uploaded demand: ${demandMap['id']} -> $firestoreId');
      } catch (e) {
        debugPrint('Failed to upload demand: $e');
      }
    }
  }

  // Retry logic for Firestore uploads
  Future<void> _uploadWithRetry(
      DocumentReference doc,
      Map<String, dynamic> data,
      {int maxRetries = 3}
      ) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await doc.set(data, SetOptions(merge: true));
        return;
      } catch (e) {
        if (attempt == maxRetries - 1) {
          rethrow;
        }
        final delay = math.pow(2, attempt).toInt();
        debugPrint('Upload failed, retrying in ${delay}s...');
        await Future.delayed(Duration(seconds: delay));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // DOWNLOAD AND MERGE FROM FIREBASE (NON-DESTRUCTIVE WITH TIMESTAMPS)
  // ---------------------------------------------------------------------------

  Future<void> _downloadAndMergeFromFirebase() async {
    debugPrint('Downloading and merging Firebase data...');

    await _downloadAndMergeClients();
    await _downloadAndMergeProducts();
    await _downloadAndMergeBills();
    await _downloadAndMergeBillItems();
    await _downloadAndMergeLedgerEntries();
    await _downloadAndMergeDemandBatches();
    await _downloadAndMergeDemands();

    debugPrint('Firebase data merged');
  }

  Future<void> _downloadAndMergeClients() async {
    final col = _col('clients');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Processing ${snapshot.docs.length} clients from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final client = Client.fromFirestore(doc);
        final remoteUpdated = client.updatedAt;

        final existing = await db.query(
          'clients',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          // New client from Firebase
          final localData = client.copyWith(isSynced: true).toMap();
          localData['firestoreId'] = doc.id;
          localData.remove('id'); // Let SQLite assign new ID

          await db.insert('clients', localData,
              conflictAlgorithm: ConflictAlgorithm.replace);
          debugPrint('Added new client from Firebase: ${client.name}');
        } else {
          final existingRow = existing.first;
          final localUpdated = DateTime.parse(existingRow['updatedAt'] as String);
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          // Only update if remote is newer AND local isn't modified
          if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
            final localData = client.copyWith(isSynced: true).toMap();
            localData['firestoreId'] = doc.id;

            await db.update('clients', localData,
                where: 'id = ?', whereArgs: [existingRow['id']]);
            debugPrint('Updated client from Firebase: ${client.name}');
          } else if (isLocallyModified) {
            debugPrint('Keeping local changes for client: ${client.name}');
          } else {
            debugPrint('Local version is newer, skipping: ${client.name}');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to download clients: $e');
    }
  }

  Future<void> _downloadAndMergeProducts() async {
    final col = _col('products');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Processing ${snapshot.docs.length} products from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final product = Product.fromFirestore(doc);
        final remoteUpdated = product.updatedAt;

        final existing = await db.query(
          'products',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          final localData = product.copyWith(isSynced: true).toMap();
          localData['firestoreId'] = doc.id;
          localData.remove('id');

          await db.insert('products', localData,
              conflictAlgorithm: ConflictAlgorithm.replace);
          debugPrint('Added new product from Firebase: ${product.name}');
        } else {
          final existingRow = existing.first;
          final localUpdated = DateTime.parse(existingRow['updatedAt'] as String);
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
            final localData = product.copyWith(isSynced: true).toMap();
            localData['firestoreId'] = doc.id;

            await db.update('products', localData,
                where: 'id = ?', whereArgs: [existingRow['id']]);
            debugPrint('Updated product from Firebase: ${product.name}');
          } else if (isLocallyModified) {
            debugPrint('Keeping local changes for product: ${product.name}');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to download products: $e');
    }
  }

  Future<void> _downloadAndMergeBills() async {
    final col = _col('bills');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Processing ${snapshot.docs.length} bills from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        final remoteUpdated = data['updatedAt'] != null
            ? DateTime.parse(data['updatedAt'] as String)
            : DateTime.now();

        final existing = await db.query(
          'bills',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          data.remove('id');
          data['firestoreId'] = doc.id;
          data['isSynced'] = 1;

          await db.insert('bills', data,
              conflictAlgorithm: ConflictAlgorithm.replace);
          debugPrint('Added new bill from Firebase');
        } else {
          final existingRow = existing.first;
          final localUpdated = existingRow['updatedAt'] != null
              ? DateTime.parse(existingRow['updatedAt'] as String)
              : DateTime.fromMillisecondsSinceEpoch(0);
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
            final updateData = Map<String, dynamic>.from(data);
            updateData.remove('id');
            updateData['firestoreId'] = doc.id;
            updateData['isSynced'] = 1;

            await db.update('bills', updateData,
                where: 'id = ?', whereArgs: [existingRow['id']]);
            debugPrint('Updated bill from Firebase');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to download bills: $e');
    }
  }

  Future<void> _downloadAndMergeBillItems() async {
    final col = _col('billItems');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Processing ${snapshot.docs.length} bill items from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        final remoteUpdated = data['updatedAt'] != null
            ? DateTime.parse(data['updatedAt'] as String)
            : DateTime.now();

        final existing = await db.query(
          'billItems',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          data.remove('id');
          data['firestoreId'] = doc.id;
          data['isSynced'] = 1;

          await db.insert('billItems', data,
              conflictAlgorithm: ConflictAlgorithm.replace);
          debugPrint('Added new bill item from Firebase');
        } else {
          final existingRow = existing.first;
          final localUpdated = existingRow['updatedAt'] != null
              ? DateTime.parse(existingRow['updatedAt'] as String)
              : DateTime.fromMillisecondsSinceEpoch(0);
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
            final updateData = Map<String, dynamic>.from(data);
            updateData.remove('id');
            updateData['firestoreId'] = doc.id;
            updateData['isSynced'] = 1;

            await db.update('billItems', updateData,
                where: 'id = ?', whereArgs: [existingRow['id']]);
            debugPrint('Updated bill item from Firebase');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to download bill items: $e');
    }
  }

  Future<void> _downloadAndMergeLedgerEntries() async {
    final col = _col('ledger');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Processing ${snapshot.docs.length} ledger entries from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final entry = LedgerEntry.fromFirestore(doc);
        final remoteUpdated = entry.updatedAt;

        final existing = await db.query(
          'ledger',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          final localData = entry.copyWith(isSynced: true).toMap();
          localData['firestoreId'] = doc.id;
          localData.remove('id');

          await db.insert('ledger', localData,
              conflictAlgorithm: ConflictAlgorithm.replace);
          debugPrint('Added new ledger entry from Firebase: ${entry.id}');
        } else {
          final existingRow = existing.first;
          final localUpdated = existingRow['updatedAt'] != null
              ? DateTime.parse(existingRow['updatedAt'] as String)
              : DateTime.fromMillisecondsSinceEpoch(0);

          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
            final localData = entry.copyWith(isSynced: true).toMap();
            localData['firestoreId'] = doc.id;
            localData.remove('id');

            await db.update('ledger', localData,
                where: 'id = ?', whereArgs: [existingRow['id']]);
            debugPrint('Updated ledger entry from Firebase: ${entry.id}');
          } else if (isLocallyModified) {
            debugPrint('Keeping local changes for ledger entry: ${entry.id}');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to download ledger entries: $e');
    }
  }


  // --------------------- DOWNLOAD & MERGE DEMAND BATCHES ---------------------
  Future<void> _downloadAndMergeDemandBatches() async {
    final col = _col('demand_batch');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Processing ${snapshot.docs.length} demand batches from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final remoteData = Map<String, dynamic>.from(doc.data());

        // Convert Timestamp -> DateTime
        final remoteUpdated = remoteData['updatedAt'] is Timestamp
            ? (remoteData['updatedAt'] as Timestamp).toDate()
            : DateTime.parse(remoteData['updatedAt'] as String);

        final existing = await db.query(
          'demand_batch',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          // New batch from Firebase
          final localData = Map<String, dynamic>.from(remoteData);
          localData['firestoreId'] = doc.id;
          localData['isSynced'] = 1;
          localData.remove('id'); // Let SQLite assign new ID

          await db.insert('demand_batch', localData, conflictAlgorithm: ConflictAlgorithm.replace);
          debugPrint('Added new demand batch from Firebase: ${doc.id}');
        } else {
          final existingRow = existing.first;
          final localUpdated = DateTime.parse(existingRow['updatedAt'] as String);
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
            final localData = Map<String, dynamic>.from(remoteData);
            localData['firestoreId'] = doc.id;
            localData['isSynced'] = 1;

            await db.update('demand_batch', localData, where: 'id = ?', whereArgs: [existingRow['id']]);
            debugPrint('Updated demand batch from Firebase: ${doc.id}');
          } else if (isLocallyModified) {
            debugPrint('Keeping local changes for demand batch: ${doc.id}');
          } else {
            debugPrint('Local version is newer, skipping: ${doc.id}');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to download demand batches: $e');
    }
  }

  // --------------------- DOWNLOAD & MERGE DEMANDS ---------------------
  Future<void> _downloadAndMergeDemands() async {
    final col = _col('demand');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Processing ${snapshot.docs.length} demands from Firebase');

      final db = await _dbHelper.database;

      for (final doc in snapshot.docs) {
        final remoteData = Map<String, dynamic>.from(doc.data());

        // Convert Timestamp -> DateTime
        final remoteUpdated = remoteData['updatedAt'] is Timestamp
            ? (remoteData['updatedAt'] as Timestamp).toDate()
            : DateTime.parse(remoteData['updatedAt'] as String);

        final existing = await db.query(
          'demand',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          // New demand from Firebase
          final localData = Map<String, dynamic>.from(remoteData);
          localData['firestoreId'] = doc.id;
          localData['isSynced'] = 1;
          localData.remove('id'); // Let SQLite assign new ID

          await db.insert('demand', localData, conflictAlgorithm: ConflictAlgorithm.replace);
          debugPrint('Added new demand from Firebase: ${doc.id}');
        } else {
          final existingRow = existing.first;
          final localUpdated = DateTime.parse(existingRow['updatedAt'] as String);
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
            final localData = Map<String, dynamic>.from(remoteData);
            localData['firestoreId'] = doc.id;
            localData['isSynced'] = 1;

            await db.update('demand', localData, where: 'id = ?', whereArgs: [existingRow['id']]);
            debugPrint('Updated demand from Firebase: ${doc.id}');
          } else if (isLocallyModified) {
            debugPrint('Keeping local changes for demand: ${doc.id}');
          } else {
            debugPrint('Local version is newer, skipping: ${doc.id}');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to download demands: $e');
    }
  }


  // ---------------------------------------------------------------------------
  // FRESH INSTALL RESTORE
  // ---------------------------------------------------------------------------

  Future<void> _restoreAllDataFromFirebase() async {
    debugPrint('Starting fresh restore from Firebase...');

    await _restoreClientsFromFirebase();
    await _restoreProductsFromFirebase();
    await _restoreBillsFromFirebase();
    await _restoreBillItemsFromFirebase();
    await _restoreLedgerFromFirebase();
    await _restoreDemandBatchesFromFirebase();
    await _restoreDemandsFromFirebase();

    debugPrint('Fresh restore completed');
  }

  Future<void> _restoreClientsFromFirebase() async {
    final col = _col('clients');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('Restoring ${snapshot.docs.length} clients');

    for (final doc in snapshot.docs) {
      try {
        final client = Client.fromFirestore(doc);

        // Check if already exists to avoid duplicates
        final existing = await db.query(
          'clients',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
        );

        if (existing.isNotEmpty) {
          debugPrint('Client already exists, skipping: ${client.name}');
          continue;
        }

        final localData = client.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;
        localData.remove('id'); // Let SQLite auto-assign

        await db.insert('clients', localData,
            conflictAlgorithm: ConflictAlgorithm.replace);
        debugPrint('Restored client: ${client.name}');
      } catch (e) {
        debugPrint('Failed to restore client: $e');
      }
    }
  }

  Future<void> _restoreProductsFromFirebase() async {
    final col = _col('products');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('Restoring ${snapshot.docs.length} products');

    for (final doc in snapshot.docs) {
      try {
        final product = Product.fromFirestore(doc);

        final existing = await db.query(
          'products',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
        );

        if (existing.isNotEmpty) {
          debugPrint('Product already exists, skipping: ${product.name}');
          continue;
        }

        final localData = product.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;
        localData.remove('id');

        await db.insert('products', localData,
            conflictAlgorithm: ConflictAlgorithm.replace);
        debugPrint('Restored product: ${product.name}');
      } catch (e) {
        debugPrint('Failed to restore product: $e');
      }
    }
  }

  Future<void> _restoreBillsFromFirebase() async {
    final col = _col('bills');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('Restoring ${snapshot.docs.length} bills');

    for (final doc in snapshot.docs) {
      try {
        final bill = Bill.fromFirestore(doc.id, doc.data());

        final existing = await db.query(
          'bills',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
        );

        if (existing.isNotEmpty) {
          debugPrint('Bill already exists, skipping');
          continue;
        }

        final localData = bill.toMap();
        localData['isSynced'] = 1;
        localData.remove('id');

        await db.insert('bills', localData,
            conflictAlgorithm: ConflictAlgorithm.replace);
        debugPrint('Restored bill: #${bill.id}');
      } catch (e) {
        debugPrint('Failed to restore bill: $e');
      }
    }
  }

  Future<void> _restoreBillItemsFromFirebase() async {
    final col = _col('bill_items');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('Restoring ${snapshot.docs.length} bill items');

    for (final doc in snapshot.docs) {
      try {
        final item = BillItem.fromFirestore(doc);

        final existing = await db.query(
          'bill_items',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
        );

        if (existing.isNotEmpty) {
          debugPrint('Bill item already exists, skipping');
          continue;
        }

        final localData = item.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;
        localData.remove('id');

        await db.insert('bill_items', localData,
            conflictAlgorithm: ConflictAlgorithm.replace);
        debugPrint('Restored bill item');
      } catch (e) {
        debugPrint('Failed to restore bill item: $e');
      }
    }
  }

  Future<void> _restoreLedgerFromFirebase() async {
    final col = _col('ledger');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('Restoring ${snapshot.docs.length} ledger entries');

    for (final doc in snapshot.docs) {
      try {
        final entry = LedgerEntry.fromFirestore(doc);

        final existing = await db.query(
          'ledger',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
        );

        if (existing.isNotEmpty) {
          debugPrint('Ledger entry already exists, skipping');
          continue;
        }

        final localData = entry.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;
        localData.remove('id');

        await db.insert('ledger', localData,
            conflictAlgorithm: ConflictAlgorithm.replace);
        debugPrint('Restored ledger entry');
      } catch (e) {
        debugPrint('Failed to restore ledger entry: $e');
      }
    }
  }

  Future<void> _restoreDemandBatchesFromFirebase() async {
    final col = _col('demand_batch');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('Restoring ${snapshot.docs.length} demand batches');

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();

        final existing = await db.query(
          'demand_batch',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
        );

        if (existing.isNotEmpty) {
          debugPrint('Demand batch already exists, skipping');
          continue;
        }

        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;
        data.remove('id');

        await db.insert('demand_batch', data,
            conflictAlgorithm: ConflictAlgorithm.replace);
        debugPrint('Restored demand batch');
      } catch (e) {
        debugPrint('Failed to restore demand batch: $e');
      }
    }
  }

  Future<void> _restoreDemandsFromFirebase() async {
    final col = _col('demand');
    if (col == null) return;

    final snapshot = await col.get();
    final db = await _dbHelper.database;

    debugPrint('Restoring ${snapshot.docs.length} demands');

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();

        final existing = await db.query(
          'demand',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
        );

        if (existing.isNotEmpty) {
          debugPrint('Demand already exists, skipping');
          continue;
        }

        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;
        data.remove('id');

        await db.insert('demand', data,
            conflictAlgorithm: ConflictAlgorithm.replace);
        debugPrint('Restored demand');
      } catch (e) {
        debugPrint('Failed to restore demand: $e');
      }
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
      debugPrint('Syncing clients...');
      await _processTableDeletions('clients');
      await _uploadUnsyncedClients();
      await _downloadAndMergeClients();
      return SyncResult(success: true, message: 'Clients synced successfully');
    } catch (e) {
      debugPrint('Client sync failed: $e');
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
      debugPrint('Syncing products...');
      await _processTableDeletions('products');
      await _uploadUnsyncedProducts();
      await _downloadAndMergeProducts();
      return SyncResult(success: true, message: 'Products synced successfully');
    } catch (e) {
      debugPrint('Product sync failed: $e');
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
      debugPrint('Syncing bills...');
      await _processTableDeletions('bills');
      await _processTableDeletions('bill_items');
      await _uploadUnsyncedBills();
      await _uploadUnsyncedBillItems();
      await _downloadAndMergeBills();
      await _downloadAndMergeBillItems();
      return SyncResult(success: true, message: 'Bills synced successfully');
    } catch (e) {
      debugPrint('Bill sync failed: $e');
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
      debugPrint('Syncing ledger...');
      await _processTableDeletions('ledger');
      await _uploadUnsyncedLedgerEntries();
      await _downloadAndMergeLedgerEntries();
      return SyncResult(success: true, message: 'Ledger synced successfully');
    } catch (e) {
      debugPrint('Ledger sync failed: $e');
      return SyncResult(success: false, message: 'Ledger sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // AUTO SYNC ON APP STARTUP
  // ---------------------------------------------------------------------------

  Future<SyncResult> autoSyncOnStartup() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      debugPrint('Starting in offline mode');
      return SyncResult(success: false, message: 'Starting offline - no connection');
    }

    _syncing = true;
    try {
      debugPrint('Auto sync on startup...');

      final restoreResult = await restoreFromFirebaseIfEmpty();
      if (restoreResult.success && restoreResult.message.contains('restored')) {
        return SyncResult(success: true, message: 'Welcome! Your data has been restored from cloud');
      }

      final syncResult = await syncAllData();
      return SyncResult(
          success: syncResult.success,
          message: syncResult.success ? 'App synced with cloud' : syncResult.message
      );

    } catch (e) {
      debugPrint('Auto sync failed: $e');
      return SyncResult(success: false, message: 'Sync failed, working offline');
    } finally {
      _syncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // UTILITY METHODS
  // ---------------------------------------------------------------------------

  Future<SyncResult> forceUploadAllData() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No connection or not authenticated');
    }

    _syncing = true;
    try {
      debugPrint('Force uploading all local data...');

      final db = await _dbHelper.database;
      final tables = ['clients', 'products', 'bills', 'bill_items', 'ledger', 'demand_batch', 'demand'];

      for (final table in tables) {
        await db.update(table, {'isSynced': 0}, where: 'isDeleted = 0');
      }

      await _uploadAllLocalChanges();

      return SyncResult(success: true, message: 'All local data uploaded to cloud');
    } catch (e) {
      debugPrint('Force upload failed: $e');
      return SyncResult(success: false, message: 'Force upload failed: $e');
    } finally {
      _syncing = false;
    }
  }

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
      status['isSyncing'] = _syncing;

      return status;
    } catch (e) {
      debugPrint('Failed to get sync status: $e');
      return {'error': e.toString()};
    }
  }

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
          debugPrint('Cleaned $deleted old deleted records from $table');
        }
      }

      if (totalCleaned > 0) {
        debugPrint('Total cleanup: $totalCleaned old deleted records removed');
      }
    } catch (e) {
      debugPrint('Cleanup failed: $e');
    }
  }

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

      debugPrint('Sync status reset - all data marked for re-upload');
      return SyncResult(success: true, message: 'Sync status reset successfully');
    } catch (e) {
      debugPrint('Reset sync status failed: $e');
      return SyncResult(success: false, message: 'Reset failed: $e');
    }
  }
}

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