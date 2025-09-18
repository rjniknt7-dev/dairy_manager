import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/product.dart';
import '../services/database_helper.dart';
import '../services/backup_service.dart';

class BillDetailsScreen extends StatefulWidget {
  final int billId;
  const BillDetailsScreen({super.key, required this.billId});

  @override
  State<BillDetailsScreen> createState() => _BillDetailsScreenState();
}

class _BillDetailsScreenState extends State<BillDetailsScreen> {
  final db = DatabaseHelper();
  final _backup = BackupService();

  Bill? bill;
  List<BillItem> items = [];
  List<Product> products = [];
  bool _loading = true;
  bool _busy = false; // disable UI during edit/delete

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fetchedBill = await db.getBillById(widget.billId);
    if (!mounted) return;

    if (fetchedBill == null) {
      setState(() => _loading = false);
      return;
    }

    final itemMaps = await db.getBillItemsByBillId(widget.billId);
    final productList = await db.getProducts();

    setState(() {
      bill = fetchedBill;
      items = itemMaps.map((e) => BillItem.fromMap(e)).toList();
      products = productList;
      _loading = false;
    });
  }

  Future<void> _updateTotals(double diffAmount) async {
    if (bill == null) return;
    final newTotal = bill!.totalAmount + diffAmount;
    await db.updateBillTotal(bill!.id!, newTotal);
    bill = bill!.copyWith(totalAmount: newTotal);
  }

  Future<void> _editItem(BillItem item) async {
    final controller =
    TextEditingController(text: item.quantity.toStringAsFixed(2));

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Quantity'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantity'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _busy
                ? null
                : () async {
              final newQty =
                  double.tryParse(controller.text.trim()) ?? item.quantity;
              final diff = newQty - item.quantity;

              setState(() => _busy = true);
              try {
                // 1️⃣ Local DB & stock
                await db.updateBillItemQuantityWithStock(item.id!, newQty);
                await db.adjustStock(item.productId, -diff);
                await _updateTotals(diff * item.price);

                // 2️⃣ Firestore backup (skip silently if offline)
                await _backup.backupBillItem(
                    bill!.id!, item.copyWith(quantity: newQty));
                await _backup.backupBill(bill!);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved offline. Sync later. $e')),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() => _busy = false);
                  Navigator.pop(context);
                  await _load();
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(BillItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Delete ${item.quantity} × item from bill?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || _busy) return;

    setState(() => _busy = true);
    try {
      // 1️⃣ Local delete + stock restore
      await db.deleteBillItem(item.id!);
      await db.adjustStock(item.productId, item.quantity);
      await _updateTotals(-(item.quantity * item.price));

      // 2️⃣ Firestore sync
      if (item.docId != null) {
        await _backup.deleteBillItem(bill!.id!, item.docId);
      }
      await _backup.backupBill(bill!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted locally. Sync later. $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (bill == null) {
      return const Scaffold(body: Center(child: Text('Bill not found')));
    }

    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(bill!.date);

    return Scaffold(
      appBar: AppBar(title: const Text('Bill Details')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bill ID: ${bill!.id}', style: const TextStyle(fontSize: 16)),
            Text('Date: $dateStr'),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  final product = products.firstWhere(
                        (p) => p.id == item.productId,
                    orElse: () => Product(
                      id: item.productId,
                      name: 'Unknown',
                      weight: 0,
                      price: 0,
                    ),
                  );
                  return ListTile(
                    title: Text(product.name),
                    subtitle: Text(
                      '₹${item.price.toStringAsFixed(2)} × ${item.quantity}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₹${(item.price * item.quantity).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: _busy ? null : () => _editItem(item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: _busy ? null : () => _deleteItem(item),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ₹${bill!.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
