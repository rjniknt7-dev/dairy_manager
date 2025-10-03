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

class _DemandScreenState extends State<DemandScreen> {
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

  @override
  void initState() {
    super.initState();
    _loadAll();
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
      SnackBar(content: Text(msg), backgroundColor: backgroundColor),
    );
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text('Purchase Orders – $dateStr'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.sync),
            tooltip: 'Sync Data',
            onPressed: _isSyncing ? null : _syncToCloud,
          ),
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Product Totals',
            onPressed: () {
              if (_batchId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DemandDetailsScreen(batchId: _batchId!),
                  ),
                );
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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DemandHistoryScreen(),
                ),
              );
            },
          ),
        ],
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
                    'Offline mode - Login to sync data',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order form
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Add Purchase Order',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<int>(
                              value: _selClientId,
                              hint: const Text('Select Client'),
                              decoration:
                              const InputDecoration(border: OutlineInputBorder()),
                              items: _clients
                                  .map((c) => DropdownMenuItem<int>(
                                  value: c.id!, child: Text(c.name)))
                                  .toList(),
                              onChanged: (v) => setState(() => _selClientId = v),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<int>(
                              value: _selProductId,
                              hint: const Text('Select Product'),
                              decoration:
                              const InputDecoration(border: OutlineInputBorder()),
                              items: _products
                                  .map((p) => DropdownMenuItem<int>(
                                  value: p.id!,
                                  child: Text('${p.name} (₹${p.price})')))
                                  .toList(),
                              onChanged: (v) => setState(() => _selProductId = v),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _qtyCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Quantity',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Purchase'),
                                    onPressed: _batchClosed ? null : _addOrder,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (_batchClosed)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[100],
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Batch Closed',
                                      style: TextStyle(color: Colors.orange),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Product totals
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Today\'s Product Totals',
                                  style: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.picture_as_pdf,
                                      color: Colors.indigo),
                                  tooltip: 'Export Purchase Order PDF',
                                  onPressed: _exportPdf,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _totals.isEmpty
                                ? const Text('No purchase orders yet',
                                style: TextStyle(color: Colors.grey))
                                : Column(
                              children: _totals.map((row) {
                                return ListTile(
                                  dense: true,
                                  leading:
                                  const Icon(Icons.inventory_2, size: 20),
                                  title: Text(row['productName'] ?? ''),
                                  trailing: Text('Qty: ${row['totalQty'] ?? 0}'),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Client details
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Client-wise Orders',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            _clientDetails.isEmpty
                                ? const Text('No client entries',
                                style: TextStyle(color: Colors.grey))
                                : Column(
                              children: _clientDetails.map((r) {
                                return ListTile(
                                  dense: true,
                                  leading:
                                  const Icon(Icons.person, size: 20),
                                  title: Text('${r['clientName']}'),
                                  subtitle: Text('${r['productName']}'),
                                  trailing: Text('Qty: ${r['qty']}'),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
