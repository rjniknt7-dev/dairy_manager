// lib/screens/edit_closed_batch_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/database_helper.dart';
import '../models/client.dart';
import '../models/product.dart';

class EditClosedBatchScreen extends StatefulWidget {
  final int batchId;
  final String date;

  const EditClosedBatchScreen({
    Key? key,
    required this.batchId,
    required this.date,
  }) : super(key: key);

  @override
  State<EditClosedBatchScreen> createState() => _EditClosedBatchScreenState();
}

class _EditClosedBatchScreenState extends State<EditClosedBatchScreen> {
  final db = DatabaseHelper();

  List<Map<String, dynamic>> _demands = [];
  List<Client> _clients = [];
  List<Product> _products = [];
  bool _isLoading = true;
  bool _hasChanges = false;

  // For inline editing
  final Map<int, TextEditingController> _quantityControllers = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final clients = await db.getClients();
      final products = await db.getProducts();

      final demands = await db.rawQuery('''
        SELECT d.*, c.name as clientName, p.name as productName
        FROM demand d
        LEFT JOIN clients c ON c.id = d.clientId
        LEFT JOIN products p ON p.id = d.productId
        WHERE d.batchId = ? AND d.isDeleted = 0
        ORDER BY c.name, p.name
      ''', [widget.batchId]);

      // Initialize controllers for each demand
      _quantityControllers.clear();
      for (final demand in demands) {
        final id = demand['id'] as int;
        final qty = demand['quantity'].toString();
        _quantityControllers[id] = TextEditingController(text: qty);
      }

      if (!mounted) return;

      setState(() {
        _clients = clients;
        _products = products;
        _demands = demands;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Failed to load data: $e', isError: true);
      }
    }
  }

  Future<void> _updateQuantity(int demandId, String newValue) async {
    final newQty = double.tryParse(newValue);
    if (newQty == null || newQty <= 0) {
      _showMessage('Invalid quantity');
      return;
    }

    try {
      await db.rawQuery('''
        UPDATE demand 
        SET quantity = ?, isSynced = 0, updatedAt = ?
        WHERE id = ?
      ''', [newQty, DateTime.now().toIso8601String(), demandId]);

      setState(() => _hasChanges = true);
      _showMessage('Quantity updated', isSuccess: true);
    } catch (e) {
      _showMessage('Failed to update: $e', isError: true);
    }
  }

  Future<void> _addDemandEntry() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddDemandBottomSheet(
        clients: _clients,
        products: _products,
        onAdd: (clientId, productId, quantity) async {
          try {
            await db.insertDemandEntry(
              batchId: widget.batchId,
              clientId: clientId,
              productId: productId,
              quantity: quantity,
            );

            setState(() => _hasChanges = true);
            _showMessage('Entry added successfully', isSuccess: true);
            _loadData();
          } catch (e) {
            _showMessage('Failed to add entry: $e', isError: true);
          }
        },
      ),
    );
  }

  Future<void> _deleteEntry(int demandId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Entry?'),
        content: const Text('This entry will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await db.rawQuery('''
        UPDATE demand 
        SET isDeleted = 1, isSynced = 0, updatedAt = ?
        WHERE id = ?
      ''', [DateTime.now().toIso8601String(), demandId]);

      setState(() => _hasChanges = true);
      _showMessage('Entry deleted', isSuccess: true);
      _loadData();
    } catch (e) {
      _showMessage('Failed to delete: $e', isError: true);
    }
  }

  Future<void> _closeBatch() async {
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Save & Close?'),
        content: const Text(
          'Save all changes and close this batch?\n\n'
              'Stock quantities will be updated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save & Close'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await db.closeBatch(widget.batchId, deductStock: false);

      if (mounted) {
        _showMessage('Batch closed successfully', isSuccess: true);
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showMessage('Failed to close batch: $e', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Colors.red.shade600
            : isSuccess
            ? Colors.green.shade600
            : Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_hasChanges) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Unsaved Changes'),
              content: const Text('You have unsaved changes. Discard them?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Discard'),
                ),
              ],
            ),
          );
          return shouldPop ?? false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Demand',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Text(
                widget.date,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          actions: [
            if (_hasChanges)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Modified',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: _closeBatch,
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Save & Close'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.green,
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _demands.isEmpty
            ? _buildEmptyState()
            : _buildDemandList(),
        floatingActionButton: FloatingActionButton(
          onPressed: _addDemandEntry,
          backgroundColor: Colors.blue,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No entries in this batch',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addDemandEntry,
            icon: const Icon(Icons.add),
            label: const Text('Add First Entry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemandList() {
    // Group demands by client
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final demand in _demands) {
      final clientName = demand['clientName'] ?? 'Unknown';
      grouped.putIfAbsent(clientName, () => []).add(demand);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final clientName = grouped.keys.elementAt(index);
        final clientDemands = grouped[clientName]!;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.blue.shade600,
                      radius: 16,
                      child: Text(
                        clientName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        clientName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${clientDemands.length} items',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...clientDemands.map((demand) => _buildDemandItem(demand)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDemandItem(Map<String, dynamic> demand) {
    final demandId = demand['id'] as int;
    final controller = _quantityControllers[demandId];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(Icons.inventory_2, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              demand['productName'] ?? '',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          SizedBox(
            width: 80,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (value) {
                setState(() => _hasChanges = true);
              },
              onSubmitted: (value) => _updateQuantity(demandId, value),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _deleteEntry(demandId),
            icon: const Icon(Icons.delete_outline, size: 20),
            color: Colors.red,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}

// Bottom sheet for adding new demand entry
class _AddDemandBottomSheet extends StatefulWidget {
  final List<Client> clients;
  final List<Product> products;
  final Function(int, int, double) onAdd;

  const _AddDemandBottomSheet({
    required this.clients,
    required this.products,
    required this.onAdd,
  });

  @override
  State<_AddDemandBottomSheet> createState() => _AddDemandBottomSheetState();
}

class _AddDemandBottomSheetState extends State<_AddDemandBottomSheet> {
  int? _selectedClientId;
  int? _selectedProductId;
  final _quantityController = TextEditingController();

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _submit() {
    final quantity = double.tryParse(_quantityController.text);
    if (_selectedClientId != null &&
        _selectedProductId != null &&
        quantity != null &&
        quantity > 0) {
      widget.onAdd(_selectedClientId!, _selectedProductId!, quantity);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Add Demand Entry',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int>(
              value: _selectedClientId,
              decoration: InputDecoration(
                labelText: 'Select Client',
                prefixIcon: const Icon(Icons.person_outline, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              items: widget.clients.map((client) {
                return DropdownMenuItem(
                  value: client.id,
                  child: Text(client.name),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedClientId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _selectedProductId,
              decoration: InputDecoration(
                labelText: 'Select Product',
                prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              items: widget.products.map((product) {
                return DropdownMenuItem(
                  value: product.id,
                  child: Text(product.name),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedProductId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                labelText: 'Quantity',
                prefixIcon: const Icon(Icons.numbers, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add Entry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}