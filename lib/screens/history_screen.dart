// lib/screens/history_screen.dart - v2.0 (Smart & Robust)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../services/database_helper.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/client.dart';
import '../models/product.dart';
import '../services/firebase_sync_service.dart';
import '../services/invoice_service.dart';
import 'billing_screen.dart';
import 'bill_details_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with TickerProviderStateMixin {
  final FirebaseSyncService _syncService = FirebaseSyncService();
  final InvoiceService _invoiceService = InvoiceService();
  final _dateFmt = DateFormat('MMM dd, yyyy');
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  List<Bill> _bills = [];
  List<Bill> _filteredBills = [];
  Map<int, Client> _clients = {};
  Map<int, Product> _products = {};

  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'all';

  late AnimationController _listAnimationController;

  @override
  void initState() {
    super.initState();
    _listAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _loadData();
  }

  @override
  void dispose() {
    _listAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final db = DatabaseHelper();
      // Fetch all data in parallel for speed
      final results = await Future.wait([
        db.getBills(),
        db.getClients(),
        db.getProducts(),
      ]);

      final billsData = results[0] as List<Map<String, dynamic>>;
      final clientsData = results[1] as List<Client>;
      final productsData = results[2] as List<Product>;

      if (mounted) {
        setState(() {
          _bills = billsData.map((e) => Bill.fromMap(e)).toList();
          _clients = {for (final c in clientsData) c.id!: c};
          _products = {for (final p in productsData) p.id!: p};
          _isLoading = false;
        });
        _filterBills(); // Apply initial filter
        _listAnimationController.forward(from: 0.0);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Failed to load history: $e');
      }
    }
  }

  void _filterBills() {
    setState(() {
      _filteredBills = _bills.where((bill) {
        final client = _clients[bill.clientId];
        final clientName = client?.name.toLowerCase() ?? '';
        final matchesSearch = _searchQuery.isEmpty ||
            clientName.contains(_searchQuery.toLowerCase()) ||
            bill.id.toString().contains(_searchQuery);

        bool matchesFilter;
        switch (_selectedFilter) {
          case 'paid':
            matchesFilter = (bill.totalAmount - bill.paidAmount).abs() < 0.01;
            break;
          case 'pending':
            matchesFilter = (bill.totalAmount - bill.paidAmount).abs() >= 0.01;
            break;
          case 'today':
            final today = DateTime.now();
            matchesFilter = bill.date.year == today.year && bill.date.month == today.month && bill.date.day == today.day;
            break;
          case 'week':
            final weekAgo = DateTime.now().subtract(const Duration(days: 7));
            matchesFilter = bill.date.isAfter(weekAgo);
            break;
          default: // 'all'
            matchesFilter = true;
        }

        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  Future<void> _navigateToDetails(Bill bill) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => BillDetailsScreen(billId: bill.id!)),
    );
    if (result == true) _loadData();
  }

  Future<void> _navigateToEdit(Bill bill) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => BillingScreen(existingBill: bill)),
    );
    if (result == true) _loadData();
  }

  // ✅ UPDATED: Uses soft delete for safety
  Future<void> _deleteBill(Bill bill) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill?'),
        content: Text('Are you sure you want to delete Invoice #${bill.id}? This action marks the bill as deleted but can be recovered if needed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final db = DatabaseHelper();
      await db.deleteBill(bill.id!);

      _syncService.syncBills().catchError((e) {
        debugPrint('Background sync for deletion failed: $e');
      });

      HapticFeedback.lightImpact();
      _showSuccessSnackBar('Bill moved to trash.');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('Failed to delete bill: $e');
    }
  }

  // ✅ UPDATED: Calculates and passes all required data for a professional invoice
  Future<void> _exportPdf(Bill bill) async {
    final client = _clients[bill.clientId];
    if (client == null) {
      _showErrorSnackBar('Client information not found for this bill.');
      return;
    }

    try {
      final db = DatabaseHelper();
      final billItemsData = await db.getBillItems(bill.id!);

      final pdfItems = billItemsData.map((item) {
        final product = _products[item.productId];
        return {'name': product?.name ?? 'Unknown', 'qty': item.quantity, 'price': item.price};
      }).toList();

      final totalClientBalance = await db.getClientBalance(client.id!);
      final thisBillBalance = bill.totalAmount - bill.paidAmount;
      final previousBalance = totalClientBalance - thisBillBalance;

      final pdfBytes = await _invoiceService.buildPdf(
        customerName: client.name,
        invoiceNo: 'INV-${bill.id}',
        date: bill.date,
        items: pdfItems,
        billTotal: bill.totalAmount,
        paidForThisBill: bill.paidAmount,
        previousBalance: previousBalance,
        currentBalance: totalClientBalance,
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice_${bill.id}.pdf');
      await file.writeAsBytes(pdfBytes);

      await Share.shareXFiles([XFile(file.path)], text: 'Invoice for ${client.name}');

    } catch (e, stackTrace) {
      debugPrint('PDF Export Error: $e\n$stackTrace');
      _showErrorSnackBar('Failed to export PDF: ${e.toString()}');
    }
  }

  void _handleMenuAction(String action, Bill bill) {
    switch (action) {
      case 'view': _navigateToDetails(bill); break;
      case 'pdf': _exportPdf(bill); break;
      case 'edit': _navigateToEdit(bill); break;
      case 'delete': _deleteBill(bill); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Billing History'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredBills.isEmpty
                ? _buildEmptyState()
                : _buildBillsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => const BillingScreen()),
        ).then((wasModified) {
          if (wasModified == true) _loadData();
        }),
        backgroundColor: Colors.purple,
        child: const Icon(Icons.add),
        tooltip: 'Create New Bill',
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            onChanged: (value) {
              setState(() => _searchQuery = value);
              _filterBills();
            },
            decoration: InputDecoration(
              hintText: 'Search by client or bill ID...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                _buildFilterChip('Pending', 'pending'),
                _buildFilterChip('Paid', 'paid'),
                _buildFilterChip('Today', 'today'),
                _buildFilterChip('This Week', 'week'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _selectedFilter = value);
          _filterBills();
        },
        selectedColor: Colors.purple.withOpacity(0.2),
        checkmarkColor: Colors.purple,
        labelStyle: TextStyle(color: isSelected ? Colors.purple.shade900 : Colors.black87),
        shape: StadiumBorder(side: BorderSide(color: isSelected ? Colors.purple : Colors.grey.shade300)),
        backgroundColor: Colors.white,
      ),
    );
  }

  Widget _buildBillsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredBills.length,
      itemBuilder: (context, index) {
        final bill = _filteredBills[index];
        // Apply list animation
        return AnimatedBuilder(
          animation: _listAnimationController,
          builder: (context, child) {
            final delay = (index * 50).clamp(0, 300);
            final animation = CurvedAnimation(
              parent: _listAnimationController,
              curve: Interval((delay / 500), 1.0, curve: Curves.easeOut),
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(animation),
                child: child,
              ),
            );
          },
          child: _buildBillCard(bill),
        );
      },
    );
  }

  Widget _buildBillCard(Bill bill) {
    final client = _clients[bill.clientId];
    final isPaid = (bill.totalAmount - bill.paidAmount).abs() < 0.01;
    final balance = bill.totalAmount - bill.paidAmount;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToDetails(bill),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client?.name ?? 'Unknown Client',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'INV-${bill.id}  •  ${_dateFmt.format(bill.date)}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) => _handleMenuAction(value, bill),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'view', child: Text('View Details')),
                      const PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatColumn('Total', _currencyFormat.format(bill.totalAmount), Colors.black87),
                  _buildStatColumn('Paid', _currencyFormat.format(bill.paidAmount), Colors.green.shade700),
                  _buildStatColumn('Balance', _currencyFormat.format(balance), isPaid ? Colors.green.shade700 : Colors.red.shade700),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('No Bills Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search term or filter.'
                : 'No bills match the selected filter.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }


  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}