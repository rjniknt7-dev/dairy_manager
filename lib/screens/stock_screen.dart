import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({Key? key}) : super(key: key);

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();
  final _numFormat = NumberFormat('#,##0.##');

  List<Map<String, dynamic>> _stock = [];
  bool _loading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  Future<void> _loadStock() async {
    setState(() => _loading = true);
    try {
      final stock = await db.getAllStock();
      if (!mounted) return;
      setState(() => _stock = stock);
    } catch (e) {
      _showSnack('Failed to load stock: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncStock() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _showSnack('Login to sync data', Colors.orange);
      return;
    }

    setState(() => _isSyncing = true);
    final result = await _syncService.syncProducts();
    setState(() => _isSyncing = false);

    _showSnack(result.message, result.success ? Colors.green : Colors.red);

    if (result.success) await _loadStock();
  }

  void _showSnack(String msg, [Color? backgroundColor]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: backgroundColor),
    );
  }

  Future<void> _editStock(int productId, String productName, double currentQty) async {
    final controller = TextEditingController(text: currentQty.toString());
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text("Edit Stock – $productName"),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: "Quantity",
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter quantity';
              final n = double.tryParse(v);
              if (n == null || n < 0) return 'Enter a valid number ≥ 0';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final newQty = double.parse(controller.text.trim());

              try {
                await db.setStock(productId, newQty);
                _showSnack('Stock updated locally for $productName');

                if (FirebaseAuth.instance.currentUser != null) {
                  final result = await _syncService.syncProducts();
                  _showSnack(
                    result.success ? 'Stock synced to cloud' : 'Will sync when connection improves',
                    result.success ? Colors.green : Colors.orange,
                  );
                }

                if (mounted) {
                  Navigator.pop(context);
                  _loadStock();
                }
              } catch (e) {
                _showSnack('Failed to update stock: $e', Colors.red);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  int _safeInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _safeDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  String _safeString(dynamic v, {String fallback = 'Unnamed Product'}) =>
      (v == null || v.toString().isEmpty) ? fallback : v.toString();

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Stock / Inventory"),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.sync),
            onPressed: _isSyncing ? null : _syncStock,
            tooltip: 'Sync Stock',
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isLoggedIn)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  const Text(
                    'Offline mode - Login to sync data',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _loadStock,
              child: _stock.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(seconds: 1),
                      opacity: 1.0,
                      child: Icon(Icons.inventory_outlined, size: 64, color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "No stock data",
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const Text(
                      "Add some products to see stock levels",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
                  : ListView.separated(
                itemCount: _stock.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final row = _stock[i];
                  final int id = _safeInt(row['id']);
                  final String name = _safeString(row['name']);
                  final double quantity = _safeDouble(row['quantity']);

                  final lowStock = quantity < 10; // highlight low stock
                  final avatarColor = lowStock ? Colors.red : Theme.of(context).primaryColor;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                    child: ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [avatarColor.withOpacity(0.7), avatarColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        "Stock: ${_numFormat.format(quantity)}",
                        style: TextStyle(color: lowStock ? Colors.red : Colors.black87),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _editStock(id, name, quantity),
                      ),
                    ),
                  );

                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
