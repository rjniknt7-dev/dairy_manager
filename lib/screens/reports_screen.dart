// lib/screens/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with TickerProviderStateMixin {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
  final _dateFormat = DateFormat('dd MMM yyyy');

  bool _loading = true;
  bool _isSyncing = false;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  Map<String, dynamic> _reportData = {};
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadReportData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReportData() async {
    setState(() => _loading = true);

    try {
      final data = await _generateComprehensiveReport(_startDate, _endDate);
      setState(() => _reportData = data);
    } catch (e) {
      _showSnack('Failed to load report: $e', Colors.red);
      debugPrint('Report error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _generateComprehensiveReport(DateTime start, DateTime end) async {
    // 1. SALES DATA
    final salesQuery = '''
      SELECT 
        b.id as billId,
        b.totalAmount,
        b.paidAmount,
        b.date as billDate,
        c.name as clientName,
        c.id as clientId,
        bi.productId,
        bi.quantity,
        bi.price as sellingPrice,
        p.name as productName,
        p.costPrice
      FROM bills b
      JOIN clients c ON c.id = b.clientId
      JOIN bill_items bi ON bi.billId = b.id
      JOIN products p ON p.id = bi.productId
      WHERE DATE(b.date) BETWEEN DATE(?) AND DATE(?)
        AND b.isDeleted = 0
      ORDER BY b.date DESC
    ''';

    final salesData = await db.rawQuery(salesQuery, [
      start.toIso8601String().split('T')[0],
      end.toIso8601String().split('T')[0]
    ]);

    // 2. PURCHASE DATA
    final purchaseQuery = '''
      SELECT 
        db.demandDate,
        db.id as batchId,
        d.productId,
        d.quantity,
        p.name as productName,
        p.costPrice
      FROM demand_batch db
      JOIN demand d ON d.batchId = db.id
      JOIN products p ON p.id = d.productId
      WHERE DATE(db.demandDate) BETWEEN DATE(?) AND DATE(?)
        AND db.closed = 1
        AND db.isDeleted = 0
        AND d.isDeleted = 0
      ORDER BY db.demandDate DESC
    ''';

    final purchaseData = await db.rawQuery(purchaseQuery, [
      start.toIso8601String().split('T')[0],
      end.toIso8601String().split('T')[0]
    ]);

    // 3. OUTSTANDING AMOUNTS – condition moved to WHERE
    final outstandingQuery = '''
      SELECT 
        c.id as clientId,
        c.name as clientName,
        c.phone as clientPhone,
        COALESCE(bills_total.total_amount, 0) - COALESCE(payments_total.paid_amount, 0) as outstanding
      FROM clients c
      LEFT JOIN (
        SELECT clientId, SUM(totalAmount) as total_amount
        FROM bills 
        WHERE isDeleted = 0
        GROUP BY clientId
      ) bills_total ON c.id = bills_total.clientId
      LEFT JOIN (
        SELECT clientId, SUM(amount) as paid_amount
        FROM ledger 
        WHERE type = 'payment' AND isDeleted = 0
        GROUP BY clientId
      ) payments_total ON c.id = payments_total.clientId
      WHERE 
        c.isDeleted = 0
        AND (COALESCE(bills_total.total_amount, 0) - COALESCE(payments_total.paid_amount, 0)) > 0
      ORDER BY outstanding DESC
    ''';

    final outstandingData = await db.rawQuery(outstandingQuery);

    // 4. CURRENT STOCK
    final stockQuery = '''
      SELECT 
        p.id,
        p.name,
        p.price as sellingPrice,
        p.costPrice,
        COALESCE(s.quantity, p.stock, 0) as currentStock,
        (COALESCE(s.quantity, p.stock, 0) * p.costPrice) as stockValue
      FROM products p
      LEFT JOIN stock s ON s.productId = p.id
      WHERE p.isDeleted = 0
      ORDER BY p.name
    ''';

    final stockData = await db.rawQuery(stockQuery);

    return _calculateAdvancedMetrics(salesData, purchaseData, outstandingData, stockData);
  }

  Map<String, dynamic> _calculateAdvancedMetrics(
      List<Map<String, dynamic>> sales,
      List<Map<String, dynamic>> purchases,
      List<Map<String, dynamic>> outstanding,
      List<Map<String, dynamic>> stock) {

    // SALES METRICS
    double totalRevenue = 0;
    double totalCostOfGoodsSold = 0;
    int totalUniqueBills = 0;
    Map<String, double> productRevenue = {};
    Map<String, double> productProfit = {};
    Map<String, double> clientRevenue = {};
    Map<String, double> clientOutstanding = {};
    Set<int> uniqueBillIds = {};

    for (final sale in sales) {
      final billId = sale['billId'] as int? ?? 0;
      final quantity = (sale['quantity'] as num?)?.toDouble() ?? 0;
      final sellingPrice = (sale['price'] as num?)?.toDouble() ?? 0;
      final costPrice = (sale['costPrice'] as num?)?.toDouble() ?? 0;
      final productName = sale['productName'] as String? ?? 'Unknown';
      final clientName = sale['clientName'] as String? ?? 'Unknown';

      final itemRevenue = quantity * sellingPrice;
      final itemCost = quantity * costPrice;
      final itemProfit = itemRevenue - itemCost;

      totalRevenue += itemRevenue;
      totalCostOfGoodsSold += itemCost;

      productRevenue[productName] = (productRevenue[productName] ?? 0) + itemRevenue;
      productProfit[productName] = (productProfit[productName] ?? 0) + itemProfit;
      clientRevenue[clientName] = (clientRevenue[clientName] ?? 0) + itemRevenue;

      if (!uniqueBillIds.contains(billId)) {
        uniqueBillIds.add(billId);
      }
    }
    totalUniqueBills = uniqueBillIds.length;

    // PURCHASE METRICS
    double totalPurchases = 0;
    Map<String, double> productPurchases = {};
    Map<String, double> productPurchaseQty = {};

    for (final purchase in purchases) {
      final quantity = (purchase['quantity'] as num?)?.toDouble() ?? 0;
      final costPrice = (purchase['costPrice'] as num?)?.toDouble() ?? 0;
      final productName = purchase['productName'] as String? ?? 'Unknown';

      final purchaseValue = quantity * costPrice;
      totalPurchases += purchaseValue;

      productPurchases[productName] = (productPurchases[productName] ?? 0) + purchaseValue;
      productPurchaseQty[productName] = (productPurchaseQty[productName] ?? 0) + quantity;
    }

    // OUTSTANDING AMOUNTS
    double totalOutstanding = 0;
    for (final client in outstanding) {
      final clientName = client['clientName'] as String? ?? 'Unknown';
      final amount = (client['outstanding'] as num?)?.toDouble() ?? 0;
      totalOutstanding += amount;
      clientOutstanding[clientName] = amount;
    }

    // STOCK ANALYSIS
    double totalStockValue = 0;
    Map<String, Map<String, dynamic>> stockAnalysis = {};
    for (final item in stock) {
      final productName = item['name'] as String? ?? 'Unknown';
      final currentStock = (item['currentStock'] as num?)?.toDouble() ?? 0;
      final stockValue = (item['stockValue'] as num?)?.toDouble() ?? 0;
      final costPrice = (item['costPrice'] as num?)?.toDouble() ?? 0;
      final sellingPrice = (item['sellingPrice'] as num?)?.toDouble() ?? 0;

      totalStockValue += stockValue;
      stockAnalysis[productName] = {
        'quantity': currentStock,
        'value': stockValue,
        'costPrice': costPrice,
        'sellingPrice': sellingPrice,
        'potentialProfit': currentStock * (sellingPrice - costPrice),
      };
    }

    // CALCULATE FINAL METRICS
    final grossProfit = totalRevenue - totalCostOfGoodsSold;
    final grossMargin = totalRevenue > 0 ? (grossProfit / totalRevenue) * 100 : 0;

    return {
      // Financial Summary
      'totalRevenue': totalRevenue,
      'totalCostOfGoodsSold': totalCostOfGoodsSold,
      'grossProfit': grossProfit,
      'grossMargin': grossMargin,
      'totalPurchases': totalPurchases,
      'totalUniqueBills': totalUniqueBills,
      'totalOutstanding': totalOutstanding,
      'totalStockValue': totalStockValue,

      // Detailed Breakdowns
      'productRevenue': productRevenue,
      'productProfit': productProfit,
      'clientRevenue': clientRevenue,
      'clientOutstanding': clientOutstanding,
      'productPurchases': productPurchases,
      'productPurchaseQty': productPurchaseQty,
      'stockAnalysis': stockAnalysis,
      'outstandingDetails': outstanding,

      // Performance Indicators
      'averageBillValue': totalUniqueBills > 0 ? totalRevenue / totalUniqueBills : 0,
      'topClient': _getTopEntry(clientRevenue),
      'topProduct': _getTopEntry(productRevenue),
      'mostProfitableProduct': _getTopEntry(productProfit),
    };
  }

  Map<String, dynamic> _getTopEntry(Map<String, double> map) {
    if (map.isEmpty) return {'name': 'None', 'value': 0.0};
    final entry = map.entries.reduce((a, b) => a.value > b.value ? a : b);
    return {'name': entry.key, 'value': entry.value};
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      await _loadReportData();
    }
  }

  Future<void> _syncData() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _showSnack('Login to sync data', Colors.orange);
      return;
    }

    setState(() => _isSyncing = true);
    final result = await _syncService.syncAllData();
    setState(() => _isSyncing = false);

    _showSnack(result.message, result.success ? Colors.green : Colors.red);
    if (result.success) await _loadReportData();
  }

  void _showSnack(String message, [Color? backgroundColor]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Dashboard'),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.cloud_sync),
            onPressed: _isSyncing ? null : _syncData,
            tooltip: 'Sync Data',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _selectDateRange,
            tooltip: 'Select Period',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.trending_up), text: 'Sales'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'Outstanding'),
            Tab(icon: Icon(Icons.inventory), text: 'Inventory'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!isLoggedIn)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  const Text(
                    'Offline mode - Login to sync data across devices',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade700, Colors.indigo.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Report Period', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(
                      '${_dateFormat.format(_startDate)} - ${_dateFormat.format(_endDate)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.indigo.shade700,
                  ),
                  icon: const Icon(Icons.edit_calendar, size: 18),
                  label: const Text('Change'),
                  onPressed: _selectDateRange,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildSalesTab(),
                _buildOutstandingTab(),
                _buildInventoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===================== _buildOverviewTab() =====================
  Widget _buildOverviewTab() {
    final totalRevenue = (_reportData['totalRevenue'] ?? 0).toDouble();
    final grossProfit = (_reportData['grossProfit'] ?? 0).toDouble();
    final grossMargin = (_reportData['grossMargin'] ?? 0).toDouble();
    final totalPurchases = (_reportData['totalPurchases'] ?? 0).toDouble();
    final totalOutstanding = (_reportData['totalOutstanding'] ?? 0).toDouble();
    final totalStockValue = (_reportData['totalStockValue'] ?? 0).toDouble();
    final avgBillValue = (_reportData['averageBillValue'] ?? 0).toDouble();
    final totalBills = (_reportData['totalUniqueBills'] ?? 0).toDouble();
    final clientRevenue = _reportData['clientRevenue'] as Map<String, double>? ?? {};

    return RefreshIndicator(
      onRefresh: _loadReportData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPIs
            Row(
              children: [
                Expanded(child: _buildKPICard('Revenue', _currencyFormat.format(totalRevenue), Colors.green, Icons.attach_money)),
                const SizedBox(width: 8),
                Expanded(child: _buildKPICard('Gross Profit', _currencyFormat.format(grossProfit), grossProfit >= 0 ? Colors.blue : Colors.red, Icons.trending_up)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildKPICard('Profit Margin', '${grossMargin.toStringAsFixed(1)}%', grossProfit >= 0 ? Colors.green : Colors.red, Icons.percent)),
                const SizedBox(width: 8),
                Expanded(child: _buildKPICard('Purchases', _currencyFormat.format(totalPurchases), Colors.orange, Icons.shopping_cart)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildKPICard('Outstanding', _currencyFormat.format(totalOutstanding), totalOutstanding > 0 ? Colors.amber : Colors.grey, Icons.account_balance_wallet)),
                const SizedBox(width: 8),
                Expanded(child: _buildKPICard('Stock Value', _currencyFormat.format(totalStockValue), Colors.purple, Icons.inventory)),
              ],
            ),
            const SizedBox(height: 20),

            // Business Insights
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Business Insights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildInsightRow('Total Bills Processed', '$totalBills'),
                    _buildInsightRow('Average Bill Value', _currencyFormat.format(avgBillValue)),
                    _buildInsightRow('Gross Margin %', '${grossMargin.toStringAsFixed(2)}%'),
                    if (totalRevenue > 0) _buildInsightRow('Revenue per Day', _currencyFormat.format(totalRevenue / (_endDate.difference(_startDate).inDays + 1))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Top Clients
            _buildTopClientsCard(clientRevenue),
          ],
        ),
      ),
    );
  }
  Widget _buildInventoryTab() {
    final stockAnalysis = _reportData['stockAnalysis'] as Map<String, Map<String, dynamic>>? ?? {};
    final totalStockValue = _reportData['totalStockValue'] as double? ?? 0;

    return RefreshIndicator(
      onRefresh: _loadReportData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Current Inventory Card
            Card(
              color: Colors.purple.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.inventory, color: Colors.purple.shade700, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Inventory',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text('${stockAnalysis.length} products in stock'),
                        ],
                      ),
                    ),
                    Text(
                      _currencyFormat.format(totalStockValue),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stock Analysis Cards
            ...stockAnalysis.entries.map((entry) {
              final data = entry.value;
              final quantity = (data['quantity'] as num?)?.toDouble() ?? 0;
              final value = (data['value'] as num?)?.toDouble() ?? 0;
              final costPrice = (data['costPrice'] as num?)?.toDouble() ?? 0;
              final sellingPrice = (data['sellingPrice'] as num?)?.toDouble() ?? 0;
              final potentialProfit = (data['potentialProfit'] as num?)?.toDouble() ?? 0;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product name & quantity
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text('Qty: ${quantity.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Cost & Selling
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Cost: ${_currencyFormat.format(costPrice)}'),
                          Text('Selling: ${_currencyFormat.format(sellingPrice)}'),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Stock Value & Potential Profit
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Stock Value: ${_currencyFormat.format(value)}'),
                          Row(
                            children: [
                              const Text('P.P: ', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                _currencyFormat.format(potentialProfit),
                                style: TextStyle(
                                  color: potentialProfit >= 0 ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }


// ===================== _buildSalesTab() =====================
  Widget _buildSalesTab() {
    final productRevenue = _reportData['productRevenue'] as Map<String, double>? ?? {};
    final productProfit = _reportData['productProfit'] as Map<String, double>? ?? {};
    final clientRevenue = _reportData['clientRevenue'] as Map<String, double>? ?? {};

    return RefreshIndicator(
      onRefresh: _loadReportData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTopProductsCard(productRevenue, productProfit),
            const SizedBox(height: 16),
            _buildTopClientsCard(clientRevenue),
          ],
        ),
      ),
    );
  }

// ===================== _buildOutstandingTab() =====================
  Widget _buildOutstandingTab() {
    final clientOutstanding = _reportData['clientOutstanding'] as Map<String, double>? ?? {};
    final outstandingDetails = _reportData['outstandingDetails'] as List<Map<String, dynamic>>? ?? [];

    return RefreshIndicator(
      onRefresh: _loadReportData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (outstandingDetails.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle, size: 64, color: Colors.green.shade300),
                      const SizedBox(height: 16),
                      const Text('All Clear!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const Text('No outstanding amounts from clients', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else ...[
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.amber.shade700, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Outstanding Payments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('${outstandingDetails.length} clients have pending payments'),
                          ],
                        ),
                      ),
                      Text(
                        _currencyFormat.format(clientOutstanding.values.fold(0.0, (a, b) => a + b)),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber.shade700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...outstandingDetails.map((client) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red.shade100,
                    child: Icon(Icons.person, color: Colors.red.shade700),
                  ),
                  title: Text(client['clientName'] as String? ?? 'Unknown'),
                  subtitle: Text(client['clientPhone'] as String? ?? 'No phone'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _currencyFormat.format((client['outstanding'] as num?)?.toDouble() ?? 0),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                      const Text('Pending', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  onTap: () {
                    // TODO: Navigate to client payment screen
                  },
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }





  Widget _buildKPICard(String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTopProductsCard(Map<String, double> revenue, Map<String, double> profit) {
    if (revenue.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.inventory_2, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('No Sales Data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text('No product sales in selected period', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final sortedProducts = revenue.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top Products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...sortedProducts.take(10).map((entry) {
              final productProfit = profit[entry.key] ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            'Profit: ${_currencyFormat.format(productProfit)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: productProfit >= 0 ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _currencyFormat.format(entry.value),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${((productProfit / entry.value) * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: productProfit >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTopClientsCard(Map<String, double> clientRevenue) {
    if (clientRevenue.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.people, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('No Client Sales', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text('No client transactions in selected period', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final sortedClients = clientRevenue.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalRevenue = clientRevenue.values.fold(0.0, (a, b) => a + b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top Clients by Revenue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...sortedClients.take(10).map((entry) {
              final percentage = totalRevenue > 0 ? (entry.value / totalRevenue) * 100 : 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Container(
                            height: 4,
                            margin: const EdgeInsets.only(top: 4),
                            child: LinearProgressIndicator(
                              value: percentage / 100,
                              backgroundColor: Colors.grey.shade300,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade400),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _currencyFormat.format(entry.value),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}