// lib/screens/bill_details_screen.dart - v2.0 (Intelligent & Smooth)
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
import '../models/ledger_entry.dart';
import '../services/database_helper.dart';
import '../services/firebase_sync_service.dart';
import '../services/invoice_service.dart';
import 'billing_screen.dart';

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
  final _dateFormat = DateFormat('MMM dd, yyyy, hh:mm a');

  Bill? bill;
  Client? client;
  List<BillItem> items = [];
  List<Product> products = [];
  bool _loading = true;
  bool _busy = false;
  bool _isGeneratingPdf = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _load();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final fetchedBill = await db.getBillById(widget.billId);
      if (fetchedBill == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final fetchedClient = await db.getClientById(fetchedBill.clientId);
      final itemMaps = await db.getBillItemsByBillId(widget.billId);
      final productList = await db.getProducts();

      if (mounted) {
        setState(() {
          bill = fetchedBill;
          client = fetchedClient;
          items = itemMaps.map((e) => BillItem.fromMap(e)).toList();
          products = productList;
          _loading = false;
        });
        _fadeController.forward(from: 0.0);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showErrorSnackBar('Failed to load bill details: $e');
      }
    }
  }

  // ✅ NEW: Smart "Add Payment" functionality
  Future<void> _addPayment() async {
    if (bill == null || client == null) return;

    final balance = bill!.totalAmount - bill!.paidAmount;
    if (balance <= 0) {
      _showSuccessSnackBar('This bill is already fully paid.');
      return;
    }

    final controller = TextEditingController(text: balance.toStringAsFixed(2));

    final amountToPay = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Payment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount Received',
            prefixText: '₹ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(double.tryParse(controller.text));
            },
            child: const Text('Confirm Payment'),
          ),
        ],
      ),
    );

    if (amountToPay == null || amountToPay <= 0) return;

    setState(() => _busy = true);
    try {
      final paymentEntry = LedgerEntry(
        clientId: bill!.clientId,
        billId: bill!.id,
        type: 'payment',
        amount: amountToPay,
        date: DateTime.now(),
        note: 'Payment for Bill #${bill!.id}',
      );

      await db.insertLedgerEntry(paymentEntry);

      final newPaidAmount = bill!.paidAmount + amountToPay;
      await db.updateBill(bill!.copyWith(
        paidAmount: newPaidAmount,
        paymentStatus: newPaidAmount >= bill!.totalAmount ? 'paid' : 'partial',
      ));

      _syncService.syncLedger();
      _syncService.syncBills();

      _showSuccessSnackBar('Payment of ${_currencyFormat.format(amountToPay)} recorded!');
    } catch (e) {
      _showErrorSnackBar('Failed to record payment: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _load();
      }
    }
  }

  // ✅ FIXED: Professional invoice with previous and current balances
  Future<void> _generateAndSharePdf() async {
    if (bill == null || client == null || _isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);

    try {
      final billItemsForPdf = items.map((item) {
        final product = products.firstWhere((p) => p.id == item.productId,
            orElse: () => Product(id: item.productId, name: 'Unknown', price: 0, quantity: 0));
        return {
          'name': product.name,
          'qty': item.quantity,
          'price': item.price,
        };
      }).toList();

      final totalClientBalance = await db.getClientBalance(client!.id!);
      final thisBillBalance = bill!.totalAmount - bill!.paidAmount;
      final previousBalance = totalClientBalance - thisBillBalance;

      // Note: You may need to update your InvoiceService to accept these new parameters
      final pdfBytes = await _invoiceService.buildPdf(
        customerName: client!.name,
        invoiceNo: 'INV-${bill!.id}',
        date: bill!.date,
        items: billItemsForPdf,
        billTotal: bill!.totalAmount,
        paidForThisBill: bill!.paidAmount,
        previousBalance: previousBalance,
        currentBalance: totalClientBalance,
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice_${bill!.id}.pdf');
      await file.writeAsBytes(pdfBytes);

      await Share.shareXFiles([XFile(file.path)], text: 'Invoice for ${client!.name}');
    } catch (e, stackTrace) {
      debugPrint('PDF generation error: $e\n$stackTrace');
      _showErrorSnackBar('Failed to generate or share invoice.');
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _navigateToEdit() async {
    if (bill == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BillingScreen(existingBill: bill),
      ),
    );
    if (result == true) {
      _load(); // Reload data if the bill was updated
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (bill == null || client == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(
          child: Text('Bill not found.', style: TextStyle(fontSize: 18)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBillHeader(),
                    const SizedBox(height: 24),
                    _buildTotalCard(),
                    const SizedBox(height: 24),
                    _buildItemsList(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      elevation: 2,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      surfaceTintColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
        title: Text(
          'Invoice #${bill!.id}',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        background: Container(color: Colors.grey.shade100),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_note),
          onPressed: _navigateToEdit,
          tooltip: 'Edit Bill',
        ),
        IconButton(
          icon: _isGeneratingPdf
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.share),
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.indigo.shade50,
                  child: Text(client!.name.isNotEmpty ? client!.name[0].toUpperCase() : 'C',
                      style: TextStyle(color: Colors.indigo.shade800, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(client!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (client!.phone.isNotEmpty) Text(client!.phone, style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bill Date:', style: TextStyle(color: Colors.grey.shade600)),
                Text(_dateFormat.format(bill!.date), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard() {
    final balance = bill!.totalAmount - bill!.paidAmount;
    return Card(
      elevation: 4,
      shadowColor: Colors.indigo.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo.shade600, Colors.indigo.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildTotalRow('Total Amount', bill!.totalAmount, Colors.white, 22),
            const Divider(color: Colors.white24, height: 24),
            _buildTotalRow('Amount Paid', bill!.paidAmount, Colors.greenAccent.shade100, 16),
            const SizedBox(height: 8),
            _buildTotalRow('Balance Due', balance, balance > 0.1 ? Colors.orange.shade200 : Colors.greenAccent.shade100, 16),
            if (balance > 0.1) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.payment, size: 20),
                  label: const Text('Record a Payment'),
                  onPressed: _busy ? null : _addPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, Color amountColor, double amountSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        Text(
          _currencyFormat.format(amount),
          style: TextStyle(fontSize: amountSize, fontWeight: FontWeight.bold, color: amountColor),
        ),
      ],
    );
  }

  Widget _buildItemsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text("No items in this bill.")))
        else
          ...items.map((item) {
            final product = products.firstWhere(
                  (p) => p.id == item.productId,
              orElse: () => Product(id: item.productId, name: 'Unknown Product', price: 0, quantity: 0),
            );
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            '${item.quantity.toInt()} x ${_currencyFormat.format(item.price)}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _currencyFormat.format(item.quantity * item.price),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Text(message)]),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [const Icon(Icons.error, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text(message))]),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [const Icon(Icons.warning, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text(message))]),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}