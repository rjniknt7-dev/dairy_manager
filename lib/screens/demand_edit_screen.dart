// lib/screens/demand_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../models/client.dart';
import '../models/product.dart';

class DemandEditScreen extends StatefulWidget {
  final int? batchId;
  final DateTime batchDate;
  final bool isNewBatch;

  const DemandEditScreen({
    Key? key,
    this.batchId,
    required this.batchDate,
    required this.isNewBatch,
  }) : super(key: key);

  @override
  State<DemandEditScreen> createState() => _DemandEditScreenState();
}

class _DemandEditScreenState extends State<DemandEditScreen> {
  final db = DatabaseHelper();
  final _quantityController = TextEditingController();

  List<Client> _clients = [];
  List<Product> _products = [];

  int? _selectedClientId;
  int? _selectedProductId;

  int? _currentBatchId;
  List<Map<String, dynamic>> _demandEntries = [];

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentBatchId = widget.batchId;
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final clients = await db.getClients();
      final products = await db.getProducts();

      List<Map<String, dynamic>> entries = [];

      if (_currentBatchId != null) {
        // Load existing entries
        entries = await db.rawQuery('''
          SELECT 
            d.id,
            d.clientId,
            d.productId,
            d.quantity,
            c.name as clientName,
            p.name as productName
          FROM demand d
          JOIN clients c ON d.clientId = c.id
          JOIN products p ON d.productId = p.id
          WHERE d.batchId = ? AND d.isDeleted = 0
          ORDER BY d.createdAt DESC
        ''', [_currentBatchId]);
      }

      if (!mounted) return;

      setState(() {
        _clients = clients;
        _products = products;
        _demandEntries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Error loading data: $e', isError: true);
      }
    }
  }

  Future<void> _addEntry() async {
    if (_selectedClientId == null || _selectedProductId == null) {
      _showMessage('Please select client and product');
      return;
    }

    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      _showMessage('Please enter valid quantity');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Create batch if new
      if (_currentBatchId == null) {
        _currentBatchId = await db.getOrCreateBatchForDate(widget.batchDate);
      }

      await db.insertDemandEntry(
        batchId: _currentBatchId!,
        clientId: _selectedClientId!,
        productId: _selectedProductId!,
        quantity: quantity,
      );

      setState(() {
        _selectedClientId = null;
        _selectedProductId = null;
        _quantityController.clear();
      });

      await _loadData();

      if (mounted) {
        _showMessage('Entry added successfully', isSuccess: true);
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to add entry: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteEntry(int entryId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await db.rawUpdate(
        'UPDATE demand SET isDeleted = 1 WHERE id = ?',
        [entryId],
      );

      await _loadData();
      _showMessage('Entry deleted', isSuccess: true);
    } catch (e) {
      _showMessage('Failed to delete: $e', isError: true);
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.isNewBatch ? 'Create Demand' : 'Edit Demand'),
            Text(
              DateFormat('dd MMM yyyy').format(widget.batchDate),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          if (_demandEntries.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Add Entry Form
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Demand Entry',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Client Dropdown
                DropdownButtonFormField<int>(
                  value: _selectedClientId,
                  decoration: const InputDecoration(
                    labelText: 'Client',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _clients.map((c) {
                    return DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedClientId = v),
                ),

                const SizedBox(height: 12),

                // Product Dropdown
                DropdownButtonFormField<int>(
                  value: _selectedProductId,
                  decoration: const InputDecoration(
                    labelText: 'Product',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _products.map((p) {
                    return DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedProductId = v),
                ),

                const SizedBox(height: 12),

                // Quantity Field
                TextField(
                  controller: _quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),

                const SizedBox(height: 16),

                // Add Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _addEntry,
                    icon: _isSaving
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.add),
                    label: Text(_isSaving ? 'Adding...' : 'Add Entry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Entries List
          Expanded(
            child: _demandEntries.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'No entries yet',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _demandEntries.length,
              itemBuilder: (context, index) {
                final entry = _demandEntries[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade50,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ),
                    title: Text(
                      entry['clientName'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(entry['productName'] ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Qty: ${entry['quantity']}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteEntry(entry['id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}