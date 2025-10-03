// lib/screens/inventory_screen.dart
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
  List<Product> _filtered = [];
  final _stockController = TextEditingController();
  final _searchController = TextEditingController();
  int? _selectedProductId;
  bool _isSaving = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadInventory();
    _searchController.addListener(_applyFilter);
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _products
          .where((p) => p.name.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _loadInventory() async {
    final products = await db.getProducts();
    if (mounted) {
      setState(() {
        _products = products;
        _filtered = products;
      });
    }
  }

  Future<void> _syncInventory() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _showSnack('Login to sync data', action: SnackBarAction(
        label: 'LOGIN',
        onPressed: () => Navigator.pushNamed(context, '/login'),
      ));
      return;
    }

    setState(() => _isSyncing = true);
    final result = await _syncService.syncProducts();
    setState(() => _isSyncing = false);

    _showSnack(result.message,
        background: result.success ? Colors.green : Colors.red);

    if (result.success) {
      await _loadInventory();
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
      await db.updateProductStock(_selectedProductId!, qty);
      _showSnack('Stock updated locally');

      if (FirebaseAuth.instance.currentUser != null) {
        final result = await _syncService.syncProducts();
        _showSnack(
          result.success ? 'Stock synced to cloud' : 'Will sync later',
          background: result.success ? Colors.green : Colors.orange,
        );
      }

      _stockController.clear();
      _selectedProductId = null;
      await _loadInventory();
    } catch (e) {
      _showSnack('Failed to update stock: $e', background: Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, {Color? background, SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: background, action: action),
    );
  }

  @override
  void dispose() {
    _stockController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.sync),
            onPressed: _isSyncing ? null : _syncInventory,
            tooltip: 'Sync Inventory',
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
                  const Expanded(
                    child: Text(
                      'Offline mode - Login to sync data',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search product…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadInventory,
              child: _filtered.isEmpty
                  ? const Center(
                child: Text(
                  'No products found',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              )
                  : ListView.separated(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: _filtered.length,
                itemBuilder: (context, i) {
                  final p = _filtered[i];
                  final needsSync = !p.isSynced && isLoggedIn;
                  return Dismissible(
                    key: ValueKey(p.id),
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Product'),
                          content: Text('Delete "${p.name}" permanently?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                    onDismissed: (_) async {
                      await db.deleteProduct(p.id!);
                      _showSnack('Deleted ${p.name}',
                          background: Colors.red);
                      await _loadInventory();
                    },
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo,
                          child: Text(
                            p.name.isNotEmpty
                                ? p.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          p.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Price: ₹${p.price.toStringAsFixed(2)}'),
                            if (needsSync)
                              Text('Pending sync',
                                  style: TextStyle(
                                      color: Colors.orange.shade600,
                                      fontSize: 12)),
                          ],
                        ),
                        trailing: Text(
                          'Stock: ${p.stock}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        onTap: () {
                          // Quick edit dialog
                          _stockController.text = p.stock.toString();
                          _selectedProductId = p.id;
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('Update Stock: ${p.name}'),
                              content: TextField(
                                controller: _stockController,
                                keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'New Quantity',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx),
                                    child: const Text('Cancel')),
                                ElevatedButton(
                                    onPressed: () async {
                                      Navigator.pop(ctx);
                                      await _updateStock();
                                    },
                                    child: const Text('Save')),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Manual Stock Update',
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _selectedProductId,
                  hint: const Text('Select Product'),
                  decoration:
                  const InputDecoration(border: OutlineInputBorder()),
                  items: _products
                      .map((p) =>
                      DropdownMenuItem<int>(value: p.id!, child: Text(p.name)))
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
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
                    label: Text(_isSaving ? 'Saving…' : 'Update Stock'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    onPressed: _isSaving ? null : _updateStock,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
