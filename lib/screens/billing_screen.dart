// lib/screens/billing_screen.dart - v2.0 (Intelligent & Smooth)
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
  final TextEditingController _clientController = TextEditingController();

  double get totalAmount => items.fold(0.0, (sum, it) => sum + (it.price * it.quantity));

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _clientController.dispose();
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

  // ✅ UPDATED: Uses the correct, non-deprecated method `updateBillComplete`
  Future<void> _saveBill() async {
    if (_saving) return;

    if (selectedClientId == null) {
      _showSnackBar("Please select a client", isError: true);
      return;
    }
    if (items.isEmpty) {
      _showSnackBar("Add at least one product", isError: true);
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
        paidAmount: widget.existingBill?.paidAmount ?? 0, // Preserve paid amount on edit
        carryForward: 0, // Carry forward should be recalculated on the server or via a separate process
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
      // ✅ ADDED: AbsorbPointer to prevent taps while saving
      body: AbsorbPointer(
        absorbing: _saving,
        child: Opacity(
          opacity: _saving ? 0.5 : 1.0,
          child: clients.isEmpty || products.isEmpty
              ? _buildEmptyState()
              : ListView(
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

  // ✅ UPDATED: Now a smart, searchable Autocomplete widget
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
                    child: const Text('Selected', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 12),
            Autocomplete<Client>(
              displayStringForOption: (Client option) => '${option.name} • ${option.phone ?? ''}',
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<Client>.empty();
                }
                return clients.where((Client option) {
                  final query = textEditingValue.text.toLowerCase();
                  return option.name.toLowerCase().contains(query) || (option.phone?.contains(query) ?? false);
                });
              },
              onSelected: (Client selection) {
                setState(() => selectedClientId = selection.id);
                _clientController.text = '${selection.name} • ${selection.phone ?? ''}';
                FocusScope.of(context).unfocus();
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                _clientController.text = controller.text;
                if (selectedClientId != null && _clientController.text.isEmpty) {
                  final client = clients.firstWhere((c) => c.id == selectedClientId, orElse: () => Client(id: -1, name: '', phone: '', address: ''));
                  if (client.id != -1) {
                    _clientController.text = '${client.name} • ${client.phone ?? ''}';
                  }
                }
                return TextField(
                  controller: _clientController,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Search & Select Client',
                    hintText: 'Type name or phone number...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _clientController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _clientController.clear();
                        setState(() => selectedClientId = null);
                        focusNode.requestFocus();
                      },
                    )
                        : null,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ✅ UPDATED: Now visually indicates stock status
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
            DropdownButtonFormField<int>(
              value: null,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'Choose product to add...',
              ),
              items: products.map((product) {
                final stock = stockMap[product.id] ?? 0;
                final inCartQty = items.where((it) => it.productId == product.id).fold(0.0, (sum, item) => sum + item.quantity);

                return DropdownMenuItem<int>(
                  value: product.id,
                  enabled: stock > 0,
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: stock > 0 ? Colors.green : Colors.red)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${product.name} • ${_currencyFormat.format(product.price)} • Stock: ${stock.toInt()}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: stock > 0 ? null : Colors.red.shade700,
                            decoration: stock > 0 ? null : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      if (inCartQty > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Text('${inCartQty.toInt()}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple)),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (pid) {
                if (pid != null) _addOrIncrementProductById(pid);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- (Keep the rest of the file unchanged) ---
  // The following methods are already well-written and don't need changes:
  // _buildItemsCard(), _buildTotalSection(), _buildItemRow(), _showSnackBar(),
  // _showSuccessDialog(), _showConfirmDialog(), _buildEmptyState()

  // NOTE: I've left the original methods below for completeness, but they
  // are the same as what you provided.

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
                const Text(
                  'Bill Items',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (items.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${items.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
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
                    Text(
                      'No items added',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
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
      decoration: BoxDecoration(
        color: Colors.purple,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Total Amount',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _currencyFormat.format(totalAmount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(BillItem item) {
    final product = products.firstWhere((p) => p.id == item.productId, orElse: ()=> Product(id: -1, name: 'Error', price: 0, quantity: 0));
    if (product.id == -1) return const SizedBox.shrink(); // Don't build row if product not found

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
                    Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_currencyFormat.format(item.price)} • Stock: ${stock.toInt()}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
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
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
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
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            vertical: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: Text(
                          '${item.quantity.toInt()}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
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
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _currencyFormat.format(itemTotal),
                  style: const TextStyle(
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                backgroundColor: Colors.purple, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ) ?? true;
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
              backgroundColor: Colors.orange, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    ) ?? false;
  }
}