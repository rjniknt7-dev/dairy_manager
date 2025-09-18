import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/database_helper.dart';
import '../services/backup_service.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({Key? key}) : super(key: key);

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final db = DatabaseHelper();
  final _backup = BackupService();
  final _numFormat = NumberFormat('#,##0.##');

  List<Map<String, dynamic>> _stock = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  Future<void> _loadStock() async {
    setState(() => _loading = true);
    try {
      final stock = await db.getAllStock();

      // Optional: back-up each row to Firestore
      await Future.wait(stock.map((row) async {
        try {
          await _backup.backupStock(row);
        } catch (_) {
          // Ignore individual failures
        }
      }));

      if (!mounted) return;
      setState(() => _stock = stock);
    } catch (e) {
      _showSnack('Failed to load stock: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _editStock(int productId, String productName, double currentQty) async {
    final controller = TextEditingController(text: currentQty.toString());
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Edit Stock – $productName"),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: "Quantity"),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter quantity';
              final n = double.tryParse(v);
              if (n == null || n < 0) return 'Enter a valid number ≥ 0';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final newQty = double.parse(controller.text.trim());

              await db.setStock(productId, newQty);

              try {
                await _backup.backupStock({
                  'id': productId,
                  'name': productName,
                  'quantity': newQty,
                });
              } catch (e) {
                _showSnack('Cloud backup failed: $e');
              }

              if (mounted) {
                Navigator.pop(context);
                _showSnack('Stock updated for $productName');
                _loadStock();
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // --------- Safe parsers ---------
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
    return Scaffold(
      appBar: AppBar(title: const Text("Stock / Inventory")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadStock,
        child: _stock.isEmpty
            ? const Center(child: Text("No stock data"))
            : ListView.builder(
          itemCount: _stock.length,
          itemBuilder: (_, i) {
            final row = _stock[i];

            // ✅ Null-safe parsing
            final int id = _safeInt(row['id']);
            final String name = _safeString(row['name']);
            final double quantity = _safeDouble(row['quantity']);

            return Card(
              margin:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                title: Text(name),
                subtitle: Text("Stock: ${_numFormat.format(quantity)}"),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _editStock(id, name, quantity),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
