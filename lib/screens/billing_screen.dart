import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/client.dart';
import '../models/product.dart';
import '../services/database_helper.dart';
import '../services/backup_service.dart';
import 'history_screen.dart';

class BillingScreen extends StatefulWidget {
  final Bill? existingBill;
  const BillingScreen({super.key, this.existingBill});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final db = DatabaseHelper();
  final backup = BackupService();

  List<Client> clients = [];
  List<Product> products = [];
  Map<int, double> stockMap = {}; // productId -> available qty

  int? selectedClientId;
  int? selectedProductId;
  List<BillItem> items = [];

  bool _saving = false;

  double get totalAmount =>
      items.fold(0.0, (sum, it) => sum + it.price * it.quantity);

  @override
  void initState() {
    super.initState();
    _loadClients();
    _loadProducts();
    if (widget.existingBill != null) _loadExistingBill();
  }

  // ---------- Data loading ----------
  Future<void> _loadClients() async {
    final list = await db.getClients();
    if (mounted) setState(() => clients = list);
  }

  Future<void> _loadProducts() async {
    final list = await db.getProducts();
    final entries = await Future.wait(list.map(
          (p) => db.getStock(p.id!).then((s) => MapEntry(p.id!, s ?? 0)),
    ));
    if (mounted) {
      setState(() {
        products = list;
        stockMap = Map.fromEntries(entries);
      });
    }
  }

  Future<void> _loadExistingBill() async {
    final bill = widget.existingBill!;
    final billItems = await db.getBillItems(bill.id!);
    await Future.wait([_loadClients(), _loadProducts()]);
    if (mounted) {
      setState(() {
        selectedClientId = bill.clientId;
        items = billItems;
      });
    }
  }
  // -----------------------------------

  bool _hasSufficientStock() {
    for (final it in items) {
      final available = stockMap[it.productId] ?? 0;
      if (it.quantity > available) return false;
    }
    return true;
  }

  Future<void> _saveBill() async {
    if (_saving) return;
    if (selectedClientId == null) {
      _showSnack("Please select a client");
      return;
    }
    if (items.isEmpty) {
      _showSnack("Add at least one product");
      return;
    }
    if (!_hasSufficientStock()) {
      _showSnack("Not enough stock");
      return;
    }

    // Confirm if editing
    if (widget.existingBill != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Update Bill'),
          content: const Text('This will overwrite the existing bill. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _saving = true);
    try {
      final bill = Bill(
        id: widget.existingBill?.id,
        clientId: selectedClientId!,
        totalAmount: totalAmount,
        paidAmount: 0,
        carryForward: 0,
        date: DateTime.now(),
      );

      int billId;
      if (widget.existingBill == null) {
        billId = await db.insertBillWithItems(bill, items);
      } else {
        billId = bill.id!;
        await db.updateBillWithItems(bill, items);
      }

      // 🔄 Firestore backup (non-blocking)
      try {
        await backup.backupBill(bill.copyWith(id: billId));
      } catch (e) {
        _showSnack("Saved offline. Sync will retry. ($e)");
      }

      if (mounted) {
        setState(() {
          selectedClientId = null;
          selectedProductId = null;
          items.clear();
        });
        _showSnack('Bill saved successfully');
      }
    } catch (e) {
      _showSnack('Error saving bill: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- Item helpers ----------
  void _addOrIncrementProductById(int productId) {
    final prod = products.firstWhere((p) => p.id == productId);
    final available = stockMap[productId] ?? 0;

    final currentQty = items
        .where((it) => it.productId == productId)
        .fold<double>(0, (s, it) => s + it.quantity);

    if (currentQty + 1 > available) {
      _showSnack("Only $available units left for ${prod.name}");
      return;
    }

    setState(() {
      final idx = items.indexWhere((it) => it.productId == productId);
      if (idx != -1) {
        items[idx] = items[idx].copyWith(quantity: items[idx].quantity + 1);
      } else {
        items.add(BillItem(
          productId: prod.id!,
          quantity: 1,
          price: prod.price,
        ));
      }
      selectedProductId = null;
    });
  }

  void _increaseQuantity(BillItem item) {
    final available = stockMap[item.productId] ?? 0;
    final current = items
        .where((it) => it.productId == item.productId)
        .fold<double>(0, (s, it) => s + it.quantity);
    if (current + 1 > available) {
      _showSnack("Only $available units left");
      return;
    }
    setState(() {
      final idx = items.indexOf(item);
      items[idx] = item.copyWith(quantity: item.quantity + 1);
    });
  }

  void _decreaseQuantity(BillItem item) {
    setState(() {
      final idx = items.indexOf(item);
      if (item.quantity > 1) {
        items[idx] = item.copyWith(quantity: item.quantity - 1);
      } else {
        items.removeAt(idx);
      }
    });
  }

  void _removeItem(BillItem item) => setState(() => items.remove(item));
  // -----------------------------------

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingBill == null ? 'New Bill' : 'Edit Bill'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Billing History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saving ? null : _saveBill,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: DropdownButtonFormField<int>(
              value: selectedClientId,
              decoration: const InputDecoration(
                  labelText: 'Select Client', border: OutlineInputBorder()),
              items: clients
                  .map((c) =>
                  DropdownMenuItem<int>(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (id) => setState(() => selectedClientId = id),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: DropdownButtonFormField<int>(
              value: selectedProductId,
              decoration: const InputDecoration(
                  labelText: 'Select Product', border: OutlineInputBorder()),
              items: products
                  .map((p) => DropdownMenuItem<int>(
                value: p.id,
                child: Text(
                    '${p.name} — ₹${p.price} (Stock: ${stockMap[p.id] ?? 0})'),
              ))
                  .toList(),
              onChanged: (pid) {
                if (pid != null) _addOrIncrementProductById(pid);
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('No items added'))
                : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return ListTile(
                    title: const Text('Total',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    trailing: Text(
                      '₹${totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  );
                }
                final it = items[index];
                final p = products.firstWhere((p) => p.id == it.productId);
                return ListTile(
                  title: Text(p.name),
                  subtitle: Text(
                      'Price: ₹${it.price.toStringAsFixed(2)}   Stock: ${stockMap[p.id] ?? 0}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _decreaseQuantity(it)),
                      Text('${it.quantity}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _increaseQuantity(it)),
                      IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeItem(it)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
