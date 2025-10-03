import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../models/product.dart';

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen>
    with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();
  final _priceFormat = NumberFormat('#,##0.00');

  List<Product> _products = [];
  List<Product> _filtered = [];
  bool _loading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_filter);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await db.getProducts();
      setState(() {
        _products = list;
        _filtered = list;
      });
    } catch (e) {
      _snack('Failed to load: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sync() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _snack('Login to sync data', Colors.orange);
      return;
    }
    setState(() => _isSyncing = true);
    final result = await _syncService.syncProducts();
    if (mounted) setState(() => _isSyncing = false);
    _snack(result.message, result.success ? Colors.green : Colors.red);
    if (result.success) await _load();
  }

  void _filter() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _products
          .where((p) => p.name.toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _delete(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await db.deleteProduct(id);
      await _load();
      _snack('Product deleted');
      if (FirebaseAuth.instance.currentUser != null) await _sync();
    } catch (e) {
      _snack('Delete failed: $e', Colors.red);
    }
  }

  void _snack(String m, [Color? c]) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m), backgroundColor: c));

  Future<void> _showForm({Product? product}) async {
    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final weightCtrl = TextEditingController(text: product?.weight.toString() ?? '');
    final priceCtrl = TextEditingController(text: product?.price.toString() ?? '');
    final costCtrl = TextEditingController(text: product?.costPrice?.toString() ?? '');
    final key = GlobalKey<FormState>();
    final isEdit = product != null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(top: 12, bottom: 16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),

                        Text(
                          isEdit ? 'Edit Product' : 'Add New Product',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Fill in the product details below',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Form fields
                        Form(
                          key: key,
                          child: Column(
                            children: [
                              _buildTextField(
                                label: 'Product Name',
                                controller: nameCtrl,
                                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                                icon: Icons.inventory_2_outlined,
                              ),
                              const SizedBox(height: 16),
                              _buildNumberField(
                                label: 'Weight (kg/ltr)',
                                controller: weightCtrl,
                                icon: Icons.scale_outlined,
                              ),
                              const SizedBox(height: 16),
                              _buildNumberField(
                                label: 'Selling Price (₹)',
                                controller: priceCtrl,
                                icon: Icons.attach_money_outlined,
                              ),
                              const SizedBox(height: 16),
                              _buildNumberField(
                                label: 'Cost Price (₹)',
                                controller: costCtrl,
                                icon: Icons.price_change_outlined,
                              ),
                              const SizedBox(height: 32),

                              // Action buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.pop(sheetContext),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        side: BorderSide(color: Theme.of(context).colorScheme.outline),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () async {
                                        if (!key.currentState!.validate()) return;
                                        final exists = _products.any((p) =>
                                        p.name.toLowerCase() ==
                                            nameCtrl.text.trim().toLowerCase() &&
                                            p.id != product?.id);
                                        if (exists) {
                                          _snack('Product already exists', Colors.red);
                                          return;
                                        }
                                        final p = Product(
                                          id: product?.id,
                                          name: nameCtrl.text.trim(),
                                          weight: double.parse(weightCtrl.text),
                                          price: double.parse(priceCtrl.text),
                                          costPrice: double.parse(costCtrl.text),
                                          stock: product?.stock ?? 0,
                                        );
                                        Navigator.pop(sheetContext);
                                        await _save(p, isEdit);
                                      },
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        backgroundColor: Theme.of(context).colorScheme.primary,
                                      ),
                                      child: Text(
                                        isEdit ? 'Update' : 'Add Product',
                                        style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24), // Extra spacing
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
      style: const TextStyle(fontSize: 16),
    );
  }

  Widget _buildNumberField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
      ],
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        final n = num.tryParse(v);
        return (n == null || n < 0) ? 'Invalid amount' : null;
      },
      style: const TextStyle(fontSize: 16),
    );
  }

  Future<void> _save(Product p, bool edit) async {
    try {
      if (edit) {
        await db.updateProduct(p.copyWith(isSynced: false, updatedAt: DateTime.now()));
      } else {
        await db.insertProduct(p.copyWith(isSynced: false, updatedAt: DateTime.now()));
      }
      await _load();
      if (FirebaseAuth.instance.currentUser != null) await _sync();
      _snack(edit ? 'Product updated successfully' : 'Product added successfully', Colors.green);
    } catch (e) {
      _snack('Save failed: $e', Colors.red);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Products',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24),
        ),
        backgroundColor: scheme.surface,
        elevation: 0,
        centerTitle: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Sync Products',
              icon: _isSyncing
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              )
                  : Icon(Icons.sync, color: scheme.primary),
              onPressed: _isSyncing ? null : _sync,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, size: 28),
      ),
      body: Column(
        children: [
          // Offline banner
          if (!loggedIn)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                border: Border(bottom: BorderSide(color: scheme.outline.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 20, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline mode - Login to sync your data',
                      style: TextStyle(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, color: scheme.primary),
                hintText: 'Search products by name...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withOpacity(0.4),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
            ),
          ),

          // Results count
          if (_filtered.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} product${_filtered.length == 1 ? '' : 's'} found',
                    style: TextStyle(
                      color: scheme.onSurface.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

          // Products list
          Expanded(
            child: _loading
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading products...'),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _load,
              color: scheme.primary,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _filtered.isEmpty
                    ? Center(
                  key: const ValueKey('empty'),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 80,
                        color: scheme.onSurface.withOpacity(0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No products found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the + button to add your first product',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurface.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  key: const ValueKey('list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: _filtered.length,
                  itemBuilder: (ctx, i) {
                    final p = _filtered[i];
                    final needSync = !p.isSynced && loggedIn;
                    final lowStock = p.stock <= 5 && p.stock > 0;
                    final outOfStock = p.stock == 0;

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: scheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.inventory_2_outlined,
                              color: scheme.primary,
                              size: 24,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (needSync)
                                Tooltip(
                                  message: 'Needs sync',
                                  child: Icon(
                                    Icons.sync_problem,
                                    size: 18,
                                    color: scheme.error,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _buildInfoChip('W:${_priceFormat.format(p.weight)}', Icons.scale),
                                    _buildInfoChip('₹${_priceFormat.format(p.price)}', Icons.attach_money),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (p.costPrice != null && p.costPrice! > 0)
                                  Text(
                                    'Cost: ₹${_priceFormat.format(p.costPrice!)}',
                                    style: TextStyle(
                                      color: scheme.onSurface.withOpacity(0.6),
                                      fontSize: 13,
                                    ),
                                  ),
                                if (p.stock > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      spacing: 8,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          'Stock: ${_priceFormat.format(p.stock)}',
                                          style: TextStyle(
                                            color: lowStock ? Colors.orange : Colors.green,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (lowStock)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Low Stock',
                                              style: TextStyle(
                                                color: Colors.orange.shade800,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                if (outOfStock)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Out of Stock',
                                      style: TextStyle(
                                        color: Colors.red.shade800,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, color: scheme.onSurface.withOpacity(0.6)),
                            onSelected: (v) {
                              if (v == 'edit') _showForm(product: p);
                              if (v == 'delete') _delete(p.id!);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 20, color: scheme.primary),
                                    const SizedBox(width: 8),
                                    const Text('Edit'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 20, color: scheme.error),
                                    const SizedBox(width: 8),
                                    const Text('Delete'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String text, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}