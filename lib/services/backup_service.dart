import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/client.dart';
import '../models/product.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/ledger_entry.dart';
import 'database_helper.dart';

class BackupService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Current Firebase user id or null if not signed in
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Helper to get a sub-collection under the current user
  CollectionReference<Map<String, dynamic>>? _col(String name) {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection(name);
  }

  // ---------------- Clients ----------------

  Future<void> backupClient(Client c) async {
    final col = _col('clients');
    if (col == null) {
      debugPrint('BackupService: no user, skipping client backup');
      return;
    }
    try {
      final id = c.id?.toString();
      final data = c.toMap();
      if (id != null) {
        await col.doc(id).set(data, SetOptions(merge: true));
      } else {
        await col.add(data);
      }
    } catch (e, st) {
      debugPrint('backupClient failed: $e\n$st');
    }
  }

  Future<void> backupClients() async {
    final col = _col('clients');
    if (col == null) {
      debugPrint('BackupService: no user, skipping backupClients');
      return;
    }
    try {
      final dbHelper = DatabaseHelper();
      final allClients = await dbHelper.getClients();
      final batch = _db.batch();
      for (final c in allClients) {
        final id = c.id?.toString();
        if (id != null) {
          batch.set(col.doc(id), c.toMap(), SetOptions(merge: true));
        }
      }
      await batch.commit();
      debugPrint('BackupService: ${allClients.length} clients backed up.');
    } catch (e, st) {
      debugPrint('backupClients failed: $e\n$st');
    }
  }

  // ---------------- Products ----------------

  Future<void> backupProduct(Product p) async {
    final col = _col('products');
    if (col == null) return;
    try {
      final id = p.id?.toString();
      if (id != null) {
        await col.doc(id).set(p.toMap(), SetOptions(merge: true));
      } else {
        await col.add(p.toMap());
      }
    } catch (e, st) {
      debugPrint('backupProduct failed: $e\n$st');
    }
  }

  Future<void> deleteProduct(int id) async {
    final col = _col('products');
    if (col == null) return;
    try {
      await col.doc(id.toString()).delete();
    } catch (e, st) {
      debugPrint('deleteProduct failed: $e\n$st');
    }
  }

  Future<void> backupProductStock(Map<String, dynamic> row) async {
    final col = _col('product_stock');
    if (col == null) return;
    try {
      final id = row['id']?.toString();
      if (id != null) {
        await col.doc(id).set(Map<String, dynamic>.from(row), SetOptions(merge: true));
      }
    } catch (e, st) {
      debugPrint('backupProductStock failed: $e\n$st');
    }
  }

