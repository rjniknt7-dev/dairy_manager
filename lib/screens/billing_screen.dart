// lib/screens/billing_screen.dart - FIXED VERSION
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
  const BillingScreen({super.key, this.existingBill});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen>
    with TickerProviderStateMixin {
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

  // Animation controllers
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late AnimationController _fabController;

  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _fabAnimation;

  double get totalAmount =>
      items.fold(0.0, (sum, it) => sum + it.price * it.quantity);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadData();
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _fabAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    _fabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

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

        _fadeController.forward();
        _slideController.forward();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _fabController.forward();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to load data: $e');
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
      _showErrorSnackBar("Please select a client");
      return;
    }
    if (items.isEmpty) {
      _showErrorSnackBar("Add at least one product");
      return;
    }
    if (!_hasSufficientStock()) {
      _showErrorSnackBar("Insufficient stock for some items");
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
        _showSuccessSnackBar('Bill saved and synced successfully');
      } catch (_) {
        _showWarningSnackBar('Bill saved locally. Will sync when online.');
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
      _showErrorSnackBar('Error saving bill: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _showUpdateConfirmation() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.update, color: Colors.orange),
            ),
            const SizedBox(width: 12),
            const Text('Update Bill'),
          ],
        ),
        content: const Text('This will overwrite the existing bill. Do you want to continue?'),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      _showWarningSnackBar("Only $available units available for ${prod.name}");
      return;
    }

    setState(() {
      final idx = items.indexWhere((it) => it.productId == productId);
      if (idx != -1) {
        items[idx] = items[idx].copyWith(quantity: items[idx].quantity + 1);
      } else {
        // Add new item at the beginning of the list
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
      _showWarningSnackBar("Only $available units available");
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
                _showWarningSnackBar("Only $available units available");
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Fixed header with slim padding
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.indigo, Color(0xFF3F51B5)],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    padding: const EdgeInsets.all(4),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.existingBill == null ? 'Create Bill' : 'Edit Bill',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors.white, size: 20),
                    padding: const EdgeInsets.all(4),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const HistoryScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Content with slim padding
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (clients.isEmpty)
                        _buildEmptyState('No clients found. Add clients first.')
                      else
                        _buildClientSelection(),

                      const SizedBox(height: 8),

                      if (products.isEmpty)
                        _buildEmptyState('No products found. Add products first.')
                      else
                        _buildProductSelection(),

                      const SizedBox(height: 8),

                      _buildItemsList(),

                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabAnimation,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (items.isNotEmpty && selectedClientId != null) ...[
              FloatingActionButton(
                heroTag: 'preview',
                onPressed: _previewBill,
                backgroundColor: Colors.orange,
                mini: true,
                child: const Icon(Icons.preview, size: 20),
              ),
              const SizedBox(height: 8),
            ],
            FloatingActionButton.extended(
              heroTag: 'save',
              onPressed: _saving ? null : _saveBill,
              label: Text(
                _saving ? 'Saving...' : 'Save Bill',
                style: const TextStyle(fontSize: 14),
              ),
              icon: _saving
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.save, size: 18),
              backgroundColor: Colors.indigo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Colors.grey[700],
          fontSize: 13,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildClientSelection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              constraints: BoxConstraints(
                maxHeight: 50, // Fixed height to prevent overflow
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonFormField<int>(
                value: selectedClientId,
                isExpanded: true, // Important for overflow fix
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  hintText: 'Choose a client...',
                ),
                items: clients.map((client) => DropdownMenuItem<int>(
                  value: client.id,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.blue.shade100,
                          child: Text(
                            client.name.isNotEmpty
                                ? client.name[0].toUpperCase()
                                : 'C',
                            style: TextStyle(
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                client.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                client.phone,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
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
    );
  }

  Widget _buildProductSelection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.inventory_2,
                      color: Colors.green.shade600, size: 18),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Add Products',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 50),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonFormField<int>(
                value: selectedProductId,
                isExpanded: true, // fixes overflow
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  hintText: 'Choose a product to add...',
                ),
                items: products.map((product) {
                  final stock = stockMap[product.id] ?? 0;
                  final existingItem = items.firstWhere(
                        (item) => item.productId == product.id,
                    orElse: () =>
                        BillItem(productId: -1, quantity: 0, price: 0),
                  );
                  final hasItem = existingItem.productId != -1;

                  return DropdownMenuItem<int>(
                    value: product.id,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: stock > 0 ? Colors.green : Colors.red,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                product.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                '${_currencyFormat.format(product.price)} • Stock: $stock',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                        if (hasItem)
                          Row(
                            children: [
                              // Decrease button
                              IconButton(
                                icon: const Icon(Icons.remove,
                                    size: 16, color: Colors.red),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _decreaseQuantity(existingItem),
                              ),
                              // Qty display
                              Text(
                                '${existingItem.quantity.toInt()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              // Increase button
                              IconButton(
                                icon: const Icon(Icons.add,
                                    size: 16, color: Colors.green),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _increaseQuantity(existingItem),
                              ),
                            ],
                          ),
                      ],
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
    );
  }

  Widget _buildItemsList() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Bill Items',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (items.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${items.length} items',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // TOTAL AMOUNT ABOVE ITEMS
            if (items.isNotEmpty) ...[
              _buildTotalSection(),
              const SizedBox(height: 12),
              const Divider(thickness: 0.5, height: 1),
              const SizedBox(height: 8),
            ],

            if (items.isEmpty)
              _buildEmptyItemsState()
            else
              ..._buildItemsListContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyItemsState() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(Icons.shopping_cart_outlined, size: 36, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            'No items added yet',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 2),
          Text(
            'Select products above to add them to the bill',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildItemsListContent() {
    return [
      // Items will be added from top (newest first)
      ...items.map((item) {
        final product = products.firstWhere((p) => p.id == item.productId);
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          child: _buildBillItemCard(item, product),
        );
      }),
    ];
  }

  Widget _buildBillItemCard(BillItem item, Product product) {
    final stock = stockMap[product.id] ?? 0;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Product Info on LEFT side
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.blue.shade100,
                      child: Text(
                        product.name[0].toUpperCase(),
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Text(
                            '${_currencyFormat.format(item.price)} • Stock: $stock',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Quantity Controls on RIGHT side
          Column(
            children: [
              // Quantity display and controls
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Remove button
                    IconButton(
                      onPressed: () => _removeItem(item),
                      icon: const Icon(Icons.close, color: Colors.red, size: 16),
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),

                    // Quantity display
                    GestureDetector(
                      onTap: () => _editQuantityWithKeyboard(item),
                      child: Container(
                        width: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Text(
                          '${item.quantity.toInt()}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // Quantity controls
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Increase button
                        GestureDetector(
                          onTap: () => _increaseQuantity(item),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(4),
                              ),
                            ),
                            child: const Icon(Icons.add, size: 12, color: Colors.green),
                          ),
                        ),
                        // Decrease button
                        GestureDetector(
                          onTap: () => _decreaseQuantity(item),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: const BorderRadius.only(
                                bottomRight: Radius.circular(4),
                              ),
                            ),
                            child: const Icon(Icons.remove, size: 12, color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Total price for this item
              const SizedBox(height: 4),
              Text(
                _currencyFormat.format(item.price * item.quantity),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade50, Colors.indigo.shade100],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Total Amount',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _currencyFormat.format(totalAmount),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _previewBill() async {
    if (selectedClientId == null || items.isEmpty) return;

    try {
      final client = clients.firstWhere((c) => c.id == selectedClientId);
      final billItems = items.map((item) {
        final product = products.firstWhere((p) => p.id == item.productId);
        return {
          'name': product.name,
          'qty': item.quantity,
          'price': item.price,
        };
      }).toList();

      final pdfBytes = await invoiceService.buildPdf(
        customerName: client.name,
        invoiceNo: 'DRAFT-${DateTime.now().millisecondsSinceEpoch}',
        date: DateTime.now(),
        items: billItems,
        receivedAmount: 0,
      );

      _showSuccessSnackBar('Bill preview generated successfully');
    } catch (e) {
      _showErrorSnackBar('Failed to generate preview: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}