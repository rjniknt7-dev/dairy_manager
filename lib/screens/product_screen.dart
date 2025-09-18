import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart'; // ✅ for consistent number formatting
import '../services/database_helper.dart';
import '../services/backup_service.dart';
import '../models/product.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // ✅ check internet

class ProductScreen extends StatefulWidget {
  const ProductScreen({Key? key}) : super(key: key);

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final _searchController = TextEditingController();
  final db = DatabaseHelper();
  final _backup = BackupService();

  final _priceFormat = NumberFormat('#,##0.00');
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchController.addListener(_filterProducts);
  }

  /// Check if online
  Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Load products: online first, then fallback to local SQLite
  Future<void> _loadProducts() async {
    setState(() => _loading = true);

    try {
      List<Product> products = [];

      if (await _isOnline()) {
        // Fetch Firestore products
        try {
          final snapshot = await _backup.getProductsFromFirestore(); // 🔹 create this in BackupService
          products = snapshot;
          // Save to local DB
          await db.saveProductsToLocal(products);
        } catch (_) {
          // Ignore Firestore error
          products = await db.getProducts();
        }
      } else {
        // Offline → get from local DB
        products = await db.getProducts();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline mode – showing cached products')),
        );
      }

      if (!mounted) return;
      setState(() {
        _products = products;
        _filteredProducts = products;
      });
    } catch (e) {
      _showSnack('Failed to load products: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts =
          _products.where((p) => p.name.toLowerCase().contains(query)).toList();
    });
  }

  Future<void> _deleteProduct(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    await db.deleteProduct(id);
    try {
      await _backup.deleteProduct(id);
    } catch (e) {
      _showSnack('Cloud delete failed: $e');
    }
    await _reloadFromLocal();
    _showSnack('Product deleted');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _reloadFromLocal() async {
    final products = await db.getProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _filteredProducts = products;
    });
  }

  /// Add or edit a product
  Future<void> _showAddEditDialog({Product? product}) async {
    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final weightCtrl = TextEditingController(text: product?.weight.toString() ?? '');
    final priceCtrl = TextEditingController(text: product?.price.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final isEditing = product != null;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEditing ? 'Edit Product' : 'Add Product'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Product Name'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null,
                ),
                TextFormField(
                  controller: weightCtrl,
                  decoration: const InputDecoration(labelText: 'Weight (kg/ltr)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter weight';
                    final n = num.tryParse(v);
                    return (n == null || n < 0) ? 'Enter valid number' : null;
                  },
                ),
                TextFormField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(labelText: 'Price (₹)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter price';
                    final n = num.tryParse(v);
                    return (n == null || n < 0) ? 'Enter valid number' : null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            child: Text(isEditing ? 'Update' : 'Add'),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final newName = nameCtrl.text.trim();
              final exists = _products.any((p) =>
              p.name.toLowerCase() == newName.toLowerCase() &&
                  p.id != product?.id);
              if (!isEditing && exists) {
                _showSnack('Product already exists');
                return;
              }

              final newProduct = Product(
                id: product?.id,
                name: newName,
                weight: double.parse(weightCtrl.text.trim()),
                price: double.parse(priceCtrl.text.trim()),
              );

              if (isEditing) {
                await db.updateProduct(newProduct);
              } else {
                try {
                  await db.insertProduct(newProduct);
                } catch (e) {
                  _showSnack('Failed to add product: $e');
                  return;
                }
              }

              try {
                if (await _isOnline()) {
                  await _backup.backupProduct(newProduct);
                }
              } catch (e) {
                _showSnack('Backup failed: $e');
              }

              if (mounted) {
                Navigator.pop(context);
                _showSnack(isEditing ? 'Product updated' : 'Product added');
                await _reloadFromLocal();
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registered Products')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadProducts,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search by name',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: _filteredProducts.isEmpty
                  ? const Center(child: Text('No products found'))
                  : ListView.builder(
                itemCount: _filteredProducts.length,
                itemBuilder: (context, index) {
                  final p = _filteredProducts[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      title: Text(p.name),
                      subtitle: Text(
                        'Weight: ${_priceFormat.format(p.weight)} | Price: ₹${_priceFormat.format(p.price)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteProduct(p.id!),
                      ),
                      onTap: () => _showAddEditDialog(product: p),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
