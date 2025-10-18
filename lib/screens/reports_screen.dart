import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
  final _dateFormat = DateFormat('dd MMM yyyy');

  TabController? _tabController;

  // Date Range - Managed at parent level
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  // Quick date filters
  String _selectedPeriod = 'Last 30 Days';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  // ============================================================================
  // DATE FILTERING
  // ============================================================================

  void _applyQuickFilter(String period) {
    setState(() {
      _selectedPeriod = period;
      final now = DateTime.now();

      switch (period) {
        case 'Today':
          _startDate = DateTime(now.year, now.month, now.day);
          _endDate = now;
          break;
        case 'Yesterday':
          final yesterday = now.subtract(const Duration(days: 1));
          _startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
          _endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
          break;
        case 'Last 7 Days':
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = now;
          break;
        case 'Last 30 Days':
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
          break;
        case 'This Month':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = now;
          break;
        case 'Last Month':
          final lastMonth = DateTime(now.year, now.month - 1, 1);
          _startDate = lastMonth;
          _endDate = DateTime(now.year, now.month, 0, 23, 59, 59);
          break;
        case 'This Year':
          _startDate = DateTime(now.year, 1, 1);
          _endDate = now;
          break;
      }
    });
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.indigo,
            colorScheme: const ColorScheme.light(primary: Colors.indigo),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedPeriod = 'Custom';
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  // ============================================================================
  // FILTER DIALOG
  // ============================================================================

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Period'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            'Today',
            'Yesterday',
            'Last 7 Days',
            'Last 30 Days',
            'This Month',
            'Last Month',
            'This Year',
          ].map((period) {
            return ListTile(
              title: Text(period),
              leading: Radio<String>(
                value: period,
                groupValue: _selectedPeriod,
                onChanged: (value) {
                  Navigator.pop(context);
                  _applyQuickFilter(period);
                },
              ),
              onTap: () {
                Navigator.pop(context);
                _applyQuickFilter(period);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _selectCustomDateRange();
            },
            child: const Text('Custom Range'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // BUILD UI - Main Controller Widget
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Business Analytics'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              // Date Range Display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.indigo.shade700,
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedPeriod == 'Custom'
                            ? '${_dateFormat.format(_startDate)} - ${_dateFormat.format(_endDate)}'
                            : _selectedPeriod,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _selectCustomDateRange,
                      icon: const Icon(Icons.edit_calendar, size: 16, color: Colors.white),
                      label: const Text('Change', style: TextStyle(color: Colors.white)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                  ],
                ),
              ),
              // Tabs
              TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard, size: 18), text: 'Overview'),
                  Tab(icon: Icon(Icons.trending_up, size: 18), text: 'Sales'),
                  Tab(icon: Icon(Icons.inventory, size: 18), text: 'Products'),
                  Tab(icon: Icon(Icons.people, size: 18), text: 'Customers'),
                  Tab(icon: Icon(Icons.attach_money, size: 18), text: 'Profit'),
                  Tab(icon: Icon(Icons.warehouse, size: 18), text: 'Stock'),
                  Tab(icon: Icon(Icons.account_balance_wallet, size: 18), text: 'Collections'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Each tab is now a lazy-loading widget with its own state management
          OverviewReportsView(
            key: ValueKey('overview_${_startDate}_${_endDate}'),
            startDate: _startDate,
            endDate: _endDate,
            currencyFormat: _currencyFormat,
            dateFormat: _dateFormat,
          ),
          SalesReportsView(
            key: ValueKey('sales_${_startDate}_${_endDate}'),
            startDate: _startDate,
            endDate: _endDate,
            currencyFormat: _currencyFormat,
            dateFormat: _dateFormat,
          ),
          ProductReportsView(
            key: ValueKey('products_${_startDate}_${_endDate}'),
            startDate: _startDate,
            endDate: _endDate,
            currencyFormat: _currencyFormat,
            dateFormat: _dateFormat,
          ),
          CustomerReportsView(
            key: ValueKey('customers_${_startDate}_${_endDate}'),
            startDate: _startDate,
            endDate: _endDate,
            currencyFormat: _currencyFormat,
            dateFormat: _dateFormat,
          ),
          ProfitReportsView(
            key: ValueKey('profit_${_startDate}_${_endDate}'),
            startDate: _startDate,
            endDate: _endDate,
            currencyFormat: _currencyFormat,
            dateFormat: _dateFormat,
          ),
          StockReportsView(
            key: ValueKey('stock_${_startDate}_${_endDate}'),
            startDate: _startDate,
            endDate: _endDate,
            currencyFormat: _currencyFormat,
            dateFormat: _dateFormat,
          ),
          CollectionReportsView(
            key: ValueKey('collections_${_startDate}_${_endDate}'),
            startDate: _startDate,
            endDate: _endDate,
            currencyFormat: _currencyFormat,
            dateFormat: _dateFormat,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// LAZY-LOADING CHILD WIDGETS
// ============================================================================

// Base class for common loading/error states
class _BaseReportView extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const _BaseReportView({
    required this.child,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: child,
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}

class ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const ErrorView({
    Key? key,
    required this.error,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade400, size: 64),
          const SizedBox(height: 16),
          Text(
            'Error loading data',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final String message;

  const EmptyView({
    Key? key,
    required this.message,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, color: Colors.grey.shade400, size: 64),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 1: OVERVIEW REPORTS VIEW
// ============================================================================

class OverviewReportsView extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  const OverviewReportsView({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.currencyFormat,
    required this.dateFormat,
  }) : super(key: key);

  @override
  State<OverviewReportsView> createState() => _OverviewReportsViewState();
}

class _OverviewReportsViewState extends State<OverviewReportsView> {
  final DatabaseHelper _db = DatabaseHelper();
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(OverviewReportsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      _dataFuture = _loadData();
    }
  }

  Future<Map<String, dynamic>> _loadData() async {
    try {
      final dashboardData = await _db.getDashboardStats();
      final dailySales = await _db.getDailySales(widget.startDate, widget.endDate);

      final totalSales = dailySales.fold<double>(
        0,
            (sum, day) => sum + ((day['totalSales'] as num?)?.toDouble() ?? 0),
      );

      final totalBills = dailySales.fold<int>(
        0,
            (sum, day) => sum + ((day['totalBills'] as int?) ?? 0),
      );

      final avgBillValue = totalBills > 0 ? totalSales / totalBills : 0.0;

      return {
        'dashboard': dashboardData,
        'totalSales': totalSales,
        'totalBills': totalBills,
        'avgBillValue': avgBillValue,
      };
    } catch (e) {
      throw e;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BaseReportView(
      onRefresh: () {
        setState(() {
          _dataFuture = _loadData();
        });
        return _dataFuture;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }

          if (snapshot.hasError) {
            return ErrorView(
              error: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _dataFuture = _loadData();
                });
              },
            );
          }

          if (!snapshot.hasData) {
            return const EmptyView(message: 'No data available');
          }

          final data = snapshot.data!;
          final dashboard = data['dashboard'] as Map<String, dynamic>;
          final totalSales = data['totalSales'] as double;
          final totalBills = data['totalBills'] as int;
          final avgBillValue = data['avgBillValue'] as double;

          final clientsCount = dashboard['clientsCount'] ?? 0;
          final productsCount = dashboard['productsCount'] ?? 0;
          final pendingPayments = dashboard['pendingPayments'] ?? 0.0;
          final lowStockCount = dashboard['lowStockCount'] ?? 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Key Metrics
                const Text('📊 Key Metrics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    _buildMetricCard(
                      'Total Sales',
                      widget.currencyFormat.format(totalSales),
                      Icons.payments,
                      Colors.green,
                      subtitle: '$totalBills bills',
                    ),
                    _buildMetricCard(
                      'Avg Bill Value',
                      widget.currencyFormat.format(avgBillValue),
                      Icons.receipt,
                      Colors.blue,
                    ),
                    _buildMetricCard(
                      'Active Customers',
                      '$clientsCount',
                      Icons.people,
                      Colors.purple,
                    ),
                    _buildMetricCard(
                      'Products',
                      '$productsCount',
                      Icons.inventory_2,
                      Colors.orange,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Alerts
                const Text('⚠️ Alerts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                if (pendingPayments > 0)
                  _buildAlertCard(
                    'Outstanding Payments',
                    widget.currencyFormat.format(pendingPayments),
                    'Total pending from customers',
                    Colors.red,
                    Icons.warning,
                  ),

                if (lowStockCount > 0)
                  _buildAlertCard(
                    'Low Stock Alert',
                    '$lowStockCount items',
                    'Products running low on inventory',
                    Colors.orange,
                    Icons.inventory,
                  ),

                const SizedBox(height: 24),

                // Quick Stats
                const Text('📈 Period Summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                Container(
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
                    children: [
                      _buildSummaryRow('Period', '${widget.dateFormat.format(widget.startDate)} - ${widget.dateFormat.format(widget.endDate)}'),
                      const Divider(height: 20),
                      _buildSummaryRow('Total Sales', widget.currencyFormat.format(totalSales)),
                      _buildSummaryRow('Total Bills', '$totalBills'),
                      _buildSummaryRow('Avg Bill', widget.currencyFormat.format(avgBillValue)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ],
      ),
    );
  }

  Widget _buildAlertCard(String title, String value, String subtitle, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 2: SALES REPORTS VIEW
// ============================================================================

class SalesReportsView extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  const SalesReportsView({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.currencyFormat,
    required this.dateFormat,
  }) : super(key: key);

  @override
  State<SalesReportsView> createState() => _SalesReportsViewState();
}

class _SalesReportsViewState extends State<SalesReportsView> {
  final DatabaseHelper _db = DatabaseHelper();
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(SalesReportsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      _dataFuture = _loadData();
    }
  }

  Future<Map<String, dynamic>> _loadData() async {
    try {
      final dailySales = await _db.getDailySales(widget.startDate, widget.endDate);
      final yearlySales = await _db.getYearlySales();
      final yoyComparison = await _db.getYearOverYearComparison(DateTime.now().year);

      return {
        'dailySales': dailySales,
        'yearlySales': yearlySales,
        'yoyComparison': yoyComparison,
      };
    } catch (e) {
      throw e;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BaseReportView(
      onRefresh: () {
        setState(() {
          _dataFuture = _loadData();
        });
        return _dataFuture;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }

          if (snapshot.hasError) {
            return ErrorView(
              error: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _dataFuture = _loadData();
                });
              },
            );
          }

          if (!snapshot.hasData) {
            return const EmptyView(message: 'No sales data available');
          }

          final data = snapshot.data!;
          final dailySales = data['dailySales'] as List<Map<String, dynamic>>;
          final yearlySales = data['yearlySales'] as Map<String, dynamic>;
          final yoyData = data['yoyComparison'] as Map<String, dynamic>;

          final totalSales = (yearlySales['totalSales'] as num?)?.toDouble() ?? 0.0;
          final totalProfit = (yearlySales['totalProfit'] as num?)?.toDouble() ?? 0.0;
          final avgBillValue = (yearlySales['avgBillValue'] as num?)?.toDouble() ?? 0.0;
          final uniqueCustomers = (yearlySales['uniqueCustomers'] as num?)?.toInt() ?? 0;
          final salesGrowth = (yoyData['salesGrowthPercent'] as num?)?.toDouble() ?? 0.0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Year Overview
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade600, Colors.blue.shade800],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.white, size: 24),
                          const SizedBox(width: 12),
                          Text(
                            'Year ${DateTime.now().year}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          if (salesGrowth != 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    salesGrowth >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${salesGrowth.abs().toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Total Sales',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.currencyFormat.format(totalSales),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'Total Profit',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.currencyFormat.format(totalProfit),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildYearStatChip('Avg Bill', widget.currencyFormat.format(avgBillValue)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildYearStatChip('Customers', '$uniqueCustomers'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Daily Sales Chart
                const Text('📈 Daily Sales', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                if (dailySales.isEmpty)
                  const EmptyView(message: 'No sales data for selected period')
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: dailySales.take(15).map((day) {
                        final date = day['date'] as String? ?? '';
                        final sales = (day['totalSales'] as num?)?.toDouble() ?? 0.0;
                        final bills = (day['totalBills'] as num?)?.toInt() ?? 0;
                        final customers = (day['uniqueCustomers'] as num?)?.toInt() ?? 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    date.isNotEmpty
                                        ? DateFormat('dd\nMMM').format(DateTime.parse(date))
                                        : '-',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.currencyFormat.format(sales),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '$bills bills • $customers customers',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildYearStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 3: PRODUCT REPORTS VIEW
// ============================================================================

class ProductReportsView extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  const ProductReportsView({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.currencyFormat,
    required this.dateFormat,
  }) : super(key: key);

  @override
  State<ProductReportsView> createState() => _ProductReportsViewState();
}

class _ProductReportsViewState extends State<ProductReportsView> {
  final DatabaseHelper _db = DatabaseHelper();
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(ProductReportsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      _dataFuture = _loadData();
    }
  }

  Future<Map<String, dynamic>> _loadData() async {
    try {
      final productReport = await _db.getProductSalesReport(
        startDate: widget.startDate,
        endDate: widget.endDate,
        limit: 50,
      );

      return {
        'productReport': productReport,
      };
    } catch (e) {
      throw e;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BaseReportView(
      onRefresh: () {
        setState(() {
          _dataFuture = _loadData();
        });
        return _dataFuture;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }

          if (snapshot.hasError) {
            return ErrorView(
              error: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _dataFuture = _loadData();
                });
              },
            );
          }

          if (!snapshot.hasData) {
            return const EmptyView(message: 'No product data available');
          }

          final data = snapshot.data!;
          final productReport = data['productReport'] as List<Map<String, dynamic>>;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Performance Table
                const Text('📊 Product Performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                if (productReport.isEmpty)
                  const EmptyView(message: 'No product data for selected period')
                else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: Row(
                            children: const [
                              Expanded(flex: 3, child: Text('Product', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(flex: 2, child: Text('Sales', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(flex: 2, child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(flex: 2, child: Text('Profit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            ],
                          ),
                        ),
                        // Rows
                        ...productReport.take(20).map((product) {
                          final name = product['productName'] as String? ?? 'Unknown';
                          final sales = (product['totalSales'] as num?)?.toDouble() ?? 0;
                          final quantity = (product['totalQuantity'] as num?)?.toDouble() ?? 0;
                          final profit = (product['totalProfit'] as num?)?.toDouble() ?? 0;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    name,
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    widget.currencyFormat.format(sales),
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    quantity.toInt().toString(),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    widget.currencyFormat.format(profit),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: profit >= 0 ? Colors.green : Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// TAB 4: CUSTOMER REPORTS VIEW
// ============================================================================

class CustomerReportsView extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  const CustomerReportsView({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.currencyFormat,
    required this.dateFormat,
  }) : super(key: key);

  @override
  State<CustomerReportsView> createState() => _CustomerReportsViewState();
}

class _CustomerReportsViewState extends State<CustomerReportsView> {
  final DatabaseHelper _db = DatabaseHelper();
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(CustomerReportsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      _dataFuture = _loadData();
    }
  }

  Future<Map<String, dynamic>> _loadData() async {
    try {
      final customerAnalysis = await _db.getCustomerAnalysis(
        startDate: widget.startDate,
        endDate: widget.endDate,
        limit: 100,
      );

      final outstanding = await _db.getOutstandingBalances();

      return {
        'customerAnalysis': customerAnalysis,
        'outstanding': outstanding,
      };
    } catch (e) {
      throw e;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BaseReportView(
      onRefresh: () {
        setState(() {
          _dataFuture = _loadData();
        });
        return _dataFuture;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }

          if (snapshot.hasError) {
            return ErrorView(
              error: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _dataFuture = _loadData();
                });
              },
            );
          }

          if (!snapshot.hasData) {
            return const EmptyView(message: 'No customer data available');
          }

          final data = snapshot.data!;
          final customerAnalysis = data['customerAnalysis'] as List<Map<String, dynamic>>;
          final outstanding = data['outstanding'] as List<Map<String, dynamic>>;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Customers
                const Text('👥 Top Customers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                if (customerAnalysis.isEmpty)
                  const EmptyView(message: 'No customer data for selected period')
                else
                  ...customerAnalysis.take(10).map((customer) {
                    final name = customer['clientName'] as String? ?? 'Unknown';
                    final total = (customer['totalPurchases'] as num?)?.toDouble() ?? 0;
                    final bills = (customer['totalBills'] as num?)?.toInt() ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.person, color: Colors.blue, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('$bills bills', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                          Text(widget.currencyFormat.format(total),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 24),

                // Outstanding
                if (outstanding.isNotEmpty) ...[
                  const Text('💰 Outstanding Balances', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...outstanding.take(10).map((customer) {
                    final name = customer['name'] as String? ?? 'Unknown';
                    final balance = (customer['balance'] as num?)?.toDouble() ?? 0;
                    final totalBills = (customer['totalBills'] as num?)?.toDouble() ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person, color: Colors.red, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('${widget.currencyFormat.format(totalBills)} billed',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                          Text(
                            widget.currencyFormat.format(balance),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// TAB 5: PROFIT REPORTS VIEW
// ============================================================================

class ProfitReportsView extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  const ProfitReportsView({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.currencyFormat,
    required this.dateFormat,
  }) : super(key: key);

  @override
  State<ProfitReportsView> createState() => _ProfitReportsViewState();
}

class _ProfitReportsViewState extends State<ProfitReportsView> {
  final DatabaseHelper _db = DatabaseHelper();
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(ProfitReportsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      _dataFuture = _loadData();
    }
  }

  Future<Map<String, dynamic>> _loadData() async {
    try {
      final profitAnalysis = await _db.getProfitAnalysis(
        startDate: widget.startDate,
        endDate: widget.endDate,
        groupBy: 'day',
      );

      return {
        'profitAnalysis': profitAnalysis,
      };
    } catch (e) {
      throw e;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BaseReportView(
      onRefresh: () {
        setState(() {
          _dataFuture = _loadData();
        });
        return _dataFuture;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }

          if (snapshot.hasError) {
            return ErrorView(
              error: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _dataFuture = _loadData();
                });
              },
            );
          }

          if (!snapshot.hasData) {
            return const EmptyView(message: 'No profit data available');
          }

          final data = snapshot.data!;
          final profitAnalysis = data['profitAnalysis'] as Map<String, dynamic>;
          final summary = profitAnalysis['summary'] as Map<String, dynamic>? ?? {};
          final trends = profitAnalysis['trends'] as List<Map<String, dynamic>>? ?? [];

          final totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 0;
          final totalCost = (summary['totalCost'] as num?)?.toDouble() ?? 0;
          final totalProfit = (summary['totalProfit'] as num?)?.toDouble() ?? 0;
          final avgMargin = (summary['avgMarginPercent'] as num?)?.toDouble() ?? 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: avgMargin > 20
                          ? [Colors.green.shade600, Colors.green.shade800]
                          : [Colors.orange.shade600, Colors.orange.shade800],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Average Profit Margin',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${avgMargin.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Sales', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  widget.currencyFormat.format(totalSales),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Cost', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  widget.currencyFormat.format(totalCost),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Profit', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  widget.currencyFormat.format(totalProfit),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Daily Profit Trend
                const Text('📊 Profit Trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                if (trends.isEmpty)
                  const EmptyView(message: 'No profit trend data available')
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: trends.take(15).map((day) {
                        final period = day['period'] as String;
                        final sales = (day['sales'] as num?)?.toDouble() ?? 0;
                        final profit = (day['profit'] as num?)?.toDouble() ?? 0;
                        final margin = sales > 0 ? (profit / sales * 100) : 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: Text(
                                  widget.dateFormat.format(DateTime.parse(period)),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      widget.currencyFormat.format(profit),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: profit >= 0 ? Colors.green : Colors.red,
                                      ),
                                    ),
                                    Text(
                                      '${margin.toStringAsFixed(1)}% margin',
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// TAB 6: STOCK REPORTS VIEW
// ============================================================================

class StockReportsView extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  const StockReportsView({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.currencyFormat,
    required this.dateFormat,
  }) : super(key: key);

  @override
  State<StockReportsView> createState() => _StockReportsViewState();
}

class _StockReportsViewState extends State<StockReportsView> {
  final DatabaseHelper _db = DatabaseHelper();
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(StockReportsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      _dataFuture = _loadData();
    }
  }

  Future<Map<String, dynamic>> _loadData() async {
    try {
      final stockAnalysis = await _db.getStockAnalysis();

      return {
        'stockAnalysis': stockAnalysis,
      };
    } catch (e) {
      throw e;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BaseReportView(
      onRefresh: () {
        setState(() {
          _dataFuture = _loadData();
        });
        return _dataFuture;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }

          if (snapshot.hasError) {
            return ErrorView(
              error: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _dataFuture = _loadData();
                });
              },
            );
          }

          if (!snapshot.hasData) {
            return const EmptyView(message: 'No stock data available');
          }

          final data = snapshot.data!;
          final analysis = data['stockAnalysis'] as Map<String, dynamic>;

          final totalStockValue = analysis['totalStockValue'] as double? ?? 0;
          final fastMoving = analysis['fastMoving'] as List<Map<String, dynamic>>? ?? [];
          final slowMoving = analysis['slowMoving'] as List<Map<String, dynamic>>? ?? [];
          final deadStock = analysis['deadStock'] as List<Map<String, dynamic>>? ?? [];
          final underStocked = analysis['underStocked'] as List<Map<String, dynamic>>? ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Total Stock Value
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple.shade600, Colors.purple.shade800],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Stock Value', style: TextStyle(color: Colors.white, fontSize: 16)),
                          SizedBox(height: 4),
                          Text('Current inventory worth', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                      Text(
                        widget.currencyFormat.format(totalStockValue),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Stock Health Grid
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.8,
                  children: [
                    _buildStockMetricCard('🚀 Fast Moving', fastMoving.length, Colors.green),
                    _buildStockMetricCard('🐌 Slow Moving', slowMoving.length, Colors.orange),
                    _buildStockMetricCard('💀 Dead Stock', deadStock.length, Colors.red),
                    _buildStockMetricCard('⚠️ Under Stocked', underStocked.length, Colors.red),
                  ],
                ),

                const SizedBox(height: 24),

                // Alerts
                if (underStocked.isNotEmpty) ...[
                  const Text('🚨 Understocked (Priority)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 12),
                  ...underStocked.take(5).map((product) => _buildStockItemCard(product, Colors.red)),
                  const SizedBox(height: 24),
                ],

                if (deadStock.isNotEmpty) ...[
                  const Text('💀 Dead Stock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...deadStock.take(5).map((product) => _buildStockItemCard(product, Colors.grey)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStockMetricCard(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory, color: color, size: 24),
          const SizedBox(height: 8),
          Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildStockItemCard(Map<String, dynamic> product, Color color) {
    final name = product['name'] as String? ?? 'Unknown';
    final stock = (product['stock'] as num?)?.toDouble() ?? 0;
    final daysOfStock = (product['daysOfStock'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${stock.toInt()} units', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Text(
            daysOfStock == 999 ? '∞ days' : '${daysOfStock.toStringAsFixed(1)}d',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 7: COLLECTION REPORTS VIEW
// ============================================================================

class CollectionReportsView extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  const CollectionReportsView({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.currencyFormat,
    required this.dateFormat,
  }) : super(key: key);

  @override
  State<CollectionReportsView> createState() => _CollectionReportsViewState();
}

class _CollectionReportsViewState extends State<CollectionReportsView> {
  final DatabaseHelper _db = DatabaseHelper();
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(CollectionReportsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      _dataFuture = _loadData();
    }
  }

  Future<Map<String, dynamic>> _loadData() async {
    try {
      final efficiency = await _db.getCollectionEfficiency(
        startDate: widget.startDate,
        endDate: widget.endDate,
      );

      return {
        'efficiency': efficiency,
      };
    } catch (e) {
      throw e;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BaseReportView(
      onRefresh: () {
        setState(() {
          _dataFuture = _loadData();
        });
        return _dataFuture;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }

          if (snapshot.hasError) {
            return ErrorView(
              error: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _dataFuture = _loadData();
                });
              },
            );
          }

          if (!snapshot.hasData) {
            return const EmptyView(message: 'No collection data available');
          }

          final data = snapshot.data!;
          final efficiency = data['efficiency'] as Map<String, dynamic>;

          // Safe numeric conversions
          final totalBilled = (efficiency['totalBilled'] as num?)?.toDouble() ?? 0;
          final totalCollected = (efficiency['totalCollected'] as num?)?.toDouble() ?? 0;
          final collectionRate = (efficiency['collectionRate'] as num?)?.toDouble() ?? 0;
          final billCount = (efficiency['billCount'] as num?)?.toInt() ?? 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Collection Efficiency
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: collectionRate >= 80
                          ? [Colors.green.shade600, Colors.green.shade800]
                          : collectionRate >= 50
                          ? [Colors.orange.shade600, Colors.orange.shade800]
                          : [Colors.red.shade600, Colors.red.shade800],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Collection Efficiency',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${collectionRate.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Billed',
                                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  widget.currencyFormat.format(totalBilled),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                const Text('Collected',
                                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  widget.currencyFormat.format(totalCollected),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Stats
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        'Total Bills',
                        '$billCount',
                        Icons.receipt,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        'Pending',
                        widget.currencyFormat.format(totalBilled - totalCollected),
                        Icons.pending,
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}