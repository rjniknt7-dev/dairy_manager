// lib/screens/demand_history_screen.dart - INTELLIGENT VERSION
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import 'demand_details_screen.dart';
import 'demand_pdf_export_screen.dart';

class DemandHistoryScreen extends StatefulWidget {
  const DemandHistoryScreen({Key? key}) : super(key: key);

  @override
  State<DemandHistoryScreen> createState() => _DemandHistoryScreenState();
}

class _DemandHistoryScreenState extends State<DemandHistoryScreen> {
  final db = DatabaseHelper();

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _productSummary = [];
  double _totalCost = 0.0;
  double _totalQuantity = 0.0;

  bool _isLoading = true;
  bool _showAnalysis = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Get only batches that have entries
      final allBatches = await db.getBatchesWithEntries();

      // Filter by date range
      final filteredHistory = allBatches.where((batch) {
        final dateStr = batch['demandDate'] as String?;
        if (dateStr == null) return false;

        try {
          final date = DateTime.parse(dateStr);
          return date.isAfter(_startDate.subtract(const Duration(days: 1))) &&
              date.isBefore(_endDate.add(const Duration(days: 1)));
        } catch (e) {
          return false;
        }
      }).toList();

      await _calculateProductSummary();

      if (!mounted) return;

      setState(() {
        _history = filteredHistory;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Error loading data: $e', isError: true);
      }
    }
  }

  Future<void> _calculateProductSummary() async {
    try {
      final demands = await db.rawQuery('''
        SELECT 
          d.productId,
          p.name as productName,
          p.costPrice,
          p.price as sellingPrice,
          SUM(d.quantity) as totalQuantity
        FROM demand d
        JOIN demand_batch db ON d.batchId = db.id
        JOIN products p ON d.productId = p.id
        WHERE db.demandDate >= ? 
          AND db.demandDate <= ?
          AND d.isDeleted = 0
          AND db.isDeleted = 0
        GROUP BY d.productId, p.name, p.costPrice, p.price
        ORDER BY totalQuantity DESC
      ''', [
        _startDate.toIso8601String().substring(0, 10),
        _endDate.toIso8601String().substring(0, 10),
      ]);

      double totalCost = 0;
      double totalQty = 0;

      final productSummary = demands.map((row) {
        final qty = (row['totalQuantity'] as num).toDouble();
        final costPrice = (row['costPrice'] as num?)?.toDouble() ?? 0.0;
        final sellingPrice = (row['sellingPrice'] as num?)?.toDouble() ?? 0.0;
        final totalProductCost = qty * costPrice;
        final totalProductRevenue = qty * sellingPrice;

        totalCost += totalProductCost;
        totalQty += qty;

        return {
          'productId': row['productId'],
          'productName': row['productName'],
          'costPrice': costPrice,
          'sellingPrice': sellingPrice,
          'totalQuantity': qty,
          'totalCost': totalProductCost,
          'totalRevenue': totalProductRevenue,
          'profit': totalProductRevenue - totalProductCost,
        };
      }).toList();

      setState(() {
        _productSummary = productSummary;
        _totalCost = totalCost;
        _totalQuantity = totalQty;
      });
    } catch (e) {
      debugPrint('Error calculating summary: $e');
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue.shade600,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }

  Future<void> _exportAnalysisReport() async {
    if (_productSummary.isEmpty) {
      _showMessage('No data to export');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DemandPdfExportScreen(
          startDate: _startDate,
          endDate: _endDate,
          productSummary: _productSummary,
          totalCost: _totalCost,
          totalQuantity: _totalQuantity,
          isSingleDay: false,
        ),
      ),
    );
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Demand History'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => setState(() => _showAnalysis = !_showAnalysis),
            icon: Icon(_showAnalysis ? Icons.history : Icons.analytics),
            tooltip: _showAnalysis ? 'Show History' : 'Show Analysis',
          ),
        ],
      ),
      body: Column(
        children: [
          // Date Range Selector
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _selectDateRange,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.date_range, color: Colors.blue.shade600, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_showAnalysis && _productSummary.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _exportAnalysisReport,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Export'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Summary Cards
          if (_showAnalysis && !_isLoading && _productSummary.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      'Orders',
                      _history.length.toString(),
                      Icons.receipt_long,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      'Products',
                      _productSummary.length.toString(),
                      Icons.inventory,
                      Colors.purple,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      'Quantity',
                      _totalQuantity.toStringAsFixed(0),
                      Icons.shopping_cart,
                      Colors.orange,
                    ),
                  ),
                ],
              ),
            ),

          // Main Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _showAnalysis
                ? _buildAnalysisView()
                : _buildHistoryView(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryView() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No orders found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'for selected date range',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _history.length,
        itemBuilder: (context, index) {
          final batch = _history[index];
          final isClosed = (batch['closed'] ?? 0) == 1;
          final date = batch['demandDate'] ?? '';
          final batchId = batch['id'] as int;
          final entryCount = batch['entryCount'] ?? 0;
          final totalQty = (batch['totalQuantity'] as num?)?.toDouble() ?? 0.0;

          DateTime? parsedDate;
          try {
            parsedDate = DateTime.parse(date);
          } catch (e) {
            parsedDate = null;
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DemandDetailsScreen(batchId: batchId),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: isClosed ? Colors.green.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            parsedDate != null ? DateFormat('dd').format(parsedDate) : '--',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isClosed ? Colors.green.shade700 : Colors.orange.shade700,
                            ),
                          ),
                          Text(
                            parsedDate != null ? DateFormat('MMM').format(parsedDate) : '--',
                            style: TextStyle(
                              fontSize: 11,
                              color: isClosed ? Colors.green.shade600 : Colors.orange.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            parsedDate != null
                                ? DateFormat('EEEE, dd MMM yyyy').format(parsedDate)
                                : date,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isClosed
                                      ? Colors.green.shade100
                                      : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isClosed ? 'CLOSED' : 'OPEN',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isClosed
                                        ? Colors.green.shade700
                                        : Colors.orange.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$entryCount entries • Qty: ${totalQty.toStringAsFixed(0)}',
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
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnalysisView() {
    if (_productSummary.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No data for analysis',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
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
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.analytics, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    const Text(
                      'Product Analysis',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _productSummary.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = _productSummary[index];
                  return ListTile(
                    title: Text(
                      product['productName'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      'C.P: ₹${product['costPrice'].toStringAsFixed(2)} • Cost: ₹${product['totalCost'].toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Qty: ${product['totalQuantity'].toStringAsFixed(1)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Profit: ₹${product['profit'].toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: product['profit'] > 0
                                ? Colors.green.shade600
                                : Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Qty: ${_totalQuantity.toStringAsFixed(1)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Cost: ₹${_totalCost.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}