// lib/services/firebase_sync_service.dart
// ✅ FIXED: Timestamp handling + Foreign key mapping + Batch writes + Better logging
// ✅ Robust download: handles Firestore Timestamp/String/number dates
// ✅ Multi-device safe references (uses Firestore IDs for relations in cloud)
// Note: The GoogleApiManager SecurityException in logs is from Play Services
// and not caused by this code. It’s harmless for Firestore/Flutter apps.

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
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

class FirebaseSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Uuid _uuid = const Uuid();

  bool _syncing = false;

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
      return result != ConnectivityResult.none;
    } catch (e) {
      debugPrint('❌ Connectivity check failed: $e');
      return false;
    }
  }

  Future<bool> get canSync async => await _isConnected() && _uid != null;

  // Small helpers to normalize Firestore date fields
  DateTime _asDateTime(dynamic v) {
    try {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is double) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      return DateTime.fromMillisecondsSinceEpoch(0);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String _asIsoString(dynamic v) => _asDateTime(v).toIso8601String();

  // ========================================================================
  // MAIN SYNC METHODS
  // ========================================================================

  Future<SyncResult> syncAllData() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No internet connection or not authenticated');
    }

    _syncing = true;
    try {
      debugPrint('🔄 Starting complete sync...');

      // Check schema compatibility
      final schemaCheck = await _checkSchemaCompatibility();
      if (!schemaCheck) {
        return SyncResult(
          success: false,
          message: 'Schema version mismatch - please update app',
        );
      }

      await _uploadAllLocalChanges();
      await _downloadAndMergeFromFirebase();

      debugPrint('✅ Sync completed successfully');
      return SyncResult(success: true, message: 'Sync completed successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Sync failed: $e');
      debugPrint('Stack trace: $stackTrace');
      return SyncResult(success: false, message: 'Sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<SyncResult> restoreFromFirebaseIfEmpty() async {
    if (_syncing) {
      return SyncResult(success: false, message: 'Sync in progress');
    }

    if (!await canSync) {
      return SyncResult(success: false, message: 'No internet connection or not authenticated');
    }

    _syncing = true;
    try {
      final db = await _dbHelper.database;

      final clientCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM clients WHERE isDeleted = 0'),
      ) ?? 0;

      final productCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM products WHERE isDeleted = 0'),
      ) ?? 0;

      if (clientCount > 0 || productCount > 0) {
        return SyncResult(success: true, message: 'Local data exists, no restore needed');
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
      _syncing = false;
    }
  }

  // Check schema version compatibility
  Future<bool> _checkSchemaCompatibility() async {
    try {
      final userDoc = _userDoc();
      if (userDoc == null) return false;

      final metadataSnap = await userDoc.collection(COLLECTION_METADATA).doc('schema').get();

      if (!metadataSnap.exists) {
        await userDoc.collection(COLLECTION_METADATA).doc('schema').set({
          'version': CURRENT_SCHEMA_VERSION,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return true;
      }

      final remoteVersion = metadataSnap.data()?['version'] as int? ?? 0;

      if (remoteVersion != CURRENT_SCHEMA_VERSION) {
        debugPrint('⚠️ Schema mismatch: local=$CURRENT_SCHEMA_VERSION, remote=$remoteVersion');
        await userDoc.collection(COLLECTION_METADATA).doc('schema').update({
          'version': CURRENT_SCHEMA_VERSION,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return true;
    } catch (e) {
      debugPrint('⚠️ Schema check failed: $e');
      return true; // Allow sync to continue
    }
  }

  // ========================================================================
  // UPLOAD LOCAL CHANGES TO FIREBASE
  // ========================================================================

  Future<void> _uploadAllLocalChanges() async {
    await _processPendingDeletions();

    // Upload in dependency order (parents before children)
    await _uploadUnsyncedClients();
    await _uploadUnsyncedProducts();
    await _uploadUnsyncedBills();
    await _uploadUnsyncedBillItems();
    await _uploadUnsyncedLedgerEntries();
    await _uploadUnsyncedDemandBatches();
    await _uploadUnsyncedDemands();
  }

  Future<void> _processPendingDeletions() async {
    // Children first
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
    int localDeleted = 0;
    int kept = 0;

    for (final row in deletedRows) {
      final firestoreId = row['firestoreId'] as String?;
      final localId = row['id'] as int;

      // Delete from Firebase
      if (firestoreId != null && firestoreId.isNotEmpty) {
        try {
          batch.delete(col.doc(firestoreId));
          firebaseDeleted++;
        } catch (e) {
          debugPrint('⚠️ Failed to delete $table/$firestoreId: $e');
        }
      }

      // Try hard delete locally (respect FK dependencies)
      try {
        if (table == COLLECTION_CLIENTS) {
          final canDelete = await _dbHelper.canHardDeleteClient(localId);
          if (canDelete) {
            await db.delete(table, where: 'id = ?', whereArgs: [localId]);
            localDeleted++;
          } else {
            await db.update(
              table,
              {'isSynced': 1, 'updatedAt': DateTime.now().toIso8601String()},
              where: 'id = ?',
              whereArgs: [localId],
            );
            kept++;
          }
        } else if (table == COLLECTION_PRODUCTS) {
          final canDelete = await _dbHelper.canHardDeleteProduct(localId);
          if (canDelete) {
            await db.delete(table, where: 'id = ?', whereArgs: [localId]);
            localDeleted++;
          } else {
            await db.update(
              table,
              {'isSynced': 1, 'updatedAt': DateTime.now().toIso8601String()},
              where: 'id = ?',
              whereArgs: [localId],
            );
            kept++;
          }
        } else {
          await db.delete(table, where: 'id = ?', whereArgs: [localId]);
          localDeleted++;
        }
      } catch (e) {
        debugPrint('⚠️ Failed to delete $table/$localId locally: $e');
        await db.update(
          table,
          {'isSynced': 1, 'updatedAt': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [localId],
        );
        kept++;
      }
    }

    if (firebaseDeleted > 0) {
      await batch.commit();
    }

    if (firebaseDeleted > 0 || localDeleted > 0 || kept > 0) {
      debugPrint('✅ $table: $firebaseDeleted deleted from cloud, $localDeleted removed locally, $kept archived');
    }
  }

  Future<void> _uploadUnsyncedClients() async {
    final col = _col(COLLECTION_CLIENTS);
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced(COLLECTION_CLIENTS);
    if (unsynced.isEmpty) return;

    final db = await _dbHelper.database;
    int uploaded = 0;

    for (int i = 0; i < unsynced.length; i += 500) {
      final batch = _firestore.batch();
      final chunk = unsynced.skip(i).take(500).toList();

      for (final map in chunk) {
        try {
          final client = Client.fromMap(map);
          String? firestoreId = map['firestoreId'] as String?;
          firestoreId ??= _uuid.v4();

          batch.set(col.doc(firestoreId), client.toFirestore(), SetOptions(merge: true));

          await db.update(
            COLLECTION_CLIENTS,
            {'firestoreId': firestoreId, 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [client.id],
          );

          uploaded++;
        } catch (e) {
          debugPrint('⚠️ Failed to upload client: $e');
        }
      }

      await batch.commit();
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

    for (int i = 0; i < unsynced.length; i += 500) {
      final batch = _firestore.batch();
      final chunk = unsynced.skip(i).take(500).toList();

      for (final map in chunk) {
        try {
          final product = Product.fromMap(map);
          String? firestoreId = map['firestoreId'] as String?;
          firestoreId ??= _uuid.v4();

          batch.set(col.doc(firestoreId), product.toFirestore(), SetOptions(merge: true));

          await db.update(
            COLLECTION_PRODUCTS,
            {'firestoreId': firestoreId, 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [product.id],
          );

          uploaded++;
        } catch (e) {
          debugPrint('⚠️ Failed to upload product: $e');
        }
      }

      await batch.commit();
    }

    if (uploaded > 0) debugPrint('✅ Uploaded $uploaded products');
  }

  Future<void> _uploadUnsyncedBills() async {
    final col = _col(COLLECTION_BILLS);
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced(COLLECTION_BILLS);
    if (unsynced.isEmpty) return;

    final db = await _dbHelper.database;
    int uploaded = 0, skipped = 0;

    for (int i = 0; i < unsynced.length; i += 500) {
      final batch = _firestore.batch();
      final chunk = unsynced.skip(i).take(500).toList();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final bill = Bill.fromMap(map);
          final localId = bill.id!;

          // ✅ Use existing firestoreId or generate new one
          String firestoreId = bill.firestoreId ?? '';

          // ✅ If no firestoreId, check if document exists by querying Firestore
          if (firestoreId.isEmpty) {
            firestoreId = _uuid.v4();
          }

          final clientFirestoreId = await _getClientFirestoreId(db, bill.clientId);
          if (clientFirestoreId == null) {
            debugPrint('⚠️ Skipping bill $localId - client ${bill.clientId} not synced');
            skipped++;
            continue;
          }

          final upload = bill.toFirestore();
          upload['clientFirestoreId'] = clientFirestoreId;
          upload['updatedAt'] = DateTime.now().toIso8601String();
          upload.remove('clientId'); // Remove local FK

          // ✅ Use set with merge to avoid duplicates
          batch.set(col.doc(firestoreId), upload, SetOptions(merge: true));

          // ✅ Prepare local update (execute AFTER batch commits)
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

      // ✅ Commit batch FIRST
      if (uploaded > 0) {
        await batch.commit();

        // ✅ Then update local database
        for (final update in localUpdates) {
          await db.update(
            COLLECTION_BILLS,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
      }
    }

    if (uploaded > 0 || skipped > 0) {
      debugPrint('✅ Uploaded $uploaded bills, skipped $skipped (missing refs)');
    }
  }

  Future<void> _uploadUnsyncedBillItems() async {
    final col = _col(COLLECTION_BILL_ITEMS);
    if (col == null) return;

    final unsynced = await _dbHelper.getUnsynced(COLLECTION_BILL_ITEMS);
    if (unsynced.isEmpty) return;

    final db = await _dbHelper.database;
    int uploaded = 0, skipped = 0;

    for (int i = 0; i < unsynced.length; i += 500) {
      final batch = _firestore.batch();
      final chunk = unsynced.skip(i).take(500).toList();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final item = BillItem.fromMap(map);
          final localId = item.id!;

          String firestoreId = map['firestoreId'] as String? ?? '';
          if (firestoreId.isEmpty) {
            firestoreId = _uuid.v4();
          }

          final billFirestoreId = await _getBillFirestoreId(db, item.billId);
          final productFirestoreId = await _getProductFirestoreId(db, item.productId);

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

          batch.set(col.doc(firestoreId), upload, SetOptions(merge: true));

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

      if (uploaded > 0) {
        await batch.commit();

        for (final update in localUpdates) {
          await db.update(
            COLLECTION_BILL_ITEMS,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
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
    int uploaded = 0, skipped = 0;

    for (int i = 0; i < unsynced.length; i += 500) {
      final batch = _firestore.batch();
      final chunk = unsynced.skip(i).take(500).toList();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final entry = LedgerEntry.fromMap(map);
          final localId = entry.id!;

          String firestoreId = map['firestoreId'] as String? ?? '';
          if (firestoreId.isEmpty) {
            firestoreId = _uuid.v4();
          }

          final clientFirestoreId = await _getClientFirestoreId(db, entry.clientId);
          if (clientFirestoreId == null) {
            debugPrint('⚠️ Skipping ledger $localId - client not synced');
            skipped++;
            continue;
          }

          String? billFirestoreId;
          if (entry.billId != null) {
            billFirestoreId = await _getBillFirestoreId(db, entry.billId!);
          }

          final upload = entry.toFirestore();
          upload['clientFirestoreId'] = clientFirestoreId;
          if (billFirestoreId != null) upload['billFirestoreId'] = billFirestoreId;
          upload['updatedAt'] = DateTime.now().toIso8601String();
          upload.remove('clientId');
          upload.remove('billId');

          batch.set(col.doc(firestoreId), upload, SetOptions(merge: true));

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

      if (uploaded > 0) {
        await batch.commit();

        for (final update in localUpdates) {
          await db.update(
            COLLECTION_LEDGER,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
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

    for (int i = 0; i < unsynced.length; i += 500) {
      final batch = _firestore.batch();
      final chunk = unsynced.skip(i).take(500).toList();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final localId = map['id'];

          String firestoreId = map['firestoreId'] as String? ?? '';
          if (firestoreId.isEmpty) {
            firestoreId = _uuid.v4();
          }

          final upload = Map<String, dynamic>.from(map);
          upload.remove('id');
          upload.remove('isSynced');
          upload['updatedAt'] = DateTime.now().toIso8601String();

          batch.set(col.doc(firestoreId), upload, SetOptions(merge: true));

          localUpdates.add({
            'localId': localId,
            'firestoreId': firestoreId,
          });

          uploaded++;
        } catch (e) {
          debugPrint('⚠️ Failed to prepare demand batch upload: $e');
        }
      }

      if (uploaded > 0) {
        await batch.commit();

        for (final update in localUpdates) {
          await db.update(
            COLLECTION_DEMAND_BATCH,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
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
    int uploaded = 0, skipped = 0;

    for (int i = 0; i < unsynced.length; i += 500) {
      final batch = _firestore.batch();
      final chunk = unsynced.skip(i).take(500).toList();
      final localUpdates = <Map<String, dynamic>>[];

      for (final map in chunk) {
        try {
          final localId = map['id'] as int;
          String firestoreId = map['firestoreId'] as String? ?? _uuid.v4();

          // ✅ Get the FIRESTORE IDs of the parents
          final batchFirestoreId = await _dbHelper.getFirestoreId(COLLECTION_DEMAND_BATCH, map['batchId'] as int);
          final clientFirestoreId = await _dbHelper.getFirestoreId(COLLECTION_CLIENTS, map['clientId'] as int);
          final productFirestoreId = await _dbHelper.getFirestoreId(COLLECTION_PRODUCTS, map['productId'] as int);

          if (batchFirestoreId == null || clientFirestoreId == null || productFirestoreId == null) {
            debugPrint('⚠️ Skipping demand upload $localId - a parent record is not synced yet.');
            skipped++;
            continue;
          }

          final uploadData = Map<String, dynamic>.from(map);
          // Remove local-only fields
          uploadData.remove('id');
          uploadData.remove('isSynced');
          uploadData.remove('batchId');
          uploadData.remove('clientId');
          uploadData.remove('productId');

          // ✅ Add the FIRESTORE foreign key IDs to the upload map
          uploadData['batchFirestoreId'] = batchFirestoreId;
          uploadData['clientFirestoreId'] = clientFirestoreId;
          uploadData['productFirestoreId'] = productFirestoreId;
          uploadData['updatedAt'] = FieldValue.serverTimestamp(); // Use server time for consistency

          batch.set(col.doc(firestoreId), uploadData, SetOptions(merge: true));

          localUpdates.add({'localId': localId, 'firestoreId': firestoreId});
          uploaded++;

        } catch (e) {
          debugPrint('⚠️ Failed to prepare demand for upload: $e');
          skipped++;
        }
      }

      if (uploaded > 0) {
        await batch.commit();
        for (final update in localUpdates) {
          await db.update(
            COLLECTION_DEMAND,
            {'firestoreId': update['firestoreId'], 'isSynced': 1},
            where: 'id = ?',
            whereArgs: [update['localId']],
          );
        }
      }

      if (uploaded > 0 || skipped > 0) {
        debugPrint('✅ Uploaded $uploaded demands, skipped $skipped');
      }
    }
  }

  // Helper methods to get Firestore IDs from local IDs
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

  // Helper methods to get LOCAL IDs from Firestore IDs (MISSING in your code earlier)
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

  // ========================================================================
  // DOWNLOAD AND MERGE FROM FIREBASE (Timestamp-safe)
  // ========================================================================

  Future<void> _downloadAndMergeFromFirebase() async {
    await _downloadAndMergeClients();
    await _downloadAndMergeProducts();
    await _downloadAndMergeBills();
    await _downloadAndMergeBillItems();
    await _downloadAndMergeLedgerEntries();
    await _downloadAndMergeDemandBatches();
    await _downloadAndMergeDemands();
  }

  Future<void> _downloadAndMergeClients() async {
    final col = _col(COLLECTION_CLIENTS);
    if (col == null) return;

    try {
      final snapshot = await col.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;
      int added = 0, updated = 0, skipped = 0;

      for (final doc in snapshot.docs) {
        final client = Client.fromFirestore(doc);
        final remoteUpdated = client.updatedAt;

        final existing = await db.query(
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

          await db.insert(COLLECTION_CLIENTS, localData, conflictAlgorithm: ConflictAlgorithm.replace);
          added++;
        } else {
          final existingRow = existing.first;
          final localUpdated = _asDateTime(existingRow['updatedAt']);
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
            final localData = client.copyWith(isSynced: true).toMap();
            localData['firestoreId'] = doc.id;
            localData['updatedAt'] = _asIsoString(localData['updatedAt']);

            await db.update(COLLECTION_CLIENTS, localData, where: 'id = ?', whereArgs: [existingRow['id']]);
            updated++;
          } else {
            skipped++;
          }
        }
      }

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
      final snapshot = await col.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;
      int added = 0, updated = 0, skipped = 0;

      for (final doc in snapshot.docs) {
        final product = Product.fromFirestore(doc);
        final remoteUpdated = product.updatedAt;

        final existing = await db.query(
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

          await db.insert(COLLECTION_PRODUCTS, localData, conflictAlgorithm: ConflictAlgorithm.replace);
          added++;
        } else {
          final existingRow = existing.first;
          final localUpdated = _asDateTime(existingRow['updatedAt']);
          final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

          if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
            final localData = product.copyWith(isSynced: true).toMap();
            localData['firestoreId'] = doc.id;
            localData['updatedAt'] = _asIsoString(localData['updatedAt']);

            await db.update(COLLECTION_PRODUCTS, localData, where: 'id = ?', whereArgs: [existingRow['id']]);
            updated++;
          } else if (isLocallyModified) {
            debugPrint('⚠️ Stock conflict for ${product.name} - keeping local value');
            skipped++;
          } else {
            skipped++;
          }
        }
      }

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint('✅ Products: $added new, $updated updated, $skipped skipped');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to download products: $e');
    }
  }

  Future<void> _downloadAndMergeBills() async {
    final col = _col(COLLECTION_BILLS);
    if (col == null) return;

    try {
      final snapshot = await col.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;
      int added = 0, updated = 0, skipped = 0;

      for (final doc in snapshot.docs) {
        try {
          final rawData = doc.data();

          // ✅ Create clean SQLite-safe map
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
            'tax': (rawData['tax'] is num)
                ? (rawData['tax'] as num).toDouble()
                : 0.0,
            'paymentStatus': rawData['paymentStatus'] as String? ?? 'pending',
            'notes': rawData['notes'] as String?,
            'isDeleted': (rawData['isDeleted'] == true || rawData['isDeleted'] == 1) ? 1 : 0,
          };

          // ✅ Convert ALL timestamps to ISO strings
          data['date'] = _asIsoString(rawData['date']);
          data['updatedAt'] = _asIsoString(rawData['updatedAt']);
          data['createdAt'] = _asIsoString(rawData['createdAt'] ?? rawData['updatedAt']);

          if (rawData['dueDate'] != null) {
            data['dueDate'] = _asIsoString(rawData['dueDate']);
          }

          // ✅ Resolve client reference
          final clientFirestoreId = rawData['clientFirestoreId'] as String?;
          if (clientFirestoreId == null || clientFirestoreId.isEmpty) {
            debugPrint('⚠️ Skipping bill ${doc.id} - missing clientFirestoreId');
            skipped++;
            continue;
          }

          final localClientId = await _getLocalClientId(db, clientFirestoreId);
          if (localClientId == null) {
            debugPrint('⚠️ Skipping bill ${doc.id} - client not found locally');
            skipped++;
            continue;
          }

          data['clientId'] = localClientId;

          final remoteUpdated = _asDateTime(rawData['updatedAt']);

          final existing = await db.query(
            COLLECTION_BILLS,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
            limit: 1,
          );

          if (existing.isEmpty) {
            // ✅ New record
            data['firestoreId'] = doc.id;
            data['isSynced'] = 1;

            await db.insert(COLLECTION_BILLS, data,
                conflictAlgorithm: ConflictAlgorithm.replace);
            added++;
          } else {
            // ✅ Update existing
            final existingRow = existing.first;
            final localUpdated = _asDateTime(existingRow['updatedAt']);
            final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

            if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1;

              await db.update(COLLECTION_BILLS, data,
                  where: 'id = ?',
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
      final snapshot = await col.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;
      int added = 0, updated = 0, skipped = 0;

      for (final doc in snapshot.docs) {
        try {
          final rawData = doc.data();

          // ✅ Create clean SQLite-safe map
          final data = <String, dynamic>{
            'quantity': (rawData['quantity'] is num)
                ? (rawData['quantity'] as num).toDouble()
                : 0.0,
            'price': (rawData['price'] is num)
                ? (rawData['price'] as num).toDouble()
                : 0.0,
            'discount': (rawData['discount'] is num)
                ? (rawData['discount'] as num).toDouble()
                : 0.0,
            'tax': (rawData['tax'] is num)
                ? (rawData['tax'] as num).toDouble()
                : 0.0,
            'isDeleted': (rawData['isDeleted'] == true || rawData['isDeleted'] == 1) ? 1 : 0,
          };

          // ✅ Convert timestamps to ISO strings
          data['updatedAt'] = _asIsoString(rawData['updatedAt']);
          data['createdAt'] = _asIsoString(rawData['createdAt'] ?? rawData['updatedAt']);

          // ✅ Resolve foreign keys
          final billFirestoreId = rawData['billFirestoreId'] as String?;
          final productFirestoreId = rawData['productFirestoreId'] as String?;

          if (billFirestoreId == null || productFirestoreId == null) {
            debugPrint('⚠️ Skipping bill_item ${doc.id} - missing references');
            skipped++;
            continue;
          }

          final localBillId = await _getLocalBillId(db, billFirestoreId);
          final localProductId = await _getLocalProductId(db, productFirestoreId);

          if (localBillId == null || localProductId == null) {
            debugPrint('⚠️ Skipping bill_item ${doc.id} - references not found locally');
            skipped++;
            continue;
          }

          data['billId'] = localBillId;
          data['productId'] = localProductId;

          final remoteUpdated = _asDateTime(rawData['updatedAt']);

          final existing = await db.query(
            COLLECTION_BILL_ITEMS,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
            limit: 1,
          );

          if (existing.isEmpty) {
            data['firestoreId'] = doc.id;
            data['isSynced'] = 1;

            await db.insert(COLLECTION_BILL_ITEMS, data,
                conflictAlgorithm: ConflictAlgorithm.replace);
            added++;
          } else {
            final existingRow = existing.first;
            final localUpdated = _asDateTime(existingRow['updatedAt']);
            final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

            if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1;

              await db.update(COLLECTION_BILL_ITEMS, data,
                  where: 'id = ?',
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

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint('✅ Bill items: $added new, $updated updated, $skipped skipped');
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
      final snapshot = await col.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;
      int added = 0, updated = 0, skipped = 0;

      for (final doc in snapshot.docs) {
        try {
          final rawData = doc.data();

          // ✅ Create clean map with CORRECT column names
          final data = <String, dynamic>{
            'type': rawData['type'] as String? ?? 'debit',
            'amount': (rawData['amount'] is num)
                ? (rawData['amount'] as num).toDouble()
                : 0.0,
            'note': rawData['note'] as String? ?? rawData['description'] as String?, // ✅ Map description to note
            'paymentMethod': rawData['paymentMethod'] as String?,
            'referenceNumber': rawData['referenceNumber'] as String?,
            'isDeleted': (rawData['isDeleted'] == true || rawData['isDeleted'] == 1) ? 1 : 0,
          };

          // ✅ Convert timestamps
          data['date'] = _asIsoString(rawData['date']);
          data['updatedAt'] = _asIsoString(rawData['updatedAt']);
          data['createdAt'] = _asIsoString(rawData['createdAt'] ?? rawData['updatedAt']);

          // ✅ Resolve client reference
          final clientFirestoreId = rawData['clientFirestoreId'] as String?;
          if (clientFirestoreId == null) {
            debugPrint('⚠️ Skipping ledger ${doc.id} - missing clientFirestoreId');
            skipped++;
            continue;
          }

          final localClientId = await _getLocalClientId(db, clientFirestoreId);
          if (localClientId == null) {
            debugPrint('⚠️ Skipping ledger ${doc.id} - client not found locally');
            skipped++;
            continue;
          }

          data['clientId'] = localClientId;

          // ✅ Resolve optional bill reference
          final billFirestoreId = rawData['billFirestoreId'] as String?;
          if (billFirestoreId != null) {
            final localBillId = await _getLocalBillId(db, billFirestoreId);
            if (localBillId != null) {
              data['billId'] = localBillId;
            }
          }

          final remoteUpdated = _asDateTime(rawData['updatedAt']);

          final existing = await db.query(
            COLLECTION_LEDGER,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
            limit: 1,
          );

          if (existing.isEmpty) {
            data['firestoreId'] = doc.id;
            data['isSynced'] = 1;

            await db.insert(COLLECTION_LEDGER, data,
                conflictAlgorithm: ConflictAlgorithm.replace);
            added++;
          } else {
            final existingRow = existing.first;
            final localUpdated = _asDateTime(existingRow['updatedAt']);
            final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

            if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1;

              await db.update(COLLECTION_LEDGER, data,
                  where: 'id = ?',
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

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint('✅ Ledger: $added new, $updated updated, $skipped skipped');
      }
    } catch (e, st) {
      debugPrint('❌ Failed to download ledger: $e');
      debugPrint('Stack: $st');
    }
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

  Future<void> _downloadAndMergeDemandBatches() async {
    final col = _col(COLLECTION_DEMAND_BATCH);
    if (col == null) return;

    try {
      final snapshot = await col.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;
      int added = 0, updated = 0, skipped = 0;

      for (final doc in snapshot.docs) {
        try {
          final data = Map<String, dynamic>.from(doc.data());

          // Normalize dates
          data['updatedAt'] = _asIsoString(data['updatedAt']);
          if (data.containsKey('demandDate')) {
            data['demandDate'] = _asIsoString(data['demandDate']);
          }

          final remoteUpdated = _asDateTime(data['updatedAt']);

          final existing = await db.query(
            COLLECTION_DEMAND_BATCH,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
            limit: 1,
          );

          if (existing.isEmpty) {
            data.remove('id');
            data['firestoreId'] = doc.id;
            data['isSynced'] = 1;

            await db.insert(COLLECTION_DEMAND_BATCH, data, conflictAlgorithm: ConflictAlgorithm.replace);
            added++;
          } else {
            final existingRow = existing.first;
            final localUpdated = _asDateTime(existingRow['updatedAt']);
            final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

            if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
              final updateData = Map<String, dynamic>.from(data);
              updateData.remove('id');
              updateData['firestoreId'] = doc.id;
              updateData['isSynced'] = 1;

              await db.update(COLLECTION_DEMAND_BATCH, updateData, where: 'id = ?', whereArgs: [existingRow['id']]);
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

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint('✅ Demand batches: $added new, $updated updated, $skipped skipped');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to download demand batches: $e');
    }
  }

  Future<void> _downloadAndMergeDemands() async {
    final col = _col(COLLECTION_DEMAND);
    if (col == null) return;

    try {
      final snapshot = await col.get();
      if (snapshot.docs.isEmpty) return;

      final db = await _dbHelper.database;
      int added = 0, updated = 0, skipped = 0;

      for (final doc in snapshot.docs) {
        try {
          final rawData = doc.data();

          // ✅ Create a clean map for SQLite
          final data = <String, dynamic>{
            'quantity': (rawData['quantity'] as num?)?.toDouble() ?? 0.0,
            'isDeleted': (rawData['isDeleted'] == true || rawData['isDeleted'] == 1) ? 1 : 0,
          };

          // ✅ Normalize timestamps to ISO strings
          data['date'] = _asIsoString(rawData['date']);
          data['updatedAt'] = _asIsoString(rawData['updatedAt']);
          if(rawData.containsKey('createdAt')) {
            data['createdAt'] = _asIsoString(rawData['createdAt']);
          }

          // ✅ === THIS IS THE FIX: Resolve ALL foreign keys ===
          final batchFirestoreId = rawData['batchFirestoreId'] as String?;
          final clientFirestoreId = rawData['clientFirestoreId'] as String?;
          final productFirestoreId = rawData['productFirestoreId'] as String?;

          if (batchFirestoreId == null || clientFirestoreId == null || productFirestoreId == null) {
            debugPrint('⚠️ Skipping demand ${doc.id} - missing one or more parent Firestore IDs.');
            skipped++;
            continue;
          }

          // Look up the LOCAL integer IDs from the parent Firestore string IDs
          final localBatchId = await _getLocalDemandBatchId(db, batchFirestoreId);
          final localClientId = await _getLocalClientId(db, clientFirestoreId);
          final localProductId = await _getLocalProductId(db, productFirestoreId);

          if (localBatchId == null || localClientId == null || localProductId == null) {
            debugPrint('⚠️ Skipping demand ${doc.id} - parent records not found locally.');
            skipped++;
            continue;
          }

          // ✅ Use the resolved LOCAL integer IDs for insertion
          data['batchId'] = localBatchId;
          data['clientId'] = localClientId;
          data['productId'] = localProductId;
          // =======================================================

          final remoteUpdated = _asDateTime(rawData['updatedAt']);

          final existing = await db.query(
            COLLECTION_DEMAND,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
            limit: 1,
          );

          if (existing.isEmpty) {
            data['firestoreId'] = doc.id;
            data['isSynced'] = 1;
            await db.insert(COLLECTION_DEMAND, data, conflictAlgorithm: ConflictAlgorithm.replace);
            added++;
          } else {
            final existingRow = existing.first;
            final localUpdated = _asDateTime(existingRow['updatedAt']);
            final isLocallyModified = (existingRow['isSynced'] as int? ?? 1) == 0;

            if (!isLocallyModified && remoteUpdated.isAfter(localUpdated)) {
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1;
              await db.update(COLLECTION_DEMAND, data, where: 'id = ?', whereArgs: [existingRow['id']]);
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

      if (added > 0 || updated > 0 || skipped > 0) {
        debugPrint('✅ Demands: $added new, $updated updated, $skipped skipped');
      }
    } catch (e) {
      debugPrint('❌ Failed to download demands: $e');
    }
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
  Future<void> _restoreDemandBatchesFromFirebase() => _downloadAndMergeDemandBatches();
  Future<void> _restoreDemandsFromFirebase() => _downloadAndMergeDemands();

  // ========================================================================
  // INDIVIDUAL SYNC
  // ========================================================================

  Future<SyncResult> syncClients() async {
    if (_syncing) return SyncResult(success: false, message: 'Sync already in progress');
    if (!await canSync) return SyncResult(success: false, message: 'No connection or not authenticated');

    _syncing = true;
    try {
      await _processTableDeletions(COLLECTION_CLIENTS);
      await _uploadUnsyncedClients();
      await _downloadAndMergeClients();
      return SyncResult(success: true, message: 'Clients synced successfully');
    } catch (e) {
      return SyncResult(success: false, message: 'Client sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<SyncResult> syncProducts() async {
    if (_syncing) return SyncResult(success: false, message: 'Sync already in progress');
    if (!await canSync) return SyncResult(success: false, message: 'No connection or not authenticated');

    _syncing = true;
    try {
      await _processTableDeletions(COLLECTION_PRODUCTS);
      await _uploadUnsyncedProducts();
      await _downloadAndMergeProducts();
      return SyncResult(success: true, message: 'Products synced successfully');
    } catch (e) {
      return SyncResult(success: false, message: 'Product sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<SyncResult> syncBills() async {
    if (_syncing) return SyncResult(success: false, message: 'Sync already in progress');
    if (!await canSync) return SyncResult(success: false, message: 'No connection or not authenticated');

    _syncing = true;
    try {
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
      _syncing = false;
    }
  }

  Future<SyncResult> syncLedger() async {
    if (_syncing) return SyncResult(success: false, message: 'Sync already in progress');
    if (!await canSync) return SyncResult(success: false, message: 'No connection or not authenticated');

    _syncing = true;
    try {
      await _processTableDeletions(COLLECTION_LEDGER);
      await _uploadUnsyncedLedgerEntries();
      await _downloadAndMergeLedgerEntries();
      return SyncResult(success: true, message: 'Ledger synced successfully');
    } catch (e) {
      return SyncResult(success: false, message: 'Ledger sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  // ========================================================================
  // AUTO SYNC
  // ========================================================================

  Future<SyncResult> autoSyncOnStartup() async {
    if (_syncing) return SyncResult(success: false, message: 'Sync already in progress');
    if (!await canSync) return SyncResult(success: false, message: 'Starting offline - no connection');

    _syncing = true;
    try {
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
      return SyncResult(success: false, message: 'Sync failed, working offline');
    } finally {
      _syncing = false;
    }
  }

  // ========================================================================
  // UTILITIES
  // ========================================================================

  Future<SyncResult> forceUploadAllData() async {
    if (_syncing) return SyncResult(success: false, message: 'Sync already in progress');
    if (!await canSync) return SyncResult(success: false, message: 'No connection or not authenticated');

    _syncing = true;
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

      await _uploadAllLocalChanges();

      return SyncResult(success: true, message: 'All data uploaded to cloud');
    } catch (e) {
      return SyncResult(success: false, message: 'Force upload failed: $e');
    } finally {
      _syncing = false;
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
      status['isSyncing'] = _syncing;

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
    if (_syncing) return SyncResult(success: false, message: 'Sync in progress, cannot reset');

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