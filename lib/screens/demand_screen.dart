// lib/screens/demand_screen.dart - FINAL VERSION
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../services/database_helper.dart';
import '../models/client.dart';
import '../models/product.dart';
import 'demand_edit_screen.dart'; // NEW
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

  int? _currentBatchId;
  bool _isBatchClosed = false;
  bool _batchExists = false;
  DateTime _batchDate = DateTime.now();

  List<Map<String, dynamic>> _productTotals = [];
  Map<String, dynamic>? _batchStats;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }
  Future<void> _debugDatabase() async {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('📊 DATABASE DEBUG CHECK');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    final database = await db.database;

    // Get today's date
    final today = DateTime.now();
    final todayStr = today.toIso8601String().substring(0, 10);
    debugPrint('📅 Today: $todayStr');

    // Get all batches
    final allBatches = await database.query(
      'demand_batch',
      orderBy: 'demandDate DESC',
      limit: 5,
    );

    debugPrint('📦 Last 5 batches in database:');
    for (var batch in allBatches) {
      final entryCount = await database.rawQuery(
        'SELECT COUNT(*) as count FROM demand WHERE batchId = ? AND isDeleted = 0',
        [batch['id']],
      );
      final count = Sqflite.firstIntValue(entryCount) ?? 0;

      debugPrint('  - ID: ${batch['id']}');
      debugPrint('    Date: ${batch['demandDate']}');
      debugPrint('    Closed: ${batch['closed']}');
      debugPrint('    Entries: $count');
      debugPrint('    IsDeleted: ${batch['isDeleted']}');
    }

    // Check today's batch specifically
    final todayBatch = await database.query(
      'demand_batch',
      where: 'demandDate = ? AND isDeleted = 0',
      whereArgs: [todayStr],
    );

    if (todayBatch.isNotEmpty) {
      debugPrint('✅ Today\'s batch found:');
      debugPrint('   ${todayBatch.first}');
    } else {
      debugPrint('❌ No batch found for today ($todayStr)');
    }

    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  Future<void> _loadData() async {
    debugPrint('═══════════════════════════════════════');
    debugPrint('🔍 DEMAND SCREEN _loadData() CALLED');
    debugPrint('═══════════════════════════════════════');

    setState(() => _isLoading = true);

    // ✅ Run database debug check
    await _debugDatabase();

    try {
      final clients = await db.getClients();
      final products = await db.getProducts();
      debugPrint('✅ Loaded ${clients.length} clients, ${products.length} products');

      final today = DateTime.now();
      final todayStr = today.toIso8601String().substring(0, 10);

      debugPrint('🔍 Looking for batch on date: $todayStr');

      // Get batch ID
      int? batchId = await db.getBatchIdForDate(today);

      debugPrint('🔍 getBatchIdForDate returned: $batchId');

      bool isClosed = false;
      bool hasEntries = false;

      List<Map<String, dynamic>> totals = [];
      Map<String, dynamic>? stats;

      if (batchId != null) {
        debugPrint('🔍 Batch found, getting details...');

        final batchInfo = await db.getBatchById(batchId);
        debugPrint('🔍 Batch info: $batchInfo');

        isClosed = (batchInfo?['closed'] ?? 0) == 1;

        totals = await db.getCurrentBatchTotals(batchId);
        debugPrint('🔍 Product totals: ${totals.length} products');

        stats = await db.getBatchStats(batchId);
        debugPrint('🔍 Stats: $stats');

        hasEntries = totals.isNotEmpty;

        debugPrint('📊 BATCH STATE:');
        debugPrint('   - ID: $batchId');
        debugPrint('   - Closed: $isClosed');
        debugPrint('   - Has Entries: $hasEntries');
        debugPrint('   - Total Products: ${totals.length}');
      } else {
        debugPrint('⚠️ No batch found for today');
      }

      if (!mounted) return;

      setState(() {
        _clients = clients;
        _products = products;
        _currentBatchId = batchId;
        _isBatchClosed = isClosed;
        _batchExists = hasEntries;
        _batchDate = today;
        _productTotals = totals;
        _batchStats = stats;
        _isLoading = false;
      });

      debugPrint('✅ STATE SET:');
      debugPrint('   - _currentBatchId: $_currentBatchId');
      debugPrint('   - _batchExists: $_batchExists');
      debugPrint('   - _isBatchClosed: $_isBatchClosed');
      debugPrint('   - _productTotals.length: ${_productTotals.length}');
      debugPrint('═══════════════════════════════════════');

    } catch (e, stack) {
      debugPrint('❌ ERROR in _loadData: $e');
      debugPrint('Stack: $stack');
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('Error loading data: $e', isError: true);
      }
    }
  }

  Future<void> _closeBatch() async {
    if (_currentBatchId == null || _isBatchClosed) return;

    if (_productTotals.isEmpty) {
      _showMessage('No demands to close');
      return;
    }

    final confirmed = await _showCloseConfirmDialog();
    if (confirmed != true) return;

    try {
      await db.closeBatch(_currentBatchId!, deductStock: false, createNextDay: false);

      if (mounted) {
        _showMessage('Demand closed successfully', isSuccess: true);
        await _loadData();
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to close: $e', isError: true);
      }
    }
  }

  Future<bool?> _showCloseConfirmDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.lock_clock, color: Colors.green.shade700),
            ),
            const SizedBox(width: 12),
            const Text('Close Today\'s Demand?', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will finalize today\'s demand order.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildStatRow('Products', '${_batchStats?['productCount'] ?? 0}', Icons.inventory_2),
                  const Divider(height: 16),
                  _buildStatRow('Clients', '${_batchStats?['clientCount'] ?? 0}', Icons.people),
                  const Divider(height: 16),
                  _buildStatRow(
                    'Total Qty',
                    (_batchStats?['totalQuantity'] ?? 0).toStringAsFixed(1),
                    Icons.shopping_cart,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can edit this later using the Edit button',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Close Demand'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🎨 Building DemandScreen - isLoading: $_isLoading');

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
              DateFormat('EEEE, dd MMM yyyy').format(_batchDate),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          // Close button (conditional)
          if (_currentBatchId != null && !_isBatchClosed && _productTotals.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: ElevatedButton.icon(
                onPressed: _closeBatch,
                icon: const Icon(Icons.lock_clock, size: 16),
                label: const Text('Close', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),

          // History button (always visible)
          IconButton(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DemandHistoryScreen()),
              );
              if (result == true && mounted) _loadData();
            },
            icon: const Icon(Icons.history),
            tooltip: 'View History',
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue.shade50,
              foregroundColor: Colors.blue.shade700,
            ),
          ),
          const SizedBox(width: 8),
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
              Builder(
                builder: (context) {
                  debugPrint('🎨 UI DECISION:');
                  debugPrint('   - batchId: $_currentBatchId');
                  debugPrint('   - batchExists: $_batchExists');
                  debugPrint('   - isClosed: $_isBatchClosed');
                  debugPrint('   - totals: ${_productTotals.length}');

                  // Decision logic
                  if (_currentBatchId == null || _productTotals.isEmpty) {
                    debugPrint('   → Showing CREATE screen');
                    return _buildCreateNewDemand();
                  }

                  if (_isBatchClosed) {
                    debugPrint('   → Showing CLOSED screen');
                    return _buildClosedDemandCard();
                  }

                  debugPrint('   → Showing OPEN screen');
                  return _buildOpenDemandCard();
                },
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ NEW: When no demand exists for today
  Widget _buildCreateNewDemand() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
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
                Icon(Icons.add_shopping_cart, size: 64, color: Colors.blue.shade300),
                const SizedBox(height: 16),
                Text(
                  'No Demand Created Yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create today\'s demand order',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () async {
                    // Navigate to edit screen in CREATE mode
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DemandEditScreen(
                          batchDate: _batchDate,
                          isNewBatch: true,
                        ),
                      ),
                    );
                    if (result == true) _loadData();
                  },
                  icon: const Icon(Icons.add, size: 24),
                  label: const Text(
                    'Create Today\'s Demand',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ NEW: When demand is closed
  Widget _buildClosedDemandCard() {
    return Column(
      children: [
        // Closed Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade50, Colors.green.shade100],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Today\'s Demand Closed',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.green.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Order finalized • ${_productTotals.length} products',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DemandEditScreen(
                        batchId: _currentBatchId!,
                        batchDate: _batchDate,
                        isNewBatch: false,
                      ),
                    ),
                  );
                  if (result == true) _loadData();
                },
                icon: const Icon(Icons.edit, size: 20),
                label: const Text('EDIT TODAY\'S DEMAND'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStatsCards(),
        const SizedBox(height: 16),
        _buildProductSummary(),
      ],
    );
  }

  // ✅ NEW: When demand is open (in progress)
  Widget _buildOpenDemandCard() {
    return Column(
      children: [
        // Status Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.blue.shade100],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade300),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.edit_calendar, color: Colors.blue.shade700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demand In Progress',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_productTotals.length} products added',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              if (_productTotals.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _closeBatch,
                  icon: const Icon(Icons.lock_clock, size: 16),
                  label: const Text('Close'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Edit Button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DemandEditScreen(
                    batchId: _currentBatchId!,
                    batchDate: _batchDate,
                    isNewBatch: false,
                  ),
                ),
              );
              if (result == true) _loadData();
            },
            icon: const Icon(Icons.edit_note, size: 24),
            label: const Text(
              'MANAGE DEMAND ENTRIES',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        if (_batchStats != null) ...[
          const SizedBox(height: 16),
          _buildStatsCards(),
        ],

        if (_productTotals.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildProductSummary(),
        ],
      ],
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Products',
            '${_batchStats?['productCount'] ?? 0}',
            Icons.inventory_2,
            Colors.purple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Clients',
            '${_batchStats?['clientCount'] ?? 0}',
            Icons.people,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Total Qty',
            (_batchStats?['totalQuantity'] ?? 0).toStringAsFixed(0),
            Icons.shopping_cart,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSummary() {
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
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.summarize, size: 18, color: Colors.purple.shade700),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Product Summary',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _productTotals.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
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
                  child: Icon(Icons.inventory_2, size: 20, color: Colors.blue.shade600),
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
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

}