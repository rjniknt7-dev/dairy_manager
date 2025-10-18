// lib/screens/demand_history_screen.dart
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

  // Date range
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  // Data
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
      // Load history
      final history = await db.getDemandHistory();

      // Filter by date range
      final filteredHistory = history.where((batch) {
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

      // Calculate product summary for date range
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
      // Get all demands in date range
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
              surface: Colors.white,
              onSurface: Colors.black,
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

  // In your demand_history_screen.dart - Replace the _exportAnalysisReport method

  // Import at the top


// Replace _exportAnalysisReport method
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

// For single day export
  Future<void> _exportPdf(int batchId, String date) async {
    try {
      final totals = await db.getBatchDetails(batchId);

      if (totals.isEmpty) {
        _showMessage('No data to export');
        return;
      }

      // Convert to the format needed for DemandPdfExportScreen
      final productSummary = totals.map((item) {
        return {
          'productName': item['productName'],
          'totalQuantity': item['totalQty'],
          'costPrice': 0.0, // Add if you have this data
          'sellingPrice': 0.0, // Add if you have this data
          'totalCost': 0.0, // Add if you have this data
          'totalRevenue': 0.0, // Add if you have this data
          'profit': 0.0, // Add if you have this data
        };
      }).toList();

      final parsedDate = DateTime.parse(date);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DemandPdfExportScreen(
            startDate: parsedDate,
            endDate: parsedDate,
            productSummary: productSummary,
            totalCost: 0.0,
            totalQuantity: totals.fold(0.0, (sum, item) => sum + (item['totalQty'] as num).toDouble()),
            isSingleDay: true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to export PDF: $e', isError: true);
      }
    }
  }

// Helper method to calculate total profit
  double _calculateTotalProfit() {
    return _productSummary.fold<double>(
      0,
          (sum, product) => sum + (product['profit'] as num).toDouble(),
    );
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
        title: const Text('Demand History & Analysis'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _showAnalysis = !_showAnalysis);
            },
            icon: Icon(_showAnalysis ? Icons.history : Icons.analytics),
            tooltip: _showAnalysis ? 'Show History' : 'Show Analysis',
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
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
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                              '${DateFormat('dd/MM/yyyy').format(_startDate)} - ${DateFormat('dd/MM/yyyy').format(_endDate)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showAnalysis ? _exportAnalysisReport : null,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Export'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Summary Cards (visible when analysis is shown)
          if (_showAnalysis && !_isLoading)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      'Total Quantity',
                      _totalQuantity.toStringAsFixed(1),
                      Icons.inventory,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      'Total Cost',
                      '₹${(_totalCost / 1000).toStringAsFixed(1)}K',
                      Icons.payments,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      'Products',
                      _productSummary.length.toString(),
                      Icons.category,
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
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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
              'No data for selected period',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Product Analysis Table
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      'Product Cost Analysis',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Table Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      flex: 3,
                      child: Text(
                        'Product',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                    const Expanded(
                      flex: 2,
                      child: Text(
                        'Quantity',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                    const Expanded(
                      flex: 2,
                      child: Text(
                        'C.P.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                    const Expanded(
                      flex: 3,
                      child: Text(
                        'Total Cost',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              // Table Rows
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _productSummary.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = _productSummary[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['productName'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
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
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              product['totalQuantity'].toStringAsFixed(1),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '₹${product['costPrice'].toStringAsFixed(2)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            '₹${product['totalCost'].toStringAsFixed(2)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Total Row
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      flex: 3,
                      child: Text(
                        'TOTAL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _totalQuantity.toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 2,
                      child: Text(''),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        '₹${_totalCost.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.blue.shade700,
                        ),
                      ),
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

  Widget _buildHistoryView() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No demand history',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'for selected date range',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
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

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isClosed
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isClosed ? Icons.check_circle : Icons.schedule,
                  color: isClosed
                      ? Colors.green.shade600
                      : Colors.orange.shade600,
                ),
              ),
              title: Text(
                date,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  isClosed ? 'Closed' : 'Open',
                  style: TextStyle(
                    color: isClosed
                        ? Colors.green.shade600
                        : Colors.orange.shade600,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DemandDetailsScreen(
                        batchId: batchId,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}