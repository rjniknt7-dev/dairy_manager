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

class FirebaseSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? _col(String name) {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection(name);
  }

  Future<bool> _isConnected() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Main sync method - handles both upload and download
  Future<SyncResult> syncAllData() async {
    if (!await _isConnected()) {
      return SyncResult(success: false, message: 'No internet connection');
    }

    if (_uid == null) {
      return SyncResult(success: false, message: 'User not authenticated');
    }

    try {
      debugPrint('Starting full sync...');

      // 1. Upload all unsynced local data
      await _uploadUnsyncedData();

      // 2. Download and merge data from Firestore
      await _downloadFromFirestore();

      debugPrint('Full sync completed');
      return SyncResult(success: true, message: 'Sync completed successfully');

    } catch (e) {
      debugPrint('Sync failed: $e');
      return SyncResult(success: false, message: 'Sync failed: $e');
    }
  }

  /// Upload all unsynced local data to Firestore
  Future<void> _uploadUnsyncedData() async {
    await _uploadUnsyncedClients();
    await _uploadUnsyncedProducts();
    await _uploadUnsyncedBills();
    await _uploadUnsyncedBillItems();
    await _uploadUnsyncedLedgerEntries();
  }

  /// Upload unsynced clients (Client uses docId property, database uses firestoreId column)
  Future<void> _uploadUnsyncedClients() async {
    final col = _col('clients');
    if (col == null) return;

    final unsyncedClients = await _dbHelper.getUnsynced('clients');
    debugPrint('Uploading ${unsyncedClients.length} unsynced clients');

    for (final clientMap in unsyncedClients) {
      try {
        final client = Client.fromMap(clientMap);
        // Client model uses docId, but database stores as firestoreId
        String? firestoreId = clientMap['firestoreId'] as String?;

        if (firestoreId == null || firestoreId.isEmpty) {
          // Create new document in Firestore
          final docRef = await col.add(client.toFirestore());
          firestoreId = docRef.id;

          // Update local record with Firestore ID and mark as synced
          final db = await _dbHelper.database;
          await db.update(
            'clients',
            {
              'firestoreId': firestoreId,  // Database uses firestoreId column
              'isSynced': 1,
              'updatedAt': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [client.id],
          );
        } else {
          // Update existing document
          await col.doc(firestoreId).set(client.toFirestore(), SetOptions(merge: true));

          // Mark as synced
          await _dbHelper.markRowSynced('clients', client.id!);
        }
      } catch (e) {
        debugPrint('Error uploading client: $e');
      }
    }
  }

  /// Upload unsynced products (Product uses firestoreId property)
  Future<void> _uploadUnsyncedProducts() async {
    final col = _col('products');
    if (col == null) return;

    final unsyncedProducts = await _dbHelper.getUnsynced('products');
    debugPrint('Uploading ${unsyncedProducts.length} unsynced products');

    for (final productMap in unsyncedProducts) {
      try {
        final product = Product.fromMap(productMap);
        String? firestoreId = product.firestoreId;

        if (firestoreId == null || firestoreId.isEmpty) {
          final docRef = await col.add(product.toFirestore());
          firestoreId = docRef.id;

          final db = await _dbHelper.database;
          await db.update(
            'products',
            {
              'firestoreId': firestoreId,
              'isSynced': 1,
              'updatedAt': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [product.id],
          );
        } else {
          await col.doc(firestoreId).set(product.toFirestore(), SetOptions(merge: true));
          await _dbHelper.markRowSynced('products', product.id!);
        }
      } catch (e) {
        debugPrint('Error uploading product: $e');
      }
    }
  }

  /// Upload unsynced bills (Bill uses firestoreId but missing isSynced)
  Future<void> _uploadUnsyncedBills() async {
    final col = _col('bills');
    if (col == null) return;

    // Since Bill model doesn't have isSynced, we get all bills and check database directly
    final db = await _dbHelper.database;
    final unsyncedBills = await db.query('bills', where: 'isSynced = 0 OR isSynced IS NULL');
    debugPrint('Uploading ${unsyncedBills.length} unsynced bills');

    for (final billMap in unsyncedBills) {
      try {
        final bill = Bill.fromMap(billMap);
        String? firestoreId = bill.firestoreId;

        if (firestoreId == null || firestoreId.isEmpty) {
          final docRef = await col.add(bill.toFirestore());
          firestoreId = docRef.id;

          await db.update(
            'bills',
            {
              'firestoreId': firestoreId,
              'isSynced': 1,
            },
            where: 'id = ?',
            whereArgs: [bill.id],
          );
        } else {
          await col.doc(firestoreId).set(bill.toFirestore(), SetOptions(merge: true));

          await db.update(
            'bills',
            {'isSynced': 1},
            where: 'id = ?',
            whereArgs: [bill.id],
          );
        }
      } catch (e) {
        debugPrint('Error uploading bill: $e');
      }
    }
  }

  /// Upload unsynced bill items (BillItem uses docId property)
  Future<void> _uploadUnsyncedBillItems() async {
    final col = _col('bill_items');
    if (col == null) return;

    final unsyncedItems = await _dbHelper.getUnsynced('bill_items');
    debugPrint('Uploading ${unsyncedItems.length} unsynced bill items');

    for (final itemMap in unsyncedItems) {
      try {
        final item = BillItem.fromMap(itemMap);
        // BillItem model uses docId, but database stores as firestoreId
        String? firestoreId = itemMap['firestoreId'] as String?;

        if (firestoreId == null || firestoreId.isEmpty) {
          final docRef = await col.add(item.toFirestore());
          firestoreId = docRef.id;

          final db = await _dbHelper.database;
          await db.update(
            'bill_items',
            {
              'firestoreId': firestoreId,
              'isSynced': 1,
              'updatedAt': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [item.id],
          );
        } else {
          await col.doc(firestoreId).set(item.toFirestore(), SetOptions(merge: true));
          await _dbHelper.markRowSynced('bill_items', item.id!);
        }
      } catch (e) {
        debugPrint('Error uploading bill item: $e');
      }
    }
  }

  /// Upload unsynced ledger entries (LedgerEntry uses docId property)
  Future<void> _uploadUnsyncedLedgerEntries() async {
    final col = _col('ledger');
    if (col == null) return;

    final unsyncedEntries = await _dbHelper.getUnsynced('ledger');
    debugPrint('Uploading ${unsyncedEntries.length} unsynced ledger entries');

    for (final entryMap in unsyncedEntries) {
      try {
        final entry = LedgerEntry.fromMap(entryMap);
        // LedgerEntry model uses docId, but database stores as firestoreId
        String? firestoreId = entryMap['firestoreId'] as String?;

        if (firestoreId == null || firestoreId.isEmpty) {
          final docRef = await col.add(entry.toFirestore());
          firestoreId = docRef.id;

          final db = await _dbHelper.database;
          await db.update(
            'ledger',
            {
              'firestoreId': firestoreId,
              'isSynced': 1,
              'updatedAt': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [entry.id],
          );
        } else {
          await col.doc(firestoreId).set(entry.toFirestore(), SetOptions(merge: true));
          await _dbHelper.markRowSynced('ledger', entry.id!);
        }
      } catch (e) {
        debugPrint('Error uploading ledger entry: $e');
      }
    }
  }

  /// Download data from Firestore and merge with local data
  Future<void> _downloadFromFirestore() async {
    await _downloadClients();
    await _downloadProducts();
    await _downloadBills();
    await _downloadBillItems();
    await _downloadLedgerEntries();
  }

  /// Download and merge clients
  Future<void> _downloadClients() async {
    final col = _col('clients');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Downloading ${snapshot.docs.length} clients from Firestore');

      for (final doc in snapshot.docs) {
        final client = Client.fromFirestore(doc);

        final db = await _dbHelper.database;
        final existing = await db.query(
          'clients',
          where: 'firestoreId = ?',  // Database uses firestoreId column
          whereArgs: [doc.id],
          limit: 1,
        );

        final localData = client.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;  // Store in firestoreId column

        if (existing.isEmpty) {
          await db.insert('clients', localData);
          debugPrint('Inserted new client from Firestore: ${doc.id}');
        } else {
          await db.update(
            'clients',
            localData,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
          );
          debugPrint('Updated client from Firestore: ${doc.id}');
        }
      }
    } catch (e) {
      debugPrint('Error downloading clients: $e');
    }
  }

  /// Download and merge products
  Future<void> _downloadProducts() async {
    final col = _col('products');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Downloading ${snapshot.docs.length} products from Firestore');

      for (final doc in snapshot.docs) {
        final product = Product.fromFirestore(doc);

        final db = await _dbHelper.database;
        final existing = await db.query(
          'products',
          where: 'firestoreId = ?',
          whereArgs: [doc.id],
          limit: 1,
        );

        final localData = product.copyWith(isSynced: true).toMap();

        if (existing.isEmpty) {
          await db.insert('products', localData);
        } else {
          await db.update(
            'products',
            localData,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
          );
        }
      }
    } catch (e) {
      debugPrint('Error downloading products: $e');
    }
  }

  /// Download and merge bills
  Future<void> _downloadBills() async {
    final col = _col('bills');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Downloading ${snapshot.docs.length} bills from Firestore');

      for (final doc in snapshot.docs) {
        final bill = Bill.fromFirestore(doc.id, doc.data());

        final db = await _dbHelper.database;
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
        } else {
          await db.update(
            'bills',
            localData,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
          );
        }
      }
    } catch (e) {
      debugPrint('Error downloading bills: $e');
    }
  }

  /// Download and merge bill items
  Future<void> _downloadBillItems() async {
    final col = _col('bill_items');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Downloading ${snapshot.docs.length} bill items from Firestore');

      for (final doc in snapshot.docs) {
        final item = BillItem.fromFirestore(doc);

        final db = await _dbHelper.database;
        final existing = await db.query(
          'bill_items',
          where: 'firestoreId = ?',  // Database uses firestoreId
          whereArgs: [doc.id],
          limit: 1,
        );

        final localData = item.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;  // Store in firestoreId column

        if (existing.isEmpty) {
          await db.insert('bill_items', localData);
        } else {
          await db.update(
            'bill_items',
            localData,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
          );
        }
      }
    } catch (e) {
      debugPrint('Error downloading bill items: $e');
    }
  }

  /// Download and merge ledger entries
  Future<void> _downloadLedgerEntries() async {
    final col = _col('ledger');
    if (col == null) return;

    try {
      final snapshot = await col.get();
      debugPrint('Downloading ${snapshot.docs.length} ledger entries from Firestore');

      for (final doc in snapshot.docs) {
        final entry = LedgerEntry.fromFirestore(doc);

        final db = await _dbHelper.database;
        final existing = await db.query(
          'ledger',
          where: 'firestoreId = ?',  // Database uses firestoreId
          whereArgs: [doc.id],
          limit: 1,
        );

        final localData = entry.copyWith(isSynced: true).toMap();
        localData['firestoreId'] = doc.id;  // Store in firestoreId column

        if (existing.isEmpty) {
          await db.insert('ledger', localData);
        } else {
          await db.update(
            'ledger',
            localData,
            where: 'firestoreId = ?',
            whereArgs: [doc.id],
          );
        }
      }
    } catch (e) {
      debugPrint('Error downloading ledger entries: $e');
    }
  }

  /// Quick sync for specific entity types
  Future<SyncResult> syncClients() async {
    try {
      await _uploadUnsyncedClients();
      await _downloadClients();
      return SyncResult(success: true, message: 'Clients synced');
    } catch (e) {
      return SyncResult(success: false, message: 'Client sync failed: $e');
    }
  }

  Future<SyncResult> syncProducts() async {
    try {
      await _uploadUnsyncedProducts();
      await _downloadProducts();
      return SyncResult(success: true, message: 'Products synced');
    } catch (e) {
      return SyncResult(success: false, message: 'Product sync failed: $e');
    }
  }

  Future<SyncResult> syncBills() async {
    try {
      await _uploadUnsyncedBills();
      await _downloadBills();
      return SyncResult(success: true, message: 'Bills synced');
    } catch (e) {
      return SyncResult(success: false, message: 'Bill sync failed: $e');
    }
  }

  /// Auto sync when app starts
  Future<void> autoSyncOnStartup() async {
    if (await _isConnected() && _uid != null) {
      await syncAllData();
    }
  }
}

/// Result class for sync operations
class SyncResult {
  final bool success;
  final String message;

  SyncResult({required this.success, required this.message});

  @override
  String toString() => 'SyncResult(success: $success, message: $message)';
}