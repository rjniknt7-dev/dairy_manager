// lib/screens/billing_screen.dart - COMPACT FIXED VERSION
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/client.dart';
import '../models/product.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../services/invoice_service.dart';
import 'history_screen.dart';

class BillingScreen extends StatefulWidget {
  final Bill? existingBill;
  const BillingScreen({Key? key, this.existingBill}) : super(key: key);

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen>
    with SingleTickerProviderStateMixin {
  final db = DatabaseHelper();
  final invoiceService = InvoiceService();
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  List<Client> clients = [];
  List<Product> products = [];
  Map<int, double> stockMap = {};

  int? selectedClientId;
  int? selectedProductId;
  List<BillItem> items = [];

  bool _saving = false;
  bool _isLoading = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  double get totalAmount =>
      items.fold(0.0, (sum, it) => sum + it.price * it.quantity);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadData();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final loadedClients = await db.getClients();
      final loadedProducts = await db.getProducts();
      final stockEntries = await Future.wait(
        loadedProducts.map((p) => db.getStock(p.id!).then((s) => MapEntry(p.id!, s))),
      );

      List<BillItem> loadedItems = [];
      int? clientId;
      if (widget.existingBill != null) {
        loadedItems = await db.getBillItems(widget.existingBill!.id!);
        clientId = widget.existingBill!.clientId;
      }

      if (mounted) {
        setState(() {
          clients = loadedClients;
          products = loadedProducts;
          stockMap = Map.fromEntries(stockEntries);
          items = loadedItems;
          selectedClientId = clientId;
          _isLoading = false;
        });

        _animationController.forward();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showSnackBar('Failed to load data: $e', success: false);
    }
  }

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
      _showSnackBar("Please select a client", success: false);
      return;
    }
    if (items.isEmpty) {
      _showSnackBar("Add at least one product", success: false);
      return;
    }
    if (!_hasSufficientStock()) {
      _showSnackBar("Insufficient stock for some items", success: false);
      return;
    }

    if (widget.existingBill != null) {
      final confirm = await _showUpdateConfirmation();
      if (!confirm) return;
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

      if (widget.existingBill == null) {
        await db.insertBillWithItems(bill, items);
      } else {
        await db.updateBillWithItems(bill, items);
      }

      try {
        await FirebaseSyncService().syncBills();
        _showSnackBar('Bill saved and synced successfully');
      } catch (_) {
        _showSnackBar('Bill saved locally. Will sync when online.', success: false);
      }

      HapticFeedback.lightImpact();

      if (mounted) {
        setState(() {
          selectedClientId = null;
          selectedProductId = null;
          items.clear();
        });
      }
    } catch (e) {
      _showSnackBar('Error saving bill: $e', success: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _showUpdateConfirmation() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.update, color: Colors.orange),
            SizedBox(width: 8),
            Text('Update Bill'),
          ],
        ),
        content: const Text('This will overwrite the existing bill. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _addOrIncrementProductById(int productId) {
    final prod = products.firstWhere((p) => p.id == productId);
    final available = stockMap[productId] ?? 0;

    final currentQty = items
        .where((it) => it.productId == productId)
        .fold<double>(0, (s, it) => s + it.quantity);

    if (currentQty + 1 > available) {
      _showSnackBar("Only $available units available for ${prod.name}", success: false);
      return;
    }

    setState(() {
      final idx = items.indexWhere((it) => it.productId == productId);
      if (idx != -1) {
        items[idx] = items[idx].copyWith(quantity: items[idx].quantity + 1);
      } else {
        items.insert(0, BillItem(
          productId: prod.id!,
          quantity: 1,
          price: prod.price,
        ));
      }
      selectedProductId = null;
    });

    HapticFeedback.lightImpact();
  }

  void _increaseQuantity(BillItem item) {
    final available = stockMap[item.productId] ?? 0;
    final current = items
        .where((it) => it.productId == item.productId)
        .fold<double>(0, (s, it) => s + it.quantity);

    if (current + 1 > available) {
      _showSnackBar("Only $available units available", success: false);
      return;
    }

    setState(() {
      final idx = items.indexOf(item);
      items[idx] = item.copyWith(quantity: item.quantity + 1);
    });

    HapticFeedback.lightImpact();
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

    HapticFeedback.lightImpact();
  }

  void _removeItem(BillItem item) {
    setState(() => items.remove(item));
    HapticFeedback.lightImpact();
  }

  void _editQuantityWithKeyboard(BillItem item) {
    TextEditingController controller = TextEditingController(text: item.quantity.toInt().toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Quantity'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantity',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newQuantity = double.tryParse(controller.text) ?? item.quantity;
              final available = stockMap[item.productId] ?? 0;

              if (newQuantity > available) {
                _showSnackBar("Only $available units available", success: false);
                return;
              }

              if (newQuantity > 0) {
                setState(() {
                  final idx = items.indexOf(item);
                  items[idx] = item.copyWith(quantity: newQuantity);
                });
              } else {
                _removeItem(item);
              }

              Navigator.pop(context);
              HapticFeedback.lightImpact();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          slivers: [
            // HEADER - COMPACT
            SliverAppBar(
              expandedHeight: 80, // REDUCED HEIGHT
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.purple,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  widget.existingBill == null ? 'Create Bill' : 'Edit Bill',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16, // SMALLER FONT
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.purple.shade600, Colors.purple.shade800],
                    ),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.history, color: Colors.white, size: 20),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HistoryScreen()),
                    );
                  },
                ),
              ],
            ),

            if (clients.isEmpty || products.isEmpty) ...[
              SliverFillRemaining(
                child: _buildEmptyState(),
              ),
            ] else ...[
              _buildContentSlivers(),
            ],
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildContentSlivers() {
    return SliverList(
      delegate: SliverChildListDelegate([
        const SizedBox(height: 8), // REDUCED SPACING
        _buildClientSelection(),
        const SizedBox(height: 8), // REDUCED SPACING
        _buildProductSelection(),
        const SizedBox(height: 8), // REDUCED SPACING
        _buildItemsList(),
        const SizedBox(height: 80), // Space for FAB
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long,
            size: 60,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            clients.isEmpty ? 'No clients found' : 'No products found',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            clients.isEmpty
                ? 'Add clients first to create bills'
                : 'Add products first to create bills',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // REPLACE ONLY THESE METHODS IN YOUR BILLING SCREEN:

  // REPLACE ONLY THESE METHODS IN YOUR BILLING SCREEN:

  Widget _buildClientSelection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.person, color: Colors.blue.shade600, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Select Client',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonFormField<int>(
                  value: selectedClientId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    hintText: 'Choose client...',
                  ),
                  items: clients.map((client) => DropdownMenuItem<int>(
                    value: client.id,
                    child: Container(
                      height: 40, // Fixed height
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              client.name.isNotEmpty ? client.name[0].toUpperCase() : 'C',
                              style: TextStyle(
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // SINGLE LINE - NO COLUMN
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: client.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' • ${client.phone}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )).toList(),
                  onChanged: (id) => setState(() => selectedClientId = id),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductSelection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.inventory_2, color: Colors.green.shade600, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Add Products',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonFormField<int>(
                  value: selectedProductId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    hintText: 'Choose product...',
                  ),
                  items: products.map((product) {
                    final stock = stockMap[product.id] ?? 0;
                    final existingItem = items.firstWhere(
                          (item) => item.productId == product.id,
                      orElse: () => BillItem(productId: -1, quantity: 0, price: 0),
                    );
                    final hasItem = existingItem.productId != -1;

                    return DropdownMenuItem<int>(
                      value: product.id,
                      child: Container(
                        height: 40, // Fixed height
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: stock > 0 ? Colors.green : Colors.red,
                              ),
                            ),
                            // SINGLE LINE - NO COLUMN
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' • ${_currencyFormat.format(product.price)} • Stock: $stock',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (hasItem)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${existingItem.quantity.toInt()}',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (pid) {
                    if (pid != null) _addOrIncrementProductById(pid);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildItemsList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.shopping_cart, color: Colors.orange.shade600, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Bill Items',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${items.length} items',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (items.isEmpty)
                _buildEmptyItemsState()
              else
                ..._buildItemsListContent(),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildEmptyItemsState() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min, // IMPORTANT: Makes column compact
        children: [
          Icon(Icons.shopping_cart_outlined, size: 36, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text(
            'No items added yet',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Select products above to add them',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildItemsListContent() {
    return [
      // TOTAL AMOUNT ABOVE ITEMS
      if (items.isNotEmpty) ...[
        _buildTotalSection(),
        const SizedBox(height: 12),
      ],

      // Items list
      ...items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final product = products.firstWhere((p) => p.id == item.productId);

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 200 + (index * 50)),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            final clampedValue = value.clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(0, 30 * (1 - clampedValue)),
              child: Opacity(
                opacity: clampedValue,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: _buildBillItemCard(item, product),
                ),
              ),
            );
          },
        );
      }),
    ];
  }

  Widget _buildBillItemCard(BillItem item, Product product) {
    final stock = stockMap[product.id] ?? 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Product info (expands nicely)
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product name
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),

                  // Stock info only
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.inventory_2_outlined,
                          size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'Stock: $stock',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Quantity Controls (smartly shrink or wrap)
            Flexible(
              flex: 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // If space is tight, shrink the buttons
                  final isTight = constraints.maxWidth < 160;
                  final iconSize = isTight ? 12.0 : 14.0;
                  final pad = isTight ? 1.0 : 2.0;

                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _removeItem(item),
                          icon: Icon(Icons.close,
                              size: iconSize, color: Colors.red),
                          padding: EdgeInsets.all(pad),
                          constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),

                        IconButton(
                          onPressed: () => _decreaseQuantity(item),
                          icon: Icon(Icons.remove, size: iconSize),
                          padding: EdgeInsets.all(pad),
                          constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red,
                          ),
                        ),

                        Container(
                          width: 36,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            '${item.quantity.toInt()}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        IconButton(
                          onPressed: () => _increaseQuantity(item),
                          icon: Icon(Icons.add, size: iconSize),
                          padding: EdgeInsets.all(pad),
                          constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.green.shade50,
                            foregroundColor: Colors.green,
                          ),
                        ),
                      ],
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






// Remove the total section from the bottom of _buildItemsList()
// The total will now be displayed above the items

  Widget _buildTotalSection() {
    return Container(
      padding: const EdgeInsets.all(12), // COMPACT
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade50, Colors.purple.shade100],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Total Amount',
            style: TextStyle(
              fontSize: 16, // SMALLER
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _currencyFormat.format(totalAmount),
            style: const TextStyle(
              fontSize: 16, // SMALLER
              fontWeight: FontWeight.bold,
              color: Colors.purple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton.extended(
      onPressed: _saving ? null : _saveBill,
      icon: _saving
          ? const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      )
          : const Icon(Icons.save, size: 20),
      label: Text(_saving ? 'Saving...' : 'Save Bill', style: const TextStyle(fontSize: 14)),
      backgroundColor: Colors.purple,
      foregroundColor: Colors.white,
    );
  }

  Future<void> _previewBill() async {
    // Preview functionality can be added later
  }

  void _showSnackBar(String message, {bool success = true}) {
    if (!mounted) return;

    final color = success ? Colors.green : Colors.red;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}