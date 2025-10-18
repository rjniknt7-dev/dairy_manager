// lib/screens/inventory_screen.dart - v2.0 (Intelligent & Polished)
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../models/product.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({Key? key}) : super(key: key);

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();

  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  final _stockController = TextEditingController();
  final _searchController = TextEditingController();
  int? _selectedProductId;
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInventory();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _stockController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInventory() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final products = await db.getProducts();
    if (mounted) {
      setState(() {
        _products = products;
        _filteredProducts = products;
        _isLoading = false;
      });
      _applyFilter();
    }
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts = _products
          .where((p) => p.name.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _syncInventory() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _showSnack('You must be logged in to sync data.');
      return;
    }

    setState(() => _isLoading = true);
    final result = await _syncService.syncProducts();
    await _loadInventory(); // Reload data from DB after sync
    if (mounted) {
      setState(() => _isLoading = false);
      _showSnack(result.message, isSuccess: result.success);
    }
  }

  Future<void> _updateStock() async {
    if (_isSaving) return;

    if (_selectedProductId == null) {
      _showSnack('Please select a product.', isError: true);
      return;
    }
    final qty = double.tryParse(_stockController.text);
    if (qty == null || qty < 0) {
      _showSnack('Please enter a valid quantity.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await db.updateProductStock(_selectedProductId!, qty);
      _showSnack('Stock updated locally. Syncing...', isSuccess: true);

      _syncService.syncProducts().then((result) {
        if (mounted) _showSnack(result.message, isSuccess: result.success);
      });

      _resetManualUpdate();
      await _loadInventory();
    } catch (e) {
      _showSnack('Failed to update stock: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetManualUpdate() {
    _stockController.clear();
    setState(() => _selectedProductId = null);
  }

  void _showManualUpdateDialog() {
    _resetManualUpdate();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Manual Stock Update'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: _selectedProductId,
                    hint: const Text('Select a Product...'),
                    isExpanded: true,
                    items: _products.map((p) => DropdownMenuItem<int>(value: p.id!, child: Text(p.name))).toList(),
                    onChanged: (v) => setDialogState(() => _selectedProductId = v),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _stockController,
                    decoration: const InputDecoration(labelText: 'New Stock Quantity', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _updateStock();
                  },
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showQuickEditDialog(Product p) {
    _stockController.text = p.stock.toStringAsFixed(0);
    _selectedProductId = p.id;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update Stock: ${p.name}'),
        content: TextField(
          controller: _stockController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New Quantity', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _updateStock();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : (isSuccess ? Colors.green.shade700 : Colors.black87),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Management'),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync),
            onPressed: _isLoading ? null : _syncInventory,
            tooltip: 'Sync Inventory',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _loadInventory,
              child: _filteredProducts.isEmpty
                  ? Center(child: Text('No products found.', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)))
                  : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                itemCount: _filteredProducts.length,
                itemBuilder: (context, i) {
                  final p = _filteredProducts[i];
                  final stock = p.stock;
                  final isLowStock = stock > 0 && stock < 10;
                  final isOutOfStock = stock <= 0;

                  return Card(
                    elevation: 1.5,
                    shadowColor: isOutOfStock ? Colors.red.withOpacity(0.1) : (isLowStock ? Colors.orange.withOpacity(0.1) : Colors.black.withOpacity(0.05)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isOutOfStock ? Colors.red.shade100 : (isLowStock ? Colors.orange.shade100 : Colors.indigo.shade50),
                        child: isOutOfStock
                            ? Icon(Icons.inventory_2_outlined, color: Colors.red.shade700)
                            : (isLowStock
                            ? Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700)
                            : Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', style: TextStyle(color: Colors.indigo.shade800, fontWeight: FontWeight.bold))),
                      ),
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Price: ₹${p.price.toStringAsFixed(2)}'),
                      trailing: Text(
                        '${stock.toInt()}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18,
                          color: isOutOfStock ? Colors.red.shade700 : (isLowStock ? Colors.orange.shade700 : Colors.black87),
                        ),
                      ),
                      onTap: () => _showQuickEditDialog(p),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showManualUpdateDialog,
        tooltip: 'Update Stock Manually',
        child: const Icon(Icons.edit_note),
      ),
    );
  }
}