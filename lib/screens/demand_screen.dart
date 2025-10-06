// lib/screens/demand_screen_combined.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:printing/printing.dart';
import '../services/pdf_service.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../models/client.dart';
import '../models/product.dart';
import 'demand_details_screen.dart';
import 'demand_history_screen.dart';

class DemandScreen extends StatefulWidget {
  const DemandScreen({Key? key}) : super(key: key);

  @override
  State<DemandScreen> createState() => _DemandScreenState();
}

class _DemandScreenState extends State<DemandScreen>
    with SingleTickerProviderStateMixin {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();
  bool _isSyncing = false;

  List<Client> _clients = [];
  List<Product> _products = [];

  int? _selClientId;
  int? _selProductId;
  final _qtyCtrl = TextEditingController();

  int? _batchId;
  bool _batchClosed = false;

  List<Map<String, dynamic>> _totals = [];
  List<Map<String, dynamic>> _clientDetails = [];

  // ADDED: Animation controllers
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  // ADDED: Animation constants
  static const _pageTransitionDuration = Duration(milliseconds: 400);
  static const _staggeredAnimationDuration = Duration(milliseconds: 600);
  static const _quickAnimationDuration = Duration(milliseconds: 300);
  static const _curve = Curves.easeOutCubic;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadAll();
  }

  // ADDED: Animation initialization
  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: _staggeredAnimationDuration,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: _curve,
      ),
    );

    _slideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: _curve,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose(); // ADDED: Dispose controller
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final clients = await db.getClients();
    final products = await db.getProducts();
    final batchId = await db.getOrCreateBatchForDate(DateTime.now());
    final batchRow = await db.getBatchById(batchId);
    final totals = await db.getCurrentBatchTotals(batchId);
    final details = await db.getBatchClientDetails(batchId);

    if (!mounted) return;
    setState(() {
      _clients = clients;
      _products = products;
      _batchId = batchId;
      _totals = totals;
      _clientDetails = details;
      _batchClosed = (batchRow?['closed'] ?? 0) == 1;
    });
  }

  Future<void> _addOrder() async {
    if (_batchClosed) {
      _showSnack('Batch is closed. Cannot add more orders.');
      return;
    }
    if (_batchId == null || _selClientId == null || _selProductId == null) {
      _showSnack('Please select client, product and quantity.');
      return;
    }

    final q = double.tryParse(_qtyCtrl.text.trim());
    if (q == null || q <= 0) {
      _showSnack('Enter a valid quantity.');
      return;
    }

    try {
      await db.insertDemandEntry(
        batchId: _batchId!,
        clientId: _selClientId!,
        productId: _selProductId!,
        quantity: q,
      );

      _qtyCtrl.clear();
      await _loadAll();
      _showSnack('Purchase order added locally.');

      if (FirebaseAuth.instance.currentUser != null) {
        setState(() => _isSyncing = true);
        final result = await _syncService.syncAllData();
        setState(() => _isSyncing = false);

        if (result.success) {
          _showSnack('Order synced to cloud.', Colors.green);
        } else {
          _showSnack('Will sync when connection improves.', Colors.orange);
        }
      }
    } catch (e) {
      _showSnack('Failed to add order: $e', Colors.red);
    }
  }

  Future<void> _closeOrderDay() async {
    if (_batchId == null || _batchClosed) return;

    try {
      await db.closeBatch(_batchId!, createNextDay: true);
      if (!mounted) return;
      _showSnack('Orders closed and stock updated locally.');
      await _loadAll();

      if (FirebaseAuth.instance.currentUser != null) {
        setState(() => _isSyncing = true);
        final result = await _syncService.syncAllData();
        setState(() => _isSyncing = false);

        if (result.success) {
          _showSnack('Changes synced to cloud.', Colors.green);
        }
      }
    } catch (e) {
      _showSnack('Failed to close batch: $e', Colors.red);
    }
  }

  Future<void> _exportPdf() async {
    if (_totals.isEmpty) {
      _showSnack('No purchase orders to export.');
      return;
    }

    try {
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final pdfData = await PDFService.buildPurchaseOrderPdf(
        date: dateStr,
        totals: _totals,
      );
      await Printing.sharePdf(
        bytes: pdfData,
        filename: 'purchase_order_$dateStr.pdf',
      );
    } catch (e) {
      _showSnack('Failed to export PDF: $e', Colors.red);
    }
  }

  Future<void> _syncToCloud() async {
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Login to sync data'),
          action: SnackBarAction(
            label: 'LOGIN',
            onPressed: () => Navigator.pushNamed(context, '/login'),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);
    final result = await _syncService.syncAllData();
    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );
  }

  void _showSnack(String msg, [Color? backgroundColor]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ADDED: Smooth navigation method
  void _navigateToScreen(Widget screen) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        transitionDuration: _pageTransitionDuration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: _quickAnimationDuration,
          child: Text(
            'Purchase Orders – $dateStr',
            key: ValueKey(dateStr),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          AnimatedSwitcher(
            duration: _quickAnimationDuration,
            child: _isSyncing
                ? SizedBox(
              key: const ValueKey('syncing'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : IconButton(
              key: const ValueKey('sync'),
              icon: const Icon(Icons.sync),
              tooltip: 'Sync Data',
              onPressed: _isSyncing ? null : _syncToCloud,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Product Totals',
            onPressed: () {
              if (_batchId != null) {
                _navigateToScreen(DemandDetailsScreen(batchId: _batchId!));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Close & Update Stock',
            onPressed: _batchClosed ? null : _closeOrderDay,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Purchase Order History',
            onPressed: () {
              _navigateToScreen(const DemandHistoryScreen());
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: Transform.translate(
              offset: Offset(0, _slideAnimation.value),
              child: Column(
                children: [
                  if (!isLoggedIn)
                    SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -1),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _animationController,
                        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
                      )),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        color: Colors.orange.shade100,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              'Offline mode - Login to sync data',
                              style: TextStyle(fontSize: 14, color: Colors.orange),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Order form
                            _buildOrderForm(),
                            const SizedBox(height: 20),

                            // Product totals
                            _buildProductTotals(),
                            const SizedBox(height: 20),

                            // Client details
                            _buildClientDetails(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ADDED: Extracted order form widget with animations
  Widget _buildOrderForm() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.5, curve: Curves.easeOut),
      )),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Purchase Order',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _buildAnimatedDropdowns(),
              const SizedBox(height: 16),
              _buildQuantityField(),
              const SizedBox(height: 20),
              _buildAddButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ADDED: Animated dropdowns
  // ADDED: Animated dropdowns with overflow handling
  // Place these inside your _DemandScreenState class

// 1️⃣ Animated Dropdowns
  Widget _buildAnimatedDropdowns() {
    return Column(
      children: [
        AnimatedContainer(
          duration: _quickAnimationDuration,
          curve: Curves.easeOut,
          child: DropdownButtonFormField<int>(
            value: _selClientId,
            hint: const Text('Select Client'),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            isExpanded: true, // ✅ prevents RenderFlex overflow
            items: _clients
                .map((c) => DropdownMenuItem<int>(
              value: c.id!,
              child: Text(c.name, overflow: TextOverflow.ellipsis),
            ))
                .toList(),
            onChanged: (v) => setState(() => _selClientId = v),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedContainer(
          duration: _quickAnimationDuration,
          curve: Curves.easeOut,
          child: DropdownButtonFormField<int>(
            value: _selProductId,
            hint: const Text('Select Product'),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            isExpanded: true, // ✅ prevents RenderFlex overflow
            items: _products
                .map((p) => DropdownMenuItem<int>(
              value: p.id!,
              child: Text('${p.name} (₹${p.price})',
                  overflow: TextOverflow.ellipsis),
            ))
                .toList(),
            onChanged: (v) => setState(() => _selProductId = v),
          ),
        ),
      ],
    );
  }

// 2️⃣ Animated Quantity Field
  Widget _buildQuantityField() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.4, 0.7, curve: Curves.easeOut),
      )),
      child: TextField(
        controller: _qtyCtrl,
        decoration: InputDecoration(
          labelText: 'Quantity',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
    );
  }

// 3️⃣ Animated Add Button
  Widget _buildAddButton() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.6, 0.9, curve: Curves.easeOut),
      )),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Purchase', style: TextStyle(fontSize: 16)),
              onPressed: _batchClosed ? null : _addOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (_batchClosed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Batch Closed',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }



  // ADDED: Product totals with animations
  Widget _buildProductTotals() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.5, 0.8, curve: Curves.easeOut),
      )),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Today\'s Product Totals',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _animationController,
                      curve: const Interval(0.7, 1.0, curve: Curves.elasticOut),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.indigo),
                      tooltip: 'Export Purchase Order PDF',
                      onPressed: _exportPdf,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTotalsList(),
            ],
          ),
        ),
      ),
    );
  }

  // ADDED: Animated totals list
  Widget _buildTotalsList() {
    if (_totals.isEmpty) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0.8, 1.0),
        ),
        child: const Center(
          child: Text('No purchase orders yet',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
        ),
      );
    }

    return Column(
      children: _totals.asMap().entries.map((entry) {
        final index = entry.key;
        final row = entry.value;

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _animationController,
            curve: Interval(0.7 + (index * 0.1), 1.0, curve: Curves.easeOut),
          )),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _animationController,
              curve: Interval(0.7 + (index * 0.1), 1.0),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.inventory_2, size: 20, color: Colors.blue.shade700),
                title: Text(
                  row['productName'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Qty: ${row['totalQty'] ?? 0}',
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ADDED: Client details with animations
  Widget _buildClientDetails() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.6, 0.9, curve: Curves.easeOut),
      )),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Client-wise Orders',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildClientDetailsList(),
            ],
          ),
        ),
      ),
    );
  }

  // ADDED: Animated client details list
  Widget _buildClientDetailsList() {
    if (_clientDetails.isEmpty) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0.9, 1.0),
        ),
        child: const Center(
          child: Text('No client entries',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
        ),
      );
    }

    return Column(
      children: _clientDetails.asMap().entries.map((entry) {
        final index = entry.key;
        final r = entry.value;

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _animationController,
            curve: Interval(0.8 + (index * 0.1), 1.0, curve: Curves.easeOut),
          )),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _animationController,
              curve: Interval(0.8 + (index * 0.1), 1.0),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.person, size: 20, color: Colors.green.shade700),
                title: Text(
                  '${r['clientName']}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '${r['productName']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Qty: ${r['qty']}',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}