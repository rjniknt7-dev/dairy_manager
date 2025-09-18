import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/backup_service.dart';
import '../models/product.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({Key? key}) : super(key: key);

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final db = DatabaseHelper();
  final _backup = BackupService();

  List<Product> _products = [];
  final _stockController = TextEditingController();
  int? _selectedProductId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    final products = await db.getProducts();
    if (mounted) {
      setState(() => _products = products);
    }
  }

  Future<void> _updateStock() async {
    if (_selectedProductId == null) {
      _showSnack('Please select a product');
      return;
    }
    final qty = double.tryParse(_stockController.text);
    if (qty == null || qty < 0) {
      _showSnack('Enter a valid quantity');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1️⃣ Update locally
      await db.updateProductStock(_selectedProductId!, qty);

      // 2️⃣ Prepare complete product info for backup
      final product = _products.firstWhere((p) => p.id == _selectedProductId);
      final backupData = {
        'id': product.id,
        'name': product.name,
        'price': product.price,
        'stockQty': qty,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      // 3️⃣ Backup to Firestore (safe even if offline—catch errors)
      await _backup.backupProductStock(backupData);
      _showSnack('Stock updated & backed up');
    } catch (e) {
      _showSnack('Stock saved locally. Backup will retry when online.');
    } finally {
      _stockController.clear();
      _selectedProductId = null;
      await _loadInventory();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _stockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock / Inventory'),
        backgroundColor: Colors.indigo,
      ),
      body: RefreshIndicator(
        onRefresh: _loadInventory,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Current Stock',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            ..._products.map((p) => ListTile(
              title: Text(p.name),
              subtitle: Text('Price: ₹${p.price.toStringAsFixed(2)}'),
              trailing: Text(
                'Stock: ${p.stock ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            )),

            const Divider(height: 32),
            const Text(
              'Manual Stock Update',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<int>(
              value: _selectedProductId,
              hint: const Text('Select Product'),
              items: _products
                  .map((p) => DropdownMenuItem<int>(
                value: p.id!,
                child: Text(p.name),
              ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedProductId = v),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _stockController,
              decoration: const InputDecoration(
                labelText: 'New Stock Quantity',
                border: OutlineInputBorder(),
              ),
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              icon: _isSaving
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Update Stock'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
              onPressed: _isSaving ? null : _updateStock,
            ),
          ],
        ),
      ),
    );
  }
}
