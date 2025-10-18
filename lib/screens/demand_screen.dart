// lib/screens/demand_screen.dart - FIXED VERSION
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../services/pdf_service.dart';
import '../services/database_helper.dart';
import '../models/client.dart';
import '../models/product.dart';
import 'demand_details_screen.dart';
import 'demand_history_screen.dart';

class DemandScreen extends StatefulWidget {
  const DemandScreen({Key? key}) : super(key: key);

  @override
  State<DemandScreen> createState() => _DemandScreenState();
}

class _DemandScreenState extends State<DemandScreen> {
  final db = DatabaseHelper();

  List<Client> _clients = [];
  List<Product> _products = [];

  int? _selectedClientId;
  int? _selectedProductId;
  final _quantityController = TextEditingController();

  int? _currentBatchId;
  bool _isBatchClosed = false;

  List<Map<String, dynamic>> _productTotals = [];
  List<Map<String, dynamic>> _clientOrders = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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
      // Load clients and products
      final clients = await db.getClients();
      final products = await db.getProducts();

      // Get or create today's batch
      final today = DateTime.now();
      final batchId = await db.getOrCreateBatchForDate(today);

      // Get batch details
      final batchInfo = await db.getBatchById(batchId);
      final isClosed = (batchInfo?['closed'] ?? 0) == 1;

      // Get current batch totals
      final totals = await db.getCurrentBatchTotals(batchId);

      // Get client-wise details
      final clientDetails = await db.getBatchClientDetails(batchId);

      if (!mounted) return;

      setState(() {
        _clients = clients;
        _products = products;
        _currentBatchId = batchId;
        _isBatchClosed = isClosed;
        _productTotals = totals;
        _clientOrders = clientDetails;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Error loading data: $e', isError: true);
      }
    }
  }

  Future<void> _addDemandEntry() async {
    if (_isBatchClosed) {
      _showMessage('Today\'s demand is closed', isError: true);
      return;
    }

    if (_selectedClientId == null || _selectedProductId == null) {
      _showMessage('Please select client and product');
      return;
    }

    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      _showMessage('Please enter valid quantity');
      return;
    }

    try {
      await db.insertDemandEntry(
        batchId: _currentBatchId!,
        clientId: _selectedClientId!,
        productId: _selectedProductId!,
        quantity: quantity,
      );

      // Clear form
      setState(() {
        _selectedClientId = null;
        _selectedProductId = null;
        _quantityController.clear();
      });

      // Reload data
      await _loadData();

      if (mounted) {
        _showMessage('Demand added successfully', isSuccess: true);
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to add demand: $e', isError: true);
      }
    }
  }

  Future<void> _closeBatch() async {
    if (_currentBatchId == null || _isBatchClosed) return;

    if (_productTotals.isEmpty) {
      _showMessage('No demands to close');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Close Today\'s Demand?'),
        content: const Text(
          'This will finalize today\'s demand and update stock quantities.\n\n'
              'You won\'t be able to add more demands for today.',
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
            child: const Text('Close & Update Stock'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Close batch and update stock (use deductStock: true if you want to reduce stock)
      await db.closeBatch(_currentBatchId!, deductStock: false, createNextDay: false);

      if (mounted) {
        _showMessage('Demand closed and stock updated', isSuccess: true);
        await _loadData();
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to close batch: $e', isError: true);
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_productTotals.isEmpty) {
      _showMessage('No data to export');
      return;
    }

    try {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final pdfData = await PDFService.buildPurchaseOrderPdf(
        date: date,
        totals: _productTotals,
      );

      await Printing.sharePdf(
        bytes: pdfData,
        filename: 'demand_$date.pdf',
      );

      if (mounted) {
        _showMessage('PDF exported successfully', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to export PDF: $e', isError: true);
      }
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
    final today = DateTime.now();
    final dateStr = '${today.day}/${today.month}/${today.year}';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Daily Demand',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              dateStr,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          if (!_isBatchClosed && _productTotals.isNotEmpty)
            TextButton.icon(
              onPressed: _closeBatch,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: const Text('Close'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.green,
              ),
            ),
          IconButton(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DemandHistoryScreen(),
                ),
              );
              if (result == true) {
                _loadData();
              }
            },
            icon: const Icon(Icons.history),
            tooltip: 'History',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isBatchClosed)
                _buildClosedBanner()
              else
                _buildEntryForm(),

              if (_productTotals.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildProductTotals(),
              ],

              if (_clientOrders.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildClientOrders(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClosedBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today\'s demand is closed',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Stock has been updated. You can view the summary below.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Demand Entry',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          // Client dropdown - FIXED
          DropdownButtonFormField<int>(
            value: _selectedClientId,
            decoration: InputDecoration(
              labelText: 'Select Client',
              prefixIcon: const Icon(Icons.person_outline, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            isExpanded: true,
            items: _clients.map((client) {
              return DropdownMenuItem<int>(
                value: client.id,
                child: Text(
                  client.name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) => setState(() => _selectedClientId = value),
          ),

          const SizedBox(height: 12),

          // Product dropdown - FIXED: Removed Expanded widget
          DropdownButtonFormField<int>(
            value: _selectedProductId,
            decoration: InputDecoration(
              labelText: 'Select Product',
              prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            isExpanded: true,
            items: _products.map((product) {
              return DropdownMenuItem<int>(
                value: product.id,
                child: Text(
                  '${product.name} - ₹${product.price}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: (value) => setState(() => _selectedProductId = value),
          ),

          const SizedBox(height: 12),

          // Quantity field
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),

          const SizedBox(height: 16),

          // Add button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _addDemandEntry,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Entry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductTotals() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Product Summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    if (_productTotals.isNotEmpty)
                      IconButton(
                        onPressed: _exportPdf,
                        icon: const Icon(Icons.picture_as_pdf, size: 20),
                        color: Colors.red,
                        tooltip: 'Export PDF',
                      ),
                    if (_currentBatchId != null)
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DemandDetailsScreen(
                                batchId: _currentBatchId!,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.visibility, size: 20),
                        color: Colors.blue,
                        tooltip: 'View Details',
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _productTotals.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _productTotals[index];
              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    size: 20,
                    color: Colors.blue.shade600,
                  ),
                ),
                title: Text(
                  item['productName'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Qty: ${item['totalQty'] ?? 0}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildClientOrders() {
    // Group by client
    final Map<String, List<Map<String, dynamic>>> groupedOrders = {};
    for (final order in _clientOrders) {
      final clientName = order['clientName'] ?? 'Unknown';
      groupedOrders.putIfAbsent(clientName, () => []).add(order);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Client Orders',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: groupedOrders.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final clientName = groupedOrders.keys.elementAt(index);
              final orders = groupedOrders[clientName]!;

              return ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade50,
                  child: Text(
                    clientName[0].toUpperCase(),
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                title: Text(
                  clientName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '${orders.length} items',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                children: orders.map((order) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const SizedBox(width: 40),
                        Expanded(
                          child: Text(
                            order['productName'] ?? '',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Qty: ${order['qty']}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}