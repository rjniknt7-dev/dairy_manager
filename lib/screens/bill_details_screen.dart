// lib/screens/bill_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../models/bill.dart';
import '../models/bill_item.dart';
import '../models/product.dart';
import '../models/client.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../services/invoice_service.dart';

class BillDetailsScreen extends StatefulWidget {
  final int billId;
  const BillDetailsScreen({super.key, required this.billId});

  @override
  State<BillDetailsScreen> createState() => _BillDetailsScreenState();
}

class _BillDetailsScreenState extends State<BillDetailsScreen>
    with TickerProviderStateMixin {
  final db = DatabaseHelper();
  final _syncService = FirebaseSyncService();
  final _invoiceService = InvoiceService();
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
  final _dateFormat = DateFormat('MMM dd, yyyy hh:mm a');

  Bill? bill;
  Client? client;
  List<BillItem> items = [];
  List<Product> products = [];
  bool _loading = true;
  bool _busy = false;
  bool _isGeneratingPdf = false;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _load();
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
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final fetchedBill = await db.getBillById(widget.billId);
      if (fetchedBill == null) {
        setState(() => _loading = false);
        return;
      }

      final clientList = await db.getClients();
      final fetchedClient = clientList.firstWhere(
            (c) => c.id == fetchedBill.clientId,
        orElse: () => Client(id: 0, name: 'Unknown Client', phone: '', address: ''),
      );

      final itemMaps = await db.getBillItemsByBillId(widget.billId);
      final productList = await db.getProducts();

      setState(() {
        bill = fetchedBill;
        client = fetchedClient;
        items = itemMaps.map((e) => BillItem.fromMap(e)).toList();
        products = productList;
        _loading = false;
      });

      // Start animations
      _fadeController.forward();
      _slideController.forward();
    } catch (e) {
      setState(() => _loading = false);
      _showErrorSnackBar('Failed to load bill details: $e');
    }
  }

  Future<void> _updateTotals(double diffAmount) async {
    if (bill == null) return;

    final newTotal = bill!.totalAmount + diffAmount;
    await db.updateBillTotal(bill!.id!, newTotal);

    setState(() {
      bill = bill!.copyWith(totalAmount: newTotal);
    });
  }

  Future<void> _editItem(BillItem item) async {
    final controller = TextEditingController(text: item.quantity.toStringAsFixed(2));

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.edit, color: Colors.blue.shade600),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Edit Quantity',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.inventory),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : () async {
                        final newQty = double.tryParse(controller.text.trim()) ?? item.quantity;
                        if (newQty <= 0) {
                          _showErrorSnackBar('Quantity must be greater than 0');
                          return;
                        }

                        final diff = newQty - item.quantity;
                        setState(() => _busy = true);

                        try {
                          await db.updateBillItemQuantityWithStock(item.id!, newQty);
                          await _updateTotals(diff * item.price);

                          await _syncService.syncBills();

                          _showSuccessSnackBar('Item updated successfully');
                        } catch (e) {
                          _showWarningSnackBar('Updated offline. Will sync when online.');
                        } finally {
                          if (mounted) {
                            setState(() => _busy = false);
                            Navigator.pop(context);
                            await _load();
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteItem(BillItem item) async {
    final product = products.firstWhere(
          (p) => p.id == item.productId,
      orElse: () => Product(id: item.productId, name: 'Unknown', weight: 0, price: 0),
    );

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
            const Text('Remove Item'),
          ],
        ),
        content: Text('Remove ${item.quantity} × ${product.name} from this bill?'),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true || _busy) return;

    setState(() => _busy = true);
    try {
      await db.deleteBillItem(item.id!);
      await db.adjustStock(item.productId, item.quantity);
      await _updateTotals(-(item.quantity * item.price));

      // Firestore sync
      await _syncService.syncBills();

      _showSuccessSnackBar('Item removed successfully');
      HapticFeedback.lightImpact();
    } catch (e) {
      _showWarningSnackBar('Removed offline. Will sync when online.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  Future<void> _generateAndSharePdf() async {
    if (bill == null || client == null) return;

    setState(() => _isGeneratingPdf = true);

    try {
      // Prepare items for PDF
      final billItems = items.map((item) {
        final product = products.firstWhere(
              (p) => p.id == item.productId,
          orElse: () => Product(
            id: item.productId,
            name: 'Unknown Product',
            weight: 0,
            price: 0,
          ),
        );
        return {
          'name': product.name,
          'qty': item.quantity,
          'price': item.price,
        };
      }).toList();

      // Calculate ledger remaining safely
      final double totalAmount = bill!.totalAmount;
      final double receivedAmount = bill!.paidAmount;
      final double ledgerRemaining = (totalAmount - receivedAmount).clamp(0, double.infinity);

      // Generate PDF using InvoiceService
      final pdfBytes = await _invoiceService.buildPdf(
        customerName: client!.name,
        invoiceNo: 'INV-${bill!.id}',
        date: bill!.date,
        items: billItems,
        receivedAmount: receivedAmount,
        ledgerRemaining: ledgerRemaining,
      );

      // Save PDF to temporary directory
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice_${bill!.id}.pdf');
      await file.writeAsBytes(pdfBytes);

      // Share PDF
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Invoice for ${client!.name}',
      );

      _showSuccessSnackBar('Invoice shared successfully');
    } catch (e, stackTrace) {
      debugPrint('PDF generation error: $e\n$stackTrace');
      _showErrorSnackBar('Failed to share invoice.');
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (bill == null || client == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bill Details')),
        body: const Center(
          child: Text('Bill not found', style: TextStyle(fontSize: 18)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // AppBar
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.indigo,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            expandedHeight: 100,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: Text(
                '${client!.name} - Invoice #${bill!.id}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),

          // Total / Paid / Balance card
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            sliver: SliverToBoxAdapter(
              child: _buildTotalCard(), // Centered total/paid/balance
            ),
          ),

          // Bill items list
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),
                _buildItemsList(),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildActionButtons(),
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
        title: Text(
          'Invoice #${bill!.id}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
      actions: [
        IconButton(
          icon: _isGeneratingPdf
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Icon(Icons.share, color: Colors.white),
          onPressed: _isGeneratingPdf ? null : _generateAndSharePdf,
          tooltip: 'Share Invoice',
        ),

      ],
    );
  }

  Widget _buildBillHeader() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.indigo.shade100,
                  child: Text(
                    client!.name.isNotEmpty ? client!.name[0].toUpperCase() : 'C',
                    style: TextStyle(
                      color: Colors.indigo.shade800,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client!.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (client!.phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              client!.phone,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ],
                      if (client!.address.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                client!.address,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bill Date',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _dateFormat.format(bill!.date),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Status',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: bill!.paidAmount >= bill!.totalAmount
                              ? Colors.green
                              : Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          bill!.paidAmount >= bill!.totalAmount ? 'Paid' : 'Pending',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
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
    );
  }

  Widget _buildItemsList() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.receipt_long, color: Colors.green.shade600),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Bill Items',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${items.length} items',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final product = products.firstWhere(
                    (p) => p.id == item.productId,
                orElse: () => Product(
                  id: item.productId,
                  name: 'Unknown Product',
                  weight: 0,
                  price: 0,
                ),
              );

              return AnimatedContainer(
                duration: Duration(milliseconds: 200 + (index * 50)),
                margin: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.blue.shade100,
                        child: Text(
                          product.name.isNotEmpty ? product.name[0].toUpperCase() : 'P',
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${_currencyFormat.format(item.price)} × ${item.quantity.toInt()}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _currencyFormat.format(item.price * item.quantity),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: _busy ? null : () => _editItem(item),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.blue.shade50,
                                  foregroundColor: Colors.blue,
                                  minimumSize: const Size(32, 32),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18),
                                onPressed: _busy ? null : () => _deleteItem(item),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.red.shade50,
                                  foregroundColor: Colors.red,
                                  minimumSize: const Size(32, 32),
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
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo.shade50, Colors.indigo.shade100],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Amount',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _currencyFormat.format(bill!.totalAmount),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Paid Amount',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  _currencyFormat.format(bill!.paidAmount),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Balance',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  _currencyFormat.format(bill!.totalAmount - bill!.paidAmount),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: (bill!.totalAmount - bill!.paidAmount) > 0
                        ? Colors.red
                        : Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: "pdf",
          onPressed: _isGeneratingPdf ? null : _generateAndSharePdf,
          backgroundColor: Colors.green,
          child: _isGeneratingPdf
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Icon(Icons.picture_as_pdf),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: "share_pdf",
          onPressed: _isGeneratingPdf ? null : _generateAndSharePdf,
          backgroundColor: Colors.green,
          icon: _isGeneratingPdf
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Icon(Icons.share),
          label: const Text('Share Invoice'),
        )
        ,
      ],
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