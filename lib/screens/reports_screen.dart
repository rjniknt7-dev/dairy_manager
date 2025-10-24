// lib/screens/reports_screen.dart - COMPLETE ENHANCED VERSION

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
  final _db = DatabaseHelper();

  TabController? _tabController;

  // Dynamic date range
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _selectedPeriod = 'Last 30 Days';

  // Comparison period
  DateTime _comparisonStartDate = DateTime.now().subtract(const Duration(days: 60));
  DateTime _comparisonEndDate = DateTime.now().subtract(const Duration(days: 30));

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

  void _applyQuickFilter(String period) {
    setState(() {
      _selectedPeriod = period;
      final now = DateTime.now();

      switch (period) {
        case 'Today':
          _startDate = DateTime(now.year, now.month, now.day);
          _endDate = now;
          _comparisonStartDate = _startDate.subtract(const Duration(days: 1));
          _comparisonEndDate = _comparisonStartDate.add(const Duration(hours: 23, minutes: 59));
          break;
        case 'Yesterday':
          final yesterday = now.subtract(const Duration(days: 1));
          _startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
          _endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
          _comparisonStartDate = _startDate.subtract(const Duration(days: 1));
          _comparisonEndDate = _endDate.subtract(const Duration(days: 1));
          break;
        case 'Last 7 Days':
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = now;
          _comparisonStartDate = now.subtract(const Duration(days: 14));
          _comparisonEndDate = _startDate;
          break;
        case 'Last 30 Days':
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
          _comparisonStartDate = now.subtract(const Duration(days: 60));
          _comparisonEndDate = _startDate;
          break;
        case 'This Month':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = now;
          final lastMonth = DateTime(now.year, now.month - 1, 1);
          _comparisonStartDate = lastMonth;
          _comparisonEndDate = DateTime(now.year, now.month, 0, 23, 59, 59);
          break;
        case 'Last Month':
          final lastMonth = DateTime(now.year, now.month - 1, 1);
          _startDate = lastMonth;
          _endDate = DateTime(now.year, now.month, 0, 23, 59, 59);
          final monthBefore = DateTime(now.year, now.month - 2, 1);
          _comparisonStartDate = monthBefore;
          _comparisonEndDate = DateTime(now.year, now.month - 1, 0, 23, 59, 59);
          break;
        case 'This Year':
          _startDate = DateTime(now.year, 1, 1);
          _endDate = now;
          _comparisonStartDate = DateTime(now.year - 1, 1, 1);
          _comparisonEndDate = DateTime(now.year - 1, 12, 31, 23, 59, 59);
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

        final duration = picked.end.difference(picked.start);
        _comparisonEndDate = picked.start.subtract(const Duration(days: 1));
        _comparisonStartDate = _comparisonEndDate.subtract(duration);
      });
    }
  }

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
            tooltip: 'Change Period',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
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
                    ),
                  ],
                ),
              ),
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
          _OverviewTab(
            startDate: _startDate,
            endDate: _endDate,
            comparisonStart: _comparisonStartDate,
            comparisonEnd: _comparisonEndDate,
            format: _currencyFormat,
            dateFormat: _dateFormat,
          ),
          _SalesTab(
            startDate: _startDate,
            endDate: _endDate,
            comparisonStart: _comparisonStartDate,
            comparisonEnd: _comparisonEndDate,
            format: _currencyFormat,
            dateFormat: _dateFormat,
          ),
          _ProductsTab(
            startDate: _startDate,
            endDate: _endDate,
            format: _currencyFormat,
          ),
          _CustomersTab(
            startDate: _startDate,
            endDate: _endDate,
            format: _currencyFormat,
          ),
          _ProfitTab(
            startDate: _startDate,
            endDate: _endDate,
            comparisonStart: _comparisonStartDate,
            comparisonEnd: _comparisonEndDate,
            format: _currencyFormat,
            dateFormat: _dateFormat,
          ),
          _StockTab(format: _currencyFormat),
          _CollectionsTab(
            startDate: _startDate,
            endDate: _endDate,
            comparisonStart: _comparisonStartDate,
            comparisonEnd: _comparisonEndDate,
            format: _currencyFormat,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 1: OVERVIEW
// ============================================================================

class _OverviewTab extends StatelessWidget {
  final DateTime startDate, endDate, comparisonStart, comparisonEnd;
  final NumberFormat format;
  final DateFormat dateFormat;

  const _OverviewTab({
    required this.startDate,
    required this.endDate,
    required this.comparisonStart,
    required this.comparisonEnd,
    required this.format,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper();

    return FutureBuilder<Map<String, dynamic>>(
      future: _loadData(db),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final data = snapshot.data ?? {};
        final current = data['current'] ?? {};
        final previous = data['previous'] ?? {};

        final currentSales = (current['totalSales'] as num?)?.toDouble() ?? 0;
        final previousSales = (previous['totalSales'] as num?)?.toDouble() ?? 0;
        final salesGrowth = previousSales > 0
            ? ((currentSales - previousSales) / previousSales * 100)
            : 0.0;

        final currentBills = (current['totalBills'] as int?) ?? 0;
        final previousBills = (previous['totalBills'] as int?) ?? 0;
        final billsGrowth = previousBills > 0
            ? ((currentBills - previousBills) / previousBills * 100)
            : 0.0;

        final avgBillValue = currentBills > 0 ? currentSales / currentBills : 0.0;
        final prevAvgBill = previousBills > 0 ? previousSales / previousBills : 0.0;
        final avgBillGrowth = prevAvgBill > 0
            ? ((avgBillValue - prevAvgBill) / prevAvgBill * 100)
            : 0.0;

        final clientsCount = (data['clientsCount'] as int?) ?? 0;
        final productsCount = (data['productsCount'] as int?) ?? 0;
        final lowStockCount = (data['lowStockCount'] as int?) ?? 0;
        final pendingAmount = (data['pendingPayments'] as num?)?.toDouble() ?? 0;

        return RefreshIndicator(
          onRefresh: () async {
            (context as Element).markNeedsBuild();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Period Comparison
              _buildComparisonCard(
                context,
                'Sales Performance',
                currentSales,
                salesGrowth,
                format,
              ),
              const SizedBox(height: 16),

              // Key Metrics Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _buildMetricCard(
                    context,
                    'Total Sales',
                    format.format(currentSales),
                    Icons.payments,
                    Colors.green,
                    subtitle: '$currentBills bills',
                    growth: salesGrowth,
                    onTap: () => Navigator.pushNamed(context, '/history'),
                  ),
                  _buildMetricCard(
                    context,
                    'Avg Bill Value',
                    format.format(avgBillValue),
                    Icons.receipt,
                    Colors.blue,
                    growth: avgBillGrowth,
                    onTap: () => Navigator.pushNamed(context, '/history'),
                  ),
                  _buildMetricCard(
                    context,
                    'Total Bills',
                    '$currentBills',
                    Icons.description,
                    Colors.purple,
                    subtitle: 'transactions',
                    growth: billsGrowth,
                    onTap: () => Navigator.pushNamed(context, '/history'),
                  ),
                  _buildMetricCard(
                    context,
                    'Customers',
                    '$clientsCount',
                    Icons.people,
                    Colors.orange,
                    subtitle: 'active',
                    onTap: () => Navigator.pushNamed(context, '/clients'),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Alerts Section
              const Text('⚠️ Alerts & Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              if (pendingAmount > 0)
                _buildAlertCard(
                  context,
                  '💰 Outstanding Payments',
                  format.format(pendingAmount),
                  'Collect pending amounts',
                  Colors.red,
                  onTap: () => Navigator.pushNamed(context, '/ledgerBook'),
                ),

              if (lowStockCount > 0)
                _buildAlertCard(
                  context,
                  '📦 Low Stock Alert',
                  '$lowStockCount items',
                  'Restock inventory soon',
                  Colors.orange,
                  onTap: () => Navigator.pushNamed(context, '/inventory'),
                ),

              _buildAlertCard(
                context,
                '📊 View All Products',
                '$productsCount items',
                'Manage your inventory',
                Colors.blue,
                onTap: () => Navigator.pushNamed(context, '/products'),
              ),

              const SizedBox(height: 24),

              // Quick Actions
              const Text('⚡ Quick Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildActionButton(
                    context,
                    'New Bill',
                    Icons.add_shopping_cart,
                    Colors.green,
                        () => Navigator.pushNamed(context, '/billing'),
                  ),
                  _buildActionButton(
                    context,
                    'Add Payment',
                    Icons.payment,
                    Colors.blue,
                        () => Navigator.pushNamed(context, '/ledgerBook'),
                  ),
                  _buildActionButton(
                    context,
                    'Stock Entry',
                    Icons.inventory,
                    Colors.purple,
                        () => Navigator.pushNamed(context, '/inventory'),
                  ),
                  _buildActionButton(
                    context,
                    'Demand',
                    Icons.local_shipping,
                    Colors.orange,
                        () => Navigator.pushNamed(context, '/demand'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadData(DatabaseHelper db) async {
    final currentData = await db.getDailySales(startDate, endDate);
    final previousData = await db.getDailySales(comparisonStart, comparisonEnd);

    final currentSales = currentData.fold<double>(
        0, (sum, day) => sum + ((day['totalSales'] as num?)?.toDouble() ?? 0));
    final currentBills = currentData.fold<int>(
        0, (sum, day) => sum + ((day['totalBills'] as int?) ?? 0));

    final previousSales = previousData.fold<double>(
        0, (sum, day) => sum + ((day['totalSales'] as num?)?.toDouble() ?? 0));
    final previousBills = previousData.fold<int>(
        0, (sum, day) => sum + ((day['totalBills'] as int?) ?? 0));

    final dashboard = await db.getDashboardStats();

    return {
      'current': {'totalSales': currentSales, 'totalBills': currentBills},
      'previous': {'totalSales': previousSales, 'totalBills': previousBills},
      'clientsCount': dashboard['clientsCount'] ?? 0,
      'productsCount': dashboard['productsCount'] ?? 0,
      'lowStockCount': dashboard['lowStockCount'] ?? 0,
      'pendingPayments': dashboard['pendingPayments'] ?? 0.0,
    };
  }

  Widget _buildComparisonCard(
      BuildContext context,
      String title,
      double value,
      double growth,
      NumberFormat format,
      ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade600, Colors.indigo.shade800],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
              _TrendIndicator(value: growth),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            format.format(value),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'vs previous period',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
      BuildContext context,
      String title,
      String value,
      IconData icon,
      Color color, {
        String? subtitle,
        double? growth,
        VoidCallback? onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                if (growth != null && growth != 0)
                  _TrendIndicator(value: growth, compact: true),
              ],
            ),
            const Spacer(),
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
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(
      BuildContext context,
      String title,
      String value,
      String subtitle,
      Color color, {
        VoidCallback? onTap,
      }) {
    return InkWell(
      onTap: onTap,
      child: Container(
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
              child: Icon(Icons.warning_rounded, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: color),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      BuildContext context,
      String label,
      IconData icon,
      Color color,
      VoidCallback onTap,
      ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: (MediaQuery.of(context).size.width - 44) / 2,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 2: SALES
// ============================================================================

class _SalesTab extends StatelessWidget {
  final DateTime startDate, endDate, comparisonStart, comparisonEnd;
  final NumberFormat format;
  final DateFormat dateFormat;

  const _SalesTab({
    required this.startDate,
    required this.endDate,
    required this.comparisonStart,
    required this.comparisonEnd,
    required this.format,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: db.getDailySales(startDate, endDate),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final dailySales = snapshot.data ?? [];

        if (dailySales.isEmpty) {
          return const Center(
            child: Text('No sales data for selected period'),
          );
        }

        final totalSales = dailySales.fold<double>(
            0, (sum, day) => sum + ((day['totalSales'] as num?)?.toDouble() ?? 0));
        final totalBills = dailySales.fold<int>(
            0, (sum, day) => sum + ((day['totalBills'] as int?) ?? 0));

        return RefreshIndicator(
          onRefresh: () async {
            (context as Element).markNeedsBuild();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary Card
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
                    const Text(
                      'Total Sales',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      format.format(totalSales),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryChip('Bills', '$totalBills'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSummaryChip(
                            'Avg',
                            format.format(totalBills > 0 ? totalSales / totalBills : 0),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Daily Breakdown
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '📅 Daily Sales',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/history'),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              ...dailySales.take(15).map((day) {
                final date = day['date'] as String? ?? '';
                final sales = (day['totalSales'] as num?)?.toDouble() ?? 0;
                final bills = (day['totalBills'] as num?)?.toInt() ?? 0;
                final customers = (day['uniqueCustomers'] as num?)?.toInt() ?? 0;

                return InkWell(
                  onTap: () {
                    // Navigate to history with date filter
                    Navigator.pushNamed(context, '/history');
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
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
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                format.format(sales),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
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
                        Icon(Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 3: PRODUCTS
// ============================================================================

class _ProductsTab extends StatelessWidget {
  final DateTime startDate, endDate;
  final NumberFormat format;

  const _ProductsTab({
    required this.startDate,
    required this.endDate,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: db.getProductSalesReport(
        startDate: startDate,
        endDate: endDate,
        limit: 100,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final products = snapshot.data ?? [];

        if (products.isEmpty) {
          return const Center(
            child: Text('No product data for selected period'),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            (context as Element).markNeedsBuild();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '📦 Product Performance',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/products'),
                    icon: const Icon(Icons.inventory, size: 16),
                    label: const Text('Manage'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Top 5 Products - Card View
              ...products.take(5).map((product) {
                final name = product['productName'] as String? ?? 'Unknown';
                final sales = (product['totalSales'] as num?)?.toDouble() ?? 0;
                final quantity = (product['totalQuantity'] as num?)?.toDouble() ?? 0;
                final profit = (product['totalProfit'] as num?)?.toDouble() ?? 0;
                final bills = (product['totalBills'] as num?)?.toInt() ?? 0;
                final stock = (product['currentStock'] as num?)?.toDouble() ?? 0;

                return InkWell(
                  onTap: () {
                    // Show product details dialog
                    _showProductDetails(context, product);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.inventory_2,
                                color: Colors.green.shade600,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Stock: ${stock.toInt()} units',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: stock < 10
                                          ? Colors.red
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey.shade400),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _buildProductStat(
                                'Sales',
                                format.format(sales),
                                Colors.green,
                              ),
                            ),
                            Expanded(
                              child: _buildProductStat(
                                'Qty',
                                quantity.toInt().toString(),
                                Colors.blue,
                              ),
                            ),
                            Expanded(
                              child: _buildProductStat(
                                'Profit',
                                format.format(profit),
                                profit >= 0 ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),

              // Remaining Products - Table View
              if (products.length > 5) ...[
                const Text(
                  'All Products',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: const [
                            Expanded(
                              flex: 3,
                              child: Text(
                                'Product',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Sales',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'Qty',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Rows
                      ...products.skip(5).map((product) {
                        final name = product['productName'] as String? ?? 'Unknown';
                        final sales = (product['totalSales'] as num?)?.toDouble() ?? 0;
                        final quantity = (product['totalQuantity'] as num?)?.toDouble() ?? 0;

                        return InkWell(
                          onTap: () => _showProductDetails(context, product),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade200),
                              ),
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
                                    format.format(sales),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    quantity.toInt().toString(),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showProductDetails(BuildContext context, Map<String, dynamic> product) {
    final name = product['productName'] as String? ?? 'Unknown';
    final sales = (product['totalSales'] as num?)?.toDouble() ?? 0;
    final quantity = (product['totalQuantity'] as num?)?.toDouble() ?? 0;
    final profit = (product['totalProfit'] as num?)?.toDouble() ?? 0;
    final bills = (product['totalBills'] as num?)?.toInt() ?? 0;
    final stock = (product['currentStock'] as num?)?.toDouble() ?? 0;
    final price = (product['currentPrice'] as num?)?.toDouble() ?? 0;
    final costPrice = (product['currentCostPrice'] as num?)?.toDouble() ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    color: Colors.green.shade600,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Stock: ${stock.toInt()} units',
                        style: TextStyle(
                          color: stock < 10 ? Colors.red : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 32),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 2,
              children: [
                _buildDetailCard('Total Sales', format.format(sales), Icons.payments),
                _buildDetailCard('Quantity Sold', quantity.toInt().toString(), Icons.shopping_cart),
                _buildDetailCard('Total Profit', format.format(profit), Icons.trending_up),
                _buildDetailCard('Bills Count', bills.toString(), Icons.receipt),
                _buildDetailCard('Selling Price', format.format(price), Icons.sell),
                _buildDetailCard('Cost Price', format.format(costPrice), Icons.attach_money),
              ],
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/products');
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit Product'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 4: CUSTOMERS
// ============================================================================

class _CustomersTab extends StatelessWidget {
  final DateTime startDate, endDate;
  final NumberFormat format;

  const _CustomersTab({
    required this.startDate,
    required this.endDate,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper();

    return FutureBuilder<Map<String, dynamic>>(
      future: _loadData(db),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final data = snapshot.data ?? {};
        final topCustomers = data['topCustomers'] as List<Map<String, dynamic>>? ?? [];
        final outstanding = data['outstanding'] as List<Map<String, dynamic>>? ?? [];

        return RefreshIndicator(
          onRefresh: () async {
            (context as Element).markNeedsBuild();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '👥 Top Customers',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/clients'),
                    icon: const Icon(Icons.people, size: 16),
                    label: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (topCustomers.isEmpty)
                const Center(child: Text('No customer data available'))
              else
                ...topCustomers.take(10).map((customer) {
                  final id = customer['clientId'] as int? ?? 0;
                  final name = customer['clientName'] as String? ?? 'Unknown';
                  final total = (customer['totalPurchases'] as num?)?.toDouble() ?? 0;
                  final bills = (customer['totalBills'] as num?)?.toInt() ?? 0;
                  final avgBill = (customer['avgBillValue'] as num?)?.toDouble() ?? 0;
                  final lastPurchase = customer['lastPurchaseDate'] as String?;

                  return InkWell(
                    onTap: () {
                      _showCustomerDetails(context, customer);
                    },
                    child: Container(
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
                            child: const Icon(
                              Icons.person,
                              color: Colors.blue,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$bills bills • Avg: ${format.format(avgBill)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (lastPurchase != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Last: ${DateFormat('dd MMM').format(DateTime.parse(lastPurchase))}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                format.format(total),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Colors.grey.shade400),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),

              // Outstanding Balances
              if (outstanding.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '💰 Outstanding Payments',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/ledgerBook'),
                      icon: const Icon(Icons.account_balance_wallet, size: 16),
                      label: const Text('Ledger'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                ...outstanding.take(10).map((customer) {
                  final id = customer['id'] as int? ?? 0;
                  final name = customer['name'] as String? ?? 'Unknown';
                  final balance = (customer['balance'] as num?)?.toDouble() ?? 0;
                  final totalBills = (customer['totalBills'] as num?)?.toDouble() ?? 0;
                  final phone = customer['phone'] as String?;

                  return InkWell(
                    onTap: () {
                      Navigator.pushNamed(context, '/ledgerBook');
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.red, size: 24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${format.format(totalBills)} billed',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (phone != null && phone.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    phone,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                format.format(balance),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Colors.grey.shade400),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadData(DatabaseHelper db) async {
    final topCustomers = await db.getCustomerAnalysis(
      startDate: startDate,
      endDate: endDate,
      limit: 50,
      orderBy: 'totalPurchases',
    );

    final outstanding = await db.getOutstandingBalances();

    return {
      'topCustomers': topCustomers,
      'outstanding': outstanding,
    };
  }

  void _showCustomerDetails(BuildContext context, Map<String, dynamic> customer) {
    final name = customer['clientName'] as String? ?? 'Unknown';
    final total = (customer['totalPurchases'] as num?)?.toDouble() ?? 0;
    final bills = (customer['totalBills'] as num?)?.toInt() ?? 0;
    final avgBill = (customer['avgBillValue'] as num?)?.toDouble() ?? 0;
    final outstanding = (customer['currentOutstanding'] as num?)?.toDouble() ?? 0;
    final phone = customer['clientPhone'] as String?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.person,
                    color: Colors.blue.shade600,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (phone != null && phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(phone, style: const TextStyle(color: Colors.grey)),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 32),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 2,
              children: [
                _buildDetailCard('Total Purchase', format.format(total), Icons.shopping_bag),
                _buildDetailCard('Total Bills', bills.toString(), Icons.receipt),
                _buildDetailCard('Avg Bill', format.format(avgBill), Icons.analytics),
                _buildDetailCard('Outstanding', format.format(outstanding), Icons.warning,
                    color: outstanding > 0 ? Colors.red : Colors.green),
              ],
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/ledgerBook');
                    },
                    icon: const Icon(Icons.account_balance_wallet),
                    label: const Text('View Ledger'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/billing');
                    },
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('New Bill'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(String label, String value, IconData icon, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color ?? Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 5: PROFIT
// ============================================================================

class _ProfitTab extends StatelessWidget {
  final DateTime startDate, endDate, comparisonStart, comparisonEnd;
  final NumberFormat format;
  final DateFormat dateFormat;

  const _ProfitTab({
    required this.startDate,
    required this.endDate,
    required this.comparisonStart,
    required this.comparisonEnd,
    required this.format,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper();

    return FutureBuilder<Map<String, dynamic>>(
      future: db.getProfitAnalysis(startDate: startDate, endDate: endDate, groupBy: 'day'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final data = snapshot.data ?? {};
        final summary = data['summary'] as Map<String, dynamic>? ?? {};
        final trends = data['trends'] as List<Map<String, dynamic>>? ?? [];

        final totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 0;
        final totalCost = (summary['totalCost'] as num?)?.toDouble() ?? 0;
        final totalProfit = (summary['totalProfit'] as num?)?.toDouble() ?? 0;
        final avgMargin = (summary['avgMarginPercent'] as num?)?.toDouble() ?? 0;

        return RefreshIndicator(
          onRefresh: () async {
            (context as Element).markNeedsBuild();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
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
                          child: _buildSummaryChip('Sales', format.format(totalSales)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSummaryChip('Cost', format.format(totalCost)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSummaryChip('Profit', format.format(totalProfit)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Daily Profit Trend
              const Text(
                '📊 Profit Trend',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              if (trends.isEmpty)
                const Center(child: Text('No profit data available'))
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
                      final cost = (day['cost'] as num?)?.toDouble() ?? 0;
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
                                dateFormat.format(DateTime.parse(period)),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    format.format(profit),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: profit >= 0 ? Colors.green : Colors.red,
                                    ),
                                  ),
                                  Text(
                                    '${margin.toStringAsFixed(1)}% margin',
                                    style: const TextStyle(
                                      fontSize: 10,
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
    );
  }

  Widget _buildSummaryChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 6: STOCK
// ============================================================================

class _StockTab extends StatelessWidget {
  final NumberFormat format;

  const _StockTab({required this.format});

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper();

    return FutureBuilder<Map<String, dynamic>>(
      future: db.getStockAnalysis(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final analysis = snapshot.data ?? {};
        final totalStockValue = (analysis['totalStockValue'] as num?)?.toDouble() ?? 0;
        final fastMoving = analysis['fastMoving'] as List<Map<String, dynamic>>? ?? [];
        final slowMoving = analysis['slowMoving'] as List<Map<String, dynamic>>? ?? [];
        final deadStock = analysis['deadStock'] as List<Map<String, dynamic>>? ?? [];
        final underStocked = analysis['underStocked'] as List<Map<String, dynamic>>? ?? [];

        return RefreshIndicator(
          onRefresh: () async {
            (context as Element).markNeedsBuild();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
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
                        Text(
                          'Total Stock Value',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Current inventory worth',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    Text(
                      format.format(totalStockValue),
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
                  _buildStockMetricCard('⚠️ Low Stock', underStocked.length, Colors.red),
                ],
              ),

              const SizedBox(height: 24),

              // Priority Alerts
              if (underStocked.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🚨 Low Stock (Priority)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/inventory'),
                      icon: const Icon(Icons.inventory, size: 16),
                      label: const Text('Manage'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...underStocked.take(5).map((product) =>
                    _buildStockItemCard(context, product, Colors.red)),
                const SizedBox(height: 24),
              ],

              if (deadStock.isNotEmpty) ...[
                const Text(
                  '💀 Dead Stock',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...deadStock.take(5).map((product) =>
                    _buildStockItemCard(context, product, Colors.grey)),
              ],
            ],
          ),
        );
      },
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
          Text(
            '$count',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStockItemCard(BuildContext context, Map<String, dynamic> product, Color color) {
    final name = product['name'] as String? ?? 'Unknown';
    final stock = (product['stock'] as num?)?.toDouble() ?? 0;
    final daysOfStock = (product['daysOfStock'] as num?)?.toDouble() ?? 0;

    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/products'),
      child: Container(
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
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${stock.toInt()} units',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Text(
              daysOfStock == 999 ? '∞ days' : '${daysOfStock.toStringAsFixed(1)}d',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 7: COLLECTIONS
// ============================================================================

class _CollectionsTab extends StatelessWidget {
  final DateTime startDate, endDate, comparisonStart, comparisonEnd;
  final NumberFormat format;

  const _CollectionsTab({
    required this.startDate,
    required this.endDate,
    required this.comparisonStart,
    required this.comparisonEnd,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper();

    return FutureBuilder<Map<String, dynamic>>(
      future: db.getCollectionEfficiency(startDate: startDate, endDate: endDate),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final efficiency = snapshot.data ?? {};
        final totalBilled = (efficiency['totalBilled'] as num?)?.toDouble() ?? 0;
        final totalCollected = (efficiency['totalCollected'] as num?)?.toDouble() ?? 0;
        final collectionRate = (efficiency['collectionRate'] as num?)?.toDouble() ?? 0;
        final billCount = (efficiency['billCount'] as num?)?.toInt() ?? 0;
        final paymentCount = (efficiency['paymentCount'] as num?)?.toInt() ?? 0;

        return RefreshIndicator(
          onRefresh: () async {
            (context as Element).markNeedsBuild();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
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
                          child: _buildCollectionChip('Billed', format.format(totalBilled)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildCollectionChip('Collected', format.format(totalCollected)),
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
                      'Payments',
                      '$paymentCount',
                      Icons.payment,
                      Colors.green,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'Pending',
                      format.format(totalBilled - totalCollected),
                      Icons.pending,
                      Colors.orange,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/ledgerBook'),
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('View Ledger Book'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.indigo,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollectionChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
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

// ============================================================================
// HELPER WIDGETS
// ============================================================================

class _TrendIndicator extends StatelessWidget {
  final double value;
  final bool compact;

  const _TrendIndicator({
    required this.value,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = value >= 0;
    final color = isPositive ? Colors.green : Colors.red;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.arrow_upward : Icons.arrow_downward,
            color: Colors.white,
            size: compact ? 12 : 14,
          ),
          const SizedBox(width: 4),
          Text(
            '${value.abs().toStringAsFixed(1)}%',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 10 : 12,
            ),
          ),
        ],
      ),
    );
  }
}