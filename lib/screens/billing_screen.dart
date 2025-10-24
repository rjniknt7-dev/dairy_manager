// lib/screens/billing_screen.dart - v2.1 (Keyboard Auto-Dismiss Fix)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/client.dart';
import '../models/product.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import 'history_screen.dart';

class BillingScreen extends StatefulWidget {
  final Bill? existingBill;
  const BillingScreen({Key? key, this.existingBill}) : super(key: key);

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final db = DatabaseHelper();
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  // State
  List<Client> clients = [];
  List<Product> products = [];
  Map<int, double> stockMap = {};
  int? selectedClientId;
  List<BillItem> items = [];

  // UI Control
  bool _saving = false;
  bool _isLoading = true;

  // ✅ ADDED: Controllers for both autocomplete fields
  final TextEditingController _clientController = TextEditingController();
  final TextEditingController _productController = TextEditingController();

  // ✅ ADDED: Focus nodes for manual focus control
  final FocusNode _clientFocusNode = FocusNode();
  final FocusNode _productFocusNode = FocusNode();

  // ✅ ADDED: Scroll controller for auto-scrolling
  final ScrollController _scrollController = ScrollController();

  double get totalAmount => items.fold(0.0, (sum, it) => sum + (it.price * it.quantity));

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _clientController.dispose();
    _productController.dispose();
    _clientFocusNode.dispose();
    _productFocusNode.dispose();
    _scrollController.dispose();
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

