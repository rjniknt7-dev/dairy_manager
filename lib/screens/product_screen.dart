// lib/screens/product_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../models/product.dart';

class ProductScreen extends StatefulWidget {
  const ProductScreen({Key? key}) : super(key: key);

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final DatabaseHelper db = DatabaseHelper();
  final FirebaseSyncService _sync = FirebaseSyncService();
  final _priceFormat = NumberFormat('#,##0.00');

  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  bool _loading = true;
  bool _isSearching = false;
  bool _isSyncing = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadProducts();
    _searchController.addListener(_filterProducts);
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    if (mounted) setState(() => _loading = true);

    try {
      final products = await db.getProducts();
      if (!mounted) return;

      setState(() {
        _products = products;
        _filteredProducts = products;
        _loading = false;
      });

      if (mounted) {
        _animationController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnackBar('Failed to load products: $e', success: false);
      }
    }
  }

  Future<void> _syncProducts() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _showSnackBar('Login to sync data', success: false);
      return;
    }

    setState(() => _isSyncing = true);
    try {
      final result = await _sync.syncProducts();
      if (mounted) {
        _showSnackBar(result.message, success: result.success);
        if (result.success) await _loadProducts();
      }
    } catch (e) {
      if (mounted) _showSnackBar('Sync failed: $e', success: false);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase().trim();
    if (mounted) {
      setState(() {
        _filteredProducts = _products.where((product) {
          return query.isEmpty ||
              product.name.toLowerCase().contains(query);
        }).toList();
      });
    }
  }

  Future<void> _deleteProduct(int id, String name) async {
    final confirm = await _showDeleteConfirmation(name);
    if (!confirm) return;

    try {
      await db.deleteProduct(id);
      await _syncProducts();

      if (mounted) {
        _loadProducts();
        _showSnackBar('$name deleted successfully');
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) _showSnackBar('Failed to delete product: $e', success: false);
    }
  }

  Future<bool> _showDeleteConfirmation(String productName) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Delete Product'),
          ],
        ),
        content: Text('Are you sure you want to delete "$productName"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _showAddEditDialog({Product? product}) async {
    if (!mounted) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            _AddEditProductScreen(
              product: product,
              onSaved: () {
                _loadProducts();
              },
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 1.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            if (_loading) ...[
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
            ] else if (_filteredProducts.isEmpty) ...[
              SliverFillRemaining(child: _buildEmptyState()),
            ] else ...[
              _buildProductsList(),
            ],
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildSliverAppBar() {
    final loggedIn = FirebaseAuth.instance.currentUser != null;

    return SliverAppBar(
      expandedHeight: 140,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.green,
      flexibleSpace: FlexibleSpaceBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isSearching
              ? Container(
            key: const ValueKey('search'),
            width: double.infinity,
            height: 40,
            margin: const EdgeInsets.only(right: 60),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search products...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.search, color: Colors.white),
              ),
            ),
          )
              : const Text(
            'Products',
            key: ValueKey('title'),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.green.shade600, Colors.green.shade800],
            ),
          ),
          child: !loggedIn ? _buildOfflineBanner() : null,
        ),
      ),
      actions: [
        if (!_isSearching)
          IconButton(
            icon: _isSyncing
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.sync, color: Colors.white),
            onPressed: _isSyncing ? null : _syncProducts,
          ),
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              _isSearching ? Icons.close : Icons.search,
              key: ValueKey(_isSearching),
              color: Colors.white,
            ),
          ),
          onPressed: () {
            if (!mounted) return;
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                _filterProducts();
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildOfflineBanner() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.cloud_off, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Offline Mode - Login to Sync',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsList() {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
              (context, index) {
            final product = _filteredProducts[index];
            final needSync = !product.isSynced && FirebaseAuth.instance.currentUser != null;
            final lowStock = product.stock <= 5 && product.stock > 0;
            final outOfStock = product.stock == 0;

            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 300 + (index * 100)),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                // ✅ FIX: Clamp the opacity value to prevent errors
                final clampedValue = value.clamp(0.0, 1.0);
                return Transform.translate(
                  offset: Offset(0, 50 * (1 - clampedValue)),
                  child: Opacity(
                    opacity: clampedValue, // ✅ Use clamped value
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: _buildProductCard(product, needSync, lowStock, outOfStock),
                    ),
                  ),
                );
              },
            );
          },
          childCount: _filteredProducts.length,
        ),
      ),
    );
  }

  Widget _buildProductCard(Product product, bool needSync, bool lowStock, bool outOfStock) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showAddEditDialog(product: product),
        child: Padding(
          padding: const EdgeInsets.all(12), // ✅ REDUCED from 16 to 12
          child: Row(
            children: [
              Hero(
                tag: 'product_${product.id}',
                child: Container(
                  width: 48, // ✅ REDUCED from 56 to 48
                  height: 48, // ✅ REDUCED from 56 to 48
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600],
                    ),
                    borderRadius: BorderRadius.circular(24), // ✅ REDUCED from 28 to 24
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade200,
                        blurRadius: 6, // ✅ REDUCED from 8 to 6
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: Colors.white,
                      size: 20, // ✅ REDUCED from 24 to 20
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12), // ✅ REDUCED from 16 to 12
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // ✅ ADDED to make column compact
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 16, // ✅ REDUCED from 18 to 16
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (needSync)
                          Tooltip(
                            message: 'Needs sync',
                            child: Icon(
                              Icons.sync_problem,
                              size: 16, // ✅ REDUCED from 18 to 16
                              color: Colors.orange,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4), // ✅ REDUCED from 6 to 4
                    Wrap(
                      spacing: 6, // ✅ REDUCED from 8 to 6
                      runSpacing: 2, // ✅ REDUCED from 4 to 2
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(1), // ✅ REDUCED from 2 to 1
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(3), // ✅ REDUCED from 4 to 3
                              ),
                              child: Icon(Icons.scale, size: 12, color: Colors.blue.shade600), // ✅ REDUCED from 14 to 12
                            ),
                            const SizedBox(width: 3), // ✅ REDUCED from 4 to 3
                            Text(
                              '${_priceFormat.format(product.quantity)} ',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12, // ✅ REDUCED from 14 to 12
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(1), // ✅ REDUCED from 2 to 1
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(3), // ✅ REDUCED from 4 to 3
                              ),
                              child: Icon(Icons.attach_money, size: 12, color: Colors.purple.shade600), // ✅ REDUCED from 14 to 12
                            ),
                            const SizedBox(width: 3), // ✅ REDUCED from 4 to 3
                            Text(
                              '₹${_priceFormat.format(product.price)}',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12, // ✅ REDUCED from 14 to 12
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (product.costPrice != null && product.costPrice! > 0) ...[
                      const SizedBox(height: 2), // ✅ REDUCED from 4 to 2
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(1), // ✅ REDUCED from 2 to 1
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(3), // ✅ REDUCED from 4 to 3
                            ),
                            child: Icon(Icons.price_change, size: 12, color: Colors.orange.shade600), // ✅ REDUCED from 14 to 12
                          ),
                          const SizedBox(width: 4), // ✅ KEPT same for readability
                          Flexible(
                            child: Text(
                              'Cost: ₹${_priceFormat.format(product.costPrice!)}',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12, // ✅ REDUCED from 14 to 12
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 2), // ✅ REDUCED from 4 to 2
                    Wrap(
                      spacing: 6, // ✅ REDUCED from 8 to 6
                      runSpacing: 2, // ✅ REDUCED from 4 to 2
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(1), // ✅ REDUCED from 2 to 1
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(3), // ✅ REDUCED from 4 to 3
                              ),
                              child: Icon(Icons.inventory, size: 12, color: Colors.green.shade600), // ✅ REDUCED from 14 to 12
                            ),
                            const SizedBox(width: 3), // ✅ REDUCED from 4 to 3
                            Text(
                              'Stock: ${_priceFormat.format(product.stock)}',
                              style: TextStyle(
                                color: outOfStock ? Colors.red : (lowStock ? Colors.orange : Colors.green),
                                fontSize: 12, // ✅ REDUCED from 14 to 12
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (lowStock)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), // ✅ REDUCED padding
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(3), // ✅ REDUCED from 4 to 3
                            ),
                            child: Text(
                              'Low Stock',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 9, // ✅ REDUCED from 10 to 9
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (outOfStock)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), // ✅ REDUCED padding
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(3), // ✅ REDUCED from 4 to 3
                            ),
                            child: Text(
                              'Out of Stock',
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontSize: 9, // ✅ REDUCED from 10 to 9
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20), // ✅ ADDED smaller icon
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (value) => _handleMenuAction(value, product),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, color: Colors.blue, size: 18), // ✅ REDUCED icon size
                        SizedBox(width: 6), // ✅ REDUCED spacing
                        Text('Edit', style: TextStyle(fontSize: 13)), // ✅ REDUCED text size
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red, size: 18), // ✅ REDUCED icon size
                        SizedBox(width: 6), // ✅ REDUCED spacing
                        Text('Delete', style: TextStyle(fontSize: 13)), // ✅ REDUCED text size
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleMenuAction(String action, Product product) {
    switch (action) {
      case 'edit':
        _showAddEditDialog(product: product);
        break;
      case 'delete':
        _deleteProduct(product.id!, product.name);
        break;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              // ✅ FIX: Clamp the scale value
              final clampedValue = value.clamp(0.0, 1.0);
              return Transform.scale(
                scale: clampedValue,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(60),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade100,
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 60,
                    color: Colors.green.shade400,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            _searchController.text.isEmpty ? 'No products yet' : 'No products found',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isEmpty
                ? 'Add your first product to get started'
                : 'Try adjusting your search',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          if (_searchController.text.isEmpty) ...[
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add First Product'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                elevation: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton.extended(
      onPressed: () => _showAddEditDialog(),
      icon: const Icon(Icons.add),
      label: const Text('Add Product'),
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      elevation: 4,
    );
  }

  void _showSnackBar(String message, {bool success = true}) {
    if (!mounted) return;

    final color = success ? Colors.green : Colors.red;
    final icon = success ? Icons.check_circle : Icons.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message))
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

// Add/Edit Product Screen as a separate widget
class _AddEditProductScreen extends StatefulWidget {
  final Product? product;
  final VoidCallback onSaved;

  const _AddEditProductScreen({
    this.product,
    required this.onSaved,
  });

  @override
  State<_AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<_AddEditProductScreen>
    with SingleTickerProviderStateMixin {
  final _db = DatabaseHelper();
  final _sync = FirebaseSyncService();
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  late TextEditingController _nameController;
  late TextEditingController _weightController;
  late TextEditingController _priceController;
  late TextEditingController _costController;

  bool _saving = false;
  bool _hasChanges = false;
  bool get _isEditing => widget.product != null;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _weightController = TextEditingController(text: widget.product?.quantity.toString() ?? '');
    _priceController = TextEditingController(text: widget.product?.price.toString() ?? '');
    _costController = TextEditingController(text: widget.product?.costPrice?.toString() ?? '');

    _nameController.addListener(_onChange);
    _weightController.addListener(_onChange);
    _priceController.addListener(_onChange);
    _costController.addListener(_onChange);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  void _onChange() {
    if (!mounted) return;

    final hasChanges = _isEditing
        ? (_nameController.text != (widget.product?.name ?? '') ||
        _weightController.text != (widget.product?.quantity.toString() ?? '') ||
        _priceController.text != (widget.product?.price.toString() ?? '') ||
        _costController.text != (widget.product?.costPrice?.toString() ?? ''))
        : (_nameController.text.isNotEmpty ||
        _weightController.text.isNotEmpty ||
        _priceController.text.isNotEmpty);

    if (_hasChanges != hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    // Check for duplicate product name
    final products = await _db.getProducts();
    final duplicate = products.any((p) =>
    p.name.toLowerCase() == _nameController.text.trim().toLowerCase() &&
        p.id != widget.product?.id);

    if (duplicate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Product with this name already exists'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);

    try {
      final product = Product(
        id: widget.product?.id,
        name: _nameController.text.trim(),
        quantity: double.parse(_weightController.text),
        price: double.parse(_priceController.text),
        costPrice: double.tryParse(_costController.text) ?? 0.0,
        stock: widget.product?.stock ?? 0.0,
      );

      if (_isEditing) {
        await _db.updateProduct(product);
      } else {
        await _db.insertProduct(product);
      }

      await _sync.syncProducts();

      if (mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Product updated successfully' : 'Product added successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        widget.onSaved();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateNumber(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter $fieldName';
    }
    final number = double.tryParse(value);
    if (number == null || number < 0) {
      return 'Enter valid $fieldName';
    }
    return null;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    _weightController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Product' : 'Add Product'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.green.shade400, Colors.green.shade600],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _isEditing ? Icons.edit : Icons.add,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              _isEditing ? 'Edit Information' : 'Product Information',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Product Name',
                            prefixIcon: const Icon(Icons.inventory_2_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Enter product name' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _weightController,
                          decoration: InputDecoration(
                            labelText: 'Quantity',
                            prefixIcon: const Icon(Icons.scale_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                          ],
                          validator: (v) => _validateNumber(v, 'weight'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _priceController,
                          decoration: InputDecoration(
                            labelText: 'Selling Price (₹)',
                            prefixIcon: const Icon(Icons.attach_money_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                          ],
                          validator: (v) => _validateNumber(v, 'price'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _costController,
                          decoration: InputDecoration(
                            labelText: 'Cost Price (₹) - Optional',
                            prefixIcon: const Icon(Icons.price_change_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                          ],
                        ),
                        if (_hasChanges) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.green.shade600),
                                const SizedBox(width: 8),
                                Text(
                                  _isEditing ? 'Changes ready to save' : 'Ready to add product',
                                  style: TextStyle(color: Colors.green.shade700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _hasChanges && !_saving ? _saveProduct : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _hasChanges ? Colors.green : Colors.grey.shade300,
                          foregroundColor: _hasChanges ? Colors.white : Colors.grey.shade500,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : Text(_isEditing ? 'Update Product' : 'Add Product'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}