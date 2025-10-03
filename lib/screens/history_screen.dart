// lib/screens/history_screen.dart
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
  final FirebaseSyncService _backup = FirebaseSyncService();
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

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadData();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final db = DatabaseHelper();
      final clients = await db.getClients();
      final products = await db.getProducts();

      final dbInstance = await db.database;
      final billsData = await dbInstance.query(
        'bills',
        where: 'isDeleted = 0',
        orderBy: 'date DESC',
      );

      setState(() {
        _bills = billsData.map((e) => Bill.fromMap(e)).toList();
        _filteredBills = _bills;
        _clients = {for (final c in clients) c.id!: c};
        _products = {for (final p in products) p.id!: p};
        _isLoading = false;
      });

      // Start animations
      _fadeController.forward();
      _slideController.forward();
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to load billing history: $e');
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

        bool matchesFilter = true;
        switch (_selectedFilter) {
          case 'paid':
            matchesFilter = bill.paidAmount >= bill.totalAmount;
            break;
          case 'pending':
            matchesFilter = bill.paidAmount < bill.totalAmount;
            break;
          case 'today':
            final today = DateTime.now();
            matchesFilter = bill.date.year == today.year &&
                bill.date.month == today.month &&
                bill.date.day == today.day;
            break;
          case 'week':
            final weekAgo = DateTime.now().subtract(const Duration(days: 7));
            matchesFilter = bill.date.isAfter(weekAgo);
            break;
        }

        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  Future<void> _showBillItems(Bill bill) async {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, _) => BillDetailsScreen(billId: bill.id!),
        transitionsBuilder: (context, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _deleteBill(Bill bill) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Delete Bill'),
          ],
        ),
        content: Text(
          'Delete bill for ${_clients[bill.clientId]?.name ?? "Unknown Client"}?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final db = DatabaseHelper();
      await db.deleteBillCompletely(bill.id!);

      // Firestore cleanup
      try {
        //await _backup.deleteBill(bill.id!);
      } catch (e) {
        _showWarningSnackBar('Deleted offline. Will sync when online.');
      }

      HapticFeedback.lightImpact();
      _showSuccessSnackBar('Bill deleted successfully');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('Failed to delete bill: $e');
    }
  }

  Future<void> _editBill(Bill bill) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, _) => BillingScreen(existingBill: bill),
        transitionsBuilder: (context, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _exportPdf(Bill bill) async {
    try {
      final db = DatabaseHelper();
      final items = await db.getBillItems(bill.id!);
      final client = _clients[bill.clientId];

      if (client == null) {
        if (!mounted) return;
        _showErrorSnackBar('Client information not found');
        return;
      }

      final billItems = items.map((item) {
        final product = _products[item.productId];
        return {
          'name': product?.name ?? 'Unknown Product',
          'qty': item.quantity,
          'price': item.price,
          'gst': null,
        };
      }).toList();

      final pdfBytes = await _invoiceService.buildPdf(
        customerName: client.name,
        invoiceNo: 'INV-${bill.id}',
        date: bill.date,
        items: billItems,
        receivedAmount: bill.paidAmount,
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice_${bill.id}.pdf');
      await file.writeAsBytes(pdfBytes);

      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)], text: 'Invoice PDF');

      if (!mounted) return;
      _showSuccessSnackBar('Invoice exported successfully');
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Failed to export PDF: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          _buildSliverFilters(),

          // Loading state
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )

          // Empty state
          else if (_filteredBills.isEmpty)
            SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: Transform.translate(
                      offset: Offset(0, 50 * (1 - _fadeAnimation.value)),
                      child: child,
                    ),
                  );
                },
                child: _buildEmptyState(),
              ),
            )

          // Bills list
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final bill = _filteredBills[index];
                  return _buildBillCard(bill);
                },
                childCount: _filteredBills.length,
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, _) => const BillingScreen(),
            transitionsBuilder: (context, animation, _, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              );
            },
          ),
        ).then((result) {
          if (result == true) _loadData();
        }),
        icon: const Icon(Icons.add),
        label: const Text('New Bill'),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.indigo,
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'Billing History',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.indigo, Color(0xFF3F51B5)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliverFilters() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.grey[50],
        child: Column(
          children: [
            TextField(
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _filterBills();
              },
              decoration: InputDecoration(
                hintText: 'Search by client name or bill ID...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'all'),
                  _buildFilterChip('Paid', 'paid'),
                  _buildFilterChip('Pending', 'pending'),
                  _buildFilterChip('Today', 'today'),
                  _buildFilterChip('This Week', 'week'),
                ],
              ),
            ),
          ],
        ),
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
        selectedColor: Colors.indigo.withOpacity(0.2),
        checkmarkColor: Colors.indigo,
        backgroundColor: Colors.white,
      ),
    );
  }

  Widget _buildBillsList() {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverAnimatedOpacity(
        opacity: _fadeAnimation.value,
        duration: const Duration(milliseconds: 600),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
                (context, index) {
              final bill = _filteredBills[index];
              return SlideTransition(
                position: _slideAnimation,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200 + (index * 50)),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: _buildBillCard(bill),
                ),
              );
            },
            childCount: _filteredBills.length,
          ),
        ),
      ),
    );
  }

  Widget _buildBillCard(Bill bill) {
    final client = _clients[bill.clientId];
    final isPaid = bill.paidAmount >= bill.totalAmount;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showBillItems(bill),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isPaid ? Colors.green.shade100 : Colors.orange.shade100,
                    child: Icon(
                      isPaid ? Icons.check_circle : Icons.schedule,
                      color: isPaid ? Colors.green : Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'INV-${bill.id}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPaid ? Colors.green : Colors.orange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isPaid ? 'Paid' : 'Pending',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          client?.name ?? 'Unknown Client',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dateFmt.format(bill.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (value) => _handleMenuAction(value, bill),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(Icons.visibility, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('View Details'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'pdf',
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Export PDF'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('Edit Bill'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          _currencyFormat.format(bill.totalAmount),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Balance',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          _currencyFormat.format(bill.totalAmount - bill.paidAmount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isPaid ? Colors.green : Colors.red,
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
      ),
    );
  }

  void _handleMenuAction(String action, Bill bill) {
    switch (action) {
      case 'view':
        _showBillItems(bill);
        break;
      case 'pdf':
        _exportPdf(bill);
        break;
      case 'edit':
        _editBill(bill);
        break;
      case 'delete':
        _deleteBill(bill);
        break;
    }
  }

  Widget _buildEmptyState() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(60),
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 60,
                color: Colors.indigo.shade300,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _searchQuery.isEmpty ? 'No bills yet' : 'No bills found',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty
                  ? 'Create your first bill to get started'
                  : 'Try adjusting your search or filter',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BillingScreen()),
                ).then((result) {
                  if (result == true) _loadData();
                }),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add),
                    SizedBox(width: 8),
                    Text('Create First Bill'),
                  ],
                ),
              ),
            ],
          ],
        ),
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