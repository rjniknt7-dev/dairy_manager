import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/client.dart';
import '../models/product.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/ledger_entry.dart';
import 'app_initializer.dart';
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

class FirebaseSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Uuid _uuid = const Uuid();

  // ✅ Thread-safe sync lock
  final _syncLock = <String, bool>{};

  // ✅ Last sync timestamps for incremental sync
  final Map<String, DateTime> _lastSyncTimestamps = {};

  // Collection name constants
  static const String COLLECTION_CLIENTS = 'clients';
  static const String COLLECTION_PRODUCTS = 'products';
  static const String COLLECTION_BILLS = 'bills';
  static const String COLLECTION_BILL_ITEMS = 'bill_items';
  static const String COLLECTION_LEDGER = 'ledger';
  static const String COLLECTION_DEMAND_BATCH = 'demand_batch';
  static const String COLLECTION_DEMAND = 'demand';
  static const String COLLECTION_METADATA = 'metadata';

  static const int CURRENT_SCHEMA_VERSION = 25;
  static const int BATCH_SIZE = 500;
  static const int DOWNLOAD_PAGE_SIZE = 1000;
  static const int MAX_RETRIES = 3;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? _col(String name) {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection(name);
  }

  DocumentReference<Map<String, dynamic>>? _userDoc() {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid);
  }

  Future<bool> _isConnected() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (e) {
      debugPrint('❌ Connectivity check failed: $e');
      return false;
    }
  }

  Future<bool> get canSync async => await _isConnected() && _uid != null;

  // ✅ Thread-safe sync lock
  bool _acquireSyncLock(String operation) {
    if (_syncLock[operation] == true) return false;
    _syncLock[operation] = true;
    return true;
  }

  void _releaseSyncLock(String operation) {
    _syncLock[operation] = false;
  }

  DateTime _asDateTime(dynamic v) {
    try {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (v is Timestamp) return v.toDate();
      if (v is String)
        return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is double) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      return DateTime.fromMillisecondsSinceEpoch(0);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String _asIsoString(dynamic v) => _asDateTime(v).toIso8601String();

  // ========================================================================
  // ✅ MAIN SYNC METHODS WITH RETRY LOGIC
  // ========================================================================

  Future<SyncResult> syncAllData() async {
    if (!_acquireSyncLock('full_sync')) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    try {
      if (!await canSync) {
        return SyncResult(success: false,
            message: 'No internet connection or not authenticated');
      }

      debugPrint('🔄 Starting complete sync...');

      final schemaCheck = await _checkSchemaCompatibility();
      if (!schemaCheck) {
        return SyncResult(
          success: false,
          message: 'Schema version mismatch - please update app',
        );
      }

      // ✅ Execute with retry logic
      await _retryOperation(() => _uploadAllLocalChanges());
      await _retryOperation(() => _downloadAndMergeFromFirebase());

      debugPrint('✅ Sync completed successfully');
      return SyncResult(success: true, message: 'Sync completed successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Sync failed: $e');
      debugPrint('Stack trace: $stackTrace');
      return SyncResult(success: false, message: 'Sync failed: $e');
    } finally {
      _releaseSyncLock('full_sync');
    }
  }

  // ✅ Retry logic for network failures
  Future<T> _retryOperation<T>(Future<T> Function() operation,
      {int maxRetries = MAX_RETRIES}) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) rethrow;

        final delay = Duration(seconds: attempts * 2);
        debugPrint('⚠️ Retry attempt $attempts/$maxRetries after ${delay
            .inSeconds}s delay');
        await Future.delayed(delay);
      }
    }
    throw Exception('Max retries exceeded');
  }

  Future<SyncResult> restoreFromFirebaseIfEmpty() async {
    if (!_acquireSyncLock('restore')) {
      return SyncResult(success: false, message: 'Sync in progress');
    }

    try {
      if (!await canSync) {
        return SyncResult(success: false,
            message: 'No internet connection or not authenticated');
      }

      final db = await _dbHelper.database;

      final clientCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM clients WHERE isDeleted = 0'),
      ) ?? 0;

      final productCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM products WHERE isDeleted = 0'),
      ) ?? 0;

      if (clientCount > 0 || productCount > 0) {
        return SyncResult(
            success: true, message: 'Local data exists, no restore needed');
      }

      debugPrint('📥 Restoring data from Firebase...');
      await _restoreAllDataFromFirebase();

      debugPrint('✅ Data restored successfully');
      return SyncResult(success: true, message: 'Data restored from Firebase');
    } catch (e, stackTrace) {
      debugPrint('❌ Restore failed: $e');
      debugPrint('Stack trace: $stackTrace');
      return SyncResult(success: false, message: 'Restore failed: $e');
    } finally {
      _releaseSyncLock('restore');
    }
  }

  Future<bool> _checkSchemaCompatibility() async {
    try {
      final userDoc = _userDoc();
      if (userDoc == null) return false;

      final metadataSnap = await userDoc.collection(COLLECTION_METADATA).doc(
          'schema').get();

      if (!metadataSnap.exists) {
        await userDoc.collection(COLLECTION_METADATA).doc('schema').set({
          'version': CURRENT_SCHEMA_VERSION,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return true;
      }

      final remoteVersion = metadataSnap.data()?['version'] as int? ?? 0;

      if (remoteVersion != CURRENT_SCHEMA_VERSION) {
        debugPrint(
            '⚠️ Schema mismatch: local=$CURRENT_SCHEMA_VERSION, remote=$remoteVersion');
        await userDoc.collection(COLLECTION_METADATA).doc('schema').update({
          'version': CURRENT_SCHEMA_VERSION,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return true;
    } catch (e) {
      debugPrint('⚠️ Schema check failed: $e');
      return true;
    }
  }

  // ========================================================================
  // ✅ OPTIMIZED UPLOAD WITH BATCH UPDATES & FK CACHING
  // ========================================================================

  Future<void> _uploadAllLocalChanges() async {
    await _processPendingDeletions();

    await _uploadUnsyncedClients();
    await _uploadUnsyncedProducts();
    await _uploadUnsyncedBills();
    await _uploadUnsyncedBillItems();
    await _uploadUnsyncedLedgerEntries();
    await _uploadUnsyncedDemandBatches();
    await _uploadUnsyncedDemands();
  }

  Future<void> _processPendingDeletions() async {
    await _processTableDeletions(COLLECTION_BILL_ITEMS);
    await _processTableDeletions(COLLECTION_BILLS);
    await _processTableDeletions(COLLECTION_LEDGER);
    await _processTableDeletions(COLLECTION_DEMAND);
    await _processTableDeletions(COLLECTION_DEMAND_BATCH);
    await _processTableDeletions(COLLECTION_PRODUCTS);
    await _processTableDeletions(COLLECTION_CLIENTS);
  }

  Future<void> _processTableDeletions(String table) async {
    final col = _col(table);
    if (col == null) return;

    final db = await _dbHelper.database;
    final deletedRows = await db.query(table, where: 'isDeleted = 1');

    if (deletedRows.isEmpty) return;

    final batch = _firestore.batch();
    int firebaseDeleted = 0;

    // ✅ Batch local deletions
    final localDeleteIds = <int>[];
    final localUpdateIds = <int>[];

    for (final row in deletedRows) {
      final firestoreId = row['firestoreId'] as String?;
      final localId = row['id'] as int;

      if (firestoreId != null && firestoreId.isNotEmpty) {
        try {
          batch.delete(col.doc(firestoreId));
          firebaseDeleted++;
        } catch (e) {
          debugPrint('⚠️ Failed to delete $table/$firestoreId: $e');
        }
      }

      try {
        bool canDelete = true;

        if (table == COLLECTION_CLIENTS) {
          canDelete = await _dbHelper.canHardDeleteClient(localId);
        } else if (table == COLLECTION_PRODUCTS) {
          canDelete = await _dbHelper.canHardDeleteProduct(localId);
        }

        if (canDelete) {
          localDeleteIds.add(localId);
        } else {
          localUpdateIds.add(localId);
        }
      } catch (e) {
        debugPrint('⚠️ Failed to process $table/$localId: $e');
        localUpdateIds.add(localId);
      }
    }

    // ✅ Commit Firestore batch
    if (firebaseDeleted > 0) {
      await batch.commit();
    }

    // ✅ Batch local database operations
    if (localDeleteIds.isNotEmpty || localUpdateIds.isNotEmpty) {
      final localBatch = db.batch();

      if (localDeleteIds.isNotEmpty) {
        for (final id in localDeleteIds) {
          localBatch.delete(table, where: 'id = ?', whereArgs: [id]);
        }
      }

      if (localUpdateIds.isNotEmpty) {
        for (final id in localUpdateIds) {
          localBatch.update(
            table,
            {'isSynced': 1, 'updatedAt': DateTime.now().toIso8601String()},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      await localBatch.commit(noResult: true);
    }

    debugPrint('✅ $table: $firebaseDeleted deleted from cloud, ${localDeleteIds
        .length} removed locally, ${localUpdateIds.length} archived');
  }

  // ✅ OPTIMIZED: Batch local DB updates
  Future<void> _uploadUnsyncedClients() async {
    final col = _col(COLLECTION_CLIENTS);
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced(COLLECTION_CLIENTS);
    if (unsynced.isEmpty) return;

    final db = await _dbHelper.database;
    int uploaded = 0;

    for (int i = 0; i < unsynced.length; i += BATCH_SIZE) {
      final chunk = unsynced.skip(i).take(BATCH_SIZE).toList();
      final firestoreBatch = _firestore.batch();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final client = Client.fromMap(map);
          String firestoreId = map['firestoreId'] as String? ?? _uuid.v4();

          firestoreBatch.set(col.doc(firestoreId), client.toFirestore(),
              SetOptions(merge: true));

          localUpdates.add({
            'localId': client.id,
            'firestoreId': firestoreId,
          });

          uploaded++;
        } catch (e) {
          debugPrint('⚠️ Failed to upload client: $e');
        }
      }

      if (localUpdates.isNotEmpty) {
        await firestoreBatch.commit();

        // ✅ FIXED: Batch local database updates
        final localBatch = db.batch();
        for (final update in localUpdates) {
          localBatch.update(
            COLLECTION_CLIENTS,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
        await localBatch.commit(noResult: true);
      }
    }

    if (uploaded > 0) debugPrint('✅ Uploaded $uploaded clients');
  }

  Future<void> _uploadUnsyncedProducts() async {
    final col = _col(COLLECTION_PRODUCTS);
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced(COLLECTION_PRODUCTS);
    if (unsynced.isEmpty) return;

    final db = await _dbHelper.database;
    int uploaded = 0;

    for (int i = 0; i < unsynced.length; i += BATCH_SIZE) {
      final chunk = unsynced.skip(i).take(BATCH_SIZE).toList();
      final firestoreBatch = _firestore.batch();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final product = Product.fromMap(map);
          String firestoreId = map['firestoreId'] as String? ?? _uuid.v4();

          firestoreBatch.set(col.doc(firestoreId), product.toFirestore(),
              SetOptions(merge: true));

          localUpdates.add({
            'localId': product.id,
            'firestoreId': firestoreId,
          });

          uploaded++;
        } catch (e) {
          debugPrint('⚠️ Failed to upload product: $e');
        }
      }

      if (localUpdates.isNotEmpty) {
        await firestoreBatch.commit();

        final localBatch = db.batch();
        for (final update in localUpdates) {
          localBatch.update(
            COLLECTION_PRODUCTS,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
        await localBatch.commit(noResult: true);
      }
    }

    if (uploaded > 0) debugPrint('✅ Uploaded $uploaded products');
  }

  // ✅ OPTIMIZED: Pre-fetch foreign keys to avoid N+1 queries
  Future<void> _uploadUnsyncedBills() async {
    final col = _col(COLLECTION_BILLS);
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced(COLLECTION_BILLS);
    if (unsynced.isEmpty) return;

    final db = await _dbHelper.database;
    int uploaded = 0,
        skipped = 0;

    // ✅ Pre-fetch all client mappings (fixes N+1 problem)
    final clientIdMap = await _buildClientIdMap(db);

    for (int i = 0; i < unsynced.length; i += BATCH_SIZE) {
      final chunk = unsynced.skip(i).take(BATCH_SIZE).toList();
      final firestoreBatch = _firestore.batch();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final bill = Bill.fromMap(map);
          final localId = bill.id!;

          String firestoreId = bill.firestoreId ?? '';
          if (firestoreId.isEmpty) {
            firestoreId = _uuid.v4();
          }

          // ✅ Use cached map instead of querying
          final clientFirestoreId = clientIdMap[bill.clientId];
          if (clientFirestoreId == null) {
            debugPrint('⚠️ Skipping bill $localId - client ${bill
                .clientId} not synced');
            skipped++;
            continue;
          }

          final upload = bill.toFirestore();
          upload['clientFirestoreId'] = clientFirestoreId;
          upload['updatedAt'] = DateTime.now().toIso8601String();
          upload.remove('clientId');

          firestoreBatch.set(
              col.doc(firestoreId), upload, SetOptions(merge: true));

          localUpdates.add({
            'localId': localId,
            'firestoreId': firestoreId,
          });

          uploaded++;
        } catch (e) {
          debugPrint('⚠️ Failed to prepare bill upload: $e');
          skipped++;
        }
      }

      if (localUpdates.isNotEmpty) {
        await firestoreBatch.commit();

        final localBatch = db.batch();
        for (final update in localUpdates) {
          localBatch.update(
            COLLECTION_BILLS,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
        await localBatch.commit(noResult: true);
      }
    }

    if (uploaded > 0 || skipped > 0) {
      debugPrint('✅ Uploaded $uploaded bills, skipped $skipped (missing refs)');
    }
  }

  // ✅ OPTIMIZED: Pre-fetch foreign keys
  Future<void> _uploadUnsyncedBillItems() async {
    final col = _col(COLLECTION_BILL_ITEMS);
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced(COLLECTION_BILL_ITEMS);
    if (unsynced.isEmpty) return;

    final db = await _dbHelper.database;
    int uploaded = 0,
        skipped = 0;

    // ✅ Pre-fetch all FK mappings
    final billIdMap = await _buildBillIdMap(db);
    final productIdMap = await _buildProductIdMap(db);

    for (int i = 0; i < unsynced.length; i += BATCH_SIZE) {
      final chunk = unsynced.skip(i).take(BATCH_SIZE).toList();
      final firestoreBatch = _firestore.batch();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final item = BillItem.fromMap(map);
          final localId = item.id!;

          String firestoreId = map['firestoreId'] as String? ?? _uuid.v4();

          final billFirestoreId = billIdMap[item.billId];
          final productFirestoreId = productIdMap[item.productId];

          if (billFirestoreId == null || productFirestoreId == null) {
            debugPrint('⚠️ Skipping bill_item $localId - missing references');
            skipped++;
            continue;
          }

          final upload = item.toFirestore();
          upload['billFirestoreId'] = billFirestoreId;
          upload['productFirestoreId'] = productFirestoreId;
          upload['updatedAt'] = DateTime.now().toIso8601String();
          upload.remove('billId');
          upload.remove('productId');

          firestoreBatch.set(
              col.doc(firestoreId), upload, SetOptions(merge: true));

          localUpdates.add({
            'localId': localId,
            'firestoreId': firestoreId,
          });

          uploaded++;
        } catch (e) {
          debugPrint('⚠️ Failed to prepare bill item upload: $e');
          skipped++;
        }
      }

      if (localUpdates.isNotEmpty) {
        await firestoreBatch.commit();

        final localBatch = db.batch();
        for (final update in localUpdates) {
          localBatch.update(
            COLLECTION_BILL_ITEMS,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
        await localBatch.commit(noResult: true);
      }
    }

    if (uploaded > 0 || skipped > 0) {
      debugPrint('✅ Uploaded $uploaded bill items, skipped $skipped');
    }
  }

  Future<void> _uploadUnsyncedLedgerEntries() async {
    final col = _col(COLLECTION_LEDGER);
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced(COLLECTION_LEDGER);
    if (unsynced.isEmpty) return;

    final db = await _dbHelper.database;
    int uploaded = 0,
        skipped = 0;

    final clientIdMap = await _buildClientIdMap(db);
    final billIdMap = await _buildBillIdMap(db);

    for (int i = 0; i < unsynced.length; i += BATCH_SIZE) {
      final chunk = unsynced.skip(i).take(BATCH_SIZE).toList();
      final firestoreBatch = _firestore.batch();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final entry = LedgerEntry.fromMap(map);
          final localId = entry.id!;

          String firestoreId = map['firestoreId'] as String? ?? _uuid.v4();

          final clientFirestoreId = clientIdMap[entry.clientId];
          if (clientFirestoreId == null) {
            debugPrint('⚠️ Skipping ledger $localId - client not synced');
            skipped++;
            continue;
          }

          String? billFirestoreId;
          if (entry.billId != null) {
            billFirestoreId = billIdMap[entry.billId];
          }

          final upload = entry.toFirestore();
          upload['clientFirestoreId'] = clientFirestoreId;
          if (billFirestoreId != null)
            upload['billFirestoreId'] = billFirestoreId;
          upload['updatedAt'] = DateTime.now().toIso8601String();
          upload.remove('clientId');
          upload.remove('billId');

          firestoreBatch.set(
              col.doc(firestoreId), upload, SetOptions(merge: true));

          localUpdates.add({
            'localId': localId,
            'firestoreId': firestoreId,
          });

          uploaded++;
        } catch (e) {
          debugPrint('⚠️ Failed to prepare ledger entry upload: $e');
          skipped++;
        }
      }

      if (localUpdates.isNotEmpty) {
        await firestoreBatch.commit();

        final localBatch = db.batch();
        for (final update in localUpdates) {
          localBatch.update(
            COLLECTION_LEDGER,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
        await localBatch.commit(noResult: true);
      }
    }

    if (uploaded > 0 || skipped > 0) {
      debugPrint('✅ Uploaded $uploaded ledger entries, skipped $skipped');
    }
  }

  Future<void> _uploadUnsyncedDemandBatches() async {
    final col = _col(COLLECTION_DEMAND_BATCH);
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced(COLLECTION_DEMAND_BATCH);
    if (unsynced.isEmpty) return;

    final db = await _dbHelper.database;
    int uploaded = 0;

    for (int i = 0; i < unsynced.length; i += BATCH_SIZE) {
      final chunk = unsynced.skip(i).take(BATCH_SIZE).toList();
      final firestoreBatch = _firestore.batch();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final localId = map['id'];

          String firestoreId = map['firestoreId'] as String? ?? _uuid.v4();

          final upload = Map<String, dynamic>.from(map);
          upload.remove('id');
          upload.remove('isSynced');
          upload['updatedAt'] = DateTime.now().toIso8601String();

          firestoreBatch.set(
              col.doc(firestoreId), upload, SetOptions(merge: true));

          localUpdates.add({
            'localId': localId,
            'firestoreId': firestoreId,
          });

          uploaded++;
        } catch (e) {
          debugPrint('⚠️ Failed to prepare demand batch upload: $e');
        }
      }

      if (localUpdates.isNotEmpty) {
        await firestoreBatch.commit();

        final localBatch = db.batch();
        for (final update in localUpdates) {
          localBatch.update(
            COLLECTION_DEMAND_BATCH,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
        await localBatch.commit(noResult: true);
      }
    }

    if (uploaded > 0) debugPrint('✅ Uploaded $uploaded demand batches');
  }

  Future<void> _uploadUnsyncedDemands() async {
    final col = _col(COLLECTION_DEMAND);
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced(COLLECTION_DEMAND);
    if (unsynced.isEmpty) return;

    final db = await _dbHelper.database;
    int uploaded = 0,
        skipped = 0;

    // ✅ Pre-fetch FK mappings
    final batchIdMap = await _buildDemandBatchIdMap(db);
    final clientIdMap = await _buildClientIdMap(db);
    final productIdMap = await _buildProductIdMap(db);

    for (int i = 0; i < unsynced.length; i += BATCH_SIZE) {
      final chunk = unsynced.skip(i).take(BATCH_SIZE).toList();
      final firestoreBatch = _firestore.batch();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final localId = map['id'] as int;
          String firestoreId = map['firestoreId'] as String? ?? _uuid.v4();

          final batchFirestoreId = batchIdMap[map['batchId'] as int];
          final clientFirestoreId = clientIdMap[map['clientId'] as int];
          final productFirestoreId = productIdMap[map['productId'] as int];

          if (batchFirestoreId == null || clientFirestoreId == null ||
              productFirestoreId == null) {
            debugPrint('⚠️ Skipping demand $localId - parent not synced');
            skipped++;
            continue;
          }

          final uploadData = Map<String, dynamic>.from(map);
          uploadData.remove('id');
          uploadData.remove('isSynced');
          uploadData.remove('batchId');
          uploadData.remove('clientId');
          uploadData.remove('productId');

          uploadData['batchFirestoreId'] = batchFirestoreId;
          uploadData['clientFirestoreId'] = clientFirestoreId;
          uploadData['productFirestoreId'] = productFirestoreId;
          uploadData['updatedAt'] = FieldValue.serverTimestamp();

          firestoreBatch.set(
              col.doc(firestoreId), uploadData, SetOptions(merge: true));

          localUpdates.add({'localId': localId, 'firestoreId': firestoreId});
          uploaded++;
        } catch (e) {
          debugPrint('⚠️ Failed to prepare demand for upload: $e');
          skipped++;
        }
      }

      if (localUpdates.isNotEmpty) {
        await firestoreBatch.commit();

        final localBatch = db.batch();
        for (final update in localUpdates) {
          localBatch.update(
            COLLECTION_DEMAND,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
        await localBatch.commit(noResult: true);
      }
    }

    if (uploaded > 0 || skipped > 0) {
      debugPrint('✅ Uploaded $uploaded demands, skipped $skipped');
    }
  }

  // ========================================================================
  // ✅ HELPER METHODS: Build FK Maps (Solves N+1 Problem)
  // ========================================================================

  Future<Map<int, String>> _buildClientIdMap(Database db) async {
    final rows = await db.query(
      COLLECTION_CLIENTS,
      columns: ['id', 'firestoreId'],
      where: 'firestoreId IS NOT NULL AND firestoreId != ""',
    );
    return {
      for (var row in rows) row['id'] as int: row['firestoreId'] as String
    };
  }

  Future<Map<int, String>> _buildProductIdMap(Database db) async {
    final rows = await db.query(
      COLLECTION_PRODUCTS,
      columns: ['id', 'firestoreId'],
      where: 'firestoreId IS NOT NULL AND firestoreId != ""',
    );
    return {
      for (var row in rows) row['id'] as int: row['firestoreId'] as String
    };
  }

  Future<Map<int, String>> _buildBillIdMap(Database db) async {
    final rows = await db.query(
      COLLECTION_BILLS,
      columns: ['id', 'firestoreId'],
      where: 'firestoreId IS NOT NULL AND firestoreId != ""',
    );
    return {
      for (var row in rows) row['id'] as int: row['firestoreId'] as String
    };
  }

  Future<Map<int, String>> _buildDemandBatchIdMap(Database db) async {
    final rows = await db.query(
      COLLECTION_DEMAND_BATCH,
      columns: ['id', 'firestoreId'],
      where: 'firestoreId IS NOT NULL AND firestoreId != ""',
    );
    return {
      for (var row in rows) row['id'] as int: row['firestoreId'] as String
    };
  }

  // Reverse mappings (Firestore ID -> Local ID)
  Future<Map<String, int>> _buildClientFirestoreToLocalMap(Database db) async {
    final rows = await db.query(
      COLLECTION_CLIENTS,
      columns: ['id', 'firestoreId'],
      where: 'firestoreId IS NOT NULL AND firestoreId != ""',
    );
    return {
      for (var row in rows) row['firestoreId'] as String: row['id'] as int
    };
  }

  Future<Map<String, int>> _buildProductFirestoreToLocalMap(Database db) async {
    final rows = await db.query(
      COLLECTION_PRODUCTS,
      columns: ['id', 'firestoreId'],
      where: 'firestoreId IS NOT NULL AND firestoreId != ""',
    );
    return {
      for (var row in rows) row['firestoreId'] as String: row['id'] as int
    };
  }

  Future<Map<String, int>> _buildBillFirestoreToLocalMap(Database db) async {
    final rows = await db.query(
      COLLECTION_BILLS,
      columns: ['id', 'firestoreId'],
      where: 'firestoreId IS NOT NULL AND firestoreId != ""',
    );
    return {
      for (var row in rows) row['firestoreId'] as String: row['id'] as int
    };
  }

  Future<Map<String, int>> _buildDemandBatchFirestoreToLocalMap(
      Database db) async {
    final rows = await db.query(
      COLLECTION_DEMAND_BATCH,
      columns: ['id', 'firestoreId'],
      where: 'firestoreId IS NOT NULL AND firestoreId != ""',
    );
    return {
      for (var row in rows) row['firestoreId'] as String: row['id'] as int
    };
  }

  // Legacy individual lookup methods (deprecated but kept for compatibility)
  Future<String?> _getClientFirestoreId(Database db, int? clientId) async {
    if (clientId == null) return null;
    final rows = await db.query(
      COLLECTION_CLIENTS,
      columns: ['firestoreId'],
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['firestoreId'] as String?;
  }

  Future<String?> _getProductFirestoreId(Database db, int? productId) async {
    if (productId == null) return null;
    final rows = await db.query(
      COLLECTION_PRODUCTS,
      columns: ['firestoreId'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['firestoreId'] as String?;
  }

  Future<String?> _getBillFirestoreId(Database db, int? billId) async {
    if (billId == null) return null;
    final rows = await db.query(
      COLLECTION_BILLS,
      columns: ['firestoreId'],
      where: 'id = ?',
      whereArgs: [billId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['firestoreId'] as String?;
  }

  Future<int?> _getLocalClientId(Database db, String firestoreId) async {
    final rows = await db.query(
      COLLECTION_CLIENTS,
      columns: ['id'],
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  Future<int?> _getLocalProductId(Database db, String firestoreId) async {
    final rows = await db.query(
      COLLECTION_PRODUCTS,
      columns: ['id'],
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  Future<int?> _getLocalBillId(Database db, String firestoreId) async {
    final rows = await db.query(
      COLLECTION_BILLS,
      columns: ['id'],
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  Future<int?> _getLocalDemandBatchId(Database db, String firestoreId) async {
    final rows = await db.query(
      COLLECTION_DEMAND_BATCH,
      columns: ['id'],
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  // ========================================================================
  // ✅ OPTIMIZED DOWNLOAD WITH PAGINATION & INCREMENTAL SYNC
  // ========================================================================

  Future<void> _downloadAndMergeFromFirebase() async {
    await _downloadAndMergeClients();
    await _downloadAndMergeProducts();
    await _downloadAndMergeBills();
    await _downloadAndMergeBillItems();
    await _downloadAndMergeLedgerEntries();
    await _downloadAndMergeDemandBatches();
    await _downloadAndMergeDemands();

    // ✅ Use transaction for multi-step operations
    await _processDownloadedBillsInTransaction();
    await _recalculateClientBalances();
  }

  // ✅ OPTIMIZED: Paginated download with incremental sync
  Future<void> _downloadAndMergeClients() async {
    final col = _col(COLLECTION_CLIENTS);
    if (col == null) return;

    try {
      // ✅ Incremental sync: only fetch updated records
      final lastSync = _lastSyncTimestamps[COLLECTION_CLIENTS];
      Query<Map<String, dynamic>> query = col;

      if (lastSync != null) {
        query = query.where(
            'updatedAt', isGreaterThan: Timestamp.fromDate(lastSync));
        debugPrint(
            '📥 Incremental sync: fetching clients updated after $lastSync');
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) {
        debugPrint('✅ No new clients to sync');
        return;
      }

      final db = await _dbHelper.database;
      int added = 0,
          updated = 0,
          skipped = 0;

      // ✅ Use transaction for batch inserts
      await db.transaction((txn) async {
        for (final doc in snapshot.docs) {
          final client = Client.fromFirestore(doc);
          final remoteUpdated = client.updatedAt;

          final existing = await txn.query(
            COLLECTION_CLIENTS,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
            limit: 1,
          );

          if (existing.isEmpty) {
            final localData = client.copyWith(isSynced: true).toMap();
            localData['firestoreId'] = doc.id;
            localData['updatedAt'] = _asIsoString(localData['updatedAt']);
            localData.remove('id');

            await txn.insert(COLLECTION_CLIENTS, localData,
                conflictAlgorithm: ConflictAlgorithm.replace);
            added++;
          } else {
            final existingRow = existing.first;
            final localUpdated = _asDateTime(existingRow['updatedAt']);
            final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) ==
                0;

            if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
              final localData = client.copyWith(isSynced: true).toMap();
              localData['firestoreId'] = doc.id;
              localData['updatedAt'] = _asIsoString(localData['updatedAt']);

              await txn.update(COLLECTION_CLIENTS, localData, where: 'id = ?',
                  whereArgs: [existingRow['id']]);
              updated++;
            } else {
              skipped++;
            }
          }
        }
      });

      _lastSyncTimestamps[COLLECTION_CLIENTS] = DateTime.now();

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint('✅ Clients: $added new, $updated updated, $skipped skipped');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to download clients: $e');
    }
  }

  Future<void> _downloadAndMergeProducts() async {
    final col = _col(COLLECTION_PRODUCTS);
    if (col == null) return;

    try {
      final lastSync = _lastSyncTimestamps[COLLECTION_PRODUCTS];
      Query<Map<String, dynamic>> query = col;

      if (lastSync != null) {
        query = query.where(
            'updatedAt', isGreaterThan: Timestamp.fromDate(lastSync));
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;
      int added = 0,
          updated = 0,
          skipped = 0;

      await db.transaction((txn) async {
        for (final doc in snapshot.docs) {
          final product = Product.fromFirestore(doc);
          final remoteUpdated = product.updatedAt;

          final existing = await txn.query(
            COLLECTION_PRODUCTS,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
            limit: 1,
          );

          if (existing.isEmpty) {
            final localData = product.copyWith(isSynced: true).toMap();
            localData['firestoreId'] = doc.id;
            localData['updatedAt'] = _asIsoString(localData['updatedAt']);
            localData.remove('id');

            await txn.insert(COLLECTION_PRODUCTS, localData,
                conflictAlgorithm: ConflictAlgorithm.replace);
            added++;
          } else {
            final existingRow = existing.first;
            final localUpdated = _asDateTime(existingRow['updatedAt']);
            final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) ==
                0;

            if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
              final localData = product.copyWith(isSynced: true).toMap();
              localData['firestoreId'] = doc.id;
              localData['updatedAt'] = _asIsoString(localData['updatedAt']);

              await txn.update(COLLECTION_PRODUCTS, localData, where: 'id = ?',
                  whereArgs: [existingRow['id']]);
              updated++;
            } else if (isLocallyModified) {
              debugPrint('⚠️ Stock conflict for ${product
                  .name} - keeping local value');
              skipped++;
            } else {
              skipped++;
            }
          }
        }
      });

      _lastSyncTimestamps[COLLECTION_PRODUCTS] = DateTime.now();

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint(
            '✅ Products: $added new, $updated updated, $skipped skipped');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to download products: $e');
    }
  }

  // ✅ OPTIMIZED: Pre-build FK maps before processing
  Future<void> _downloadAndMergeBills() async {
    final col = _col(COLLECTION_BILLS);
    if (col == null) return;

    try {
      final lastSync = _lastSyncTimestamps[COLLECTION_BILLS];
      Query<Map<String, dynamic>> query = col;

      if (lastSync != null) {
        query = query.where(
            'updatedAt', isGreaterThan: Timestamp.fromDate(lastSync));
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;

      // ✅ Pre-fetch FK map
      final clientFirestoreToLocalMap = await _buildClientFirestoreToLocalMap(
          db);

      int added = 0,
          updated = 0,
          skipped = 0;

      await db.transaction((txn) async {
        for (final doc in snapshot.docs) {
          try {
            final rawData = doc.data();

            final data = <String, dynamic>{
              'totalAmount': (rawData['totalAmount'] is num)
                  ? (rawData['totalAmount'] as num).toDouble()
                  : 0.0,
              'paidAmount': (rawData['paidAmount'] is num)
                  ? (rawData['paidAmount'] as num).toDouble()
                  : 0.0,
              'carryForward': (rawData['carryForward'] is num)
                  ? (rawData['carryForward'] as num).toDouble()
                  : 0.0,
              'discount': (rawData['discount'] is num)
                  ? (rawData['discount'] as num).toDouble()
                  : 0.0,
              'tax': (rawData['tax'] is num) ? (rawData['tax'] as num)
                  .toDouble() : 0.0,
              'paymentStatus': rawData['paymentStatus'] as String? ?? 'pending',
              'notes': rawData['notes'] as String?,
              'isDeleted': (rawData['isDeleted'] == true ||
                  rawData['isDeleted'] == 1) ? 1 : 0,
            };

            data['date'] = _asIsoString(rawData['date']);
            data['updatedAt'] = _asIsoString(rawData['updatedAt']);
            data['createdAt'] =
                _asIsoString(rawData['createdAt'] ?? rawData['updatedAt']);
            if (rawData['dueDate'] != null) {
              data['dueDate'] = _asIsoString(rawData['dueDate']);
            }

            final clientFirestoreId = rawData['clientFirestoreId'] as String?;
            if (clientFirestoreId == null || clientFirestoreId.isEmpty) {
              debugPrint(
                  '⚠️ Skipping bill ${doc.id} - missing clientFirestoreId');
              skipped++;
              continue;
            }

            // ✅ Use pre-built map instead of individual query
            final localClientId = clientFirestoreToLocalMap[clientFirestoreId];
            if (localClientId == null) {
              debugPrint(
                  '⚠️ Skipping bill ${doc.id} - client not found locally');
              skipped++;
              continue;
            }

            data['clientId'] = localClientId;

            final remoteUpdated = _asDateTime(rawData['updatedAt']);

            final existing = await txn.query(
              COLLECTION_BILLS,
              where: 'firestoreId = ?',
              whereArgs: [doc.id],
              limit: 1,
            );

            if (existing.isEmpty) {
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1;

              await txn.insert(COLLECTION_BILLS, data,
                  conflictAlgorithm: ConflictAlgorithm.replace);
              added++;
            } else {
              final existingRow = existing.first;
              final localUpdated = _asDateTime(existingRow['updatedAt']);
              final isLocallyModified = (existingRow['isSynced'] as int? ??
                  1) == 0;

              if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
                data['firestoreId'] = doc.id;
                data['isSynced'] = 1;

                await txn.update(COLLECTION_BILLS, data, where: 'id = ?',
                    whereArgs: [existingRow['id']]);
                updated++;
              } else {
                skipped++;
              }
            }
          } catch (e, st) {
            debugPrint('! Failed to process bill ${doc.id}: $e');
            debugPrint('Stack: $st');
            skipped++;
          }
        }
      });

      _lastSyncTimestamps[COLLECTION_BILLS] = DateTime.now();

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint('✅ Bills: $added new, $updated updated, $skipped skipped');
      }
    } catch (e, st) {
      debugPrint('❌ Failed to download bills: $e');
      debugPrint('Stack: $st');
    }
  }

  Future<void> _downloadAndMergeBillItems() async {
    final col = _col(COLLECTION_BILL_ITEMS);
    if (col == null) return;

    try {
      final lastSync = _lastSyncTimestamps[COLLECTION_BILL_ITEMS];
      Query<Map<String, dynamic>> query = col;

      if (lastSync != null) {
        query = query.where(
            'updatedAt', isGreaterThan: Timestamp.fromDate(lastSync));
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;

      // ✅ Pre-fetch FK maps
      final billFirestoreToLocalMap = await _buildBillFirestoreToLocalMap(db);
      final productFirestoreToLocalMap = await _buildProductFirestoreToLocalMap(
          db);

      int added = 0,
          updated = 0,
          skipped = 0;

      await db.transaction((txn) async {
        for (final doc in snapshot.docs) {
          try {
            final rawData = doc.data();

            final data = <String, dynamic>{
              'quantity': (rawData['quantity'] is num)
                  ? (rawData['quantity'] as num).toDouble()
                  : 0.0,
              'price': (rawData['price'] is num) ? (rawData['price'] as num)
                  .toDouble() : 0.0,
              'discount': (rawData['discount'] is num)
                  ? (rawData['discount'] as num).toDouble()
                  : 0.0,
              'tax': (rawData['tax'] is num) ? (rawData['tax'] as num)
                  .toDouble() : 0.0,
              'isDeleted': (rawData['isDeleted'] == true ||
                  rawData['isDeleted'] == 1) ? 1 : 0,
            };

            data['updatedAt'] = _asIsoString(rawData['updatedAt']);
            data['createdAt'] =
                _asIsoString(rawData['createdAt'] ?? rawData['updatedAt']);

            final billFirestoreId = rawData['billFirestoreId'] as String?;
            final productFirestoreId = rawData['productFirestoreId'] as String?;

            if (billFirestoreId == null || productFirestoreId == null) {
              debugPrint(
                  '⚠️ Skipping bill_item ${doc.id} - missing references');
              skipped++;
              continue;
            }

            final localBillId = billFirestoreToLocalMap[billFirestoreId];
            final localProductId = productFirestoreToLocalMap[productFirestoreId];

            if (localBillId == null || localProductId == null) {
              debugPrint('⚠️ Skipping bill_item ${doc
                  .id} - references not found locally');
              skipped++;
              continue;
            }

            data['billId'] = localBillId;
            data['productId'] = localProductId;

            final remoteUpdated = _asDateTime(rawData['updatedAt']);

            final existing = await txn.query(
              COLLECTION_BILL_ITEMS,
              where: 'firestoreId = ?',
              whereArgs: [doc.id],
              limit: 1,
            );

            if (existing.isEmpty) {
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1;

              await txn.insert(COLLECTION_BILL_ITEMS, data,
                  conflictAlgorithm: ConflictAlgorithm.replace);
              added++;
            } else {
              final existingRow = existing.first;
              final localUpdated = _asDateTime(existingRow['updatedAt']);
              final isLocallyModified = (existingRow['isSynced'] as int? ??
                  1) == 0;

              if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
                data['firestoreId'] = doc.id;
                data['isSynced'] = 1;

                await txn.update(COLLECTION_BILL_ITEMS, data, where: 'id = ?',
                    whereArgs: [existingRow['id']]);
                updated++;
              } else {
                skipped++;
              }
            }
          } catch (e, st) {
            debugPrint('! Failed to process bill item ${doc.id}: $e');
            debugPrint('Stack: $st');
            skipped++;
          }
        }
      });

      _lastSyncTimestamps[COLLECTION_BILL_ITEMS] = DateTime.now();

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint(
            '✅ Bill items: $added new, $updated updated, $skipped skipped');
      }
    } catch (e, st) {
      debugPrint('❌ Failed to download bill items: $e');
      debugPrint('Stack: $st');
    }
  }

  Future<void> _downloadAndMergeLedgerEntries() async {
    final col = _col(COLLECTION_LEDGER);
    if (col == null) return;

    try {
      final lastSync = _lastSyncTimestamps[COLLECTION_LEDGER];
      Query<Map<String, dynamic>> query = col;

      if (lastSync != null) {
        query = query.where(
            'updatedAt', isGreaterThan: Timestamp.fromDate(lastSync));
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;

      // ✅ Pre-fetch FK maps
      final clientFirestoreToLocalMap = await _buildClientFirestoreToLocalMap(
          db);
      final billFirestoreToLocalMap = await _buildBillFirestoreToLocalMap(db);

      int added = 0,
          updated = 0,
          skipped = 0;

      await db.transaction((txn) async {
        for (final doc in snapshot.docs) {
          try {
            final rawData = doc.data();

            final data = <String, dynamic>{
              'type': rawData['type'] as String? ?? 'debit',
              'amount': (rawData['amount'] is num) ? (rawData['amount'] as num)
                  .toDouble() : 0.0,
              'note': rawData['note'] as String? ??
                  rawData['description'] as String?,
              'paymentMethod': rawData['paymentMethod'] as String?,
              'referenceNumber': rawData['referenceNumber'] as String?,
              'isDeleted': (rawData['isDeleted'] == true ||
                  rawData['isDeleted'] == 1) ? 1 : 0,
            };

            data['date'] = _asIsoString(rawData['date']);
            data['updatedAt'] = _asIsoString(rawData['updatedAt']);
            data['createdAt'] =
                _asIsoString(rawData['createdAt'] ?? rawData['updatedAt']);

            final clientFirestoreId = rawData['clientFirestoreId'] as String?;
            if (clientFirestoreId == null) {
              debugPrint(
                  '⚠️ Skipping ledger ${doc.id} - missing clientFirestoreId');
              skipped++;
              continue;
            }

            final localClientId = clientFirestoreToLocalMap[clientFirestoreId];
            if (localClientId == null) {
              debugPrint(
                  '⚠️ Skipping ledger ${doc.id} - client not found locally');
              skipped++;
              continue;
            }

            data['clientId'] = localClientId;

            final billFirestoreId = rawData['billFirestoreId'] as String?;
            if (billFirestoreId != null) {
              final localBillId = billFirestoreToLocalMap[billFirestoreId];
              if (localBillId != null) {
                data['billId'] = localBillId;
              }
            }

            final remoteUpdated = _asDateTime(rawData['updatedAt']);

            final existing = await txn.query(
              COLLECTION_LEDGER,
              where: 'firestoreId = ?',
              whereArgs: [doc.id],
              limit: 1,
            );

            if (existing.isEmpty) {
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1;

              await txn.insert(COLLECTION_LEDGER, data,
                  conflictAlgorithm: ConflictAlgorithm.replace);
              added++;
            } else {
              final existingRow = existing.first;
              final localUpdated = _asDateTime(existingRow['updatedAt']);
              final isLocallyModified = (existingRow['isSynced'] as int? ??
                  1) == 0;

              if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
                data['firestoreId'] = doc.id;
                data['isSynced'] = 1;

                await txn.update(COLLECTION_LEDGER, data, where: 'id = ?',
                    whereArgs: [existingRow['id']]);
                updated++;
              } else {
                skipped++;
              }
            }
          } catch (e, st) {
            debugPrint('! Failed to process ledger entry ${doc.id}: $e');
            debugPrint('Stack: $st');
            skipped++;
          }
        }
      });

      _lastSyncTimestamps[COLLECTION_LEDGER] = DateTime.now();

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint('✅ Ledger: $added new, $updated updated, $skipped skipped');
      }
    } catch (e, st) {
      debugPrint('❌ Failed to download ledger: $e');
      debugPrint('Stack: $st');
    }
  }

  Future<void> _downloadAndMergeDemandBatches() async {
    final col = _col(COLLECTION_DEMAND_BATCH);
    if (col == null) return;

    try {
      final lastSync = _lastSyncTimestamps[COLLECTION_DEMAND_BATCH];
      Query<Map<String, dynamic>> query = col;

      if (lastSync != null) {
        query = query.where(
            'updatedAt', isGreaterThan: Timestamp.fromDate(lastSync));
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;
      int added = 0,
          updated = 0,
          skipped = 0;

      await db.transaction((txn) async {
        for (final doc in snapshot.docs) {
          try {
            final data = Map<String, dynamic>.from(doc.data());

            data['updatedAt'] = _asIsoString(data['updatedAt']);
            if (data.containsKey('demandDate')) {
              data['demandDate'] = _asIsoString(data['demandDate']);
            }

            final remoteUpdated = _asDateTime(data['updatedAt']);

            final existing = await txn.query(
              COLLECTION_DEMAND_BATCH,
              where: 'firestoreId = ?',
              whereArgs: [doc.id],
              limit: 1,
            );

            if (existing.isEmpty) {
              data.remove('id');
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1;

              await txn.insert(COLLECTION_DEMAND_BATCH, data,
                  conflictAlgorithm: ConflictAlgorithm.replace);
              added++;
            } else {
              final existingRow = existing.first;
              final localUpdated = _asDateTime(existingRow['updatedAt']);
              final isLocallyModified = (existingRow['isSynced'] as int? ??
                  1) == 0;

              if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
                final updateData = Map<String, dynamic>.from(data);
                updateData.remove('id');
                updateData['firestoreId'] = doc.id;
                updateData['isSynced'] = 1;

                await txn.update(
                    COLLECTION_DEMAND_BATCH, updateData, where: 'id = ?',
                    whereArgs: [existingRow['id']]);
                updated++;
              } else {
                skipped++;
              }
            }
          } catch (e) {
            debugPrint('⚠️ Failed to process demand_batch ${doc.id}: $e');
            skipped++;
          }
        }
      });

      _lastSyncTimestamps[COLLECTION_DEMAND_BATCH] = DateTime.now();

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint(
            '✅ Demand batches: $added new, $updated updated, $skipped skipped');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to download demand batches: $e');
    }
  }

  Future<void> _downloadAndMergeDemands() async {
    final col = _col(COLLECTION_DEMAND);
    if (col == null) return;

    try {
      final lastSync = _lastSyncTimestamps[COLLECTION_DEMAND];
      Query<Map<String, dynamic>> query = col;

      if (lastSync != null) {
        query = query.where(
            'updatedAt', isGreaterThan: Timestamp.fromDate(lastSync));
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;

      // ✅ Pre-fetch FK maps
      final batchFirestoreToLocalMap = await _buildDemandBatchFirestoreToLocalMap(
          db);
      final clientFirestoreToLocalMap = await _buildClientFirestoreToLocalMap(
          db);
      final productFirestoreToLocalMap = await _buildProductFirestoreToLocalMap(
          db);

      int added = 0,
          updated = 0,
          skipped = 0;

      await db.transaction((txn) async {
        for (final doc in snapshot.docs) {
          try {
            final rawData = doc.data();

            final data = <String, dynamic>{
              'quantity': (rawData['quantity'] as num?)?.toDouble() ?? 0.0,
              'isDeleted': (rawData['isDeleted'] == true ||
                  rawData['isDeleted'] == 1) ? 1 : 0,
            };

            data['date'] = _asIsoString(rawData['date']);
            data['updatedAt'] = _asIsoString(rawData['updatedAt']);
            if (rawData.containsKey('createdAt')) {
              data['createdAt'] = _asIsoString(rawData['createdAt']);
            }

            final batchFirestoreId = rawData['batchFirestoreId'] as String?;
            final clientFirestoreId = rawData['clientFirestoreId'] as String?;
            final productFirestoreId = rawData['productFirestoreId'] as String?;

            if (batchFirestoreId == null || clientFirestoreId == null ||
                productFirestoreId == null) {
              debugPrint('⚠️ Skipping demand ${doc
                  .id} - missing one or more parent Firestore IDs.');
              skipped++;
              continue;
            }

            final localBatchId = batchFirestoreToLocalMap[batchFirestoreId];
            final localClientId = clientFirestoreToLocalMap[clientFirestoreId];
            final localProductId = productFirestoreToLocalMap[productFirestoreId];

            if (localBatchId == null || localClientId == null ||
                localProductId == null) {
              debugPrint('⚠️ Skipping demand ${doc
                  .id} - parent records not found locally.');
              skipped++;
              continue;
            }

            data['batchId'] = localBatchId;
            data['clientId'] = localClientId;
            data['productId'] = localProductId;

            final remoteUpdated = _asDateTime(rawData['updatedAt']);

            final existing = await txn.query(
              COLLECTION_DEMAND,
              where: 'firestoreId = ?',
              whereArgs: [doc.id],
              limit: 1,
            );

            if (existing.isEmpty) {
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1;
              await txn.insert(COLLECTION_DEMAND, data,
                  conflictAlgorithm: ConflictAlgorithm.replace);
              added++;
            } else {
              final existingRow = existing.first;
              final localUpdated = _asDateTime(existingRow['updatedAt']);
              final isLocallyModified = (existingRow['isSynced'] as int? ??
                  1) == 0;

              if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
                data['firestoreId'] = doc.id;
                data['isSynced'] = 1;
                await txn.update(COLLECTION_DEMAND, data, where: 'id = ?',
                    whereArgs: [existingRow['id']]);
                updated++;
              } else {
                skipped++;
              }
            }
          } catch (e) {
            debugPrint('! Failed to process demand ${doc.id}: $e');
            skipped++;
          }
        }
      });

      _lastSyncTimestamps[COLLECTION_DEMAND] = DateTime.now();

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint('✅ Demands: $added new, $updated updated, $skipped skipped');
      }
    } catch (e) {
      debugPrint('❌ Failed to download demands: $e');
    }
  }

  // ========================================================================
  // ✅ PROCESS DOWNLOADED BILLS IN TRANSACTION (Atomic Operation)
  // ========================================================================

  Future<void> _processDownloadedBillsInTransaction() async {
    final db = await _dbHelper.database;

    final billsWithoutLedger = await db.rawQuery('''
      SELECT b.*, c.id as localClientId 
      FROM bills b
      JOIN clients c ON b.clientId = c.id
      WHERE b.isDeleted = 0 
        AND b.isSynced = 1
        AND NOT EXISTS (
          SELECT 1 FROM ledger l 
          WHERE l.billId = b.id AND l.type = 'bill' AND l.isDeleted = 0
        )
    ''');

    if (billsWithoutLedger.isEmpty) return;

    debugPrint('📥 Processing ${billsWithoutLedger
        .length} downloaded bills for ledger entries and stock updates');

    // ✅ Use transaction for atomicity
    await db.transaction((txn) async {
      for (final billMap in billsWithoutLedger) {
        final billId = billMap['id'] as int;
        final clientId = billMap['localClientId'] as int;
        final totalAmount = (billMap['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final billDate = billMap['date'] as String;

        try {
          // 1. Create ledger entry for the bill
          await txn.insert('ledger', {
            'clientId': clientId,
            'billId': billId,
            'type': 'bill',
            'amount': totalAmount,
            'date': billDate,
            'note': 'Bill #$billId',
            'isSynced': 1,
            'updatedAt': DateTime.now().toIso8601String(),
            'createdAt': DateTime.now().toIso8601String(),
          });

          // 2. Get bill items
          final billItems = await txn.query(
            'bill_items',
            where: 'billId = ? AND isDeleted = 0',
            whereArgs: [billId],
          );

          // ✅ Batch stock updates
          for (final itemMap in billItems) {
            final productId = itemMap['productId'] as int;
            final quantity = (itemMap['quantity'] as num).toDouble();

            await txn.rawUpdate(
              'UPDATE products SET stock = stock - ?, isSynced = 0, updatedAt = ? WHERE id = ?',
              [quantity, DateTime.now().toIso8601String(), productId],
            );
          }

          debugPrint('✅ Processed downloaded bill $billId with ${billItems
              .length} items');
        } catch (e) {
          debugPrint('❌ Failed to process downloaded bill $billId: $e');
          rethrow; // ✅ Rollback transaction on error
        }
      }
    });

    debugPrint('✅ Successfully processed ${billsWithoutLedger
        .length} bills in transaction');
  }

  // ✅ Recalculate client balances
  Future<void> _recalculateClientBalances() async {
    final db = await _dbHelper.database;

    final clients = await db.query('clients', where: 'isDeleted = 0');

    for (final client in clients) {
      final clientId = client['id'] as int;

      final balanceResult = await db.rawQuery('''
        SELECT 
          SUM(CASE WHEN type = 'bill' THEN amount ELSE 0 END) as totalBilled,
          SUM(CASE WHEN type = 'payment' THEN amount ELSE 0 END) as totalPaid
        FROM ledger 
        WHERE clientId = ? AND isDeleted = 0
      ''', [clientId]);

      if (balanceResult.isNotEmpty) {
        final totalBilled = (balanceResult.first['totalBilled'] as num?)
            ?.toDouble() ?? 0.0;
        final totalPaid = (balanceResult.first['totalPaid'] as num?)
            ?.toDouble() ?? 0.0;
        final balance = totalBilled - totalPaid;

        final currentBalance = (client['balance'] as num?)?.toDouble() ?? 0.0;
        if (currentBalance != balance) {
          await db.update(
            'clients',
            {
              'balance': balance,
              'updatedAt': DateTime.now().toIso8601String(),
              'isSynced': 0,
            },
            where: 'id = ?',
            whereArgs: [clientId],
          );
        }
      }
    }

    debugPrint('✅ Recalculated balances for ${clients.length} clients');
  }

  // ========================================================================
  // FRESH INSTALL RESTORE
  // ========================================================================

  Future<void> _restoreAllDataFromFirebase() async {
    await _downloadAndMergeFromFirebase();
  }

  Future<void> _restoreClientsFromFirebase() => _downloadAndMergeClients();

  Future<void> _restoreProductsFromFirebase() => _downloadAndMergeProducts();

  Future<void> _restoreBillsFromFirebase() => _downloadAndMergeBills();

  Future<void> _restoreBillItemsFromFirebase() => _downloadAndMergeBillItems();

  Future<void> _restoreLedgerFromFirebase() => _downloadAndMergeLedgerEntries();

  Future<void> _restoreDemandBatchesFromFirebase() =>
      _downloadAndMergeDemandBatches();

  Future<void> _restoreDemandsFromFirebase() => _downloadAndMergeDemands();

  // ========================================================================
  // INDIVIDUAL SYNC
  // ========================================================================

  Future<SyncResult> syncClients() async {
    if (!_acquireSyncLock('clients')) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    try {
      if (!await canSync) {
        return SyncResult(
            success: false, message: 'No connection or not authenticated');
      }

      await _processTableDeletions(COLLECTION_CLIENTS);
      await _uploadUnsyncedClients();
      await _downloadAndMergeClients();
      return SyncResult(success: true, message: 'Clients synced successfully');
    } catch (e) {
      return SyncResult(success: false, message: 'Client sync failed: $e');
    } finally {
      _releaseSyncLock('clients');
    }
  }

  Future<SyncResult> syncProducts() async {
    if (!_acquireSyncLock('products')) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    try {
      if (!await canSync) {
        return SyncResult(
            success: false, message: 'No connection or not authenticated');
      }

      await _processTableDeletions(COLLECTION_PRODUCTS);
      await _uploadUnsyncedProducts();
      await _downloadAndMergeProducts();
      return SyncResult(success: true, message: 'Products synced successfully');
    } catch (e) {
      return SyncResult(success: false, message: 'Product sync failed: $e');
    } finally {
      _releaseSyncLock('products');
    }
  }

  Future<SyncResult> syncBills() async {
    if (!_acquireSyncLock('bills')) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    try {
      if (!await canSync) {
        return SyncResult(
            success: false, message: 'No connection or not authenticated');
      }

      await _processTableDeletions(COLLECTION_BILLS);
      await _processTableDeletions(COLLECTION_BILL_ITEMS);
      await _uploadUnsyncedBills();
      await _uploadUnsyncedBillItems();
      await _downloadAndMergeBills();
      await _downloadAndMergeBillItems();
      return SyncResult(success: true, message: 'Bills synced successfully');
    } catch (e) {
      return SyncResult(success: false, message: 'Bill sync failed: $e');
    } finally {
      _releaseSyncLock('bills');
    }
  }

  Future<SyncResult> syncLedger() async {
    if (!_acquireSyncLock('ledger')) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    try {
      if (!await canSync) {
        return SyncResult(
            success: false, message: 'No connection or not authenticated');
      }

      await _processTableDeletions(COLLECTION_LEDGER);
      await _uploadUnsyncedLedgerEntries();
      await _downloadAndMergeLedgerEntries();
      return SyncResult(success: true, message: 'Ledger synced successfully');
    } catch (e) {
      return SyncResult(success: false, message: 'Ledger sync failed: $e');
    } finally {
      _releaseSyncLock('ledger');
    }
  }

  // ========================================================================
  // AUTO SYNC
  // ========================================================================

  Future<SyncResult> autoSyncOnStartup() async {
    if (!_acquireSyncLock('auto_sync')) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    try {
      if (!await canSync) {
        return SyncResult(
            success: false, message: 'Starting offline - no connection');
      }

      final restoreResult = await restoreFromFirebaseIfEmpty();
      if (restoreResult.success && restoreResult.message.contains('restored')) {
        return SyncResult(success: true, message: 'Data restored from cloud');
      }

      final syncResult = await syncAllData();
      return SyncResult(
        success: syncResult.success,
        message: syncResult.success ? 'Synced with cloud' : syncResult.message,
      );
    } catch (e) {
      return SyncResult(
          success: false, message: 'Sync failed, working offline');
    } finally {
      _releaseSyncLock('auto_sync');
    }
  }

  // ========================================================================
  // UTILITIES
  // ========================================================================

  Future<SyncResult> forceUploadAllData() async {
    if (!_acquireSyncLock('force_upload')) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    try {
      if (!await canSync) {
        return SyncResult(
            success: false, message: 'No connection or not authenticated');
      }

      final db = await _dbHelper.database;
      final tables = [
        COLLECTION_CLIENTS,
        COLLECTION_PRODUCTS,
        COLLECTION_BILLS,
        COLLECTION_BILL_ITEMS,
        COLLECTION_LEDGER,
        COLLECTION_DEMAND_BATCH,
        COLLECTION_DEMAND
      ];

      for (final table in tables) {
        await db.update(table, {'isSynced': 0}, where: 'isDeleted = 0');
      }

      await _uploadAllLocalChanges();

      return SyncResult(success: true, message: 'All data uploaded to cloud');
    } catch (e) {
      return SyncResult(success: false, message: 'Force upload failed: $e');
    } finally {
      _releaseSyncLock('force_upload');
    }
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final db = await _dbHelper.database;
      final Map<String, dynamic> status = {};

      final tables = [
        COLLECTION_CLIENTS,
        COLLECTION_PRODUCTS,
        COLLECTION_BILLS,
        COLLECTION_BILL_ITEMS,
        COLLECTION_LEDGER
      ];

      for (final table in tables) {
        final totalCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 0'),
        ) ?? 0;

        final unsyncedCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 0 AND isSynced = 0'),
        ) ?? 0;

        final deletedCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table WHERE isDeleted = 1'),
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
      status['isSyncing'] = _syncLock.values.any((v) => v == true);

      return status;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> cleanupDeletedRecords({int daysOld = 90}) async {
    try {
      final db = await _dbHelper.database;
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      final cutoffString = cutoffDate.toIso8601String();

      final tables = [
        COLLECTION_BILLS,
        COLLECTION_BILL_ITEMS,
        COLLECTION_LEDGER,
        COLLECTION_DEMAND,
        COLLECTION_DEMAND_BATCH
      ];
      int totalCleaned = 0;

      for (final table in tables) {
        final deleted = await db.delete(
          table,
          where: 'isDeleted = 1 AND isSynced = 1 AND updatedAt < ?',
          whereArgs: [cutoffString],
        );
        totalCleaned += deleted;
      }

      if (totalCleaned > 0) {
        debugPrint('✅ Cleaned $totalCleaned old records (>$daysOld days)');
      }
    } catch (e) {
      debugPrint('⚠️ Cleanup failed: $e');
    }
  }

  Future<SyncResult> resetSyncStatus() async {
    if (_syncLock.values.any((v) => v == true)) {
      return SyncResult(success: false, message: 'Sync in progress, cannot reset');
    }

    try {
      final db = await _dbHelper.database;
      final tables = [
        COLLECTION_CLIENTS,
        COLLECTION_PRODUCTS,
        COLLECTION_BILLS,
        COLLECTION_BILL_ITEMS,
        COLLECTION_LEDGER,
        COLLECTION_DEMAND_BATCH,
        COLLECTION_DEMAND
      ];

      for (final table in tables) {
        await db.update(table, {'isSynced': 0}, where: 'isDeleted = 0');
      }

      // ✅ Clear sync timestamps for fresh sync
      _lastSyncTimestamps.clear();

      return SyncResult(success: true, message: 'Sync status reset successfully');
    } catch (e) {
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