        // ✅ Set initial client name if editing
        if (clientId != null) {
          final client = clients.firstWhere(
                (c) => c.id == clientId,
            orElse: () => Client(id: -1, name: '', phone: '', address: ''),
          );
          if (client.id != -1) {
            _clientController.text = '${client.name} • ${client.phone ?? ''}';
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Failed to load data: $e', isError: true);
      }
    }
  }

  bool _hasSufficientStock() {
    for (final it in items) {
      final available = stockMap[it.productId] ?? 0;
      if (it.quantity > available) {
        final productName = products.firstWhere((p) => p.id == it.productId, orElse: () => Product(id: -1, name: 'Unknown', price: 0, quantity: 0)).name;
        _showSnackBar('Insufficient stock for $productName', isError: true);
        return false;
      }
    }
    return true;
  }

  Future<void> _saveBill() async {
    if (_saving) return;

    if (selectedClientId == null) {
      _showSnackBar("Please select a client", isError: true);
      // ✅ Auto-focus client field
      _clientFocusNode.requestFocus();
      return;
    }
    if (items.isEmpty) {
      _showSnackBar("Add at least one product", isError: true);
      // ✅ Auto-focus product field
      _productFocusNode.requestFocus();
      return;
    }
    if (!_hasSufficientStock()) return;

    if (widget.existingBill != null) {
      final confirm = await _showConfirmDialog(
        'Update Bill', 'This will overwrite the existing bill. Continue?', confirmText: 'Update',
      );
      if (confirm != true) return;
    }

    setState(() => _saving = true);

    try {
      final bill = Bill(
        id: widget.existingBill?.id,
        clientId: selectedClientId!,
        totalAmount: totalAmount,
        paidAmount: widget.existingBill?.paidAmount ?? 0,
        carryForward: 0,
        date: DateTime.now(),
      );

      if (widget.existingBill == null) {
        await db.insertBillWithItems(bill, items);
      } else {
        await db.updateBillComplete(bill, items);
      }

      debugPrint('✅ Bill saved to local database');

      FirebaseSyncService().syncBills().catchError((e) {
        debugPrint('Background sync failed: $e');
      });

      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _saving = false);

      final shouldClose = await _showSuccessDialog();
      if (mounted && shouldClose) {
        Navigator.of(context).pop(true);
      } else if (mounted) {
        _resetForm();
      }

    } catch (e) {
      debugPrint('Error saving bill: $e');
      if (mounted) {
        setState(() => _saving = false);
        _showSnackBar('Error saving bill: ${e.toString()}', isError: true);
      }
    }
  }

  void _resetForm() {
    setState(() {
      selectedClientId = null;
      items.clear();
      _clientController.clear();
      _productController.clear();
    });
    // ✅ Focus back to client field
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _clientFocusNode.requestFocus();
      }
    });
  }

  void _addOrIncrementProductById(int productId) {
    final prod = products.firstWhere((p) => p.id == productId);
    final available = stockMap[productId] ?? 0;
    final currentQty = items.where((it) => it.productId == productId).fold<double>(0, (s, it) => s + it.quantity);

    if (currentQty + 1 > available) {
      _showSnackBar("Only ${available.toInt()} units of ${prod.name} available", isError: true);
      return;
    }

    setState(() {
      final idx = items.indexWhere((it) => it.productId == productId);
      if (idx != -1) {
        items[idx] = items[idx].copyWith(quantity: items[idx].quantity + 1);
      } else {
        items.insert(0, BillItem(productId: prod.id!, quantity: 1, price: prod.price));
      }
    });
    HapticFeedback.lightImpact();

    // ✅ Auto-scroll to items section after adding product
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _increaseQuantity(BillItem item) {
    final prod = products.firstWhere((p) => p.id == item.productId);
    final available = stockMap[item.productId] ?? 0;
    if (item.quantity + 1 > available) {
      _showSnackBar("Only ${available.toInt()} units of ${prod.name} available", isError: true);
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
    _showSnackBar('Item removed');
    HapticFeedback.lightImpact();
  }

  void _editQuantity(BillItem item) {
    final product = products.firstWhere((p) => p.id == item.productId);
    final controller = TextEditingController(text: item.quantity.toInt().toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(product.name, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Quantity',
            border: const OutlineInputBorder(),
            suffixText: 'Max: ${stockMap[item.productId]?.toInt() ?? 0}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final newQty = double.tryParse(controller.text) ?? item.quantity;
              final available = stockMap[item.productId] ?? 0;
              if (newQty > available) {
                Navigator.pop(context);
                _showSnackBar("Only ${available.toInt()} units available", isError: true);
                return;
              }
              if (newQty > 0) {
                setState(() => items[items.indexOf(item)] = item.copyWith(quantity: newQty));
              } else {
                _removeItem(item);
              }
              Navigator.pop(context);
              HapticFeedback.lightImpact();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
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
        appBar: AppBar(title: Text(widget.existingBill == null ? 'Create Bill' : 'Edit Bill')),
        body: const Center(child: CircularProgressIndicator(color: Colors.purple)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.existingBill == null ? 'Create Bill' : 'Edit Bill'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'View History',
            onPressed: () async {
              final result = await Navigator.push(
                context, MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
              if (result == true) _loadData();
            },
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Opacity(
          opacity: _saving ? 0.5 : 1.0,
          child: clients.isEmpty || products.isEmpty
              ? _buildEmptyState()
              : ListView(
            controller: _scrollController, // ✅ ADDED: Scroll controller
            padding: const EdgeInsets.all(12),
            children: [
              _buildClientCard(),
              const SizedBox(height: 12),
              _buildProductCard(),
              const SizedBox(height: 12),
              _buildItemsCard(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (clients.isEmpty || products.isEmpty)
          ? null
          : FloatingActionButton.extended(
        onPressed: _saving ? null : _saveBill,
        backgroundColor: _saving ? Colors.grey.shade400 : Colors.purple,
        label: Text(_saving ? 'SAVING...' : 'SAVE BILL', style: const TextStyle(fontWeight: FontWeight.bold)),
        icon: _saving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.check, size: 24),
      ),
    );
  }

  // ✅ FIXED: Client card with proper keyboard dismissal and auto-navigation
  Widget _buildClientCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.person, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              const Text('Select Client', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (selectedClientId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                  child: const Text('Selected', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600)),
                ),
            ]),
            const SizedBox(height: 12),
            Autocomplete<Client>(
              displayStringForOption: (Client option) => '${option.name} • ${option.phone ?? ''}',

              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return clients;
                }

                final query = textEditingValue.text.toLowerCase();
                final filtered = clients.where((Client option) {
                  return option.name.toLowerCase().contains(query) ||
                      (option.phone?.contains(query) ?? false);
                }).toList();

                return filtered;
              },

              // ✅ FIXED: Proper keyboard dismissal and auto-navigation
              onSelected: (Client selection) {
                setState(() => selectedClientId = selection.id);
                _clientController.text = '${selection.name} • ${selection.phone ?? ''}';

                // ✅ METHOD 1: Unfocus current field
                _clientFocusNode.unfocus();

                // ✅ METHOD 2: Dismiss all keyboards (more aggressive)
                FocusManager.instance.primaryFocus?.unfocus();

                // ✅ Auto-navigate to product field after selection
                Future.delayed(const Duration(milliseconds: 400), () {
                  if (mounted) {
                    _productFocusNode.requestFocus();

                    // ✅ Auto-scroll to product section
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        200, // Approximate position of product card
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  }
                });

                HapticFeedback.selectionClick();
              },

              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                // Sync controller
                if (controller != _clientController) {
                  controller.text = _clientController.text;
                  controller.selection = _clientController.selection;
                }

                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (value) => _clientController.text = value,
                  decoration: InputDecoration(
                    labelText: 'Search & Select Client',
                    hintText: 'Tap to see all or type to search...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        controller.clear();
                        _clientController.clear();
                        setState(() => selectedClientId = null);
                        focusNode.requestFocus();
                      },
                    )
                        : null,
                  ),
                );
              },

              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
                      child: options.isEmpty
                          ? Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.search_off, color: Colors.grey.shade400),
                            const SizedBox(width: 12),
                            Text('No similar client found', style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                          : ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final client = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(client),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.blue.shade100,
                                    child: Text(
                                      client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(client.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        if (client.phone != null && client.phone!.isNotEmpty)
                                          Text(client.phone!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ✅ FIXED: Product card with keyboard dismissal and field clearing
  Widget _buildProductCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.inventory_2, size: 20, color: Colors.green),
              SizedBox(width: 8),
              Text('Add Products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),

            Autocomplete<Product>(
              displayStringForOption: (Product option) {
                final stock = stockMap[option.id] ?? 0;
                return '${option.name} • ₹${option.price} • Stock: ${stock.toInt()}';
              },

              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return products;
                }

                final query = textEditingValue.text.toLowerCase();
                return products.where((Product option) {
                  return option.name.toLowerCase().contains(query);
                }).toList();
              },

              // ✅ FIXED: Keyboard dismissal and field clearing
              onSelected: (Product selection) {
                _addOrIncrementProductById(selection.id!);

                // ✅ Clear the product search field
                _productController.clear();

                // ✅ Dismiss keyboard
                _productFocusNode.unfocus();
                FocusManager.instance.primaryFocus?.unfocus();

                // ✅ Refresh to clear autocomplete field
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (mounted) {
                    setState(() {});
                  }
                });

                HapticFeedback.selectionClick();
              },

              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                // ✅ Sync with our product controller
                if (controller != _productController) {
                  controller.text = _productController.text;
                  controller.selection = _productController.selection;
                }

                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (value) => _productController.text = value,
                  decoration: InputDecoration(
                    labelText: 'Search & Add Product',
                    hintText: 'Tap to see all or type to search...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        controller.clear();
                        _productController.clear();
                        focusNode.requestFocus();
                      },
                    )
                        : null,
                  ),
                );
              },

              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250, maxWidth: 400),
                      child: options.isEmpty
                          ? Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.search_off, color: Colors.grey.shade400),
                            const SizedBox(width: 12),
                            Text('No similar product found', style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                          : ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final product = options.elementAt(index);
                          final stock = stockMap[product.id] ?? 0;
                          final inCartQty = items
                              .where((it) => it.productId == product.id)
                              .fold(0.0, (sum, item) => sum + item.quantity);
                          final hasStock = stock > 0;

                          return InkWell(
                            onTap: hasStock ? () => onSelected(product) : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: hasStock ? null : Colors.grey.shade50,
                                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hasStock ? Colors.green : Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: hasStock ? null : Colors.grey,
                                            decoration: hasStock ? null : TextDecoration.lineThrough,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '₹${product.price} • Stock: ${stock.toInt()}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (inCartQty > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${inCartQty.toInt()} in cart',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purple,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            clients.isEmpty ? 'No clients found' : 'No products found',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            clients.isEmpty ? 'Add clients to create bills' : 'Add products to create bills',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart, size: 20, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('Bill Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (items.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Text('${items.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('No items added', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              )
            else ...[
              _buildTotalSection(),
              const SizedBox(height: 12),
              ...items.map((item) => _buildItemRow(item)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotalSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Total Amount', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(_currencyFormat.format(totalAmount), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildItemRow(BillItem item) {
    final product = products.firstWhere((p) => p.id == item.productId, orElse: () => Product(id: -1, name: 'Error', price: 0, quantity: 0));
    if (product.id == -1) return const SizedBox.shrink();

    final stock = stockMap[product.id] ?? 0;
    final itemTotal = item.price * item.quantity;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('${_currencyFormat.format(item.price)} • Stock: ${stock.toInt()}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                onPressed: () => _removeItem(item),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 16),
                      onPressed: () => _decreaseQuantity(item),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    InkWell(
                      onTap: () => _editQuantity(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(border: Border.symmetric(vertical: BorderSide(color: Colors.grey.shade300))),
                        child: Text('${item.quantity.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      onPressed: () => _increaseQuantity(item),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(6)),
                child: Text(_currencyFormat.format(itemTotal), style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<bool> _showSuccessDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 28),
            const SizedBox(width: 12),
            const Text('Bill Saved!', style: TextStyle(fontSize: 18)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bill saved successfully', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.cloud_sync, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text('Syncing in background...', style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount:', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(_currencyFormat.format(totalAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
              child: const Text('Create Another'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ) ??
        true;
  }

  Future<bool> _showConfirmDialog(String title, String message, {String confirmText = 'Confirm'}) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: const TextStyle(fontSize: 18)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    ) ??
        false;
  }
}