// ---------------- NEW: Fetch products from Firestore ----------------

  Future<List<Product>> getProductsFromFirestore() async {
    final col = _col('products');
    if (col == null) return [];
    try {
      final snapshot = await col.get();
      return snapshot.docs.map((d) => Product.fromMap(d.data())).toList();
    } catch (e, st) {
      debugPrint('getProductsFromFirestore failed: $e\n$st');
      return [];
    }
  }

  // ---------------- Bills ----------------

  Future<void> backupBill(Bill bill) async {
    final col = _col('bills');
    if (col == null) return;
    try {
      final id = bill.id?.toString();
      final data = bill.toMap();
      final docRef = id != null ? col.doc(id) : await col.add(data);
      if (id != null) {
        await docRef.set(data, SetOptions(merge: true));
      }

      // Backup bill items
      if (bill.id != null) {
        final items = await DatabaseHelper().getBillItems(bill.id!);
        for (final it in items) {
          final itemsCol = docRef.collection('items');
          final itemId = it.id?.toString();
          if (itemId != null) {
            await itemsCol.doc(itemId).set(it.toFirestore(), SetOptions(merge: true));
          } else {
            await itemsCol.add(it.toFirestore());
          }
        }
      }
    } catch (e, st) {
      debugPrint('backupBill failed: $e\n$st');
    }
  }

  Future<void> deleteBill(int id) async {
    final col = _col('bills');
    if (col == null) return;
    try {
      final doc = col.doc(id.toString());
      final itemsSnap = await doc.collection('items').get();
      if (itemsSnap.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final d in itemsSnap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
      await doc.delete();
    } catch (e, st) {
      debugPrint('deleteBill failed: $e\n$st');
    }
  }

  Future<void> backupBillItem(int billId, BillItem item) async {
    final col = _col('bills');
    if (col == null) return;
    try {
      final itemsCol = col.doc(billId.toString()).collection('items');
      final itemId = item.id?.toString();
      final data = item.toFirestore();
      if (itemId != null) {
        await itemsCol.doc(itemId).set(data, SetOptions(merge: true));
      } else {
        await itemsCol.add(data);
      }
    } catch (e, st) {
      debugPrint('backupBillItem failed: $e\n$st');
    }
  }

  Future<void> deleteBillItem(int billId, String? itemDocId) async {
    final col = _col('bills');
    if (col == null || itemDocId == null) return;
    try {
      await col.doc(billId.toString()).collection('items').doc(itemDocId).delete();
    } catch (e, st) {
      debugPrint('deleteBillItem failed: $e\n$st');
    }
  }

  // ---------------- Ledger ----------------

  Future<void> backupLedgerEntry(LedgerEntry e) async {
    final col = _col('ledger');
    if (col == null) return;
    try {
      final id = e.id?.toString();
      if (id != null) {
        await col.doc(id).set(e.toMap(), SetOptions(merge: true));
      } else {
        await col.add(e.toMap());
      }
    } catch (e, st) {
      debugPrint('backupLedgerEntry failed: $e\n$st');
    }
  }

  Future<void> backupLedger(LedgerEntry e) => backupLedgerEntry(e);

  // ---------------- Stock ----------------

  Future<void> backupStock(Map<String, dynamic> row) async {
    final col = _col('stock');
    if (col == null) return;
    try {
      final id = row['id']?.toString();
      if (id != null) {
        await col.doc(id).set(Map<String, dynamic>.from(row), SetOptions(merge: true));
      }
    } catch (e, st) {
      debugPrint('backupStock failed: $e\n$st');
    }
  }

  // ---------------- Bulk Backups ----------------

  Future<void> backupAllProducts() async {
    final col = _col('products');
    if (col == null) return;
    final db = DatabaseHelper();
    final products = await db.getProducts();
    final batch = _db.batch();
    for (final p in products) {
      final id = p.id?.toString();
      if (id != null) {
        batch.set(col.doc(id), p.toMap(), SetOptions(merge: true));
      }
    }
    await batch.commit();
  }

  Future<void> backupAllBills() async {
    final db = DatabaseHelper();
    final bills = await db.getBills();
    for (final bMap in bills) {
      final bill = Bill.fromMap(bMap);  // use your Bill model’s factory
      await backupBill(bill);
    }
  }

  Future<void> backupAllLedgerEntries() async {
    final col = _col('ledger');
    if (col == null) return;

    final db = DatabaseHelper();
    final entries = await db.getLedgerEntries(); // <- returns List<Map<String,dynamic>>
    final batch = _db.batch();

    for (final row in entries) {
      // Convert raw map to your LedgerEntry model
      final entry = LedgerEntry.fromMap(row);
      final id = entry.id?.toString();
      if (id != null) {
        batch.set(
          col.doc(id),
          entry.toMap(),
          SetOptions(merge: true),
        );
      }
    }

    await batch.commit();
  }


  // ---------------- Demand Batches ----------------

  Future<void> backupDemandBatch(int batchId) async {
    final col = _col('demand_batches');
    if (col == null) return;
    try {
      final batch = await DatabaseHelper().getBatchById(batchId);
      if (batch == null) return;
      final doc = col.doc(batchId.toString());
      await doc.set(Map<String, dynamic>.from(batch), SetOptions(merge: true));

      final items = await DatabaseHelper()
          .rawQuery('SELECT * FROM demand WHERE batchId = ?', [batchId]);
      final itemsCol = doc.collection('items');
      for (final r in items) {
        final id = r['id']?.toString();
        if (id != null) {
          await itemsCol.doc(id).set(Map<String, dynamic>.from(r), SetOptions(merge: true));
        } else {
          await itemsCol.add(Map<String, dynamic>.from(r));
        }
      }
    } catch (e, st) {
      debugPrint('backupDemandBatch failed: $e\n$st');
    }
  }

  Future<void> backupAllDemandBatches() async {
    final batches = await DatabaseHelper().getDemandHistory();
    for (final b in batches) {
      final id = b['id'] as int?;
      if (id != null) await backupDemandBatch(id);
    }
  }



  // ---------------- Convenience ----------------

  Future<void> upsertClient(Client c) => backupClient(c);

}
