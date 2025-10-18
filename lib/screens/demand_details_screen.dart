// lib/screens/demand_details_screen.dart
import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class DemandDetailsScreen extends StatefulWidget {
  final int batchId;
  const DemandDetailsScreen({Key? key, required this.batchId})
      : super(key: key);

  @override
  State<DemandDetailsScreen> createState() => _DemandDetailsScreenState();
}

class _DemandDetailsScreenState extends State<DemandDetailsScreen> {
  final db = DatabaseHelper();

  List<Map<String, dynamic>> _clientDetails = [];
  List<Map<String, dynamic>> _productTotals = [];
  Map<String, dynamic>? _batchInfo;
  bool _isLoading = true;

  // Summary stats
  int _totalClients = 0;
  int _totalProducts = 0;
  double _totalQuantity = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load batch info
      final batchInfo = await db.getBatchById(widget.batchId);

      // Load client details
      final clientDetails = await db.getBatchClientDetails(widget.batchId);

      // Load product totals
      final productTotals = await db.getBatchDetails(widget.batchId);

      // Calculate summary stats
      final uniqueClients = <int>{};
      double totalQty = 0;

      for (final detail in clientDetails) {
        uniqueClients.add(detail['clientId'] as int);
        totalQty += (detail['qty'] as num).toDouble();
      }

      if (!mounted) return;

      setState(() {
        _batchInfo = batchInfo;
        _clientDetails = clientDetails;
        _productTotals = productTotals;
        _totalClients = uniqueClients.length;
        _totalProducts = productTotals.length;
        _totalQuantity = totalQty;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Error loading data: $e', isError: true);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = _batchInfo?['demandDate'] ?? '';
    final isClosed = (_batchInfo?['closed'] ?? 0) == 1;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Demand Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              if (date.isNotEmpty)
                Text(
                  date,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          bottom: TabBar(
            labelColor: Colors.blue.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.blue.shade700,
            tabs: const [
              Tab(text: 'BY CLIENT', icon: Icon(Icons.people, size: 20)),
              Tab(text: 'BY PRODUCT', icon: Icon(Icons.inventory_2, size: 20)),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            _buildSummaryCard(isClosed),
            Expanded(
              child: TabBarView(
                children: [
                  _buildClientView(),
                  _buildProductView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(bool isClosed) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isClosed
              ? [Colors.green.shade600, Colors.green.shade700]
              : [Colors.blue.shade600, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (isClosed ? Colors.green : Colors.blue).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryItem(
                Icons.people,
                'Clients',
                _totalClients.toString(),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.3),
              ),
              _buildSummaryItem(
                Icons.inventory_2,
                'Products',
                _totalProducts.toString(),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.3),
              ),
              _buildSummaryItem(
                Icons.numbers,
                'Total Qty',
                _totalQuantity.toStringAsFixed(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isClosed ? Icons.check_circle : Icons.schedule,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  isClosed ? 'Batch Closed' : 'Batch Open',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.9), size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientView() {
    if (_clientDetails.isEmpty) {
      return _buildEmptyState('No client orders', Icons.people_outline);
    }

    // Group by client
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final detail in _clientDetails) {
      final clientName = detail['clientName'] ?? 'Unknown';
      grouped.putIfAbsent(clientName, () => []).add(detail);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final clientName = grouped.keys.elementAt(index);
        final orders = grouped[clientName]!;
        final clientTotal = orders.fold<double>(
          0,
              (sum, order) => sum + (order['qty'] as num).toDouble(),
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.all(16),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade50,
              child: Text(
                clientName[0].toUpperCase(),
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              clientName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.shopping_bag, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${orders.length} items',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.inventory, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Total: ${clientTotal.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            children: orders.map((order) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.inventory_2,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        order['productName'] ?? '',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Qty: ${order['qty']}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildProductView() {
    if (_productTotals.isEmpty) {
      return _buildEmptyState('No products', Icons.inventory_2_outlined);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _productTotals.length,
      itemBuilder: (context, index) {
        final product = _productTotals[index];
        final productName = product['productName'] ?? '';
        final totalQty = product['totalQty'] ?? 0;

        // Calculate percentage of total
        final percentage = _totalQuantity > 0
            ? ((totalQty as num) / _totalQuantity * 100).toStringAsFixed(1)
            : '0';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Qty: $totalQty',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$percentage% of total',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.trending_up,
                  color: Colors.green.shade600,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}